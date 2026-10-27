import 'dart:math';

import '../../core/json.dart';
import '../../domain/catalog/concept_catalog.dart';
import '../../domain/game/game_models.dart' show PlayerStyle;

/// Explicit eligibility for the current context/orientation, consents and gear.
/// Missing concepts/actions/zones are inadmissible, never implicitly allowed.
/// The existing runtime is not connected to this input yet.
final class ConceptDeckEligibility {
  ConceptDeckEligibility({
    required Map<String, Set<String>> actionIdsByConcept,
    required Map<String, Set<String>> zoneIdsByConcept,
  }) : actionIdsByConcept = Map.unmodifiable({
         for (final entry in actionIdsByConcept.entries)
           entry.key: Set<String>.unmodifiable(entry.value),
       }),
       zoneIdsByConcept = Map.unmodifiable({
         for (final entry in zoneIdsByConcept.entries)
           entry.key: Set<String>.unmodifiable(entry.value),
       });

  final Map<String, Set<String>> actionIdsByConcept;
  final Map<String, Set<String>> zoneIdsByConcept;

  bool allowsAction(String conceptId, String actionId) =>
      actionIdsByConcept[conceptId]?.contains(actionId) ?? false;

  bool allowsZone(String conceptId, String zoneId) =>
      zoneIdsByConcept[conceptId]?.contains(zoneId) ?? false;
}

/// One logical stock entry per concept. Variants never get their own quota.
/// Each cycle is initialized explicitly; exhaustion never resets this stock.
final class ConceptDeckStock {
  ConceptDeckStock._(Map<String, int> capacity, Map<String, int> remaining)
    : capacity = Map.unmodifiable(capacity),
      remaining = Map.unmodifiable(remaining);

  factory ConceptDeckStock.startCycle({
    required ConceptCatalog catalog,
    required int initialClothing,
  }) {
    RangeError.checkNotNegative(initialClothing, 'initialClothing');
    final singleClothing = min(2, initialClothing);
    final doubleClothing = (initialClothing - singleClothing + 1) ~/ 2;
    final capacity = <String, int>{
      for (final concept in catalog.concepts)
        concept.id: switch (concept.capacityRule) {
          ConceptCapacityRule.initial_clothing_single => singleClothing,
          ConceptCapacityRule.initial_clothing_double => doubleClothing,
          null =>
            concept.kind == ConceptKind.evolution ? concept.stages.length : 1,
        },
    };
    return ConceptDeckStock._(capacity, capacity);
  }

  /// Restore the saved cycle capacities, never recalculate from current clothes.
  factory ConceptDeckStock.fromJson(JsonMap json) {
    final reader = JsonReader(json, 'ConceptDeckStock');
    reader.only({'schema_version', 'capacity', 'remaining'});
    reader.integer('schema_version', min: 1, max: 1);
    final capacities = reader.child(
      json['capacity'],
      'capacity',
      'ConceptDeckStock',
    );
    final remaining = reader.child(
      json['remaining'],
      'remaining',
      'ConceptDeckStock',
    );
    if (capacities.json.length != remaining.json.length ||
        !capacities.json.keys.toSet().containsAll(remaining.json.keys)) {
      reader.fail(
        'remaining',
        'Remaining counters must match capacity identities',
      );
    }
    final capacity = <String, int>{};
    final available = <String, int>{};
    for (final id in capacities.json.keys) {
      if (id.trim().isEmpty) reader.fail('capacity', 'Empty concept identity');
      capacity[id] = capacities.integer(id, min: 0);
      available[id] = remaining.integer(id, min: 0, max: capacity[id]);
    }
    return ConceptDeckStock._(capacity, available);
  }

  final Map<String, int> capacity;
  final Map<String, int> remaining;

  JsonMap toJson() => {
    'schema_version': 1,
    'capacity': capacity,
    'remaining': remaining,
  };

  int remainingFor(String conceptId) {
    final value = remaining[conceptId];
    if (value == null) throw ArgumentError.value(conceptId, 'conceptId');
    return value;
  }

  /// Consume once per actually engaged usage, whatever its gameplay origin.
  /// No stage is consumed; the same stage can be used again within this quota.
  /// Usage identity, reservation and retry deduplication belong to Lot 3.
  ConceptDeckStock consume(String conceptId) {
    final available = remainingFor(conceptId);
    if (available == 0) throw StateError('Concept quota exhausted: $conceptId');
    return ConceptDeckStock._(capacity, {
      ...remaining,
      conceptId: available - 1,
    });
  }
}

/// An available definition/zone, not a selected or committed usage.
final class ConceptDeckChoice {
  const ConceptDeckChoice({
    required this.actionId,
    required this.chili,
    this.zoneId,
  });

  final String actionId;
  final String? zoneId;
  final int chili;
}

final class ConceptDeckCandidate {
  ConceptDeckCandidate({
    required this.concept,
    required this.drawClass,
    required List<ConceptDeckChoice> choices,
  }) : choices = List.unmodifiable(choices);

  final CardConcept concept;
  final int drawClass;
  final List<ConceptDeckChoice> choices;

  ConceptDeckChoice materialize(
    Random random, {
    double Function(ConceptDeckChoice)? weight,
  }) => weight == null
      ? choices[random.nextInt(choices.length)]
      : weightedChoice(choices, random, weight);
}

final class ConceptDeckPool {
  ConceptDeckPool._({
    required Map<int, List<ConceptDeckCandidate>> classes,
    required Map<int, double> probabilities,
  }) : classes = Map.unmodifiable({
         for (final entry in classes.entries)
           entry.key: List<ConceptDeckCandidate>.unmodifiable(entry.value),
       }),
       probabilities = Map.unmodifiable(probabilities);

  final Map<int, List<ConceptDeckCandidate>> classes;
  final Map<int, double> probabilities;
  bool get isEmpty => classes.isEmpty;
  Iterable<ConceptDeckCandidate> get candidates =>
      classes.values.expand((v) => v);

  /// No stage/zone selection, quota consumption or automatic cycle fallback.
  ConceptDeckCandidate? draw(
    Random random, {
    double Function(ConceptDeckCandidate)? preferenceWeight,
  }) {
    if (isEmpty) return null;
    var point = random.nextDouble();
    var selectedClass = classes.keys.last;
    for (final entry in probabilities.entries) {
      if (point < entry.value) {
        selectedClass = entry.key;
        break;
      }
      point -= entry.value;
    }
    final concepts = classes[selectedClass]!;
    return preferenceWeight == null
        ? concepts[random.nextInt(concepts.length)]
        : weightedChoice<ConceptDeckCandidate>(
            concepts,
            random,
            preferenceWeight,
          );
  }
}

T weightedChoice<T>(List<T> items, Random random, double Function(T) weight) {
  final weights = [for (final item in items) weight(item)];
  if (weights.any((w) => !w.isFinite || w <= 0)) {
    throw ArgumentError('Invalid draw weight');
  }
  // Preserve the existing RNG contract when preference makes no distinction.
  if (weights.toSet().length == 1) return items[random.nextInt(items.length)];
  var point = random.nextDouble() * weights.fold<double>(0, (s, w) => s + w);
  for (var i = 0; i < items.length; i++) {
    point -= weights[i];
    if (point < 0) return items[i];
  }
  return items.last;
}

/// Pure concept → class pool. No parallel hybrid decks or 70/30 weighting.
final class ConceptDeckEngine {
  const ConceptDeckEngine();

  static const styleWeights = <PlayerStyle, Map<int, int>>{
    PlayerStyle.SOFT: {1: 45, 2: 40, 3: 13, 4: 2},
    PlayerStyle.EPICE: {1: 20, 2: 40, 3: 30, 4: 10},
    PlayerStyle.INTENABLE: {1: 10, 2: 25, 3: 40, 4: 25},
  };

  ConceptDeckPool prepare({
    required ConceptCatalog catalog,
    required ConceptDeckStock stock,
    required ConceptDeckEligibility eligibility,
    required int globalChili,
    required PlayerStyle style,
    Set<String> unavailableConceptIds = const {},
  }) {
    RangeError.checkValueInInterval(globalChili, 1, 4, 'globalChili');
    final classes = <int, List<ConceptDeckCandidate>>{};
    for (final concept in catalog.concepts) {
      // Quota and current holding/reservation exclusions come first.
      if (stock.remainingFor(concept.id) == 0 ||
          unavailableConceptIds.contains(concept.id)) {
        continue;
      }
      final candidate = candidateFor(
        concept: concept,
        catalog: catalog,
        eligibility: eligibility,
        globalChili: globalChili,
      );
      if (candidate != null) {
        classes.putIfAbsent(candidate.drawClass, () => []).add(candidate);
      }
    }
    // Sort to keep probability intervals stable, independent of catalogue order.
    final ordered = {
      for (final level in [1, 2, 3, 4])
        if (classes.containsKey(level)) level: classes[level]!,
    };
    final weights = styleWeights[style]!;
    final total = ordered.keys.fold<int>(
      0,
      (sum, level) => sum + weights[level]!,
    );
    return ConceptDeckPool._(
      classes: ordered,
      probabilities: {
        for (final level in ordered.keys) level: weights[level]! / total,
      },
    );
  }

  /// Definition/context projection only. Does not create, reserve or spend stock.
  ConceptDeckCandidate? candidateFor({
    required CardConcept concept,
    required ConceptCatalog catalog,
    required ConceptDeckEligibility eligibility,
    required int globalChili,
  }) {
    RangeError.checkValueInInterval(globalChili, 1, 4, 'globalChili');
    final choices = _choices(concept, catalog, eligibility, globalChili);
    if (choices.isEmpty) return null;
    final maximum = choices.map((choice) => choice.chili).reduce(max);
    return ConceptDeckCandidate(
      concept: concept,
      choices: choices,
      drawClass: concept.kind == ConceptKind.zones
          ? max(1, maximum - 1)
          : maximum,
    );
  }

  List<ConceptDeckChoice> _choices(
    CardConcept concept,
    ConceptCatalog catalog,
    ConceptDeckEligibility eligibility,
    int ceiling,
  ) {
    final choices = <ConceptDeckChoice>[];
    void add(String actionId, int chili, [String? zoneId]) {
      if (chili <= ceiling) {
        choices.add(
          ConceptDeckChoice(actionId: actionId, chili: chili, zoneId: zoneId),
        );
      }
    }

    for (final stage in concept.stages) {
      if (eligibility.allowsAction(concept.id, stage.id)) {
        add(stage.id, stage.chili);
      }
    }
    for (final variant in concept.variants) {
      if (!eligibility.allowsAction(concept.id, variant.id)) continue;
      if (concept.kind != ConceptKind.zones) {
        add(variant.id, variant.chili!);
        continue;
      }
      if (variant.freeZone) {
        // Physical choice stays private and unspecified. Retain eligibility,
        // but never infer a concrete zone or apply its modifier to this usage.
        if (catalog.zones.any(
          (zone) => eligibility.allowsZone(concept.id, zone.id),
        )) {
          add(variant.id, concept.intrinsicChili!);
        }
        continue;
      }
      for (final zone in catalog.zones) {
        if (variant.zoneId == zone.id &&
            eligibility.allowsZone(concept.id, zone.id)) {
          add(
            variant.id,
            zone.effectiveChili(concept.intrinsicChili!),
            zone.id,
          );
        }
      }
    }
    return choices;
  }
}
