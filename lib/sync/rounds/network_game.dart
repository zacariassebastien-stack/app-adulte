import '../../engines/auction/auction_engine.dart';
import '../../engines/corruption/corruption_engine.dart';
import '../../engines/lifecycle/lifecycle_engine.dart';
import '../../engines/recovery/recovery_engine.dart';
import '../../domain/session/session_state.dart';
import '../commit_reveal/commit_reveal.dart';
import '../protocol/idempotency.dart';
import '../protocol/network_dtos.dart';

enum NetworkGamePhase {
  commit,
  reveal,
  ready,
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
}

enum CounterDecision { accept, bid }

enum FinalDefenseDecision { renounce, defend }

enum TieDecision { concede, abandon }

final class NetworkCorruptionDto {
  NetworkCorruptionDto({
    required this.offeredBy,
    required this.objective,
    required List<ActionPromise> actions,
    this.accepted,
  }) : actions = List.unmodifiable(actions);

  final String offeredBy;
  final CorruptionObjective objective;
  final List<ActionPromise> actions;
  final bool? accepted;

  Map<String, Object?> toJson() => {
    'offered_by': offeredBy,
    'objective': objective.name,
    'accepted': accepted,
    'actions': [
      for (final action in actions)
        {
          'card_id': action.cardId,
          'source': action.source.name,
          'status': action.status.name,
          'visibility': action.visibility.name,
        },
    ],
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
              ActionPromise(
                cardId: action['card_id']! as String,
                source: CardZone.values.byName(action['source']! as String),
                status: ActionExecutionStatus.values.byName(
                  action['status']! as String,
                ),
                visibility: PromiseVisibility.values.byName(
                  action['visibility']! as String,
                ),
              ),
        ],
      );
}

final class NetworkRecoveryDto {
  const NetworkRecoveryDto({
    required this.playerId,
    required this.cardId,
    required this.variantId,
    required this.source,
    required this.completed,
    required this.gain,
    this.response,
  });

  final String playerId;
  final String cardId;
  final String variantId;
  final RecoverySource source;
  final bool completed;
  final int gain;
  final RecoveryResponse? response;

  Map<String, Object?> toJson() => {
    'player_id': playerId,
    'card_id': cardId,
    'variant_id': variantId,
    'source': source.name,
    'completed': completed,
    'gain': gain,
    'response': response?.name,
  };

  factory NetworkRecoveryDto.fromJson(Map<String, Object?> json) =>
      NetworkRecoveryDto(
        playerId: json['player_id']! as String,
        cardId: json['card_id']! as String,
        variantId: json['variant_id']! as String,
        source: RecoverySource.values.byName(json['source']! as String),
        completed: json['completed']! as bool,
        gain: json['gain']! as int,
        response: json['response'] == null
            ? null
            : RecoveryResponse.values.byName(json['response']! as String),
      );
}

final class NetworkInitialResolutionDto {
  NetworkInitialResolutionDto({
    required this.tied,
    required this.gap,
    required this.gapCost,
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
  final Map<String, int> actionPoints;
  final bool inversionAllowed;

  Map<String, Object?> toJson() => {
    'tied': tied,
    'winner_player_id': winnerPlayerId,
    'loser_player_id': loserPlayerId,
    'gap': gap,
    'gap_cost': gapCost,
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
    this.cardId,
    this.variantId,
    this.inverted = false,
    this.mutualAbandon = false,
  });

  final String? retainedPlayerId;
  final String? cardId;
  final String? variantId;
  final bool inverted;
  final bool mutualAbandon;

  Map<String, Object?> toJson() => {
    'retained_player_id': retainedPlayerId,
    'card_id': cardId,
    'variant_id': variantId,
    'inverted': inverted,
    'mutual_abandon': mutualAbandon,
  };

  factory NetworkFinalResolutionDto.fromJson(Map<String, Object?> json) =>
      NetworkFinalResolutionDto(
        retainedPlayerId: json['retained_player_id'] as String?,
        cardId: json['card_id'] as String?,
        variantId: json['variant_id'] as String?,
        inverted: json['inverted']! as bool,
        mutualAbandon: json['mutual_abandon']! as bool,
      );
}

final class NetworkGameRoundStateDto {
  NetworkGameRoundStateDto({
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
    this.ownReveal,
    this.opponentReveal,
    this.initialResolution,
    this.counterBid,
    this.finalDefense,
    this.finalResolution,
    this.corruption,
    Map<String, NetworkRecoveryDto>? recoveryByPlayer,
    Set<String>? recoveryDonePlayerIds,
  }) : commits = Map.unmodifiable(commits),
       actionPoints = Map.unmodifiable(actionPoints),
       readyNextPlayerIds = Set.unmodifiable(readyNextPlayerIds),
       tieDecisions = Map.unmodifiable(tieDecisions),
       recoveryByPlayer = Map.unmodifiable(recoveryByPlayer ?? const {}),
       recoveryDonePlayerIds = Set.unmodifiable(
         recoveryDonePlayerIds ?? const {},
       );

  final String roundId;
  final String sessionId;
  final String sessionRound;
  final int roundNumber;
  final NetworkGamePhase phase;
  final String playerId;
  final Map<String, String> commits;
  final Map<String, int> actionPoints;
  final Set<String> readyNextPlayerIds;
  final Map<String, TieDecision> tieDecisions;
  final ChoiceRevealDto? ownReveal;
  final ChoiceRevealDto? opponentReveal;
  final NetworkInitialResolutionDto? initialResolution;
  final NetworkAuctionBidDto? counterBid;
  final NetworkAuctionBidDto? finalDefense;
  final NetworkFinalResolutionDto? finalResolution;
  final NetworkCorruptionDto? corruption;
  final Map<String, NetworkRecoveryDto> recoveryByPlayer;
  final Set<String> recoveryDonePlayerIds;

  bool get ownCommitRecorded => commits.containsKey(playerId);
  bool get ownRevealRecorded => ownReveal != null;

  Map<String, Object?> toJson() => {
    'schema_version': networkSchemaVersion,
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
    'own_reveal': ownReveal?.toJson(),
    'opponent_reveal': opponentReveal?.toJson(),
    'initial_resolution': initialResolution?.toJson(),
    'counter_bid': counterBid?.toJson(),
    'final_defense': finalDefense?.toJson(),
    'final_resolution': finalResolution?.toJson(),
    'corruption': corruption?.toJson(),
    'recovery_by_player': {
      for (final entry in recoveryByPlayer.entries)
        entry.key: entry.value.toJson(),
    },
    'recovery_done': {for (final id in recoveryDonePlayerIds) id: true},
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
      ownReveal: reveal('own_reveal'),
      opponentReveal: reveal('opponent_reveal'),
      initialResolution: optional(
        'initial_resolution',
        NetworkInitialResolutionDto.fromJson,
      ),
      counterBid: optional('counter_bid', NetworkAuctionBidDto.fromJson),
      finalDefense: optional('final_defense', NetworkAuctionBidDto.fromJson),
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
    );
  }
}

abstract interface class NetworkGameRepository {
  Future<NetworkGameRoundStateDto> openCurrentRound({
    required NetworkCommandDto command,
  });

  Future<NetworkGameRoundStateDto> getCurrentRound({required String sessionId});

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
    required List<String> cardIds,
  });

  Future<NetworkGameRoundStateDto> respondCorruption({
    required NetworkCommandDto command,
    required bool accepted,
  });

  Future<NetworkGameRoundStateDto> resolveCorruption({
    required NetworkCommandDto command,
    required List<ActionPromise> actions,
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

String _phaseWire(NetworkGamePhase phase) => switch (phase) {
  NetworkGamePhase.commit => 'COMMIT',
  NetworkGamePhase.reveal => 'REVEAL',
  NetworkGamePhase.ready => 'READY',
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
};

NetworkGamePhase _phaseFromWire(String value) => switch (value) {
  'COMMIT' => NetworkGamePhase.commit,
  'REVEAL' => NetworkGamePhase.reveal,
  'READY' => NetworkGamePhase.ready,
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
  _ => throw FormatException('Unknown network game phase: $value'),
};
