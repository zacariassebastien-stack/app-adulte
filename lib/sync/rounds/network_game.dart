import '../../engines/auction/auction_engine.dart';
import '../../engines/corruption/corruption_engine.dart';
import '../../engines/deck/deck_cycle_state.dart';
import '../../engines/lifecycle/lifecycle_engine.dart';
import '../../engines/recovery/recovery_engine.dart';
import '../../domain/game/game_models.dart';
import '../../domain/session/session_state.dart';
import '../commit_reveal/commit_reveal.dart';
import '../protocol/idempotency.dart';
import '../protocol/network_dtos.dart';
import '../protocol/network_usage_projection.dart';

// Wire enum names intentionally match the stable SQL/JSON protocol.
// ignore_for_file: constant_identifier_names

enum NetworkGamePhase {
  commit,
  reveal,
  ready,
  negotiationProposal,
  negotiationResponse,
  negotiationAdaptation,
  negotiationValidation,
  counterDecision,
  finalDefenseDecision,
  tieDecision,
  finalResolved,
  corruptionDecision,
  corruptionResponse,
  corruptionExecution,
  recovery,
  recoveryResponse,
  recoveryExecution,
  waitingNext,
  closed,
  sessionClosed,
}

enum NetworkCompromiseOrigin { INITIAL_DUEL, AUCTION, RECOVERY }

enum NetworkCardDirection { GENERAL, FAIRE, RECEVOIR, MUTUEL, SOLO, SIMULTANE }

NetworkCardDirection invertNetworkDirection(NetworkCardDirection direction) =>
    switch (direction) {
      NetworkCardDirection.FAIRE => NetworkCardDirection.RECEVOIR,
      NetworkCardDirection.RECEVOIR => NetworkCardDirection.FAIRE,
      _ => direction,
    };

final class NetworkCompromiseCardDto {
  const NetworkCompromiseCardDto.fromUsage(
    this.usage, {
    required this.origin,
    this.logicalOrder,
  });
  final NetworkUsageProjection usage;
  final NetworkCompromiseOrigin origin;
  final int? logicalOrder;
  String get usageId => usage.usageId;
  String get conceptId => usage.conceptId;
  String get cardId => conceptId;
  String get variantId =>
      (usage.resolvedAction['stage_id'] ?? usage.resolvedAction['variant_id'])!
          as String;
  String get ownerPlayerId => usage.ownerPlayerId;
  NetworkCardDirection get nativeDirection => NetworkCardDirection.values
      .byName(usage.toJson()['native_direction']! as String);
  NetworkCardDirection get effectiveDirection => NetworkCardDirection.values
      .byName(usage.resolvedAction['direction']! as String);
  int get snapshotValue => usage.snapshotValue!;
  NetworkCompromiseCardDto copyWith({
    NetworkCardDirection? effectiveDirection,
    int? logicalOrder,
  }) {
    final direction = effectiveDirection ?? this.effectiveDirection;
    final resolved = direction == this.effectiveDirection
        ? usage
        : usage.resolved(inverted: direction != nativeDirection);
    if (resolved.resolvedAction['direction'] != direction.name) {
      throw StateError('No frozen resolution for this direction');
    }
    return NetworkCompromiseCardDto.fromUsage(
      resolved,
      origin: origin,
      logicalOrder: logicalOrder ?? this.logicalOrder,
    );
  }

  Map<String, Object?> toJson() => {
    ...usage.toJson(),
    'origin': origin.name,
    'logical_order': ?logicalOrder,
  };
  factory NetworkCompromiseCardDto.fromJson(Map<String, Object?> json) {
    final native = Map<String, Object?>.from(json)
      ..remove('origin')
      ..remove('logical_order');
    return NetworkCompromiseCardDto.fromUsage(
      NetworkUsageProjection.fromJson(native),
      origin: NetworkCompromiseOrigin.values.byName(json['origin']! as String),
      logicalOrder: json['logical_order'] as int?,
    );
  }
}

final class NetworkNegotiationOfferDto {
  NetworkNegotiationOfferDto({
    required this.inversionRequested,
    required this.directPa,
    List<NetworkCompromiseCardDto> cards = const [],
  }) : cards = List.unmodifiable(cards);

  final bool inversionRequested;
  final int directPa;
  final List<NetworkCompromiseCardDto> cards;
  int get totalValue =>
      directPa + cards.fold(0, (sum, card) => sum + card.snapshotValue);

  Map<String, Object?> toJson() => {
    'inversion_requested': inversionRequested,
    'direct_pa': directPa,
    'cards': [for (final card in cards) card.toJson()],
  };

  factory NetworkNegotiationOfferDto.fromJson(Map<String, Object?> json) =>
      NetworkNegotiationOfferDto(
        inversionRequested: json['inversion_requested']! as bool,
        directPa: json['direct_pa']! as int,
        cards: [
          for (final raw in (json['cards'] as List?) ?? const [])
            NetworkCompromiseCardDto.fromJson(
              Map<String, Object?>.from(raw! as Map),
            ),
        ],
      );
}

final class NetworkNegotiationResponseDto {
  const NetworkNegotiationResponseDto({
    required this.acceptInversion,
    required this.acceptAuction,
  });
  final bool acceptInversion;
  final bool acceptAuction;
  Map<String, Object?> toJson() => {
    'accept_inversion': acceptInversion,
    'accept_auction': acceptAuction,
  };
  factory NetworkNegotiationResponseDto.fromJson(Map<String, Object?> json) =>
      NetworkNegotiationResponseDto(
        acceptInversion: json['accept_inversion']! as bool,
        acceptAuction: json['accept_auction']! as bool,
      );
}

final class NetworkNegotiationDto {
  const NetworkNegotiationDto({this.proposal, this.response, this.finalOffer});
  final NetworkNegotiationOfferDto? proposal;
  final NetworkNegotiationResponseDto? response;
  final NetworkNegotiationOfferDto? finalOffer;
  Map<String, Object?> toJson() => {
    'proposal': proposal?.toJson(),
    'response': response?.toJson(),
    'final_offer': finalOffer?.toJson(),
  };
  factory NetworkNegotiationDto.fromJson(Map<String, Object?> json) {
    T? optional<T>(String key, T Function(Map<String, Object?>) parse) {
      final value = json[key];
      return value == null
          ? null
          : parse(Map<String, Object?>.from(value as Map));
    }

    return NetworkNegotiationDto(
      proposal: optional('proposal', NetworkNegotiationOfferDto.fromJson),
      response: optional('response', NetworkNegotiationResponseDto.fromJson),
      finalOffer: optional('final_offer', NetworkNegotiationOfferDto.fromJson),
    );
  }
}

enum CounterDecision { accept, bid }

enum FinalDefenseDecision { renounce, defend }

enum TieDecision { concede, abandon }

/// Shared promise; its action is a frozen usage projection, never a catalogue lookup.
final class NetworkCorruptionActionDto {
  NetworkCorruptionActionDto.fromUsage(
    NetworkUsageProjection usage, {
    this.source = CardZone.DISCARD,
    this.status = ActionExecutionStatus.PROPOSED,
    this.visibility = PromiseVisibility.VISIBLE,
  }) : usage = usage.withoutPersonalValues();
  final NetworkUsageProjection usage;
  final CardZone source;
  final ActionExecutionStatus status;
  final PromiseVisibility visibility;
  String get cardId => usage.conceptId;
  String get identity => usage.usageId;
  NetworkCorruptionActionDto copyWith({ActionExecutionStatus? status}) =>
      NetworkCorruptionActionDto.fromUsage(
        usage,
        source: source,
        status: status ?? this.status,
        visibility: visibility,
      );
  Map<String, Object?> toJson() => {
    ...usage.toJson(),
    'source': source.name,
    'status': status.name,
    'visibility': visibility.name,
  };
  factory NetworkCorruptionActionDto.fromJson(Map<String, Object?> json) {
    final native = Map<String, Object?>.from(json)
      ..remove('source')
      ..remove('status')
      ..remove('visibility');
    return NetworkCorruptionActionDto.fromUsage(
      NetworkUsageProjection.fromJson(native),
      source: CardZone.values.byName(json['source']! as String),
      status: ActionExecutionStatus.values.byName(json['status']! as String),
      visibility: PromiseVisibility.values.byName(
        json['visibility']! as String,
      ),
    );
  }
}

final class NetworkCorruptionDto {
  NetworkCorruptionDto({
    required this.offeredBy,
    required this.objective,
    required List<NetworkCorruptionActionDto> actions,
    this.accepted,
  }) : actions = List.unmodifiable(actions);

  final String offeredBy;
  final CorruptionObjective objective;
  final List<NetworkCorruptionActionDto> actions;
  final bool? accepted;

  Map<String, Object?> toJson() => {
    'offered_by': offeredBy,
    'objective': objective.name,
    'accepted': accepted,
    'actions': [for (final action in actions) action.toJson()],
  };

  factory NetworkCorruptionDto.fromJson(Map<String, Object?> json) =>
      NetworkCorruptionDto(
        offeredBy: json['offered_by']! as String,
        objective: CorruptionObjective.values.byName(
          json['objective']! as String,
        ),
        accepted: json['accepted'] as bool?,
        actions: [
          for (final raw in json['actions']! as List)
            if (Map<String, Object?>.from(raw! as Map) case final action)
              NetworkCorruptionActionDto.fromJson(action),
        ],
      );
}

final class NetworkRecoveryDto {
  NetworkRecoveryDto.fromUsage(
    NetworkUsageProjection usage, {
    required this.source,
    this.completed = false,
    this.gain = 0,
    this.response,
  }) : usage = usage.withoutPersonalValues();
  final NetworkUsageProjection usage;
  final RecoverySource source;
  final bool completed;
  final int gain;
  final RecoveryResponse? response;
  String get playerId => usage.ownerPlayerId;
  String get cardId => usage.conceptId;
  String get usageId => usage.usageId;
  String get variantId =>
      (usage.resolvedAction['stage_id'] ?? usage.resolvedAction['variant_id'])!
          as String;
  Map<String, Object?> toJson() => {
    ...usage.toJson(),
    'player_id': playerId,
    'source': source.name,
    'completed': completed,
    'gain': gain,
    'response': response?.name,
  };
  factory NetworkRecoveryDto.fromJson(Map<String, Object?> json) {
    final native = Map<String, Object?>.from(json);
    for (final key in [
      'player_id',
      'source',
      'completed',
      'gain',
      'response',
    ]) {
      native.remove(key);
    }
    final usage = NetworkUsageProjection.fromJson(native);
    if (json['player_id'] != usage.ownerPlayerId) {
      throw const FormatException('Recovery owner mismatch');
    }
    return NetworkRecoveryDto.fromUsage(
      usage,
      source: RecoverySource.values.byName(json['source']! as String),
      completed: json['completed']! as bool,
      gain: json['gain']! as int,
      response: json['response'] == null
          ? null
          : RecoveryResponse.values.byName(json['response']! as String),
    );
  }
}

final class NetworkInitialResolutionDto {
  NetworkInitialResolutionDto({
    required this.tied,
    required this.gap,
    required this.gapCost,
    this.highValue = 0,
    required Map<String, int> actionPoints,
    this.winnerPlayerId,
    this.loserPlayerId,
    this.inversionAllowed = false,
  }) : actionPoints = Map.unmodifiable(actionPoints);

  final bool tied;
  final String? winnerPlayerId;
  final String? loserPlayerId;
  final int gap;
  final int gapCost;
  final int highValue;
  final Map<String, int> actionPoints;
  final bool inversionAllowed;

  Map<String, Object?> toJson() => {
    'tied': tied,
    'winner_player_id': winnerPlayerId,
    'loser_player_id': loserPlayerId,
    'gap': gap,
    'gap_cost': gapCost,
    'high_value': highValue,
    'action_points': actionPoints,
    'inversion_allowed': inversionAllowed,
  };

  factory NetworkInitialResolutionDto.fromJson(Map<String, Object?> json) =>
      NetworkInitialResolutionDto(
        tied: json['tied']! as bool,
        winnerPlayerId: json['winner_player_id'] as String?,
        loserPlayerId: json['loser_player_id'] as String?,
        gap: json['gap']! as int,
        gapCost: json['gap_cost']! as int,
        highValue: (json['high_value'] as int?) ?? 0,
        actionPoints: Map<String, int>.from(json['action_points']! as Map),
        inversionAllowed: json['inversion_allowed']! as bool,
      );
}

final class NetworkAuctionBidDto {
  const NetworkAuctionBidDto({
    required this.playerId,
    required this.amount,
    required this.target,
  });

  final String playerId;
  final int amount;
  final AuctionTarget target;

  Map<String, Object?> toJson() => {
    'player_id': playerId,
    'amount': amount,
    'target': target.name,
  };

  factory NetworkAuctionBidDto.fromJson(Map<String, Object?> json) =>
      NetworkAuctionBidDto(
        playerId: json['player_id']! as String,
        amount: json['amount']! as int,
        target: AuctionTarget.values.byName(json['target']! as String),
      );
}

final class NetworkFinalResolutionDto {
  const NetworkFinalResolutionDto({
    this.retainedPlayerId,
    this.initialWinnerPlayerId,
    this.finalWinnerPlayerId,
    this.cardId,
    this.variantId,
    this.usageId,
    this.inverted = false,
    this.mutualAbandon = false,
    this.compromise = const [],
  });

  final String? retainedPlayerId;
  final String? initialWinnerPlayerId;
  final String? finalWinnerPlayerId;
  final String? cardId;
  final String? variantId;
  final String? usageId;
  final bool inverted;
  final bool mutualAbandon;
  final List<NetworkCompromiseCardDto> compromise;

  Map<String, Object?> toJson() => {
    'retained_player_id': retainedPlayerId,
    'initial_winner_player_id': initialWinnerPlayerId,
    'final_winner_player_id': finalWinnerPlayerId,
    'usage_id': ?(usageId ?? compromise.firstOrNull?.usageId),
    'concept_id': ?(cardId ?? compromise.firstOrNull?.conceptId),
    'inverted': inverted,
    'mutual_abandon': mutualAbandon,
    'compromise': [for (final card in compromise) card.toJson()],
  };

  factory NetworkFinalResolutionDto.fromJson(Map<String, Object?> json) =>
      NetworkFinalResolutionDto(
        retainedPlayerId: json['retained_player_id'] as String?,
        initialWinnerPlayerId: json['initial_winner_player_id'] as String?,
        finalWinnerPlayerId: json['final_winner_player_id'] as String?,
        cardId: json['concept_id'] as String?,
        usageId: json['usage_id'] as String?,
        variantId: json['variant_id'] as String?,
        inverted: json['inverted']! as bool,
        mutualAbandon: json['mutual_abandon']! as bool,
        compromise: [
          for (final raw in (json['compromise'] as List?) ?? const [])
            NetworkCompromiseCardDto.fromJson(
              Map<String, Object?>.from(raw! as Map),
            ),
        ],
      );
}

final class NetworkGameRoundStateDto {
  NetworkGameRoundStateDto({
    this.usageContractVersion,
    required this.roundId,
    required this.sessionId,
    required this.sessionRound,
    required this.roundNumber,
    required this.phase,
    required this.playerId,
    required Map<String, String> commits,
    required Map<String, int> actionPoints,
    required Set<String> readyNextPlayerIds,
    required Map<String, TieDecision> tieDecisions,
    this.hybridOrientation = HybridDeckOrientation.faceToFace,
    this.deckCycle = 1,
    this.infiniteMode = false,
    this.deckStyle = PlayerStyle.SOFT,
    Map<String, int>? deckAdjustment,
    this.ownReveal,
    this.opponentReveal,
    this.initialResolution,
    this.counterBid,
    this.finalDefense,
    this.negotiation,
    this.finalResolution,
    this.corruption,
    Map<String, NetworkRecoveryDto>? recoveryByPlayer,
    Set<String>? recoveryDonePlayerIds,
    List<NetworkRecoveryDto>? recoveryHistory,
  }) : commits = Map.unmodifiable(commits),
       actionPoints = Map.unmodifiable(actionPoints),
       readyNextPlayerIds = Set.unmodifiable(readyNextPlayerIds),
       tieDecisions = Map.unmodifiable(tieDecisions),
       deckAdjustment = Map.unmodifiable(deckAdjustment ?? const {}),
       recoveryByPlayer = Map.unmodifiable(recoveryByPlayer ?? const {}),
       recoveryDonePlayerIds = Set.unmodifiable(
         recoveryDonePlayerIds ?? const {},
       ),
       recoveryHistory = List.unmodifiable(recoveryHistory ?? const []);

  final String roundId;
  final int? usageContractVersion;
  final String sessionId;
  final String sessionRound;
  final int roundNumber;
  final NetworkGamePhase phase;
  final String playerId;
  final Map<String, String> commits;
  final Map<String, int> actionPoints;
  final Set<String> readyNextPlayerIds;
  final Map<String, TieDecision> tieDecisions;
  final HybridDeckOrientation hybridOrientation;
  final int deckCycle;
  final bool infiniteMode;
  final PlayerStyle deckStyle;
  final Map<String, int> deckAdjustment;
  final ChoiceRevealDto? ownReveal;
  final ChoiceRevealDto? opponentReveal;
  final NetworkInitialResolutionDto? initialResolution;
  final NetworkAuctionBidDto? counterBid;
  final NetworkAuctionBidDto? finalDefense;
  final NetworkNegotiationDto? negotiation;
  final NetworkFinalResolutionDto? finalResolution;
  final NetworkCorruptionDto? corruption;
  final Map<String, NetworkRecoveryDto> recoveryByPlayer;
  final Set<String> recoveryDonePlayerIds;
  final List<NetworkRecoveryDto> recoveryHistory;

  bool get ownCommitRecorded => commits.containsKey(playerId);
  bool get ownRevealRecorded => ownReveal != null;

  Map<String, Object?> toJson() => {
    'schema_version': networkSchemaVersion,
    'usage_contract_version': ?usageContractVersion,
    'round_id': roundId,
    'session_id': sessionId,
    'session_round': sessionRound,
    'round_number': roundNumber,
    'phase': _phaseWire(phase),
    'player_id': playerId,
    'commits': commits,
    'action_points': actionPoints,
    'ready_next': {for (final id in readyNextPlayerIds) id: true},
    'tie_decisions': {
      for (final entry in tieDecisions.entries) entry.key: entry.value.name,
    },
    'hybrid_orientation': hybridOrientation == HybridDeckOrientation.faceToFace
        ? 'FACE_TO_FACE'
        : 'DISTANCE',
    'deck_cycle': deckCycle,
    'infinite_mode': infiniteMode,
    'deck_style': deckStyle.name,
    'deck_adjustment': deckAdjustment,
    'own_reveal': ownReveal?.toJson(),
    'opponent_reveal': opponentReveal?.toJson(),
    'initial_resolution': initialResolution?.toJson(),
    'counter_bid': counterBid?.toJson(),
    'final_defense': finalDefense?.toJson(),
    'negotiation': negotiation?.toJson(),
    'final_resolution': finalResolution?.toJson(),
    'corruption': corruption?.toJson(),
    'recovery_by_player': {
      for (final entry in recoveryByPlayer.entries)
        entry.key: entry.value.toJson(),
    },
    'recovery_done': {for (final id in recoveryDonePlayerIds) id: true},
    'recovery_history': [for (final item in recoveryHistory) item.toJson()],
  };

  factory NetworkGameRoundStateDto.fromJson(Map<String, Object?> json) {
    T? optional<T>(String key, T Function(Map<String, Object?>) parse) {
      final value = json[key];
      return value == null
          ? null
          : parse(Map<String, Object?>.from(value as Map));
    }

    ChoiceRevealDto? reveal(String key) =>
        optional(key, ChoiceRevealDto.fromJson);
    final ready = Map<String, Object?>.from(
      (json['ready_next'] as Map?) ?? const {},
    );
    final ties = Map<String, Object?>.from(
      (json['tie_decisions'] as Map?) ?? const {},
    );
    final recoveries = Map<String, Object?>.from(
      (json['recovery_by_player'] as Map?) ?? const {},
    );
    final recoveryDone = Map<String, Object?>.from(
      (json['recovery_done'] as Map?) ?? const {},
    );
    return NetworkGameRoundStateDto(
      roundId: json['round_id']! as String,
      sessionId: json['session_id']! as String,
      usageContractVersion: json['usage_contract_version'] as int?,
      sessionRound: json['session_round']! as String,
      roundNumber: json['round_number']! as int,
      phase: _phaseFromWire(json['phase']! as String),
      playerId: json['player_id']! as String,
      commits: Map<String, String>.from(json['commits']! as Map),
      actionPoints: Map<String, int>.from(json['action_points']! as Map),
      readyNextPlayerIds: {
        for (final entry in ready.entries)
          if (entry.value == true) entry.key,
      },
      tieDecisions: {
        for (final entry in ties.entries)
          entry.key: TieDecision.values.byName(entry.value! as String),
      },
      hybridOrientation: json['hybrid_orientation'] == 'DISTANCE'
          ? HybridDeckOrientation.distance
          : HybridDeckOrientation.faceToFace,
      deckCycle: (json['deck_cycle'] as int?) ?? 1,
      infiniteMode: (json['infinite_mode'] as bool?) ?? false,
      deckStyle: PlayerStyle.values.byName(
        (json['deck_style'] as String?) ?? PlayerStyle.SOFT.name,
      ),
      deckAdjustment: Map<String, int>.from(
        (json['deck_adjustment'] as Map?) ?? const {},
      ),
      ownReveal: reveal('own_reveal'),
      opponentReveal: reveal('opponent_reveal'),
      initialResolution: optional(
        'initial_resolution',
        NetworkInitialResolutionDto.fromJson,
      ),
      counterBid: optional('counter_bid', NetworkAuctionBidDto.fromJson),
      finalDefense: optional('final_defense', NetworkAuctionBidDto.fromJson),
      negotiation: optional('negotiation', NetworkNegotiationDto.fromJson),
      finalResolution: optional(
        'final_resolution',
        NetworkFinalResolutionDto.fromJson,
      ),
      corruption: optional('corruption', NetworkCorruptionDto.fromJson),
      recoveryByPlayer: {
        for (final entry in recoveries.entries)
          entry.key: NetworkRecoveryDto.fromJson(
            Map<String, Object?>.from(entry.value! as Map),
          ),
      },
      recoveryDonePlayerIds: {
        for (final entry in recoveryDone.entries)
          if (entry.value == true) entry.key,
      },
      recoveryHistory: [
        for (final raw in (json['recovery_history'] as List?) ?? const [])
          NetworkRecoveryDto.fromJson(Map<String, Object?>.from(raw! as Map)),
      ],
    );
  }
}

abstract interface class NetworkGameRepository {
  Future<NetworkGameRoundStateDto> openCurrentRound({
    required NetworkCommandDto command,
  });

  Future<NetworkGameRoundStateDto> getCurrentRound({required String sessionId});

  Future<NetworkGameRoundStateDto> getRound({
    required String sessionId,
    required String roundId,
  });

  Future<NetworkGameRoundStateDto> submitCommit({
    required NetworkCommandDto command,
    required ChoiceCommitmentDto commitment,
  });

  Future<NetworkGameRoundStateDto> submitReveal({
    required NetworkCommandDto command,
    required ChoiceRevealDto reveal,
  });

  Future<NetworkGameRoundStateDto> submitInitialResolution({
    required NetworkCommandDto command,
    required NetworkInitialResolutionDto resolution,
  });

  Future<NetworkGameRoundStateDto> submitCounterDecision({
    required NetworkCommandDto command,
    required CounterDecision decision,
    int? amount,
    AuctionTarget? target,
  });

  Future<NetworkGameRoundStateDto> submitFinalDefense({
    required NetworkCommandDto command,
    required FinalDefenseDecision decision,
    int? amount,
  });

  Future<NetworkGameRoundStateDto> submitTieDecision({
    required NetworkCommandDto command,
    required TieDecision decision,
  });

  Future<NetworkGameRoundStateDto> submitCorruptionOffer({
    required NetworkCommandDto command,
    required CorruptionObjective objective,
    required List<NetworkCorruptionActionDto> actions,
  });

  Future<NetworkGameRoundStateDto> respondCorruption({
    required NetworkCommandDto command,
    required bool accepted,
  });

  Future<NetworkGameRoundStateDto> resolveCorruption({
    required NetworkCommandDto command,
    required List<NetworkCorruptionActionDto> actions,
  });

  Future<NetworkGameRoundStateDto> skipCorruption({
    required NetworkCommandDto command,
  });

  Future<NetworkGameRoundStateDto> submitRecovery({
    required NetworkCommandDto command,
    required NetworkRecoveryDto recovery,
  });

  Future<NetworkGameRoundStateDto> respondRecovery({
    required NetworkCommandDto command,
    required RecoveryResponse response,
  });

  Future<NetworkGameRoundStateDto> resolveRecovery({
    required NetworkCommandDto command,
    required NetworkRecoveryDto recovery,
  });

  Future<NetworkGameRoundStateDto> skipRecovery({
    required NetworkCommandDto command,
  });

  Future<NetworkGameRoundStateDto> readyNextRound({
    required NetworkCommandDto command,
  });

  Stream<NetworkGameRoundStateDto> watchRound({
    required String sessionId,
    required String roundId,
  });
}

/// Capability introduced by the V3 ABA migration. Keeping it separate lets a
/// client still deserialize a legacy in-flight round while all newly opened
/// Supabase rounds use the bounded V3 negotiation.
abstract interface class NetworkNegotiationRepository {
  Future<NetworkGameRoundStateDto> submitNegotiationProposal({
    required NetworkCommandDto command,
    required NetworkNegotiationOfferDto offer,
  });
  Future<NetworkGameRoundStateDto> respondNegotiation({
    required NetworkCommandDto command,
    required NetworkNegotiationResponseDto response,
  });
  Future<NetworkGameRoundStateDto> adaptNegotiation({
    required NetworkCommandDto command,
    required NetworkNegotiationOfferDto offer,
  });
  Future<NetworkGameRoundStateDto> validateNegotiation({
    required NetworkCommandDto command,
    required bool accepted,
  });
}

abstract interface class NetworkSessionFlowRepository {
  Future<NetworkGameRoundStateDto> setHybridOrientation({
    required NetworkCommandDto command,
    required HybridDeckOrientation orientation,
  });
  Future<NetworkGameRoundStateDto> continueDeckCycle({
    required NetworkCommandDto command,
    required DeckExhaustionChoice choice,
    required int expectedCycle,
  });
}

abstract interface class NetworkCommitCancellationRepository {
  Future<NetworkGameRoundStateDto> cancelCommit({
    required NetworkCommandDto command,
  });
}

abstract interface class NetworkSessionClosureRepository {
  Future<NetworkGameRoundStateDto> closeSession({
    required NetworkCommandDto command,
  });
}

String _phaseWire(NetworkGamePhase phase) => switch (phase) {
  NetworkGamePhase.commit => 'COMMIT',
  NetworkGamePhase.reveal => 'REVEAL',
  NetworkGamePhase.ready => 'READY',
  NetworkGamePhase.negotiationProposal => 'NEGOTIATION_PROPOSAL',
  NetworkGamePhase.negotiationResponse => 'NEGOTIATION_RESPONSE',
  NetworkGamePhase.negotiationAdaptation => 'NEGOTIATION_ADAPTATION',
  NetworkGamePhase.negotiationValidation => 'NEGOTIATION_VALIDATION',
  NetworkGamePhase.counterDecision => 'COUNTER_DECISION',
  NetworkGamePhase.finalDefenseDecision => 'FINAL_DEFENSE_DECISION',
  NetworkGamePhase.tieDecision => 'TIE_DECISION',
  NetworkGamePhase.finalResolved => 'FINAL_RESOLVED',
  NetworkGamePhase.corruptionDecision => 'CORRUPTION_DECISION',
  NetworkGamePhase.corruptionResponse => 'CORRUPTION_RESPONSE',
  NetworkGamePhase.corruptionExecution => 'CORRUPTION_EXECUTION',
  NetworkGamePhase.recovery => 'RECOVERY',
  NetworkGamePhase.recoveryResponse => 'RECOVERY_RESPONSE',
  NetworkGamePhase.recoveryExecution => 'RECOVERY_EXECUTION',
  NetworkGamePhase.waitingNext => 'WAITING_NEXT',
  NetworkGamePhase.closed => 'CLOSED',
  NetworkGamePhase.sessionClosed => 'SESSION_CLOSED',
};

NetworkGamePhase _phaseFromWire(String value) => switch (value) {
  'COMMIT' => NetworkGamePhase.commit,
  'REVEAL' => NetworkGamePhase.reveal,
  'READY' => NetworkGamePhase.ready,
  'NEGOTIATION_PROPOSAL' => NetworkGamePhase.negotiationProposal,
  'NEGOTIATION_RESPONSE' => NetworkGamePhase.negotiationResponse,
  'NEGOTIATION_ADAPTATION' => NetworkGamePhase.negotiationAdaptation,
  'NEGOTIATION_VALIDATION' => NetworkGamePhase.negotiationValidation,
  'COUNTER_DECISION' => NetworkGamePhase.counterDecision,
  'FINAL_DEFENSE_DECISION' => NetworkGamePhase.finalDefenseDecision,
  'TIE_DECISION' => NetworkGamePhase.tieDecision,
  'FINAL_RESOLVED' => NetworkGamePhase.finalResolved,
  'CORRUPTION_DECISION' => NetworkGamePhase.corruptionDecision,
  'CORRUPTION_RESPONSE' => NetworkGamePhase.corruptionResponse,
  'CORRUPTION_EXECUTION' => NetworkGamePhase.corruptionExecution,
  'RECOVERY' => NetworkGamePhase.recovery,
  'RECOVERY_RESPONSE' => NetworkGamePhase.recoveryResponse,
  'RECOVERY_EXECUTION' => NetworkGamePhase.recoveryExecution,
  'WAITING_NEXT' => NetworkGamePhase.waitingNext,
  'CLOSED' => NetworkGamePhase.closed,
  'SESSION_CLOSED' => NetworkGamePhase.sessionClosed,
  _ => throw FormatException('Unknown network game phase: $value'),
};
