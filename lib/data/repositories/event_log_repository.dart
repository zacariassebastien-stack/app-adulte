import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/session/session_state.dart';
import '../../domain/game/events.dart';
import '../local/app_database.dart';
import '../local/media_guard.dart';

final class EventLogRepository {
  EventLogRepository(this.database);

  final AppDatabase database;

  /// Returns false for an exact idempotent replay. Conflicting IDs or sequence
  /// numbers fail and never create a duplicate.
  Future<bool> append(StoredEvent event) =>
      database.transaction(() => _append(event));

  Future<void> appendAll(List<StoredEvent> events) async {
    await database.transaction(() async {
      for (final event in events) {
        await _append(event);
      }
    });
  }

  Future<bool> _append(StoredEvent event) async {
    assertNoPersistedMedia(event.payload);
    if (event.payload.containsKey('event_version')) {
      GameEvent.fromStored(event);
    }
    final payloadJson = jsonEncode(event.payload);
    final existingQuery = database.select(database.eventLogs)
      ..where(
        (e) =>
            e.sessionId.equals(event.sessionId) &
            e.eventId.equals(event.eventId),
      );
    final existing = await existingQuery.getSingleOrNull();
    if (existing != null) {
      final exact =
          existing.sequence == event.sequence &&
          existing.type == event.type &&
          existing.payloadJson == payloadJson &&
          existing.createdAt.isAtSameMomentAs(event.createdAt);
      if (exact) return false;
      throw StateError('Conflicting replay for event ${event.eventId}');
    }
    await database
        .into(database.eventLogs)
        .insert(
          EventLogsCompanion.insert(
            sessionId: event.sessionId,
            eventId: event.eventId,
            sequence: event.sequence,
            type: event.type,
            payloadJson: payloadJson,
            createdAt: event.createdAt,
          ),
        );
    return true;
  }

  Future<List<StoredEvent>> forSession(String sessionId) async {
    final query = database.select(database.eventLogs)
      ..where((e) => e.sessionId.equals(sessionId))
      ..orderBy([(e) => OrderingTerm.asc(e.sequence)]);
    return (await query.get())
        .map(
          (row) => StoredEvent(
            sessionId: row.sessionId,
            eventId: row.eventId,
            sequence: row.sequence,
            type: row.type,
            payload: (jsonDecode(row.payloadJson) as Map)
                .cast<String, Object?>(),
            createdAt: row.createdAt,
          ),
        )
        .toList(growable: false);
  }

  /// Local internal reader, never a partner-facing projection. Unknown future
  /// versions fail explicitly; forSession retains access to the original row.
  Future<List<GameEvent>> gameEventsForSession(String sessionId) async =>
      (await forSession(
        sessionId,
      )).map(GameEvent.fromStored).toList(growable: false);
}
