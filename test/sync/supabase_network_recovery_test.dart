import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:couple_cards/data/remote/supabase_network_game_repository.dart';
import 'package:couple_cards/data/remote/supabase_lobby_repository.dart';
import 'package:couple_cards/sync/sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late HttpServer server;
  late SupabaseClient client;
  late SupabaseNetworkGameRepository repository;
  late Future<void> Function(HttpRequest) handle;
  final round = <String, Object?>{
    'round_id': 'round-1',
    'session_id': 'session',
    'session_round': 'session.round-1',
    'round_number': 1,
    'phase': 'COMMIT',
    'player_id': 'bob',
    'usage_contract_version': 1,
    'commits': <String, String>{'alice': 'existing-commit'},
    'action_points': {'alice': 100, 'bob': 100},
  };

  Future<void> reply(HttpRequest request, Object body) async {
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(body));
    await request.response.close();
  }

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      await request.drain<void>();
      await handle(request);
    });
    client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    await client.auth.recoverSession(
      jsonEncode({
        'access_token': 'local-test-token',
        'token_type': 'bearer',
        'user': {
          'id': 'bob',
          'app_metadata': <String, Object?>{},
          'user_metadata': <String, Object?>{},
          'aud': 'authenticated',
          'created_at': '2026-01-01T00:00:00Z',
        },
      }),
    );
    repository = SupabaseNetworkGameRepository(
      client: client,
      requestTimeout: const Duration(milliseconds: 500),
    );
  });

  tearDown(() async {
    await client.dispose();
    await server.close(force: true);
  });

  test(
    'stalled canonical read expires, releases coalescing and ignores late response',
    () async {
      final firstReceived = Completer<HttpRequest>();
      final secondReceived = Completer<HttpRequest>();
      var reads = 0;
      handle = (request) async {
        if (request.uri.path.endsWith('/get_current_network_game_round')) {
          reads++;
          if (reads == 1) {
            firstReceived.complete(request);
            return;
          }
          if (reads == 2) {
            secondReceived.complete(request);
            return;
          }
          await reply(request, round);
        } else {
          await reply(request, {'revision': 2});
        }
      };
      final first = repository.getCurrentRound(sessionId: 'session');
      final firstFailure = expectLater(first, throwsA(isA<TimeoutException>()));
      await firstReceived.future;
      await firstFailure;
      final second = repository.getCurrentRound(sessionId: 'session');
      final pending = await secondReceived.future;
      await reply(await firstReceived.future, {...round, 'round_number': 0});
      final shared = repository.getCurrentRound(sessionId: 'session');
      await reply(pending, round);
      final results = await Future.wait([second, shared]);
      expect(
        results.every((r) => r.roundNumber == 1 && r.roundRevision == 2),
        isTrue,
      );
      expect(results.first.commits['alice'], 'existing-commit');
      // Each transport read also verifies the revision. The late read may finish
      // its read-only verification; it cannot complete the expired future again.
      // The shared caller adds no extra read.
      expect(reads, 4);
    },
  );

  test(
    'session nickname RPC and restored session keep explicit player IDs',
    () async {
      final calls = <String>[];
      final session = {
        'id': 'session',
        'join_code': 'ABCDEF',
        'status': 'ready',
        'expires_at': '2027-01-01T00:00:00Z',
        'players': [
          {'user_id': 'bob', 'role': 'PLAYER_2', 'game_nickname': 'Julie'},
          {'user_id': 'alice', 'role': 'PLAYER_1', 'game_nickname': 'Seb'},
        ],
      };
      handle = (request) async {
        calls.add(request.uri.path.split('/').last);
        await reply(request, session);
      };
      final lobby = SupabaseLobbyRepository(client: client);
      final updated = await lobby.setGameNickname(
        sessionId: 'session',
        nickname: 'Julie',
      );
      final restored = await lobby.getSession('session');
      expect(updated.participantNames, {'alice': 'Seb', 'bob': 'Julie'});
      expect(restored.participantNames, updated.participantNames);
      expect(calls, ['set_session_game_nickname', 'get_game_session']);
    },
  );

  test(
    'stalled command times out without automatically resending it',
    () async {
      final received = Completer<HttpRequest>();
      var commands = 0;
      handle = (request) async {
        if (request.uri.path.endsWith('/close_network_game_session')) {
          commands++;
          received.complete(request);
        } else if (request.uri.path.contains('/rpc/')) {
          await reply(request, round);
        } else {
          await reply(request, {'revision': 2});
        }
      };
      final operation = repository.closeSession(
        command: NetworkCommandDto(
          commandId: 'existing-command',
          sessionId: 'session',
          playerId: 'bob',
          type: 'CLOSE_SESSION',
          payload: {'round_id': 'round-1'},
        ),
      );
      await expectLater(operation, throwsA(isA<TimeoutException>()));
      await reply(await received.future, round);
      final canonical = await repository.getCurrentRound(sessionId: 'session');
      expect(canonical.roundId, 'round-1');
      expect(commands, 1);
    },
  );
}
