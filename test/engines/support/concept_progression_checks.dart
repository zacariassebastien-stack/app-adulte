import 'dart:convert';
import 'dart:io';
import '../../../lib/domain/catalog/concept_catalog.dart';
import '../../../lib/engines/deck/concept_deck_engine.dart';
import '../../../lib/engines/deck/concept_spice_progression.dart';

Map<String, void Function()> conceptProgressionChecks() {
  ConceptCatalog catalog(Set<String> ids) {
    final document =
        jsonDecode(
              File('assets/catalog/concepts/active.fr.json').readAsStringSync(),
            )
            as Map<String, Object?>;
    return ConceptCatalog.fromJson({
      ...document,
      'concepts': [
        for (final raw in document['concepts']! as List)
          if (ids.contains((raw as Map)['concept_id'] ?? raw['id'])) raw,
      ],
    });
  }

  Iterable<ConceptDeckCandidate> project(ConceptCatalog c, int ceiling) {
    final eligibility = ConceptDeckEligibility(
      actionIdsByConcept: {
        for (final concept in c.concepts)
          concept.id: {
            ...concept.stages.map((s) => s.id),
            ...concept.variants.map((v) => v.id),
          },
      },
      zoneIdsByConcept: {
        for (final concept in c.concepts)
          concept.id: c.zones.map((z) => z.id).toSet(),
      },
    );
    return [
      for (final concept in c.concepts)
        if (const ConceptDeckEngine().candidateFor(
              concept: concept,
              catalog: c,
              eligibility: eligibility,
              globalChili: ceiling,
            )
            case final candidate?)
          candidate,
    ];
  }

  int level(ConceptCatalog c, ConceptDeckStock stock, [int current = 1]) =>
      const ConceptSpiceProgression().unlockedLevel(
        currentLevel: current,
        stock: stock,
        project: (ceiling) => project(c, ceiling),
      );
  void check(bool value, String message) {
    if (!value) throw StateError(message);
  }

  return {
    'equal remaining fractions do not unlock': () {
      final c = catalog({'001', '003'});
      final stock = ConceptDeckStock.startCycle(catalog: c, initialClothing: 0);
      check(c.concepts.length == 2, 'Fixture selection failed');
      check(level(c, stock) == 1, 'Equality must not unlock');
    },
    'virtual next ceiling unlocks without restoring or consuming capacity': () {
      final c = catalog({'001', '003'});
      final stock = ConceptDeckStock.startCycle(
        catalog: c,
        initialClothing: 0,
      ).consume('001');
      final before = jsonEncode(stock.toJson());
      check(
        level(c, stock) == 2,
        'Current remaining fraction should unlock next',
      );
      check(jsonEncode(stock.toJson()) == before, 'Projection mutated quotas');
      check(
        project(
          c,
          1,
        ).every((x) => x.choices.every((choice) => choice.chili <= 1)),
        'Virtual stage leaked into real choices',
      );
    },
    'same conceptual capacity participates in both projections without stage copies':
        () {
          final c = catalog({'001', '003'});
          final stock = ConceptDeckStock.startCycle(
            catalog: c,
            initialClothing: 0,
          ).consume('003');
          check(level(c, stock) == 1, '3/4 is not below 2/3');
          check(
            project(c, 1).length == 2 && project(c, 2).length == 2,
            'Stage duplication',
          );
          check(
            stock.remainingFor('003') == stock.capacity['003']! - 1,
            'Stage acquired a separate quota',
          );
        },
    'missing next stock blocks and empty current stock preserves V4 transition':
        () {
          final c = catalog({'019'});
          final stock = ConceptDeckStock.startCycle(
            catalog: c,
            initialClothing: 0,
          );
          check(level(c, stock) == 1, 'No class 2 must block');
          check(
            level(c, stock, 2) == 3,
            'Empty class 2 should unlock available class 3',
          );
        },
    'free zone classification uses the same minus-one policy in virtual projection':
        () {
          final c = catalog({'005'});
          check(
            project(c, 2).single.drawClass == 1,
            'Wrong current free-zone class',
          );
          check(
            project(c, 3).single.drawClass == 2,
            'Wrong projected free-zone class',
          );
          check(
            project(c, 3).single.choices.any((x) => x.chili == 3),
            'Draw discount changed real spice',
          );
        },
  };
}
