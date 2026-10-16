import 'dart:math';
import '../../domain/catalog/v4_catalog.dart';

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
