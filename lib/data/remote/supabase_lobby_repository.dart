import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/lobby/join_code.dart';
import '../../features/lobby/lobby_models.dart';
import '../../features/lobby/lobby_repository.dart';

final class SupabaseLobbyRepository implements LobbyRepository {
  SupabaseLobbyRepository({
    required this.client,
    JoinCodeGenerator? codeGenerator,
  }) : codeGenerator = codeGenerator ?? JoinCodeGenerator();

  final SupabaseClient client;
  final JoinCodeGenerator codeGenerator;

  Future<String> _identity() async {
    final existing = client.auth.currentUser;
    if (existing != null) return existing.id;
    final response = await client.auth.signInAnonymously();
    final id = response.user?.id;
    if (id == null) throw const LobbyNetworkException();
    return id;
  }

  @override
  Future<LobbySession> createSession({required String commandId}) async {
    await _identity();
    for (var attempt = 0; attempt < 6; attempt++) {
      try {
        final result = await client.rpc<Map<String, dynamic>>(
          'create_game_session',
          params: {
            'p_join_code': codeGenerator.generate(),
            'p_command_id': commandId,
          },
        );
        return _map(result);
      } on PostgrestException catch (error) {
        if (error.code == '23505') continue;
        throw _translate(error);
      } on AuthException {
        throw const LobbyNetworkException();
      }
    }
    throw const LobbyNetworkException();
  }

  @override
  Future<LobbySession> joinSession({
    required String code,
    required String commandId,
  }) async {
    await _identity();
    try {
      final result = await client.rpc<Map<String, dynamic>>(
        'join_game_session',
        params: {
          'p_join_code': JoinCode.normalize(code),
          'p_command_id': commandId,
        },
      );
      return _map(result);
    } on PostgrestException catch (error) {
      throw _translate(error);
    } on AuthException {
      throw const LobbyNetworkException();
    }
  }

  @override
  Future<LobbySession> getSession(String sessionId) async {
    await _identity();
    try {
      return _map(
        await client.rpc<Map<String, dynamic>>(
          'get_game_session',
          params: {'p_session_id': sessionId},
        ),
      );
    } on PostgrestException catch (error) {
      throw _translate(error);
    }
  }

  @override
  Stream<LobbySession> watchSession(String sessionId) async* {
    await _identity();
    yield await getSession(sessionId);
    await for (final _
        in client
            .from('session_players')
            .stream(primaryKey: ['session_id', 'user_id'])
            .eq('session_id', sessionId)) {
      yield await getSession(sessionId);
    }
  }

  LobbySession _map(Object? value) {
    if (value is Map<String, dynamic>) {
      return LobbySession.fromSupabaseJson(value.cast<String, Object?>());
    }
    if (value is List && value.length == 1 && value.first is Map) {
      return LobbySession.fromSupabaseJson(
        Map<String, Object?>.from(value.first! as Map),
      );
    }
    throw const FormatException('Invalid Supabase lobby response');
  }

  LobbyException _translate(PostgrestException error) {
    final marker = '${error.message} ${error.details ?? ''}';
    if (marker.contains('LOBBY_NOT_FOUND')) {
      return const InvalidJoinCodeException();
    }
    if (marker.contains('LOBBY_EXPIRED')) {
      return const ExpiredLobbyException();
    }
    if (marker.contains('LOBBY_FULL')) return const FullLobbyException();
    return const LobbyNetworkException();
  }
}
