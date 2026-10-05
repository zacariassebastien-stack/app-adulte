import 'dart:math';

import '../../domain/game/game_models.dart';

final class DeckCandidateV3 {
  const DeckCandidateV3({
    required this.cardId,
    required this.variantId,
    required this.spiceLevel,
    required this.distanceExcluded,
    String? occurrenceId,
  }) : occurrenceId = occurrenceId ?? '$cardId::$variantId';

  final String cardId;
  final String variantId;
  final int spiceLevel;
  final bool distanceExcluded;
  final String occurrenceId;

  String get occurrenceKey => occurrenceId;

  String get contentKey => '$cardId::$variantId';

  DeckCandidateV3 withOccurrence(String value) => DeckCandidateV3(
    cardId: cardId,
    variantId: variantId,
    spiceLevel: spiceLevel,
    distanceExcluded: distanceExcluded,
    occurrenceId: value,
  );
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
