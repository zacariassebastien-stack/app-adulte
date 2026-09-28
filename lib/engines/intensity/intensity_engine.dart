import '../../domain/game/balance_config.dart';

final class IntensityState {
  const IntensityState({
    required this.active,
    required this.unlocked,
    required this.maximum,
  });
  final int active;
  final int unlocked;
  final int maximum;
}

final class IntensityChange {
  const IntensityChange({
    required this.state,
    required this.actionPoints,
    required this.cost,
  });
  final IntensityState state;
  final Map<String, int> actionPoints;
  final int cost;
}

final class IntensityEngine {
  const IntensityEngine({this.config = const BalanceConfig()});
  final BalanceConfig config;

  int unlockCost(IntensityState state, int target) {
    if (target <= state.unlocked) return 0;
    return [
      for (var level = state.unlocked + 1; level <= target; level++)
        config.chiliUnlockCosts[level] ?? 0,
    ].fold(0, (sum, value) => sum + value);
  }

  IntensityChange change({
    required IntensityState state,
    required int target,
    required bool mutualAgreement,
    required Map<String, int> actionPoints,
    Map<String, int> payments = const {},
  }) {
    if (!mutualAgreement) throw StateError('Mutual agreement is required');
    if (target < 1 || target > 5 || target > state.maximum) {
      throw ArgumentError(
        'Target intensity is outside the agreed session range',
      );
    }
    final cost = unlockCost(state, target);
    if (payments.values.fold(0, (sum, value) => sum + value) != cost) {
      throw ArgumentError('Payments must exactly cover the unlock cost');
    }
    final points = Map<String, int>.from(actionPoints);
    for (final entry in payments.entries) {
      final current = points[entry.key] ?? 0;
      if (entry.value < 0 || entry.value > current) {
        throw StateError('Intensity payment would create PA debt');
      }
      points[entry.key] = current - entry.value;
    }
    return IntensityChange(
      state: IntensityState(
        active: target,
        unlocked: target > state.unlocked ? target : state.unlocked,
        maximum: state.maximum,
      ),
      actionPoints: Map.unmodifiable(points),
      cost: cost,
    );
  }
}
