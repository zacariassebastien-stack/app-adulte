import '../../domain/catalog/enums.dart';
import '../../domain/catalog/requirements.dart';
import '../../domain/game/events.dart';
import '../../domain/game/balance_config.dart';
import '../../domain/game/game_models.dart';
import '../../domain/session/session_state.dart';

// ignore_for_file: constant_identifier_names
enum ActionExecutionStatus { PROPOSED, ACCEPTED, COMPLETED, SKIPPED, STOPPED }

final class LifecycleTransition {
  const LifecycleTransition({required this.cards, required this.events});
  final List<CardRuntimeState> cards;
  final List<GameEvent> events;
}

final class LifecycleEngine {
  const LifecycleEngine({this.config = const BalanceConfig()});
  final BalanceConfig config;

  int refillNeeded(List<CardRuntimeState> cards) {
    final handCount = cards.where((card) => card.zone == CardZone.HAND).length;
    return (config.handSize - handCount).clamp(0, config.handSize);
  }

  bool shouldEndSession({
    required bool explicitHumanDecision,
    required bool technicalClosure,
    required int actionPoints,
    required bool indicativeDurationReached,
  }) => explicitHumanDecision || technicalClosure;

  EngineSessionContext changeProximity(
    EngineSessionContext context,
    ProximityState proximity,
  ) {
    if (context.mode != SessionMode.hybrid) {
      throw StateError('Only HYBRID sessions can switch proximity explicitly');
    }
    return context.copyWith(proximity: proximity);
  }

  EngineSessionContext closeTemporaryMeeting(EngineSessionContext context) =>
      context.copyWith(proximity: ProximityState.SEPARATED);

  List<CardRuntimeState> lock(List<CardRuntimeState> cards, String cardId) {
    final target = cards.where((card) => card.cardId == cardId).firstOrNull;
    if (target == null || target.zone != CardZone.HAND) {
      throw StateError('Only a card in HAND can be locked');
    }
    return [
      for (final card in cards) card.copyWith(locked: card.cardId == cardId),
    ];
  }

  List<CardRuntimeState> engage(List<CardRuntimeState> cards, String cardId) =>
      [
        for (final card in cards)
          if (card.cardId == cardId && card.zone == CardZone.HAND)
            card.copyWith(zone: CardZone.ENGAGED, locked: false)
          else
            card,
      ];

  List<CardRuntimeState> closeRound(List<CardRuntimeState> cards) => [
    for (final card in cards)
      if (card.zone == CardZone.ENGAGED)
        card.copyWith(zone: CardZone.DISCARD, locked: false)
      else
        card,
  ];

  GameEvent startRound(String roundId) =>
      GameEvent(GameEventType.ROUND_STARTED, {'round_id': roundId});

  LifecycleTransition closeRoundWithEvents(List<CardRuntimeState> cards) {
    final discarded = cards
        .where((card) => card.zone == CardZone.ENGAGED)
        .map((card) => card.cardId)
        .toList(growable: false);
    return LifecycleTransition(
      cards: closeRound(cards),
      events: [
        for (final cardId in discarded)
          GameEvent(GameEventType.CARD_DISCARDED, {'card_id': cardId}),
        GameEvent(GameEventType.ROUND_CLOSED),
      ],
    );
  }

  GameEvent actionEvent(ActionExecutionStatus status, String cardId) =>
      GameEvent(
        switch (status) {
          ActionExecutionStatus.ACCEPTED => GameEventType.ACTION_ACCEPTED,
          ActionExecutionStatus.COMPLETED => GameEventType.ACTION_COMPLETED,
          ActionExecutionStatus.SKIPPED => GameEventType.ACTION_SKIPPED,
          ActionExecutionStatus.STOPPED => GameEventType.CONSENT_STOP,
          ActionExecutionStatus.PROPOSED => GameEventType.CORRUPTION_PROPOSED,
        },
        {'card_id': cardId},
      );

  List<CardRuntimeState> redrawDiscard(
    List<CardRuntimeState> cards,
    String cardId,
  ) => [
    for (final card in cards)
      if (card.cardId == cardId && card.zone == CardZone.DISCARD)
        card.copyWith(zone: CardZone.HAND, locked: false)
      else
        card,
  ];

  List<CardRuntimeState> exhaustDiscardAction(
    List<CardRuntimeState> cards,
    String cardId, {
    required bool actuallyCompleted,
  }) => [
    for (final card in cards)
      if (card.cardId == cardId &&
          card.zone == CardZone.DISCARD &&
          actuallyCompleted)
        card.copyWith(zone: CardZone.EXHAUSTED, locked: false)
      else
        card,
  ];

  bool canUseForCorruption(CardRuntimeState card) =>
      card.zone == CardZone.DISCARD;

  bool contextualRefreshAllowed({
    required Set<IneligibilityCode> before,
    required Set<IneligibilityCode> after,
  }) {
    if (before.isNotEmpty || after.isEmpty) return false;
    const contextual = {
      IneligibilityCode.SESSION_MODE,
      IneligibilityCode.PROXIMITY,
      IneligibilityCode.PHYSICAL_STATE,
      IneligibilityCode.CLOTHES,
      IneligibilityCode.ACCESSORY,
      IneligibilityCode.MEDIA_CAPABILITY,
      IneligibilityCode.TEMPORARY_MEETING,
      IneligibilityCode.SESSION_FLAG,
    };
    return after.every(contextual.contains);
  }

  EngineSessionContext applyEffects({
    required EngineSessionContext beforeAction,
    required EngineSessionContext current,
    required List<StateEffect> effects,
    required String actorId,
    required String partnerId,
    required ActionExecutionStatus status,
  }) {
    if (status != ActionExecutionStatus.COMPLETED) return current;
    final clothes = Map<String, int>.from(current.clothesByPlayer);
    final physical = Map<String, String>.from(current.physicalStateByPlayer);
    final flags = Map<String, bool>.from(current.flags);
    for (final effect in effects) {
      final subjects = switch (effect.target) {
        ParticipantRole.PARTNER => [partnerId],
        ParticipantRole.MUTUAL => [actorId, partnerId],
        _ => [actorId],
      };
      switch (effect.type) {
        case StateEffectType.CLOTHES_DELTA:
          for (final player in subjects) {
            clothes[player] = ((clothes[player] ?? 0) + effect.clothesDelta!)
                .clamp(0, 1 << 30);
          }
        case StateEffectType.SET_PHYSICAL_STATE_TEMPORARY:
          for (final player in subjects) {
            physical[player] = effect.physicalState!;
          }
        case StateEffectType.RESTORE_PHYSICAL_STATE_AFTER_ACTION:
          physical
            ..clear()
            ..addAll(beforeAction.physicalStateByPlayer);
        case StateEffectType.SET_SESSION_FLAG:
          flags[effect.flagId!] = effect.flagValue!;
        case StateEffectType.CLEAR_SESSION_FLAG:
          flags.remove(effect.flagId);
      }
    }
    return current.copyWith(
      clothesByPlayer: clothes,
      physicalStateByPlayer: physical,
      flags: flags,
      proximity: current.proximity,
    );
  }

  (EngineSessionContext, GameEvent) consentStop(
    EngineSessionContext context,
    String variantId,
  ) {
    final removed = {...context.removedVariantIds, variantId};
    return (
      context.copyWith(removedVariantIds: removed),
      GameEvent(GameEventType.CONSENT_STOP, {'variant_id': variantId}),
    );
  }
}
