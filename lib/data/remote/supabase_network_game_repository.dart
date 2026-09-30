import 'dart:async';
import 'dart:developer' as developer;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../engines/auction/auction_engine.dart';
import '../../engines/corruption/corruption_engine.dart';
import '../../engines/recovery/recovery_engine.dart';
import '../../sync/sync.dart';

final class SupabaseNetworkGameRepository implements NetworkGameRepository {
  SupabaseNetworkGameRepository({required this.client});

  final SupabaseClient client;

  Future<String> _identity() async {
    final existing = client.auth.currentUser;
    if (existing != null) return existing.id;
    final response = await client.auth.signInAnonymously();
    final id = response.user?.id;
    if (id == null) throw const NetworkRoundException('ROUND_AUTH_REQUIRED');
    return id;
  }

  @override
  Future<NetworkGameRoundStateDto> openCurrentRound({
    required NetworkCommandDto command,
  }) => _rpc('open_network_game_round', command);

  @override
  Future<NetworkGameRoundStateDto> getCurrentRound({
    required String sessionId,
  }) async {
    final playerId = await _identity();
    return _call('get_current_network_game_round', {
      'p_session_id': sessionId,
      'p_player_id': playerId,
    });
  }

  @override
  Future<NetworkGameRoundStateDto> submitCommit({
    required NetworkCommandDto command,
    required ChoiceCommitmentDto commitment,
  }) {
    _matching(command, commitment.playerId);
    return _rpc(
      'submit_network_round_commit',
      command,
      extra: {'p_digest': commitment.digest},
    );
  }

  @override
  Future<NetworkGameRoundStateDto> submitReveal({
    required NetworkCommandDto command,
    required ChoiceRevealDto reveal,
  }) {
    _matching(command, reveal.playerId);
    return _rpc(
      'submit_network_round_reveal',
      command,
      extra: {
        'p_choice_payload': reveal.choice.toJson(),
        'p_nonce': reveal.nonce,
      },
    );
  }

  @override
  Future<NetworkGameRoundStateDto> submitInitialResolution({
    required NetworkCommandDto command,
    required NetworkInitialResolutionDto resolution,
  }) => _rpc(
    'submit_network_initial_resolution',
    command,
    extra: {'p_resolution': resolution.toJson()},
  );

  @override
  Future<NetworkGameRoundStateDto> submitCounterDecision({
    required NetworkCommandDto command,
    required CounterDecision decision,
    int? amount,
    AuctionTarget? target,
  }) => _rpc(
    'submit_network_counter_decision',
    command,
    extra: {
      'p_decision': decision.name.toUpperCase(),
      'p_amount': amount,
      'p_target': target?.name,
    },
  );

  @override
  Future<NetworkGameRoundStateDto> submitFinalDefense({
    required NetworkCommandDto command,
    required FinalDefenseDecision decision,
    int? amount,
  }) => _rpc(
    'submit_network_final_defense',
    command,
    extra: {
      'p_decision': switch (decision) {
        FinalDefenseDecision.renounce => 'YIELD',
        FinalDefenseDecision.defend => 'DEFEND',
      },
      'p_amount': amount,
    },
  );

  @override
  Future<NetworkGameRoundStateDto> submitTieDecision({
    required NetworkCommandDto command,
    required TieDecision decision,
  }) => _rpc(
    'submit_network_tie_decision',
    command,
    extra: {'p_decision': decision.name.toUpperCase()},
  );

  @override
  Future<NetworkGameRoundStateDto> submitCorruptionOffer({
    required NetworkCommandDto command,
    required CorruptionObjective objective,
    required List<String> cardIds,
  }) => _rpc(
    'submit_network_corruption_offer',
    command,
    extra: {'p_objective': objective.name, 'p_card_ids': cardIds},
  );

  @override
  Future<NetworkGameRoundStateDto> respondCorruption({
    required NetworkCommandDto command,
    required bool accepted,
  }) => _rpc(
    'respond_network_corruption',
    command,
    extra: {'p_accepted': accepted},
  );

  @override
  Future<NetworkGameRoundStateDto> resolveCorruption({
    required NetworkCommandDto command,
    required List<ActionPromise> actions,
  }) => _rpc(
    'resolve_network_corruption',
    command,
    extra: {
      'p_actions': [
        for (final action in actions)
          {
            'card_id': action.cardId,
            'source': action.source.name,
            'status': action.status.name,
            'visibility': action.visibility.name,
          },
      ],
    },
  );

  @override
  Future<NetworkGameRoundStateDto> skipCorruption({
    required NetworkCommandDto command,
  }) => _rpc('skip_network_corruption', command);

  @override
  Future<NetworkGameRoundStateDto> submitRecovery({
    required NetworkCommandDto command,
    required NetworkRecoveryDto recovery,
  }) => _rpc(
    'submit_network_recovery',
    command,
    extra: {'p_recovery': recovery.toJson()},
  );

  @override
  Future<NetworkGameRoundStateDto> respondRecovery({
    required NetworkCommandDto command,
    required RecoveryResponse response,
  }) => _rpc(
    'respond_network_recovery',
    command,
    extra: {'p_response': response.name},
  );

  @override
  Future<NetworkGameRoundStateDto> resolveRecovery({
    required NetworkCommandDto command,
    required NetworkRecoveryDto recovery,
  }) => _rpc(
    'resolve_network_recovery',
    command,
    extra: {'p_recovery': recovery.toJson()},
  );

  @override
  Future<NetworkGameRoundStateDto> skipRecovery({
    required NetworkCommandDto command,
  }) => _rpc('skip_network_recovery', command);

  @override
  Future<NetworkGameRoundStateDto> readyNextRound({
    required NetworkCommandDto command,
  }) => _rpc('ready_network_next_round', command);

  @override
  Stream<NetworkGameRoundStateDto> watchRound({
    required String sessionId,
    required String roundId,
  }) async* {
    await _identity();
    yield await getCurrentRound(sessionId: sessionId);
    await for (final _
        in client
            .from('network_rounds')
            .stream(primaryKey: ['id'])
            .eq('id', roundId)) {
      yield await getCurrentRound(sessionId: sessionId);
    }
  }

  Future<NetworkGameRoundStateDto> _rpc(
    String function,
    NetworkCommandDto command, {
    Map<String, Object?> extra = const {},
  }) async {
    final identity = await _identity();
    _matching(command, identity);
    final roundId = command.payload['round_id'] as String?;
    return _call(function, {
      'p_session_id': command.sessionId,
      'p_round_id': ?roundId,
      'p_player_id': command.playerId,
      'p_command_id': command.commandId,
      ...extra,
    });
  }

  Future<NetworkGameRoundStateDto> _call(
    String function,
    Map<String, Object?> parameters,
  ) async {
    try {
      return _map(await client.rpc<Object?>(function, params: parameters));
    } on PostgrestException catch (error) {
      final diagnostic =
          '$function: PostgREST ${error.code} ${_safeMessage(error.message)}';
      developer.log('Network game RPC failed: $diagnostic');
      throw NetworkRoundException(
        _knownCode('${error.message} ${error.details ?? ''}'),
        diagnostic: diagnostic,
      );
    } on AuthException {
      throw const NetworkRoundException('ROUND_AUTH_REQUIRED');
    }
  }

  void _matching(NetworkCommandDto command, String playerId) {
    if (command.playerId != playerId) {
      throw const NetworkRoundException('ROUND_IDENTITY_MISMATCH');
    }
  }

  NetworkGameRoundStateDto _map(Object? value) {
    if (value is Map<String, dynamic>) {
      return NetworkGameRoundStateDto.fromJson(value.cast<String, Object?>());
    }
    if (value is List && value.length == 1 && value.first is Map) {
      return NetworkGameRoundStateDto.fromJson(
        Map<String, Object?>.from(value.first! as Map),
      );
    }
    throw const FormatException('Invalid Supabase network game response');
  }

  String _knownCode(String marker) {
    const codes = [
      'ROUND_AUTH_REQUIRED',
      'ROUND_IDENTITY_MISMATCH',
      'ROUND_NOT_MEMBER',
      'ROUND_SESSION_NOT_READY',
      'ROUND_NOT_FOUND',
      'ROUND_COMMAND_CONFLICT',
      'ROUND_COMMIT_CLOSED',
      'ROUND_REVEAL_CLOSED',
      'ROUND_COMMIT_MISSING',
      'ROUND_REVEAL_MISMATCH',
      'ROUND_INVALID_ARGUMENT',
      'ROUND_INVALID_PHASE',
      'ROUND_NOT_ACTIVE_PLAYER',
      'ROUND_INVALID_BID',
      'ROUND_INSUFFICIENT_PA',
      'ROUND_INVERSION_FORBIDDEN',
      'ROUND_RESOLUTION_MISMATCH',
      'ROUND_CORRUPTION_FORBIDDEN',
      'ROUND_RECOVERY_NOT_ELIGIBLE',
    ];
    return codes.firstWhere(
      marker.contains,
      orElse: () => 'ROUND_NETWORK_ERROR',
    );
  }

  String _safeMessage(String message) => message
      .replaceAll(RegExp(r"'([^']|'')*'"), "'<redacted>'")
      .replaceAll(RegExp(r'\{[^}]*\}'), '<redacted-json>')
      .replaceAll(RegExp(r'\[[^\]]*\]'), '<redacted-json>')
      .replaceAll(
        RegExp(
          r'\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b',
        ),
        '<redacted-id>',
      )
      .replaceAll(RegExp(r'\b[0-9a-fA-F]{32,}\b'), '<redacted-secret>')
      .replaceAll(RegExp(r'eyJ[A-Za-z0-9._-]+'), '<redacted-token>');
}
