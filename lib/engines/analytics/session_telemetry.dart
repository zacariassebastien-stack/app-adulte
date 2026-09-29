import '../../domain/domain.dart';
import '../corruption/corruption_engine.dart';

/// Describes a decision that the caller has already established as legal.
/// This class does not grant permission or replace any Phase 3 gate.
final class DecisionOpportunity {
  DecisionOpportunity({
    required this.id,
    required this.playerId,
    required Iterable<BehaviorAxis> axes,
    this.availableAmount,
    Iterable<String> cards = const [],
    Iterable<String> tags = const [],
  }) : axes = List.unmodifiable(axes),
       cards = List.unmodifiable(cards),
       tags = List.unmodifiable(tags);
  final String id, playerId;
  final List<BehaviorAxis> axes;
  final List<String> cards, tags;
  final int? availableAmount;
}

/// Local ordered journal, injected sink and clock. No network and no RNG.
/// A resumed session supplies the persisted last sequence.
final class SessionTelemetry {
  SessionTelemetry({
    required this.sessionId,
    required this.clock,
    required this.sink,
    int lastSequence = 0,
  }) : _sequence = lastSequence {
    if (lastSequence < 0) throw ArgumentError('Invalid sequence');
  }
  final String sessionId;
  final DateTime Function() clock;
  final void Function(StoredEvent) sink;
  int _sequence;
  String? roundId;
  int get lastSequence => _sequence;

  void record(
    GameEventType type,
    Map<String, Object?> facts, {
    String? owner,
    DataVisibility visibility = DataVisibility.SESSION_PRIVATE_INTERNAL,
    Iterable<PrivateAnalyticsContext> analytics = const [],
  }) {
    final event = GameEvent.record(
      type,
      {if (roundId != null) 'round_id': roundId, ...facts},
      ownerPlayerId: owner,
      visibility: visibility,
      analytics: analytics,
    );
    final next = _sequence + 1;
    final stored = event.toStored(
      sessionId: sessionId,
      eventId: '$sessionId.event.$next',
      sequence: next,
      at: clock(),
    );
    sink(stored);
    _sequence = next;
  }

  DecisionOpportunity opportunity(
    String playerId,
    String kind,
    Iterable<BehaviorAxis> axes, {
    int? availableAmount,
    Iterable<String> cards = const [],
    Iterable<String> tags = const [],
    String? correlationId,
  }) {
    final op = DecisionOpportunity(
      id: correlationId ?? '$sessionId.op.${_sequence + 1}',
      playerId: playerId,
      axes: axes,
      availableAmount: availableAmount,
      cards: cards,
      tags: tags,
    );
    record(
      GameEventType.DECISION_OPPORTUNITY,
      {'player_id': playerId, 'kind': kind, 'opportunity_id': op.id},
      owner: playerId,
      visibility: DataVisibility.PLAYER_PRIVATE,
      analytics: contexts(op, ObservationStage.OPPORTUNITY),
    );
    return op;
  }

  List<PrivateAnalyticsContext> contexts(
    DecisionOpportunity op,
    ObservationStage stage, {
    NonPerformanceReason reason = NonPerformanceReason.NONE,
    CombatValueSnapshot? snapshot,
    int? amount,
    String? chosenCardId,
    Iterable<String> chosenTags = const [],
  }) => [
    for (final axis in op.axes)
      PrivateAnalyticsContext(
        playerId: op.playerId,
        opportunityId: op.id,
        axis: axis,
        stage: stage,
        reason: reason,
        snapshot: snapshot,
        amount: amount,
        availableAmount: op.availableAmount,
        availableCardIds: op.cards,
        availableTagIds: op.tags,
        chosenCardId: chosenCardId,
        chosenTags: chosenTags,
      ),
  ];

  void decision(
    DecisionOpportunity op,
    GameEventType type,
    Map<String, Object?> facts, {
    bool attempted = false,
    bool accepted = false,
    bool completed = false,
    NonPerformanceReason neutralReason = NonPerformanceReason.NONE,
    CombatValueSnapshot? snapshot,
    int? amount,
    String? chosenCardId,
    Iterable<String> chosenTags = const [],
  }) {
    final excluded =
        neutralReason != NonPerformanceReason.NONE &&
        neutralReason != NonPerformanceReason.STRATEGIC;
    record(
      type,
      {'player_id': op.playerId, 'opportunity_id': op.id, ...facts},
      owner: op.playerId,
      visibility: DataVisibility.PLAYER_PRIVATE,
      analytics: [
        if (excluded)
          ...contexts(op, ObservationStage.EXCLUDED, reason: neutralReason)
        else
          for (final stage in [
            if (attempted) ObservationStage.ATTEMPT,
            if (accepted) ObservationStage.ACCEPTED,
            if (completed) ObservationStage.COMPLETED,
          ])
            ...contexts(
              op,
              stage,
              snapshot: snapshot,
              amount: amount,
              chosenCardId: chosenCardId,
              chosenTags: chosenTags,
            ),
      ],
    );
  }

  void styleChanged(
    DecisionOpportunity op,
    PlayerStyle previous,
    PlayerStyle next,
  ) => decision(
    op,
    GameEventType.PLAYER_STYLE_CHANGED,
    {'previous_style': previous.name, 'new_style': next.name},
    attempted: true,
    completed: true,
  );

  void drawn(
    String playerId,
    EngineCard card,
    List<EngineVariant> accessible,
  ) => record(
    GameEventType.CARD_DRAWN_PRIVATE,
    {
      'player_id': playerId,
      'card_id': card.id,
      'tags': card.tags.toList(),
      'precision': card.precision.name,
      'accessible_variants': [
        for (final v in accessible)
          {
            'variant_id': v.id,
            'chili_level': v.chiliLevel,
            'tags': v.tags.toList(),
          },
      ],
    },
    owner: playerId,
    visibility: DataVisibility.PLAYER_PRIVATE,
  );
  void lockChanged(String playerId, String cardId, bool locked) => record(
    GameEventType.CARD_LOCK_CHANGED_PRIVATE,
    {'player_id': playerId, 'card_id': cardId, 'locked': locked},
    owner: playerId,
    visibility: DataVisibility.PLAYER_PRIVATE,
  );

  void committed(
    DecisionOpportunity op,
    CombatValueSnapshot snapshot,
    Iterable<String> tags,
  ) => decision(
    op,
    GameEventType.CARD_COMMITTED,
    {
      'card_id': snapshot.cardId,
      'variant_id': snapshot.variantId,
      'voluntary_player_id': snapshot.playerId,
      'voluntary_role': snapshot.roleAtCommit.name,
      'snapshot': snapshot.toJson(),
    },
    attempted: true,
    completed: true,
    snapshot: snapshot,
    chosenCardId: snapshot.cardId,
    chosenTags: tags,
  );

  void executed(
    DecisionOpportunity op, {
    required String actionId,
    required String cardId,
    required String variantId,
    required ActionSource source,
    required String voluntaryPlayerId,
    required Map<String, ProfileRole> plannedRoles,
    required Map<String, ProfileRole> actualRoles,
    required String status,
    NonPerformanceReason reason = NonPerformanceReason.NONE,
  }) {
    if (!{'COMPLETED', 'SKIPPED', 'STOPPED'}.contains(status)) {
      throw ArgumentError('Invalid execution status');
    }
    if (status != 'COMPLETED' && actualRoles.isNotEmpty) {
      throw ArgumentError('Unperformed action cannot have executed roles');
    }
    if (status == 'STOPPED') reason = NonPerformanceReason.CONSENT_STOP;
    if (status == 'SKIPPED' && reason == NonPerformanceReason.NONE) {
      reason = NonPerformanceReason.UNKNOWN;
    }
    decision(
      op,
      GameEventType.ACTION_EXECUTION_RECORDED,
      {
        'action_id': actionId,
        'card_id': cardId,
        'variant_id': variantId,
        'source': source.name,
        'voluntary_player_id': voluntaryPlayerId,
        'planned_roles': plannedRoles.map((k, v) => MapEntry(k, v.name)),
        'actual_roles': actualRoles.map((k, v) => MapEntry(k, v.name)),
        'status': status,
        'reason': reason.name,
      },
      attempted: true,
      accepted: status == 'COMPLETED',
      completed: status == 'COMPLETED',
      neutralReason: reason,
    );
  }

  void extension(
    DecisionOpportunity op, {
    required int amount,
    required Map<String, int> before,
    required Map<String, int> after,
  }) => decision(
    op,
    GameEventType.MUTUAL_PA_EXTENSION,
    {
      'player_ids': before.keys.toList(),
      'amount_each': amount,
      'pa_before': before,
      'pa_after': after,
    },
    attempted: true,
    accepted: true,
    completed: true,
  );

  void corruptionProposed(
    DecisionOpportunity op,
    CorruptionOffer offer,
    String recipientId, {
    Map<String, String> variantByCard = const {},
  }) => decision(op, GameEventType.CORRUPTION_PROPOSED, {
    'offer_id': op.id,
    'offered_by': offer.offeredBy,
    'recipient_id': recipientId,
    'objective': offer.objective.name,
    'combination_size': offer.actions.length,
    'repetition_count':
        offer.actions.length -
        offer.actions.map((a) => a.cardId).toSet().length,
    'actions': [
      for (var i = 0; i < offer.actions.length; i++)
        {
          'action_id': '${op.id}.action.$i',
          'card_id': offer.actions[i].cardId,
          if (variantByCard.containsKey(offer.actions[i].cardId))
            'variant_id': variantByCard[offer.actions[i].cardId],
          'source': offer.actions[i].source.name,
          'visibility': offer.actions[i].visibility.name,
          'ordinal': i,
          'status': 'PROPOSED',
        },
    ],
  }, attempted: true);

  void chiliProposal(
    DecisionOpportunity op,
    int previous,
    int target,
    String recipientId,
  ) => decision(
    op,
    target > previous
        ? GameEventType.CHILI_INCREASE_PROPOSED
        : GameEventType.CHILI_DECREASE_PROPOSED,
    {
      'previous_level': previous,
      'target_level': target,
      'recipient_id': recipientId,
    },
    attempted: true,
  );
  void chiliResponse(
    DecisionOpportunity op,
    int previous,
    int target,
    String recipientId, {
    required bool accepted,
  }) => decision(
    op,
    target > previous
        ? (accepted
              ? GameEventType.CHILI_INCREASE_ACCEPTED
              : GameEventType.CHILI_INCREASE_DECLINED)
        : (accepted
              ? GameEventType.CHILI_DECREASE_ACCEPTED
              : GameEventType.CHILI_DECREASE_DECLINED),
    {
      'target_level': target,
      'recipient_id': recipientId,
      'decision_kind': 'INTENSITY_ONLY',
    },
    accepted: accepted,
  );
}
