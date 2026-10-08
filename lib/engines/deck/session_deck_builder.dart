import 'dart:math';

import '../../domain/game/balance_config.dart';
import '../../domain/game/game_models.dart';

final class DeckCandidateV3 {
  const DeckCandidateV3({
    required this.cardId,
    required this.variantId,
    required this.spiceLevel,
    required this.distanceExcluded,
    this.stage = 1,
    String? sequenceKey,
    String? occurrenceId,
  }) : sequenceKey = sequenceKey ?? variantId,
       occurrenceId = occurrenceId ?? '$cardId::$variantId';

  final String cardId;
  final String variantId;
  final int spiceLevel;
  final bool distanceExcluded;
  final int stage;
  final String sequenceKey;
  final String occurrenceId;

  String get occurrenceKey => occurrenceId;

  String get contentKey => '$cardId::$variantId';

  DeckCandidateV3 withOccurrence(String value) => DeckCandidateV3(
    cardId: cardId,
    variantId: variantId,
    spiceLevel: spiceLevel,
    distanceExcluded: distanceExcluded,
    stage: stage,
    sequenceKey: sequenceKey,
    occurrenceId: value,
  );
}

/// Persistent progression for one V4 pool rotation.
///
/// Counts are based on unique variants, never on materialized occurrences.
final class V4SpiceProgression {
  V4SpiceProgression({
    required Map<int, int> initialUnitsBySpice,
    Set<String> consumedVariantIds = const {},
    this.unlockedLevel = 1,
  }) : initialUnitsBySpice = Map.unmodifiable({
         for (var level = 1; level <= 4; level++)
           level: initialUnitsBySpice[level] ?? 0,
       }),
       consumedVariantIds = Set.unmodifiable(consumedVariantIds) {
    if (unlockedLevel < 1 || unlockedLevel > 4) {
      throw ArgumentError.value(unlockedLevel, 'unlockedLevel');
    }
  }

  factory V4SpiceProgression.fromCandidates(
    Iterable<DeckCandidateV3> candidates, {
    int unlockedLevel = 1,
  }) {
    final unique = <String, DeckCandidateV3>{
      for (final candidate in candidates) candidate.variantId: candidate,
    };
    return V4SpiceProgression(
      initialUnitsBySpice: {
        for (var level = 1; level <= 4; level++)
          level: unique.values
              .where((candidate) => candidate.spiceLevel == level)
              .length,
      },
      unlockedLevel: unlockedLevel,
    );
  }

  final Map<int, int> initialUnitsBySpice;
  final Set<String> consumedVariantIds;
  final int unlockedLevel;

  int initialUnits(int level) => initialUnitsBySpice[level] ?? 0;

  int remainingUnits(int level, Iterable<DeckCandidateV3> candidates) {
    final variants = <String>{};
    for (final candidate in candidates) {
      if (candidate.spiceLevel == level &&
          !consumedVariantIds.contains(candidate.variantId)) {
        variants.add(candidate.variantId);
      }
    }
    return variants.length;
  }

  double? remainingRatio(int level, Iterable<DeckCandidateV3> candidates) {
    final initial = initialUnits(level);
    if (initial == 0) return null;
    return remainingUnits(level, candidates) / initial;
  }

  bool isPlayable(int effectiveSpice) => effectiveSpice <= unlockedLevel;

  V4SpiceProgression consume(
    String variantId,
    Iterable<DeckCandidateV3> candidates,
  ) {
    if (consumedVariantIds.contains(variantId) ||
        !candidates.any((candidate) => candidate.variantId == variantId)) {
      return this;
    }
    final consumed = {...consumedVariantIds, variantId};
    var level = unlockedLevel;
    while (level < 4 && _canUnlock(level, level + 1, candidates, consumed)) {
      level++;
    }
    return V4SpiceProgression(
      initialUnitsBySpice: initialUnitsBySpice,
      consumedVariantIds: consumed,
      unlockedLevel: level,
    );
  }

  bool _canUnlock(
    int current,
    int next,
    Iterable<DeckCandidateV3> candidates,
    Set<String> consumed,
  ) {
    final currentInitial = initialUnits(current);
    final nextInitial = initialUnits(next);
    if (nextInitial == 0) return false;
    if (currentInitial == 0) return true;
    var currentRemaining = 0;
    var nextRemaining = 0;
    final seen = <String>{};
    for (final candidate in candidates) {
      if (!seen.add(candidate.variantId) ||
          consumed.contains(candidate.variantId)) {
        continue;
      }
      if (candidate.spiceLevel == current) currentRemaining++;
      if (candidate.spiceLevel == next) nextRemaining++;
    }
    // Exact fraction comparison avoids rounding percentages.
    return currentRemaining * nextInitial < nextRemaining * currentInitial;
  }
}

final class V4HandGenerationResult {
  V4HandGenerationResult({
    required List<DeckCandidateV3> hand,
    required List<DeckCandidateV3> drawn,
    required List<DeckCandidateV3> remainingPool,
  }) : hand = List.unmodifiable(hand),
       drawn = List.unmodifiable(drawn),
       remainingPool = List.unmodifiable(remainingPool);

  final List<DeckCandidateV3> hand;
  final List<DeckCandidateV3> drawn;
  final List<DeckCandidateV3> remainingPool;
}

/// V4 generation policy layered on the existing session deck candidates.
/// Distribution deliberately does not inspect the unlocked spice level.
final class V4HandGenerator {
  const V4HandGenerator({this.config = const BalanceConfig()});

  final BalanceConfig config;

  Set<int> guaranteedSpices(PlayerStyle style) => switch (style) {
    PlayerStyle.SOFT => const {1, 2},
    PlayerStyle.EPICE => const {2, 3},
    PlayerStyle.INTENABLE => const {3, 4},
  };

  V4HandGenerationResult refill({
    required Iterable<DeckCandidateV3> currentHand,
    required Iterable<DeckCandidateV3> pool,
    required Iterable<DeckCandidateV3> allCandidates,
    required V4SpiceProgression progression,
    required PlayerStyle style,
    required Random random,
    HybridDeckOrientation? orientation,
    int? targetSize,
  }) {
    final target = targetSize ?? config.handSize;
    final hand = currentHand.toList();
    final remaining = pool.toList();
    final drawn = <DeckCandidateV3>[];
    final guarantee = guaranteedSpices(style);
    var guaranteeSatisfied = hand.any(
      (candidate) => guarantee.contains(candidate.spiceLevel),
    );
    var playableSatisfied = hand.any(
      (candidate) => progression.isPlayable(candidate.spiceLevel),
    );

    while (hand.length < target) {
      final available = _available(
        pool: remaining,
        allCandidates: allCandidates,
        progression: progression,
        handCardIds: hand.map((candidate) => candidate.cardId).toSet(),
      );
      if (available.isEmpty) break;
      final guaranteed = guaranteeSatisfied
          ? const <DeckCandidateV3>[]
          : available
                .where((candidate) => guarantee.contains(candidate.spiceLevel))
                .toList();
      final playable = playableSatisfied
          ? const <DeckCandidateV3>[]
          : available
                .where(
                  (candidate) => progression.isPlayable(candidate.spiceLevel),
                )
                .toList();
      final preferred = guaranteed.isNotEmpty
          ? guaranteed
          : playable.isNotEmpty
          ? playable
          : available;
      final choice = _weightedChoice(preferred, style, random, orientation);
      hand.add(choice);
      drawn.add(choice);
      if (guarantee.contains(choice.spiceLevel)) guaranteeSatisfied = true;
      if (progression.isPlayable(choice.spiceLevel)) {
        playableSatisfied = true;
      }
      remaining.removeWhere(
        (candidate) => candidate.variantId == choice.variantId,
      );
    }
    return V4HandGenerationResult(
      hand: hand,
      drawn: drawn,
      remainingPool: remaining,
    );
  }

  List<DeckCandidateV3> _available({
    required List<DeckCandidateV3> pool,
    required Iterable<DeckCandidateV3> allCandidates,
    required V4SpiceProgression progression,
    required Set<String> handCardIds,
  }) {
    final lowestBySequence = <String, int>{};
    for (final candidate in allCandidates) {
      if (progression.consumedVariantIds.contains(candidate.variantId)) {
        continue;
      }
      lowestBySequence.update(
        candidate.sequenceKey,
        (stage) => min(stage, candidate.stage),
        ifAbsent: () => candidate.stage,
      );
    }
    final unique = <String, DeckCandidateV3>{};
    for (final candidate in pool) {
      if (progression.consumedVariantIds.contains(candidate.variantId) ||
          handCardIds.contains(candidate.cardId) ||
          lowestBySequence[candidate.sequenceKey] != candidate.stage) {
        continue;
      }
      unique.putIfAbsent(candidate.variantId, () => candidate);
    }
    return unique.values.toList();
  }

  DeckCandidateV3 _weightedChoice(
    List<DeckCandidateV3> candidates,
    PlayerStyle style,
    Random random,
    HybridDeckOrientation? orientation,
  ) {
    final weights = config.styleDistributions[style]!;
    final physicalCount = candidates
        .where((candidate) => candidate.distanceExcluded)
        .length;
    final remoteCount = candidates.length - physicalCount;
    double weight(DeckCandidateV3 candidate) {
      final spice = weights[candidate.spiceLevel] ?? 0;
      if (orientation == null || physicalCount == 0 || remoteCount == 0) {
        return spice;
      }
      final physicalShare = orientation == HybridDeckOrientation.faceToFace
          ? .70
          : .30;
      final groupWeight = candidate.distanceExcluded
          ? physicalShare / physicalCount
          : (1 - physicalShare) / remoteCount;
      return spice * groupWeight;
    }

    final total = candidates.fold<double>(
      0,
      (sum, candidate) => sum + weight(candidate),
    );
    if (total <= 0) return candidates[random.nextInt(candidates.length)];
    var cursor = random.nextDouble() * total;
    for (final candidate in candidates) {
      cursor -= weight(candidate);
      if (cursor < 0) return candidate;
    }
    return candidates.last;
  }
}

final class DeckSubstitution {
  const DeckSubstitution({
    required this.requestedSpice,
    required this.actualSpice,
    required this.count,
  });
  final int requestedSpice;
  final int actualSpice;
  final int count;
}

final class DeckShortage {
  DeckShortage({
    required this.requestedSpice,
    required this.requestedCount,
    required this.availableCount,
    required this.missingCount,
    required Map<int, int> replacementsBySpice,
  }) : replacementsBySpice = Map.unmodifiable(replacementsBySpice);

  final int requestedSpice;
  final int requestedCount;
  final int availableCount;
  final int missingCount;
  final Map<int, int> replacementsBySpice;
}

final class SessionDeckBuildResult {
  SessionDeckBuildResult({
    required List<DeckCandidateV3> cards,
    required List<DeckSubstitution> substitutions,
    List<DeckShortage> shortages = const [],
  }) : cards = List.unmodifiable(cards),
       substitutions = List.unmodifiable(substitutions),
       shortages = List.unmodifiable(shortages);
  final List<DeckCandidateV3> cards;
  final List<DeckSubstitution> substitutions;
  final List<DeckShortage> shortages;
  bool get adjusted => substitutions.isNotEmpty;
}

/// Builds the eligible session deck. Selection inside a finished deck is left
/// to [SessionDeckRuntime], which performs an unbiased random draw.
final class SessionDeckBuilderV3 {
  const SessionDeckBuilderV3();

  SessionDeckBuildResult build({
    required Iterable<DeckCandidateV3> eligible,
    required Map<int, int> targetBySpice,
    required PlayerStyle style,
  }) {
    final pool = eligible.toList(growable: false);
    final result = <DeckCandidateV3>[];
    final substitutions = <(int, int)>[];
    final missingByRequested = <int, int>{};
    final availableByLevel = <int, int>{
      for (var level = 1; level <= 5; level++)
        level: pool.where((card) => card.spiceLevel == level).length,
    };
    for (final entry
        in targetBySpice.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key))) {
      final requested = entry.key;
      final group = pool.where((card) => card.spiceLevel == requested).toList();
      final levels = _fallbackLevels(requested, style);
      for (var slot = 0; slot < entry.value; slot++) {
        DeckCandidateV3? chosen = _chooseForSlot(
          group,
          result,
          requested,
          entry.value,
        );
        if (chosen == null) {
          missingByRequested[requested] =
              (missingByRequested[requested] ?? 0) + 1;
          for (final level in levels) {
            final fallback = pool
                .where((card) => card.spiceLevel == level)
                .toList();
            chosen = _chooseForSlot(fallback, result, level, entry.value);
            if (chosen != null) {
              substitutions.add((requested, level));
              break;
            }
          }
        }
        if (chosen == null) break;
        result.add(chosen);
      }
    }
    final grouped = <String, int>{};
    for (final item in substitutions) {
      grouped['${item.$1}:${item.$2}'] =
          (grouped['${item.$1}:${item.$2}'] ?? 0) + 1;
    }
    final occurrences = <String, int>{};
    final materialized = <DeckCandidateV3>[];
    for (final card in result) {
      final ordinal = (occurrences[card.contentKey] ?? 0) + 1;
      occurrences[card.contentKey] = ordinal;
      materialized.add(card.withOccurrence('${card.contentKey}::$ordinal'));
    }
    final substitutionsByRequested = <int, Map<int, int>>{};
    for (final item in substitutions) {
      final byActual = substitutionsByRequested.putIfAbsent(item.$1, () => {});
      byActual[item.$2] = (byActual[item.$2] ?? 0) + 1;
    }
    return SessionDeckBuildResult(
      cards: materialized,
      substitutions: [
        for (final entry in grouped.entries)
          DeckSubstitution(
            requestedSpice: int.parse(entry.key.split(':')[0]),
            actualSpice: int.parse(entry.key.split(':')[1]),
            count: entry.value,
          ),
      ],
      shortages: [
        for (final entry in targetBySpice.entries)
          if ((missingByRequested[entry.key] ?? 0) > 0)
            DeckShortage(
              requestedSpice: entry.key,
              requestedCount: entry.value,
              availableCount: availableByLevel[entry.key] ?? 0,
              missingCount: missingByRequested[entry.key]!,
              replacementsBySpice:
                  substitutionsByRequested[entry.key] ?? const {},
            ),
      ],
    );
  }

  DeckCandidateV3? _chooseForSlot(
    List<DeckCandidateV3> group,
    List<DeckCandidateV3> result,
    int requestedSpice,
    int targetSlots,
  ) {
    if (group.isEmpty) return null;
    final sameTarget = result.where(
      (card) => card.spiceLevel == requestedSpice,
    );
    final counts = <String, int>{};
    for (final card in sameTarget) {
      counts[card.contentKey] = (counts[card.contentKey] ?? 0) + 1;
    }
    final distinct = group.where(
      (card) => !counts.containsKey(card.contentKey),
    );
    if (distinct.isNotEmpty) return distinct.first;
    for (final card in group) {
      final next = (counts[card.contentKey] ?? 0) + 1;
      if (next * 2 < targetSlots) return card;
    }
    return null;
  }

  List<int> _fallbackLevels(int requested, PlayerStyle style) {
    final higher = [for (var i = requested + 1; i <= 5; i++) i];
    final lower = [for (var i = requested - 1; i >= 1; i--) i];
    return style == PlayerStyle.SOFT
        ? [...lower, ...higher]
        : [...higher, ...lower];
  }
}

enum HybridDeckOrientation { faceToFace, distance }

final class HybridSessionDecks {
  HybridSessionDecks({required List<DeckCandidateV3> source})
    : faceToFace = _compose(source, physicalShare: 0.70),
      distance = _compose(source, physicalShare: 0.30);

  final List<DeckCandidateV3> faceToFace;
  final List<DeckCandidateV3> distance;

  static List<DeckCandidateV3> _compose(
    List<DeckCandidateV3> source, {
    required double physicalShare,
  }) {
    final physical = source.where((card) => card.distanceExcluded).toList();
    final remote = source.where((card) => !card.distanceExcluded).toList();
    if (physical.isEmpty || remote.isEmpty) return List.of(source);
    final size = source.length;
    final physicalCount = (size * physicalShare).round();
    final selected = [
      ..._repeatTo(physical, physicalCount),
      ..._repeatTo(remote, size - physicalCount),
    ];
    final ordinals = <String, int>{};
    return [
      for (final card in selected)
        card.withOccurrence(
          '${card.contentKey}::${ordinals.update(card.contentKey, (value) => value + 1, ifAbsent: () => 1)}',
        ),
    ];
  }

  static List<DeckCandidateV3> _repeatTo(
    List<DeckCandidateV3> values,
    int count,
  ) => [for (var i = 0; i < count; i++) values[i % values.length]];
}

final class SessionDeckRuntime {
  SessionDeckRuntime({
    required List<DeckCandidateV3> faceToFace,
    required List<DeckCandidateV3> distance,
    Random? random,
  }) : faceToFace = List.of(faceToFace),
       distance = List.of(distance),
       _random = random ?? Random.secure();

  final List<DeckCandidateV3> faceToFace;
  final List<DeckCandidateV3> distance;
  final Random _random;

  DeckCandidateV3? draw(
    HybridDeckOrientation orientation, {
    Set<String> avoidCardIds = const {},
  }) {
    var active = orientation == HybridDeckOrientation.faceToFace
        ? faceToFace
        : distance;
    var other = orientation == HybridDeckOrientation.faceToFace
        ? distance
        : faceToFace;
    if (active.isEmpty && other.isNotEmpty) {
      final fallback = active;
      active = other;
      other = fallback;
    }
    if (active.isEmpty) return null;
    final allowedIndexes = [
      for (var index = 0; index < active.length; index++)
        if (!avoidCardIds.contains(active[index].cardId)) index,
    ];
    final candidates = allowedIndexes.isEmpty
        ? [for (var index = 0; index < active.length; index++) index]
        : allowedIndexes;
    final drawn = active.removeAt(
      candidates[_random.nextInt(candidates.length)],
    );
    final mirror = other.indexWhere(
      (candidate) => candidate.occurrenceId == drawn.occurrenceId,
    );
    if (mirror >= 0) other.removeAt(mirror);
    return drawn;
  }
}

enum DeckExhaustionChoice {
  continueSpicier,
  continueIntenable,
  infinite,
  newCustomizedGame,
  finish,
}

final class DeckCycleState {
  const DeckCycleState({
    required this.style,
    this.infinite = false,
    this.recentOccurrenceKeys = const [],
  });
  final PlayerStyle style;
  final bool infinite;
  final List<String> recentOccurrenceKeys;

  DeckCycleState next(DeckExhaustionChoice choice) => switch (choice) {
    DeckExhaustionChoice.continueSpicier => DeckCycleState(
      style: style == PlayerStyle.SOFT
          ? PlayerStyle.EPICE
          : PlayerStyle.INTENABLE,
      recentOccurrenceKeys: recentOccurrenceKeys,
    ),
    DeckExhaustionChoice.continueIntenable => DeckCycleState(
      style: PlayerStyle.INTENABLE,
      recentOccurrenceKeys: recentOccurrenceKeys,
    ),
    DeckExhaustionChoice.infinite => DeckCycleState(
      style: style,
      infinite: true,
      recentOccurrenceKeys: recentOccurrenceKeys,
    ),
    DeckExhaustionChoice.newCustomizedGame ||
    DeckExhaustionChoice.finish => this,
  };

  List<DeckCandidateV3> avoidImmediateRepeat(List<DeckCandidateV3> deck) {
    final recent = recentOccurrenceKeys.toSet();
    return [
      ...deck.where((card) => !recent.contains(card.occurrenceKey)),
      ...deck.where((card) => recent.contains(card.occurrenceKey)),
    ];
  }
}
