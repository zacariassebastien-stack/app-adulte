import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:couple_cards/data/catalog_loader/catalog_loader.dart';
import 'package:couple_cards/domain/domain.dart';
import 'package:couple_cards/features/game/network_duel_controller.dart';
import 'package:couple_cards/features/game/network_duel_secret_store.dart';
import 'package:couple_cards/features/lobby/lobby_models.dart';
import 'package:couple_cards/sync/sync.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Catalog catalog;
  late LobbySession session;

  setUpAll(() async {
    catalog = await const CatalogLoader().load(
      (path) => File(path).readAsString(),
    );
    session = LobbySession(
      id: '11111111-1111-1111-1111-111111111111',
      joinCode: 'ABC234',
      status: LobbyStatus.ready,
      expiresAt: DateTime.utc(2026, 9, 30),
      players: const [
        LobbyPlayer(userId: 'alice', role: LobbyPlayerRole.player1),
        LobbyPlayer(userId: 'bob', role: LobbyPlayerRole.player2),
      ],
    );
  });

  test('two private hands use the real draw and eligibility engines', () async {
    final backend = _RoundBackend();
    final alice = _controller(backend, session, catalog, 'alice');
    final bob = _controller(backend, session, catalog, 'bob');
    await Future.wait([alice.start(), bob.start()]);

    expect(alice.hand, hasLength(4));
    expect(bob.hand, hasLength(4));
    expect(
      alice.hand.every((card) => catalog.cards.contains(card.definition)),
      isTrue,
    );
    expect(
      bob.hand.every((card) => catalog.cards.contains(card.definition)),
      isTrue,
    );
    expect(jsonEncode(alice.round!.toJson()), isNot(contains('hand')));
    expect(jsonEncode(bob.round!.toJson()), isNot(contains('personal_value')));
    expect(backend.roundCreations, 1);
    alice.dispose();
    bob.dispose();
  });

  test('one commit waits and discloses no choice or nonce', () async {
    final backend = _RoundBackend();
    final alice = _controller(backend, session, catalog, 'alice');
    final bob = _controller(backend, session, catalog, 'bob');
    await Future.wait([alice.start(), bob.start()]);
    alice.selectCard(alice.hand.first.id);
    await alice.confirmSelection();

    expect(alice.state, NetworkDuelViewState.waitingForPartner);
    expect(bob.state, NetworkDuelViewState.choosing);
    expect(backend.commits, hasLength(1));
    expect(backend.reveals, isEmpty);
    final publicState = jsonEncode(backend.state('bob').toJson());
    expect(publicState, isNot(contains(alice.hand.first.id)));
    expect(publicState, isNot(contains('nonce-alice')));
    alice.dispose();
    bob.dispose();
  });

  test(
    'two commits reveal automatically and resolve identically once',
    () async {
      final backend = _RoundBackend();
      final alice = _controller(backend, session, catalog, 'alice');
      final bob = _controller(backend, session, catalog, 'bob');
      await Future.wait([alice.start(), bob.start()]);
      final aliceCard = alice.hand.first;
      final bobCard = bob.hand.last;
      alice.selectCard(aliceCard.id);
      bob.selectCard(bobCard.id);
      await alice.confirmSelection();
      await bob.confirmSelection();
      await _settle();

      expect(backend.commits, hasLength(2));
      expect(backend.reveals, hasLength(2));
      expect(alice.round!.phase, NetworkRoundPhase.ready);
      expect(bob.round!.phase, NetworkRoundPhase.ready);
      expect(alice.state, NetworkDuelViewState.resolved);
      expect(bob.state, NetworkDuelViewState.resolved);
      expect(alice.resolution!.winnerPlayerId, bob.resolution!.winnerPlayerId);
      expect(alice.resolution!.gap, bob.resolution!.gap);
      expect(alice.resolution!.gapCost, bob.resolution!.gapCost);
      expect(alice.resolution!.actionPoints, bob.resolution!.actionPoints);
      expect(_snapshot(alice, 'alice').personalValue, aliceCard.personalValue);
      expect(_snapshot(bob, 'bob').personalValue, bobCard.personalValue);

      backend.notify();
      backend.notify();
      await _settle();
      expect(alice.resolutionCount, 1);
      expect(bob.resolutionCount, 1);
      alice.dispose();
      bob.dispose();
    },
  );

  test(
    'invalid reveal is refused and READY requires both valid reveals',
    () async {
      final backend = _RoundBackend();
      final aliceRepository = backend.repository('alice');
      final bobRepository = backend.repository('bob');
      final created = await aliceRepository.createRound(
        command: _command('create-a', 'alice', 'CREATE'),
        roundNumber: 1,
      );
      final aliceChoice = ChoicePayload(
        cardId: 'card.hug',
        variantId: 'variant.hug.base',
        parameters: const {},
      );
      final bobChoice = ChoicePayload(
        cardId: 'card.kiss_me',
        variantId: 'variant.kiss_me.base',
        parameters: const {},
      );
      const contract = CommitRevealContract();
      for (final item in [
        ('alice', aliceChoice, 'a', aliceRepository),
        ('bob', bobChoice, 'b', bobRepository),
      ]) {
        await item.$4.submitCommit(
          command: _command(
            'commit-${item.$1}',
            item.$1,
            'COMMIT',
            created.roundId,
          ),
          commitment: contract.commit(
            sessionRound: created.sessionRound,
            playerId: item.$1,
            choice: item.$2,
            nonce: item.$3,
          ),
        );
      }
      expect(backend.phase, NetworkRoundPhase.reveal);
      await expectLater(
        aliceRepository.submitReveal(
          command: _command('bad-reveal', 'alice', 'REVEAL', created.roundId),
          reveal: ChoiceRevealDto(
            sessionRound: created.sessionRound,
            playerId: 'alice',
            choice: aliceChoice,
            nonce: 'wrong',
          ),
        ),
        throwsA(isA<NetworkRoundException>()),
      );
      expect(backend.phase, NetworkRoundPhase.reveal);
      expect(backend.reveals, isEmpty);
    },
  );

  test(
    'reconnection resumes round 1 with the locally persisted secret',
    () async {
      final backend = _RoundBackend();
      final store = MemoryNetworkDuelSecretStore();
      final first = _controller(
        backend,
        session,
        catalog,
        'alice',
        store: store,
      );
      await first.start();
      first.selectCard(first.hand.first.id);
      await first.confirmSelection();
      first.dispose();

      final resumed = _controller(
        backend,
        session,
        catalog,
        'alice',
        store: store,
      );
      await resumed.start();
      expect(resumed.round!.roundNumber, 1);
      expect(resumed.state, NetworkDuelViewState.waitingForPartner);
      expect(backend.roundCreations, 1);
      expect(backend.commits, hasLength(1));
      resumed.dispose();
    },
  );
}

CombatValueSnapshot _snapshot(NetworkDuelController controller, String id) {
  final duel = controller.resolution!;
  return duel.first.snapshot.playerId == id
      ? duel.first.snapshot
      : duel.second.snapshot;
}

NetworkDuelController _controller(
  _RoundBackend backend,
  LobbySession session,
  Catalog catalog,
  String playerId, {
  NetworkDuelSecretStore? store,
}) => NetworkDuelController(
  session: session,
  playerId: playerId,
  repository: backend.repository(playerId),
  secretStore: store ?? MemoryNetworkDuelSecretStore(),
  catalog: catalog,
  nonceFactory: () => 'nonce-$playerId',
  clock: () => DateTime.utc(2026, 9, 29, 12),
);

Future<void> _settle() async {
  for (var index = 0; index < 12; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}

NetworkCommandDto _command(
  String id,
  String player,
  String type, [
  String? roundId,
]) => NetworkCommandDto(
  commandId: id,
  sessionId: '11111111-1111-1111-1111-111111111111',
  playerId: player,
  type: type,
  payload: {'round_id': ?roundId},
);

final class _RoundBackend {
  static const sessionId = '11111111-1111-1111-1111-111111111111';
  static const roundId = '22222222-2222-2222-2222-222222222222';
  static const sessionRound = '$sessionId.round-1';

  final commits = <String, ChoiceCommitmentDto>{};
  final reveals = <String, ChoiceRevealDto>{};
  final commands = <String, String>{};
  final _changes = StreamController<void>.broadcast();
  bool created = false;
  int roundCreations = 0;

  NetworkRoundPhase get phase => commits.length < 2
      ? NetworkRoundPhase.commit
      : reveals.length < 2
      ? NetworkRoundPhase.reveal
      : NetworkRoundPhase.ready;

  NetworkRoundRepository repository(String playerId) =>
      _RoundRepository(this, playerId);

  NetworkRoundStateDto state(String playerId) => NetworkRoundStateDto(
    roundId: roundId,
    sessionId: sessionId,
    sessionRound: sessionRound,
    roundNumber: 1,
    phase: phase,
    playerId: playerId,
    commits: {for (final item in commits.entries) item.key: item.value.digest},
    ownReveal: reveals[playerId],
    opponentReveal: phase == NetworkRoundPhase.ready
        ? reveals.entries.firstWhere((item) => item.key != playerId).value
        : null,
  );

  void notify() => _changes.add(null);
}

final class _RoundRepository implements NetworkRoundRepository {
  _RoundRepository(this.backend, this.playerId);
  final _RoundBackend backend;
  final String playerId;

  @override
  Future<NetworkRoundStateDto> createRound({
    required NetworkCommandDto command,
    required int roundNumber,
  }) async {
    if (!backend.created) {
      backend.created = true;
      backend.roundCreations++;
    }
    return backend.state(playerId);
  }

  @override
  Future<NetworkRoundStateDto> submitCommit({
    required NetworkCommandDto command,
    required ChoiceCommitmentDto commitment,
  }) async {
    if (backend.commands[command.commandId] case final kind?) {
      if (kind != 'COMMIT') throw const NetworkRoundException('CONFLICT');
      return backend.state(playerId);
    }
    if (backend.phase != NetworkRoundPhase.commit) {
      throw const NetworkRoundException('ROUND_COMMIT_CLOSED');
    }
    backend.commands[command.commandId] = 'COMMIT';
    backend.commits[playerId] = commitment;
    backend.notify();
    return backend.state(playerId);
  }

  @override
  Future<NetworkRoundStateDto> submitReveal({
    required NetworkCommandDto command,
    required ChoiceRevealDto reveal,
  }) async {
    if (backend.commands[command.commandId] case final kind?) {
      if (kind != 'REVEAL') throw const NetworkRoundException('CONFLICT');
      return backend.state(playerId);
    }
    if (backend.phase != NetworkRoundPhase.reveal) {
      throw const NetworkRoundException('ROUND_REVEAL_CLOSED');
    }
    if (!const CommitRevealContract().verify(
      backend.commits[playerId]!,
      reveal,
    )) {
      throw const NetworkRoundException('ROUND_REVEAL_MISMATCH');
    }
    backend.commands[command.commandId] = 'REVEAL';
    backend.reveals[playerId] = reveal;
    backend.notify();
    return backend.state(playerId);
  }

  @override
  Future<NetworkRoundStateDto> getRoundState({
    required String sessionId,
    required String roundId,
  }) async => backend.state(playerId);

  @override
  Stream<NetworkRoundStateDto> watchRoundState({
    required String sessionId,
    required String roundId,
  }) async* {
    yield backend.state(playerId);
    await for (final _ in backend._changes.stream) {
      yield backend.state(playerId);
    }
  }
}
