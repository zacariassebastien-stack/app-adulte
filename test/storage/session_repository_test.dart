import 'package:couple_cards/data/local/app_database.dart';
import 'package:couple_cards/data/repositories/event_log_repository.dart';
import 'package:couple_cards/data/repositories/session_repository.dart';
import 'package:couple_cards/domain/domain.dart';
import 'package:test/test.dart';

void main() {
  late AppDatabase database;
  late SessionRepository sessions;
  final now = DateTime.utc(2026, 9, 28, 9);

  SessionCheckpoint checkpoint({List<PersistedCardState>? cards}) =>
      SessionCheckpoint(
        sessionId: 'session.1',
        mode: SessionMode.face_to_face,
        status: SessionPersistenceStatus.PAUSED,
        players: const [
          PersistedPlayerState(
            playerId: 'alice',
            actionPoints: 42,
            chiliLevel: 3,
            style: 'TACTICAL',
          ),
          PersistedPlayerState(
            playerId: 'bob',
            actionPoints: 37,
            chiliLevel: 4,
            style: 'PLAYFUL',
          ),
        ],
        cards:
            cards ??
            const [
              PersistedCardState(
                playerId: 'alice',
                cardId: 'card.hand',
                zone: CardZone.HAND,
                ordinal: 0,
                locked: true,
              ),
              PersistedCardState(
                playerId: 'alice',
                cardId: 'card.engaged',
                zone: CardZone.ENGAGED,
                ordinal: 1,
              ),
              PersistedCardState(
                playerId: 'alice',
                cardId: 'card.discard',
                zone: CardZone.DISCARD,
                ordinal: 2,
              ),
              PersistedCardState(
                playerId: 'alice',
                cardId: 'card.exhausted',
                zone: CardZone.EXHAUSTED,
                ordinal: 3,
              ),
            ],
        rounds: [
          PersistedRoundState(
            roundId: 'round.7',
            ordinal: 7,
            status: RoundPersistenceStatus.INTERRUPTED,
            state: const {'step': 'awaiting_reveal'},
            startedAt: now,
            updatedAt: now,
          ),
        ],
        snapshots: [
          PersistedCombatValueSnapshot(
            roundId: 'round.7',
            snapshot: CombatValueSnapshot.fromJson({
              'player_id': 'alice',
              'card_id': 'card.engaged',
              'variant_id': 'variant.1',
              'role_at_commit': 'FAIRE',
              'personal_value': 17,
              'committed_at': now.toIso8601String(),
            }),
          ),
        ],
        createdAt: now,
        updatedAt: now,
        interruptedRoundId: 'round.7',
      );

  setUp(() {
    database = AppDatabase.memory();
    sessions = SessionRepository(database);
  });
  tearDown(() => database.close());

  test('saves and resumes complete interrupted session state', () async {
    await sessions.save(checkpoint());
    final saved = (await sessions.load('session.1'))!;
    expect(saved.players.map((p) => p.actionPoints), [42, 37]);
    expect(saved.players.map((p) => p.chiliLevel), [3, 4]);
    expect(saved.players.map((p) => p.style), ['TACTICAL', 'PLAYFUL']);
    expect(saved.cards.map((c) => c.zone), CardZone.values);
    expect(saved.cards.first.locked, isTrue);
    expect(saved.interruptedRoundId, 'round.7');
    expect(saved.rounds.single.status, RoundPersistenceStatus.INTERRUPTED);
    expect(saved.snapshots.single.snapshot.personalValue, 17);
    expect(saved.snapshots.single.snapshot.roleAtCommit, ProfileRole.FAIRE);
  });

  test('card lock is persisted independently', () async {
    await sessions.save(checkpoint());
    await sessions.setCardLocked(
      sessionId: 'session.1',
      playerId: 'alice',
      cardId: 'card.hand',
      locked: false,
    );
    expect((await sessions.load('session.1'))!.cards.first.locked, isFalse);
  });

  test('failed checkpoint replacement rolls back atomically', () async {
    await sessions.save(checkpoint());
    final duplicate = const PersistedCardState(
      playerId: 'alice',
      cardId: 'same',
      zone: CardZone.HAND,
      ordinal: 0,
    );
    await expectLater(
      sessions.save(checkpoint(cards: [duplicate, duplicate])),
      throwsA(anything),
    );
    final saved = (await sessions.load('session.1'))!;
    expect(saved.cards.length, 4);
    expect(saved.cards.first.cardId, 'card.hand');
  });

  test('session deletion also removes its EventLog', () async {
    await sessions.save(checkpoint());
    final events = EventLogRepository(database);
    await events.append(
      StoredEvent(
        sessionId: 'session.1',
        eventId: 'e1',
        sequence: 1,
        type: 'ROUND_SAVED',
        payload: const {},
        createdAt: now,
      ),
    );
    await sessions.delete('session.1');
    expect(await sessions.load('session.1'), isNull);
    expect(await events.forSession('session.1'), isEmpty);
  });

  test('round history rejects photo and video data', () async {
    final bad = checkpoint();
    final round = bad.rounds.single;
    final altered = SessionCheckpoint(
      sessionId: bad.sessionId,
      mode: bad.mode,
      status: bad.status,
      players: bad.players,
      cards: bad.cards,
      rounds: [
        PersistedRoundState(
          roundId: round.roundId,
          ordinal: round.ordinal,
          status: round.status,
          state: const {'video_path': 'x'},
          startedAt: now,
          updatedAt: now,
        ),
      ],
      snapshots: bad.snapshots,
      createdAt: now,
      updatedAt: now,
      interruptedRoundId: bad.interruptedRoundId,
    );
    expect(() => sessions.save(altered), throwsArgumentError);
  });

  test('public and private states serialize disjoint contracts', () {
    final public = PublicSessionState(
      sessionId: 's',
      mode: SessionMode.distance,
      playerIds: const ['a', 'b'],
    );
    const private = PrivatePlayerState(
      sessionId: 's',
      playerId: 'a',
      actionPoints: 9,
      chiliLevel: 2,
      style: 'CALM',
    );
    expect(public.toJson(), isNot(contains('action_points')));
    expect(public.toJson(), isNot(contains('style')));
    expect(private.toJson(), isNot(contains('player_ids')));
    expect(private.toJson(), isNot(contains('mode')));
  });
}
