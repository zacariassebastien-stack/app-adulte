import 'dart:async';
import 'dart:math';

import 'package:couple_cards/features/lobby/join_code.dart';
import 'package:couple_cards/features/lobby/lobby_controller.dart';
import 'package:couple_cards/features/lobby/lobby_models.dart';
import 'package:couple_cards/features/lobby/lobby_repository.dart';
import 'package:couple_cards/features/lobby/two_phone_lobby_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('join codes are human-safe, normalized and validated', () {
    final generator = JoinCodeGenerator(random: Random(42));
    final codes = {
      for (var index = 0; index < 20; index++) generator.generate(),
    };

    expect(codes, hasLength(20));
    expect(codes, everyElement(predicate<String>(JoinCode.isValid)));
    expect(JoinCode.normalize(' abcd23 '), 'ABCD23');
    expect(JoinCode.isValid('O0I1AA'), isFalse);
  });

  test('session creation registers PLAYER_1 and waits', () async {
    final backend = FakeLobbyBackend();
    final host = backend.repository('host');
    final session = await host.createSession(commandId: 'create-1');

    expect(session.status, LobbyStatus.waiting);
    expect(session.players.single.role, LobbyPlayerRole.player1);
    expect(session.joinCode, 'ABC234');
  });

  test('second player joins and both observers receive ready', () async {
    final backend = FakeLobbyBackend();
    final host = backend.repository('host');
    final guest = backend.repository('guest');
    final created = await host.createSession(commandId: 'create-1');
    final update = host
        .watchSession(created.id)
        .firstWhere((item) => item.ready);

    final joined = await guest.joinSession(
      code: created.joinCode,
      commandId: 'join-1',
    );

    expect(joined.ready, isTrue);
    expect((await update).players, hasLength(2));
  });

  test('third player is refused', () async {
    final backend = FakeLobbyBackend();
    final created = await backend
        .repository('host')
        .createSession(commandId: 'create-1');
    await backend
        .repository('guest')
        .joinSession(code: created.joinCode, commandId: 'join-1');

    expect(
      () => backend
          .repository('third')
          .joinSession(code: created.joinCode, commandId: 'join-2'),
      throwsA(isA<FullLobbyException>()),
    );
  });

  test('invalid and expired codes are refused distinctly', () async {
    final backend = FakeLobbyBackend();
    expect(
      () => backend
          .repository('guest')
          .joinSession(code: 'ZZZ999', commandId: 'join-1'),
      throwsA(isA<InvalidJoinCodeException>()),
    );
    final created = await backend
        .repository('host')
        .createSession(commandId: 'create-1');
    backend.expire(created.id);
    expect(
      () => backend
          .repository('guest')
          .joinSession(code: created.joinCode, commandId: 'join-2'),
      throwsA(isA<ExpiredLobbyException>()),
    );
  });

  test('join command is idempotent', () async {
    final backend = FakeLobbyBackend();
    final created = await backend
        .repository('host')
        .createSession(commandId: 'create-1');
    final guest = backend.repository('guest');
    final first = await guest.joinSession(
      code: created.joinCode,
      commandId: 'same-command',
    );
    final second = await guest.joinSession(
      code: created.joinCode,
      commandId: 'same-command',
    );

    expect(second.id, first.id);
    expect(second.players, hasLength(2));
  });

  test('Supabase DTO mapping keeps lobby fields', () {
    final lobby = LobbySession.fromSupabaseJson({
      'id': 'session-id',
      'join_code': 'ABC234',
      'status': 'ready',
      'expires_at': '2026-09-29T14:00:00Z',
      'players': [
        {'user_id': 'a', 'role': 'PLAYER_1'},
        {'user_id': 'b', 'role': 'PLAYER_2'},
      ],
    });

    expect(lobby.id, 'session-id');
    expect(lobby.ready, isTrue);
    expect(lobby.expiresAt, DateTime.utc(2026, 9, 29, 14));
  });

  test(
    'controller ignores double create and reaches ready via stream',
    () async {
      final backend = FakeLobbyBackend();
      final controller = LobbyController(
        repository: backend.repository('host'),
        commandIdFactory: () => 'create-1',
      );
      final first = controller.create();
      final duplicate = controller.create();
      await Future.wait([first, duplicate]);
      expect(backend.createCalls, 1);
      expect(controller.state, LobbyViewState.waiting);

      await backend
          .repository('guest')
          .joinSession(code: controller.session!.joinCode, commandId: 'join-1');
      await Future<void>.delayed(Duration.zero);
      expect(controller.state, LobbyViewState.ready);
      controller.dispose();
    },
  );

  test('controller exposes network loss and retry', () async {
    final backend = FakeLobbyBackend();
    final controller = LobbyController(
      repository: backend.repository('host'),
      commandIdFactory: () => 'create-1',
    );
    await controller.create();
    backend.failStreams();
    await Future<void>.delayed(Duration.zero);
    expect(controller.state, LobbyViewState.offline);
    await controller.retry();
    expect(controller.state, LobbyViewState.waiting);
    controller.dispose();
  });

  testWidgets('UI creates a lobby then displays ready automatically', (
    tester,
  ) async {
    final backend = FakeLobbyBackend();
    await tester.pumpWidget(
      MaterialApp(
        home: TwoPhoneLobbyScreen(repository: backend.repository('host')),
      ),
    );
    await tester.tap(find.byKey(const Key('create-lobby')));
    await tester.pump();
    expect(find.byKey(const Key('lobby-waiting')), findsOneWidget);
    expect(find.text('ABC234'), findsOneWidget);

    await backend
        .repository('guest')
        .joinSession(code: 'ABC234', commandId: 'join-1');
    await tester.pump();
    expect(find.byKey(const Key('lobby-ready')), findsOneWidget);
    expect(find.text('2/2 joueurs connectés'), findsOneWidget);
  });
}

final class FakeLobbyBackend {
  final sessions = <String, LobbySession>{};
  final commands = <String, String>{};
  final changes = StreamController<LobbySession>.broadcast();
  int createCalls = 0;

  LobbyRepository repository(String userId) =>
      _FakeLobbyRepository(this, userId);

  void expire(String id) {
    final current = sessions[id]!;
    sessions[id] = LobbySession(
      id: current.id,
      joinCode: current.joinCode,
      status: current.status,
      expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
      players: current.players,
    );
  }

  void failStreams() => changes.addError(const LobbyNetworkException());
}

final class _FakeLobbyRepository implements LobbyRepository {
  _FakeLobbyRepository(this.backend, this.userId);
  final FakeLobbyBackend backend;
  final String userId;

  @override
  Future<LobbySession> createSession({required String commandId}) async {
    backend.createCalls++;
    if (backend.commands[commandId] case final existing?) {
      return backend.sessions[existing]!;
    }
    final id = 'session-${backend.sessions.length + 1}';
    final session = LobbySession(
      id: id,
      joinCode: 'ABC234',
      status: LobbyStatus.waiting,
      expiresAt: DateTime.now().add(const Duration(hours: 2)),
      players: [LobbyPlayer(userId: userId, role: LobbyPlayerRole.player1)],
    );
    backend.sessions[id] = session;
    backend.commands[commandId] = id;
    return session;
  }

  @override
  Future<LobbySession> joinSession({
    required String code,
    required String commandId,
  }) async {
    if (backend.commands[commandId] case final existing?) {
      return backend.sessions[existing]!;
    }
    final session = backend.sessions.values
        .where((item) => item.joinCode == JoinCode.normalize(code))
        .firstOrNull;
    if (session == null) throw const InvalidJoinCodeException();
    if (session.expiresAt.isBefore(DateTime.now())) {
      throw const ExpiredLobbyException();
    }
    if (session.players.any((player) => player.userId == userId)) {
      return session;
    }
    if (session.players.length >= 2) throw const FullLobbyException();
    final ready = LobbySession(
      id: session.id,
      joinCode: session.joinCode,
      status: LobbyStatus.ready,
      expiresAt: session.expiresAt,
      players: [
        ...session.players,
        LobbyPlayer(userId: userId, role: LobbyPlayerRole.player2),
      ],
    );
    backend.sessions[session.id] = ready;
    backend.commands[commandId] = session.id;
    backend.changes.add(ready);
    return ready;
  }

  @override
  Future<LobbySession> getSession(String sessionId) async =>
      backend.sessions[sessionId]!;

  @override
  Stream<LobbySession> watchSession(String sessionId) =>
      backend.changes.stream.where((session) => session.id == sessionId);
}
