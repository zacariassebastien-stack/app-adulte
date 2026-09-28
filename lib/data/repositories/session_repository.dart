import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/catalog/enums.dart';
import '../../domain/round/combat_value_snapshot.dart';
import '../../domain/session/session_state.dart';
import '../local/app_database.dart';
import '../local/media_guard.dart';

final class SessionRepository {
  SessionRepository(this.database);

  final AppDatabase database;

  /// Replaces one complete checkpoint in a single SQLite transaction.
  Future<void> save(SessionCheckpoint checkpoint) async {
    _validate(checkpoint);
    await database.transaction(() async {
      await database
          .into(database.sessions)
          .insertOnConflictUpdate(
            SessionsCompanion.insert(
              id: checkpoint.sessionId,
              mode: checkpoint.mode.name,
              status: checkpoint.status.name,
              interruptedRoundId: Value(checkpoint.interruptedRoundId),
              createdAt: checkpoint.createdAt,
              updatedAt: checkpoint.updatedAt,
            ),
          );
      await _deleteChildren(checkpoint.sessionId);
      await database.batch((batch) {
        batch.insertAll(database.sessionPlayers, [
          for (final player in checkpoint.players)
            SessionPlayersCompanion.insert(
              sessionId: checkpoint.sessionId,
              playerId: player.playerId,
              profileId: Value(player.profileId),
              actionPoints: player.actionPoints,
              chiliLevel: player.chiliLevel,
              style: Value(player.style),
            ),
        ]);
        batch.insertAll(database.sessionCards, [
          for (final card in checkpoint.cards)
            SessionCardsCompanion.insert(
              sessionId: checkpoint.sessionId,
              playerId: card.playerId,
              cardId: card.cardId,
              variantId: Value(card.variantId),
              zone: card.zone.name,
              ordinal: card.ordinal,
              locked: Value(card.locked),
            ),
        ]);
        batch.insertAll(database.rounds, [
          for (final round in checkpoint.rounds)
            RoundsCompanion.insert(
              sessionId: checkpoint.sessionId,
              roundId: round.roundId,
              ordinal: round.ordinal,
              status: round.status.name,
              stateJson: jsonEncode(round.state),
              startedAt: round.startedAt,
              updatedAt: round.updatedAt,
            ),
        ]);
        batch.insertAll(database.combatValueSnapshots, [
          for (final item in checkpoint.snapshots)
            CombatValueSnapshotsCompanion.insert(
              sessionId: checkpoint.sessionId,
              roundId: item.roundId,
              playerId: item.snapshot.playerId,
              cardId: item.snapshot.cardId,
              variantId: item.snapshot.variantId,
              roleAtCommit: item.snapshot.roleAtCommit.name,
              personalValue: item.snapshot.personalValue,
              committedAt: item.snapshot.committedAt,
            ),
        ]);
      });
    });
  }

  Future<SessionCheckpoint?> load(String sessionId) async {
    final sessionQuery = database.select(database.sessions)
      ..where((s) => s.id.equals(sessionId));
    final session = await sessionQuery.getSingleOrNull();
    if (session == null) return null;

    final playersQuery = database.select(database.sessionPlayers)
      ..where((p) => p.sessionId.equals(sessionId))
      ..orderBy([(p) => OrderingTerm.asc(p.playerId)]);
    final cardsQuery = database.select(database.sessionCards)
      ..where((c) => c.sessionId.equals(sessionId))
      ..orderBy([(c) => OrderingTerm.asc(c.ordinal)]);
    final roundsQuery = database.select(database.rounds)
      ..where((r) => r.sessionId.equals(sessionId))
      ..orderBy([(r) => OrderingTerm.asc(r.ordinal)]);
    final snapshotsQuery = database.select(database.combatValueSnapshots)
      ..where((s) => s.sessionId.equals(sessionId))
      ..orderBy([
        (s) => OrderingTerm.asc(s.roundId),
        (s) => OrderingTerm.asc(s.playerId),
      ]);

    final players = await playersQuery.get();
    final cards = await cardsQuery.get();
    final rounds = await roundsQuery.get();
    final snapshots = await snapshotsQuery.get();
    return SessionCheckpoint(
      sessionId: session.id,
      mode: SessionMode.values.byName(session.mode),
      status: SessionPersistenceStatus.values.byName(session.status),
      players: [
        for (final row in players)
          PersistedPlayerState(
            playerId: row.playerId,
            profileId: row.profileId,
            actionPoints: row.actionPoints,
            chiliLevel: row.chiliLevel,
            style: row.style,
          ),
      ],
      cards: [
        for (final row in cards)
          PersistedCardState(
            playerId: row.playerId,
            cardId: row.cardId,
            variantId: row.variantId,
            zone: CardZone.values.byName(row.zone),
            ordinal: row.ordinal,
            locked: row.locked,
          ),
      ],
      rounds: [
        for (final row in rounds)
          PersistedRoundState(
            roundId: row.roundId,
            ordinal: row.ordinal,
            status: RoundPersistenceStatus.values.byName(row.status),
            state: (jsonDecode(row.stateJson) as Map).cast<String, Object?>(),
            startedAt: row.startedAt,
            updatedAt: row.updatedAt,
          ),
      ],
      snapshots: [
        for (final row in snapshots)
          PersistedCombatValueSnapshot(
            roundId: row.roundId,
            snapshot: CombatValueSnapshot.fromJson(<String, Object?>{
              'player_id': row.playerId,
              'card_id': row.cardId,
              'variant_id': row.variantId,
              'role_at_commit': row.roleAtCommit,
              'personal_value': row.personalValue,
              'committed_at': row.committedAt.toUtc().toIso8601String(),
            }),
          ),
      ],
      createdAt: session.createdAt,
      updatedAt: session.updatedAt,
      interruptedRoundId: session.interruptedRoundId,
    );
  }

  Future<void> setCardLocked({
    required String sessionId,
    required String playerId,
    required String cardId,
    required bool locked,
  }) async {
    final changed =
        await (database.update(database.sessionCards)..where(
              (c) =>
                  c.sessionId.equals(sessionId) &
                  c.playerId.equals(playerId) &
                  c.cardId.equals(cardId),
            ))
            .write(SessionCardsCompanion(locked: Value(locked)));
    if (changed != 1) throw StateError('Card not found');
  }

  Future<void> delete(String sessionId) async {
    await database.transaction(() async {
      await _deleteChildren(sessionId);
      await (database.delete(
        database.eventLogs,
      )..where((e) => e.sessionId.equals(sessionId))).go();
      await (database.delete(
        database.sessions,
      )..where((s) => s.id.equals(sessionId))).go();
    });
  }

  Future<void> _deleteChildren(String sessionId) async {
    await (database.delete(
      database.combatValueSnapshots,
    )..where((s) => s.sessionId.equals(sessionId))).go();
    await (database.delete(
      database.rounds,
    )..where((r) => r.sessionId.equals(sessionId))).go();
    await (database.delete(
      database.sessionCards,
    )..where((c) => c.sessionId.equals(sessionId))).go();
    await (database.delete(
      database.sessionPlayers,
    )..where((p) => p.sessionId.equals(sessionId))).go();
  }

  static void _validate(SessionCheckpoint checkpoint) {
    if (checkpoint.sessionId.trim().isEmpty) {
      throw ArgumentError('sessionId is empty');
    }
    for (final player in checkpoint.players) {
      if (player.actionPoints < 0) {
        throw ArgumentError('PA cannot be negative');
      }
      if (player.chiliLevel < 1 || player.chiliLevel > 5) {
        throw ArgumentError('chiliLevel must be between 1 and 5');
      }
      if (player.style != null && player.style!.trim().isEmpty) {
        throw ArgumentError('style is empty');
      }
    }
    for (final round in checkpoint.rounds) {
      assertNoPersistedMedia(round.state);
    }
    if (checkpoint.interruptedRoundId != null &&
        !checkpoint.rounds.any(
          (round) =>
              round.roundId == checkpoint.interruptedRoundId &&
              round.status == RoundPersistenceStatus.INTERRUPTED,
        )) {
      throw ArgumentError(
        'interruptedRoundId must reference an interrupted round',
      );
    }
  }
}
