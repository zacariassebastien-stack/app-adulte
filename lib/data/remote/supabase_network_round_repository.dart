import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../sync/commit_reveal/commit_reveal.dart';
import '../../sync/protocol/idempotency.dart';
import '../../sync/rounds/network_round.dart';

final class SupabaseNetworkRoundRepository implements NetworkRoundRepository {
  SupabaseNetworkRoundRepository({required this.client});

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
  Future<NetworkRoundStateDto> createRound({
    required NetworkCommandDto command,
    required int roundNumber,
  }) => _rpc(
    'create_network_round',
    command,
    extra: {'p_round_number': roundNumber},
  );

  @override
  Future<NetworkRoundStateDto> submitCommit({
    required NetworkCommandDto command,
    required ChoiceCommitmentDto commitment,
  }) {
    _requireMatchingPlayer(command, commitment.playerId);
    return _rpc(
      'submit_network_round_commit',
      command,
      roundId: command.payload['round_id'] as String?,
      extra: {'p_digest': commitment.digest},
    );
  }

  @override
  Future<NetworkRoundStateDto> submitReveal({
    required NetworkCommandDto command,
    required ChoiceRevealDto reveal,
  }) {
    _requireMatchingPlayer(command, reveal.playerId);
    return _rpc(
      'submit_network_round_reveal',
      command,
      roundId: command.payload['round_id'] as String?,
      extra: {
        'p_choice_payload': reveal.choice.toJson(),
        'p_nonce': reveal.nonce,
      },
    );
  }

  @override
  Future<NetworkRoundStateDto> getRoundState({
    required String sessionId,
    required String roundId,
  }) async {
    final playerId = await _identity();
    try {
      return _map(
        await client.rpc<Object?>(
          'get_network_round_state',
          params: {
            'p_session_id': sessionId,
            'p_round_id': roundId,
            'p_player_id': playerId,
          },
        ),
      );
    } on PostgrestException catch (error) {
      throw _translate(error, operation: 'get_network_round_state');
    }
  }

  @override
  Stream<NetworkRoundStateDto> watchRoundState({
    required String sessionId,
    required String roundId,
  }) async* {
    await _identity();
    yield await getRoundState(sessionId: sessionId, roundId: roundId);
    await for (final _
        in client
            .from('network_rounds')
            .stream(primaryKey: ['id'])
            .eq('id', roundId)) {
      yield await getRoundState(sessionId: sessionId, roundId: roundId);
    }
  }

  Future<NetworkRoundStateDto> _rpc(
    String function,
    NetworkCommandDto command, {
    String? roundId,
    Map<String, Object?> extra = const {},
  }) async {
    final identity = await _identity();
    _requireMatchingPlayer(command, identity);
    if (roundId == null && function != 'create_network_round') {
      throw const NetworkRoundException('ROUND_ID_REQUIRED');
    }
    try {
      return _map(
        await client.rpc<Object?>(
          function,
          params: {
            'p_session_id': command.sessionId,
            'p_round_id': ?roundId,
            'p_player_id': command.playerId,
            'p_command_id': command.commandId,
            ...extra,
          },
        ),
      );
    } on PostgrestException catch (error) {
      throw _translate(error, operation: function);
    } on AuthException {
      throw const NetworkRoundException('ROUND_AUTH_REQUIRED');
    }
  }

  void _requireMatchingPlayer(NetworkCommandDto command, String playerId) {
    if (command.playerId != playerId) {
      throw const NetworkRoundException('ROUND_IDENTITY_MISMATCH');
    }
  }

  NetworkRoundStateDto _map(Object? value) {
    if (value is Map<String, dynamic>) {
      return NetworkRoundStateDto.fromJson(value.cast<String, Object?>());
    }
    if (value is List && value.length == 1 && value.first is Map) {
      return NetworkRoundStateDto.fromJson(
        Map<String, Object?>.from(value.first! as Map),
      );
    }
    throw const FormatException('Invalid Supabase network round response');
  }

  NetworkRoundException _translate(
    PostgrestException error, {
    required String operation,
  }) {
    final marker = '${error.message} ${error.details ?? ''}';
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
    ];
    final publicCode = codes.firstWhere(
      marker.contains,
      orElse: () => 'ROUND_NETWORK_ERROR',
    );
    final diagnostic =
        '$operation: PostgREST ${error.code} ${_safeMessage(error.message)}';
    if (kDebugMode) debugPrint('Network round RPC failed: $diagnostic');
    return NetworkRoundException(publicCode, diagnostic: diagnostic);
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
