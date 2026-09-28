import 'package:couple_cards/data/local/app_database.dart';
import 'package:couple_cards/data/repositories/event_log_repository.dart';
import 'package:couple_cards/domain/domain.dart';
import 'package:test/test.dart';

void main() {
  late AppDatabase database;
  late EventLogRepository repository;
  final now = DateTime.utc(2026, 9, 28, 10);
  StoredEvent event(
    String id,
    int sequence, {
    Map<String, Object?> payload = const {},
  }) => StoredEvent(
    sessionId: 'session.1',
    eventId: id,
    sequence: sequence,
    type: 'TEST',
    payload: payload,
    createdAt: now,
  );

  setUp(() {
    database = AppDatabase.memory();
    repository = EventLogRepository(database);
  });
  tearDown(() => database.close());

  test('returns events in sequence order', () async {
    await repository.append(event('e2', 2));
    await repository.append(event('e1', 1));
    expect((await repository.forSession('session.1')).map((e) => e.eventId), [
      'e1',
      'e2',
    ]);
  });

  test(
    'exact replay is idempotent and conflicting replay is rejected',
    () async {
      expect(await repository.append(event('e1', 1)), isTrue);
      expect(await repository.append(event('e1', 1)), isFalse);
      await expectLater(repository.append(event('e1', 2)), throwsStateError);
      expect((await repository.forSession('session.1')).length, 1);
    },
  );

  test('sequence uniqueness prevents duplicates', () async {
    await repository.append(event('e1', 1));
    await expectLater(repository.append(event('e2', 1)), throwsA(anything));
    expect((await repository.forSession('session.1')).length, 1);
  });

  test('appendAll is atomic', () async {
    await expectLater(
      repository.appendAll([event('e1', 1), event('e2', 1)]),
      throwsA(anything),
    );
    expect(await repository.forSession('session.1'), isEmpty);
  });

  test('EventLog rejects media references and bytes', () async {
    await expectLater(
      repository.append(event('e1', 1, payload: const {'photo': 'x'})),
      throwsArgumentError,
    );
    await expectLater(
      repository.append(
        event(
          'e2',
          2,
          payload: const {
            'blob': <int>[1, 2],
          },
        ),
      ),
      throwsArgumentError,
    );
  });
}
