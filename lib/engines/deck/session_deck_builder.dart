import 'dart:math';

import '../../domain/game/game_models.dart';

final class DeckCandidateV3 {
  const DeckCandidateV3({
    required this.cardId,
    required this.variantId,
    required this.spiceLevel,
    required this.distanceExcluded,
  });

  final String cardId;
  final String variantId;
  final int spiceLevel;
  final bool distanceExcluded;

  String get occurrenceKey => '$cardId::$variantId';
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

final class SessionDeckBuildResult {
  SessionDeckBuildResult({
    required List<DeckCandidateV3> cards,
    required List<DeckSubstitution> substitutions,
  }) : cards = List.unmodifiable(cards),
       substitutions = List.unmodifiable(substitutions);
  final List<DeckCandidateV3> cards;
  final List<DeckSubstitution> substitutions;
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
    return SessionDeckBuildResult(
      cards: result,
      substitutions: [
        for (final entry in grouped.entries)
          DeckSubstitution(
            requestedSpice: int.parse(entry.key.split(':')[0]),
            actualSpice: int.parse(entry.key.split(':')[1]),
            count: entry.value,
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
      counts[card.cardId] = (counts[card.cardId] ?? 0) + 1;
    }
    final distinct = group.where((card) => !counts.containsKey(card.cardId));
    if (distinct.isNotEmpty) return distinct.first;
    for (final card in group) {
      final next = (counts[card.cardId] ?? 0) + 1;
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
    return [
      ..._repeatTo(physical, physicalCount),
      ..._repeatTo(remote, size - physicalCount),
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

  DeckCandidateV3? draw(HybridDeckOrientation orientation) {
    final active = orientation == HybridDeckOrientation.faceToFace
        ? faceToFace
        : distance;
    final other = orientation == HybridDeckOrientation.faceToFace
        ? distance
        : faceToFace;
    if (active.isEmpty) return null;
    final drawn = active.removeAt(_random.nextInt(active.length));
    final mirror = other.indexWhere(
      (candidate) => candidate.occurrenceKey == drawn.occurrenceKey,
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
