import '../../domain/game/events.dart';
import '../../domain/game/game_models.dart';
import '../../domain/session/session_state.dart';
import '../lifecycle/lifecycle_engine.dart';

// ignore_for_file: constant_identifier_names
enum CorruptionObjective { OWN_INITIAL_ACTION, INVERT_WINNING_ACTION }

enum PromiseVisibility { VISIBLE, MYSTERY }

final class ActionPromise {
  const ActionPromise({
    required this.cardId,
    required this.source,
    this.occurrenceId,
    this.variantId,
    this.effectiveSpice,
    this.status = ActionExecutionStatus.PROPOSED,
    this.visibility = PromiseVisibility.VISIBLE,
  });
  final String cardId;
  final String? occurrenceId;
  final String? variantId;
  final int? effectiveSpice;
  String get identity => occurrenceId ?? cardId;
  final CardZone source;
  final ActionExecutionStatus status;
  final PromiseVisibility visibility;
  ActionPromise copyWith({ActionExecutionStatus? status}) => ActionPromise(
    cardId: cardId,
    occurrenceId: occurrenceId,
    variantId: variantId,
    effectiveSpice: effectiveSpice,
    source: source,
    status: status ?? this.status,
    visibility: visibility,
  );
}

final class CorruptionOffer {
  CorruptionOffer({
    required this.offeredBy,
    required this.objective,
    required List<ActionPromise> actions,
  }) : actions = List.unmodifiable(actions) {
    if (actions.isEmpty) {
      throw ArgumentError(
        'A corruption offer must contain at least one action',
      );
    }
    if (actions.any((action) => action.source != CardZone.DISCARD)) {
      throw ArgumentError('Only discard cards can be corruption actions');
    }
    if (actions.map((action) => action.identity).toSet().length !=
        actions.length) {
      throw ArgumentError('A corruption occurrence can only be proposed once');
    }
  }
  final String offeredBy;
  final CorruptionObjective objective;
  final List<ActionPromise> actions;
}

final class CorruptionResolution {
  const CorruptionResolution({
    required this.cards,
    required this.events,
    this.stoppedByConsent = false,
  });
  final List<CardRuntimeState> cards;
  final List<GameEvent> events;
  final bool stoppedByConsent;
}

final class CorruptionEngine {
  const CorruptionEngine({this.lifecycle = const LifecycleEngine()});
  final LifecycleEngine lifecycle;

  int power(CorruptionOffer offer) => 0;

  CorruptionResolution resolve({
    required CorruptionOffer offer,
    required bool accepted,
    required List<CardRuntimeState> cards,
  }) {
    var updated = cards;
    final events = <GameEvent>[GameEvent(GameEventType.CORRUPTION_PROPOSED)];
    if (!accepted) return CorruptionResolution(cards: updated, events: events);
    events.add(GameEvent(GameEventType.ACTION_ACCEPTED));
    for (final action in offer.actions) {
      if (action.status == ActionExecutionStatus.STOPPED) {
        events.add(
          GameEvent(GameEventType.CONSENT_STOP, {'card_id': action.cardId}),
        );
        return CorruptionResolution(
          cards: updated,
          events: events,
          stoppedByConsent: true,
        );
      }
      if (action.status == ActionExecutionStatus.COMPLETED &&
          action.source == CardZone.DISCARD) {
        updated = lifecycle.exhaustDiscardAction(
          updated,
          action.identity,
          actuallyCompleted: true,
        );
        events.add(
          GameEvent(GameEventType.CARD_EXHAUSTED, {'card_id': action.cardId}),
        );
        events.add(
          GameEvent(GameEventType.ACTION_COMPLETED, {'card_id': action.cardId}),
        );
      } else if (action.status == ActionExecutionStatus.SKIPPED) {
        events.add(
          GameEvent(GameEventType.ACTION_SKIPPED, {'card_id': action.cardId}),
        );
      }
    }
    return CorruptionResolution(cards: updated, events: events);
  }
}
