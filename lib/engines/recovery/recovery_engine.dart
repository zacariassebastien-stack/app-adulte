import '../../domain/catalog/enums.dart';
import '../../domain/game/balance_config.dart';
import '../../domain/game/events.dart';
import '../../domain/game/game_models.dart';
import '../eligibility/eligibility_engine.dart';
import '../lifecycle/lifecycle_engine.dart';

// ignore_for_file: constant_identifier_names
enum RecoveryResponse { ACCEPT, ACCEPT_WITH_ONE_DISCARD_CONDITION, REFUSE }

enum RecoverySource { HAND, DISCARD, CATALOG }

final class RecoveryGate {
  const RecoveryGate({
    required this.betweenRounds,
    required this.usedSinceLastNormalDuel,
  });
  final bool betweenRounds;
  final bool usedSinceLastNormalDuel;
}

final class RecoveryActionResult {
  const RecoveryActionResult({
    required this.actionPoints,
    required this.gain,
    required this.events,
  });
  final int actionPoints;
  final int gain;
  final List<GameEvent> events;
}

final class RecoveryEngine {
  const RecoveryEngine({
    this.config = const BalanceConfig(),
    this.eligibility = const EligibilityEngine(),
    this.lifecycle = const LifecycleEngine(),
  });
  final BalanceConfig config;
  final EligibilityEngine eligibility;
  final LifecycleEngine lifecycle;

  bool available({required int currentPa, required RecoveryGate gate}) =>
      gate.betweenRounds &&
      !gate.usedSinceLastNormalDuel &&
      currentPa <= config.initialPa * config.recoveryThreshold;

  CardEligibility actionEligibility({
    required EngineCard card,
    required EngineSessionContext context,
    required PlayerGameProfile actor,
    required PlayerGameProfile partner,
    required ProfileHierarchy hierarchy,
  }) => eligibility.evaluate(
    card: card,
    context: context,
    actor: actor,
    partner: partner,
    hierarchy: hierarchy,
    recovery: true,
  );

  RecoveryActionResult resolve({
    required int currentPa,
    required RecoveryResponse response,
    required List<
      (PreferenceValue preference, ProfileRole role, bool completed)
    >
    performedRoles,
    int conditionCount = 0,
  }) {
    if (response == RecoveryResponse.ACCEPT_WITH_ONE_DISCARD_CONDITION &&
        conditionCount != 1) {
      throw ArgumentError('Exactly one discard condition is required');
    }
    if (response != RecoveryResponse.ACCEPT_WITH_ONE_DISCARD_CONDITION &&
        conditionCount != 0) {
      throw ArgumentError('Discard condition is not allowed for this response');
    }
    if (response == RecoveryResponse.REFUSE) {
      return RecoveryActionResult(
        actionPoints: currentPa,
        gain: 0,
        events: const [],
      );
    }
    var gain = 0;
    for (final item in performedRoles) {
      if (item.$3) gain += item.$1.valueFor(item.$2) ?? 0;
    }
    return RecoveryActionResult(
      actionPoints: currentPa + gain,
      gain: gain,
      events: [
        if (gain > 0) GameEvent(GameEventType.STATE_UPDATED, {'pa_gain': gain}),
      ],
    );
  }

  List<CardRuntimeState> applyLifecycle({
    required List<CardRuntimeState> cards,
    required String cardId,
    required RecoverySource source,
    required bool completed,
  }) {
    if (!completed || source == RecoverySource.CATALOG) return cards;
    if (source == RecoverySource.DISCARD) {
      return lifecycle.exhaustDiscardAction(
        cards,
        cardId,
        actuallyCompleted: true,
      );
    }
    return lifecycle.closeRound(lifecycle.engage(cards, cardId));
  }

  RecoveryGate afterRecovery(RecoveryGate gate) => RecoveryGate(
    betweenRounds: gate.betweenRounds,
    usedSinceLastNormalDuel: true,
  );

  RecoveryGate afterNormalDuel() =>
      const RecoveryGate(betweenRounds: true, usedSinceLastNormalDuel: false);

  ({Map<String, int> actionPoints, GameEvent event}) mutualExtension({
    required Map<String, int> actionPoints,
    required int amount,
    required bool mutualAgreement,
  }) {
    if (!mutualAgreement) throw StateError('Mutual agreement is required');
    if (amount < 0) throw ArgumentError.value(amount, 'amount');
    return (
      actionPoints: Map.unmodifiable({
        for (final entry in actionPoints.entries)
          entry.key: entry.value + amount,
      }),
      event: GameEvent(GameEventType.MUTUAL_PA_EXTENSION, {'amount': amount}),
    );
  }
}
