import 'dart:convert';
import 'dart:io';

import 'package:couple_cards/sync/sync.dart';
import 'package:test/test.dart';

void main() {
  const contract = CommitRevealContract();
  final aliceChoice = ChoicePayload(
    cardId: 'card-a',
    variantId: 'variant-a',
    parameters: const {'duration': 10},
  );
  final bobChoice = ChoicePayload(
    cardId: 'card-b',
    variantId: 'variant-b',
    parameters: const {'duration': 20},
  );

  ChoiceCommitmentDto commitment(
    String player,
    ChoicePayload choice,
    String nonce,
  ) => contract.commit(
    sessionRound: 'session-1.round-1',
    playerId: player,
    choice: choice,
    nonce: nonce,
  );

  ChoiceRevealDto reveal(String player, ChoicePayload choice, String nonce) =>
      ChoiceRevealDto(
        sessionRound: 'session-1.round-1',
        playerId: player,
        choice: choice,
        nonce: nonce,
      );

  NetworkCommandDto command(
    String id,
    String player,
    String type, {
    String session = 'session-1',
    String round = 'round-1',
  }) => NetworkCommandDto(
    commandId: id,
    sessionId: session,
    playerId: player,
    type: type,
    payload: {'round_id': round},
  );

  test('two members commit and duplicate command is idempotent', () async {
    final backend = _FakeRoundBackend(contract: contract);
    final alice = backend.repository('alice');
    final bob = backend.repository('bob');
    await alice.createRound(
      command: command('create', 'alice', 'CREATE'),
      roundNumber: 1,
    );
    final first = await alice.submitCommit(
      command: command('commit-a', 'alice', 'COMMIT'),
      commitment: commitment('alice', aliceChoice, 'nonce-a'),
    );
    final duplicate = await alice.submitCommit(
      command: command('commit-a', 'alice', 'COMMIT'),
      commitment: commitment('alice', aliceChoice, 'nonce-a'),
    );

    expect(first.phase, NetworkRoundPhase.commit);
    expect(duplicate.commits, first.commits);
    expect(duplicate.commits, hasLength(1));
    final both = await bob.submitCommit(
      command: command('commit-b', 'bob', 'COMMIT'),
      commitment: commitment('bob', bobChoice, 'nonce-b'),
    );
    expect(both.phase, NetworkRoundPhase.reveal);
    expect(both.commits, hasLength(2));
  });

  test('payload and nonce stay hidden before reveal is authorized', () async {
    final backend = _FakeRoundBackend(contract: contract);
    final alice = backend.repository('alice');
    await alice.createRound(
      command: command('create', 'alice', 'CREATE'),
      roundNumber: 1,
    );
    final state = await alice.submitCommit(
      command: command('commit-a', 'alice', 'COMMIT'),
      commitment: commitment('alice', aliceChoice, 'nonce-a'),
    );
    final encoded = jsonEncode(state.toJson());

    expect(encoded, isNot(contains('card-a')));
    expect(encoded, isNot(contains('nonce-a')));
    expect(state.opponentReveal, isNull);
  });

  test('reveal is refused before both commits', () async {
    final backend = _FakeRoundBackend(contract: contract);
    final alice = backend.repository('alice');
    await alice.createRound(
      command: command('create', 'alice', 'CREATE'),
      roundNumber: 1,
    );
    await alice.submitCommit(
      command: command('commit-a', 'alice', 'COMMIT'),
      commitment: commitment('alice', aliceChoice, 'nonce-a'),
    );

    expect(
      () => alice.submitReveal(
        command: command('reveal-a', 'alice', 'REVEAL'),
        reveal: reveal('alice', aliceChoice, 'nonce-a'),
      ),
      throwsA(_code('ROUND_REVEAL_CLOSED')),
    );
  });

  test('valid reveals become mutually visible only when both exist', () async {
    final backend = _FakeRoundBackend(contract: contract);
    final alice = backend.repository('alice');
    final bob = backend.repository('bob');
    await _readyForReveal(backend, aliceChoice, bobChoice, contract);
    final first = await alice.submitReveal(
      command: command('reveal-a', 'alice', 'REVEAL'),
      reveal: reveal('alice', aliceChoice, 'nonce-a'),
    );
    expect(first.ownRevealRecorded, isTrue);
    expect(first.opponentReveal, isNull);

    final ready = await bob.submitReveal(
      command: command('reveal-b', 'bob', 'REVEAL'),
      reveal: reveal('bob', bobChoice, 'nonce-b'),
    );
    expect(ready.phase, NetworkRoundPhase.ready);
    expect(ready.opponentReveal?.playerId, 'alice');
    final reconnected = await alice.getRoundState(
      sessionId: 'session-1',
      roundId: 'round-1',
    );
    expect(reconnected.ownReveal?.playerId, 'alice');
    expect(reconnected.opponentReveal?.playerId, 'bob');
  });

  test('wrong nonce and modified payload are rejected', () async {
    final backend = _FakeRoundBackend(contract: contract);
    final alice = backend.repository('alice');
    await _readyForReveal(backend, aliceChoice, bobChoice, contract);

    expect(
      () => alice.submitReveal(
        command: command('bad-nonce', 'alice', 'REVEAL'),
        reveal: reveal('alice', aliceChoice, 'wrong'),
      ),
      throwsA(_code('ROUND_REVEAL_MISMATCH')),
    );
    expect(
      () => alice.submitReveal(
        command: command('bad-payload', 'alice', 'REVEAL'),
        reveal: reveal(
          'alice',
          ChoicePayload(
            cardId: 'changed',
            variantId: 'variant-a',
            parameters: const {'duration': 10},
          ),
          'nonce-a',
        ),
      ),
      throwsA(_code('ROUND_REVEAL_MISMATCH')),
    );
  });

  test('foreign player and mismatched session or round are refused', () async {
    final backend = _FakeRoundBackend(contract: contract);
    final alice = backend.repository('alice');
    await alice.createRound(
      command: command('create', 'alice', 'CREATE'),
      roundNumber: 1,
    );
    expect(
      () => backend
          .repository('mallory')
          .getRoundState(sessionId: 'session-1', roundId: 'round-1'),
      throwsA(_code('ROUND_NOT_MEMBER')),
    );
    expect(
      () => alice.getRoundState(sessionId: 'wrong-session', roundId: 'round-1'),
      throwsA(_code('ROUND_NOT_FOUND')),
    );
    expect(
      () => alice.getRoundState(sessionId: 'session-1', roundId: 'wrong-round'),
      throwsA(_code('ROUND_NOT_FOUND')),
    );
  });

  test('round DTO round-trips without unrelated private fields', () async {
    final backend = _FakeRoundBackend(contract: contract);
    final alice = backend.repository('alice');
    final state = await alice.createRound(
      command: command('create', 'alice', 'CREATE'),
      roundNumber: 1,
    );
    final json = state.toJson();
    final encoded = jsonEncode(json);
    expect(NetworkRoundStateDto.fromJson(json).toJson(), json);
    for (final forbidden in [
      'hand',
      'personal_values',
      'preferences',
      'consent',
      'draw_style',
    ]) {
      expect(encoded, isNot(contains(forbidden)));
    }
  });

  test('migration protects reveals behind security-definer RPCs', () {
    final sql = File(
      'supabase/migrations/202609290002_network_duel_round.sql',
    ).readAsStringSync();
    expect(
      sql,
      contains(
        'alter table public.network_round_reveals enable row level security',
      ),
    );
    expect(
      sql,
      contains(
        'revoke all on public.network_round_reveals from anon, authenticated',
      ),
    );
    expect(sql, contains('security definer'));
    expect(sql, contains("if v_round.phase <> 'REVEAL'"));
    expect(sql, contains("raise exception 'ROUND_REVEAL_MISMATCH'"));
  });
}

Matcher _code(String code) => predicate<Object>(
  (error) => error is NetworkRoundException && error.code == code,
);

Future<void> _readyForReveal(
  _FakeRoundBackend backend,
  ChoicePayload aliceChoice,
  ChoicePayload bobChoice,
  CommitRevealContract contract,
) async {
  final alice = backend.repository('alice');
  final bob = backend.repository('bob');
  await alice.createRound(
    command: NetworkCommandDto(
      commandId: 'create',
      sessionId: 'session-1',
      playerId: 'alice',
      type: 'CREATE',
      payload: const {'round_id': 'round-1'},
    ),
    roundNumber: 1,
  );
  for (final entry in [
    ('alice', aliceChoice, 'nonce-a', alice),
    ('bob', bobChoice, 'nonce-b', bob),
  ]) {
    await entry.$4.submitCommit(
      command: NetworkCommandDto(
        commandId: 'commit-${entry.$1}',
        sessionId: 'session-1',
        playerId: entry.$1,
        type: 'COMMIT',
        payload: const {'round_id': 'round-1'},
      ),
      commitment: contract.commit(
        sessionRound: 'session-1.round-1',
        playerId: entry.$1,
        choice: entry.$2,
        nonce: entry.$3,
      ),
    );
  }
}

final class _FakeRoundBackend {
  _FakeRoundBackend({required this.contract});
  final CommitRevealContract contract;
  final members = const {'alice', 'bob'};
  final commits = <String, ChoiceCommitmentDto>{};
  final reveals = <String, ChoiceRevealDto>{};
  final commands = <String, String>{};
  bool created = false;

  NetworkRoundRepository repository(String playerId) =>
      _FakeRoundRepository(this, playerId);

  NetworkRoundPhase get phase => !created || commits.length < 2
      ? NetworkRoundPhase.commit
      : reveals.length < 2
      ? NetworkRoundPhase.reveal
      : NetworkRoundPhase.ready;

  NetworkRoundStateDto state(String playerId) => NetworkRoundStateDto(
    roundId: 'round-1',
    sessionId: 'session-1',
    sessionRound: 'session-1.round-1',
    roundNumber: 1,
    phase: phase,
    playerId: playerId,
    commits: {for (final item in commits.entries) item.key: item.value.digest},
    ownReveal: reveals[playerId],
    opponentReveal: phase == NetworkRoundPhase.ready
        ? reveals.entries.firstWhere((item) => item.key != playerId).value
        : null,
  );
}

final class _FakeRoundRepository implements NetworkRoundRepository {
  _FakeRoundRepository(this.backend, this.playerId);
  final _FakeRoundBackend backend;
  final String playerId;

  void _member() {
    if (!backend.members.contains(playerId)) {
      throw const NetworkRoundException('ROUND_NOT_MEMBER');
    }
  }

  void _target(String sessionId, String roundId) {
    _member();
    if (!backend.created || sessionId != 'session-1' || roundId != 'round-1') {
      throw const NetworkRoundException('ROUND_NOT_FOUND');
    }
  }

  @override
  Future<NetworkRoundStateDto> createRound({
    required NetworkCommandDto command,
    required int roundNumber,
  }) async {
    _member();
    if (command.sessionId != 'session-1' || roundNumber != 1) {
      throw const NetworkRoundException('ROUND_NOT_FOUND');
    }
    backend.created = true;
    backend.commands[command.commandId] = 'CREATE';
    return backend.state(playerId);
  }

  @override
  Future<NetworkRoundStateDto> submitCommit({
    required NetworkCommandDto command,
    required ChoiceCommitmentDto commitment,
  }) async {
    _target(command.sessionId, command.payload['round_id']! as String);
    if (backend.commands[command.commandId] case final existing?) {
      if (existing != 'COMMIT') {
        throw const NetworkRoundException('ROUND_COMMAND_CONFLICT');
      }
      return backend.state(playerId);
    }
    if (backend.phase != NetworkRoundPhase.commit) {
      throw const NetworkRoundException('ROUND_COMMIT_CLOSED');
    }
    backend.commands[command.commandId] = 'COMMIT';
    backend.commits[playerId] = commitment;
    return backend.state(playerId);
  }

  @override
  Future<NetworkRoundStateDto> submitReveal({
    required NetworkCommandDto command,
    required ChoiceRevealDto reveal,
  }) async {
    _target(command.sessionId, command.payload['round_id']! as String);
    if (backend.phase != NetworkRoundPhase.reveal) {
      throw const NetworkRoundException('ROUND_REVEAL_CLOSED');
    }
    final commitment = backend.commits[playerId]!;
    if (!backend.contract.verify(commitment, reveal)) {
      throw const NetworkRoundException('ROUND_REVEAL_MISMATCH');
    }
    backend.commands[command.commandId] = 'REVEAL';
    backend.reveals[playerId] = reveal;
    return backend.state(playerId);
  }

  @override
  Future<NetworkRoundStateDto> getRoundState({
    required String sessionId,
    required String roundId,
  }) async {
    _target(sessionId, roundId);
    return backend.state(playerId);
  }

  @override
  Stream<NetworkRoundStateDto> watchRoundState({
    required String sessionId,
    required String roundId,
  }) async* {
    yield await getRoundState(sessionId: sessionId, roundId: roundId);
  }
}
