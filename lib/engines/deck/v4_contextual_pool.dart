import 'dart:math';

import '../../domain/catalog/v4_catalog.dart';
import 'session_deck_builder.dart';

final class V4PoolContext {
  const V4PoolContext({
    required this.presence,
    this.availableAccessories = const {},
    this.excludedCardIds = const {},
    this.excludedVariantIds = const {},
  });

  final V4SessionPresence presence;
  final Set<String> availableAccessories;
  final Set<String> excludedCardIds;
  final Set<String> excludedVariantIds;
}

final class V4ContextualPoolSnapshot {
  const V4ContextualPoolSnapshot({
    required this.globalRemaining,
    required this.active,
    required this.drawable,
  });

  final List<DeckCandidateV3> globalRemaining;
  final List<DeckCandidateV3> active;
  final List<DeckCandidateV3> drawable;
}

/// Pure projection of the persistent global cycle into the current context.
/// It never mutates progression and never looks at PA values.
final class V4ContextualPool {
  const V4ContextualPool();

  V4ContextualPoolSnapshot project({
    required Iterable<DeckCandidateV3> allCandidates,
    required V4SpiceProgression progression,
    required V4PoolContext context,
    Set<String> inHandOccurrenceIds = const {},
  }) {
    final global = <String, DeckCandidateV3>{
      for (final candidate in allCandidates)
        if (!progression.consumedOccurrenceIds.contains(candidate.occurrenceId))
          candidate.occurrenceId: candidate,
    }.values.toList(growable: false);

    // A later stage never bypasses an unconsumed lower stage, even when the
    // lower stage is temporarily incompatible with the current context.
    final lowestBySequence = <String, int>{};
    for (final candidate in global) {
      lowestBySequence.update(
        candidate.sequenceKey,
        (value) => min(value, candidate.stage),
        ifAbsent: () => candidate.stage,
      );
    }
    final active = [
      for (final candidate in global)
        if (lowestBySequence[candidate.sequenceKey] == candidate.stage &&
            _eligible(candidate, context))
          candidate,
    ];
    return V4ContextualPoolSnapshot(
      globalRemaining: global,
      active: active,
      drawable: [
        for (final candidate in active)
          if (!inHandOccurrenceIds.contains(candidate.occurrenceId)) candidate,
      ],
    );
  }

  bool isContextuallyEligible(
    DeckCandidateV3 candidate,
    V4PoolContext context,
  ) => _eligible(candidate, context);

  bool _eligible(DeckCandidateV3 candidate, V4PoolContext context) {
    if (!candidate.presence.supports(context.presence) ||
        context.excludedCardIds.contains(candidate.cardId) ||
        context.excludedVariantIds.contains(candidate.variantId)) {
      return false;
    }
    final required = candidate.requiredAccessoriesAnyOf;
    return required.isEmpty ||
        required.any(context.availableAccessories.contains);
  }
}

/// Materializes only the deliberate V4 multiplicities. Standard units retain
/// one stable occurrence. Clothing capacity uses two one-item occurrences for
/// granularity, then the minimum number of two-item occurrences needed to
/// cover the remaining removable clothing.
final class V4PoolMaterializer {
  const V4PoolMaterializer();

  List<DeckCandidateV3> materialize({
    required Iterable<DeckCandidateV3> candidates,
    required int totalRemovableClothing,
  }) {
    final total = max(0, totalRemovableClothing);
    final oneCount = min(2, total);
    final twoCount = ((total - oneCount) / 2).ceil();
    return [
      for (final candidate in candidates)
        ..._copies(candidate, switch (candidate.poolMultiplicity) {
          V4PoolMultiplicity.standard => 1,
          V4PoolMultiplicity.removableClothingOne => oneCount,
          V4PoolMultiplicity.removableClothingTwo => twoCount,
        }),
    ];
  }

  Iterable<DeckCandidateV3> _copies(
    DeckCandidateV3 candidate,
    int count,
  ) sync* {
    for (var index = 1; index <= count; index++) {
      yield candidate.withOccurrence('${candidate.contentKey}::occ-$index');
    }
  }
}

enum V4ClothingState { habille, sousVetements, nu }

final class V4ClothingSnapshot {
  const V4ClothingSnapshot({
    required this.state,
    required this.removableClothing,
  }) : assert(removableClothing >= 0);

  final V4ClothingState state;
  final int removableClothing;
}

/// Small deterministic clothing transition model. Cards 006/007 remove from
/// the current count cumulatively. Cards 008..011 reset to a complete outfit
/// before applying their action. Cards 012/013 accept the players' outcome.
final class V4ClothingEngine {
  const V4ClothingEngine();

  V4ClothingSnapshot apply({
    required V4ClothingSnapshot current,
    required V4ClothingBehavior behavior,
    required int fullOutfitCount,
    V4ClothingSnapshot? chosenOutcome,
  }) {
    final full = max(2, fullOutfitCount);
    return switch (behavior) {
      V4ClothingBehavior.none => current,
      V4ClothingBehavior.removeOne => _fromCount(
        max(0, current.removableClothing - 1),
      ),
      V4ClothingBehavior.removeTwo => _fromCount(
        max(0, current.removableClothing - 2),
      ),
      V4ClothingBehavior.resetThenUnderwear => const V4ClothingSnapshot(
        state: V4ClothingState.sousVetements,
        removableClothing: 1,
      ),
      V4ClothingBehavior.resetThenNude ||
      V4ClothingBehavior.resetThenStripComplete => const V4ClothingSnapshot(
        state: V4ClothingState.nu,
        removableClothing: 0,
      ),
      V4ClothingBehavior.resetThenStrip => _fromCount(max(0, full - 1)),
      V4ClothingBehavior.chooseOutfit || V4ClothingBehavior.changeOutfit =>
        chosenOutcome ??
            (throw ArgumentError('A chosen clothing outcome is required')),
    };
  }

  V4ClothingSnapshot _fromCount(int count) => V4ClothingSnapshot(
    state: count == 0 ? V4ClothingState.nu : V4ClothingState.habille,
    removableClothing: max(0, count),
  );
}
