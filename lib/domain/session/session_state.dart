import '../catalog/enums.dart';
import '../round/combat_value_snapshot.dart';

// Wire names are persisted. Renaming one requires a storage migration.
// ignore_for_file: constant_identifier_names
enum CardZone { POOL, HAND, RESERVED, ENGAGED, DISCARD, EXHAUSTED }

enum RoundPersistenceStatus { ACTIVE, INTERRUPTED, COMPLETED }

enum SessionPersistenceStatus { ACTIVE, PAUSED, COMPLETED }

/// Explicitly public projection. It intentionally cannot contain private data.
final class PublicSessionState {
  const PublicSessionState({
    required this.sessionId,
    required this.mode,
    required this.playerIds,
    this.currentRoundId,
  });

  final String sessionId;
  final SessionMode mode;
  final List<String> playerIds;
  final String? currentRoundId;

  Map<String, Object?> toJson() => <String, Object?>{
    'session_id': sessionId,
    'mode': mode.name,
    'player_ids': List<String>.unmodifiable(playerIds),
    'current_round_id': currentRoundId,
  };
}

/// Owner-only state. There is deliberately no inheritance relationship with
/// [PublicSessionState], so a private graph cannot be published by accident.
final class PrivatePlayerState {
  const PrivatePlayerState({
    required this.sessionId,
    required this.playerId,
    required this.actionPoints,
    required this.chiliLevel,
    this.style,
  });

  final String sessionId;
  final String playerId;
  final int actionPoints;
  final int chiliLevel;
  final String? style;

  Map<String, Object?> toJson() => <String, Object?>{
    'session_id': sessionId,
    'player_id': playerId,
    'action_points': actionPoints,
    'chili_level': chiliLevel,
    'style': style,
  };
}

final class PersistedPlayerState {
  const PersistedPlayerState({
    required this.playerId,
    required this.actionPoints,
    required this.chiliLevel,
    this.style,
    this.profileId,
  });

  final String playerId;
  final String? profileId;
  final int actionPoints;
  final int chiliLevel;
  final String? style;
}

final class PersistedCardState {
  const PersistedCardState({
    required this.playerId,
    required this.cardId,
    required this.zone,
    required this.ordinal,
    this.variantId,
    this.locked = false,
  });

  final String playerId;
  final String cardId;
  final String? variantId;
  final CardZone zone;
  final int ordinal;
  final bool locked;
}

final class PersistedRoundState {
  const PersistedRoundState({
    required this.roundId,
    required this.ordinal,
    required this.status,
    required this.state,
    required this.startedAt,
    required this.updatedAt,
  });

  final String roundId;
  final int ordinal;
  final RoundPersistenceStatus status;
  final Map<String, Object?> state;
  final DateTime startedAt;
  final DateTime updatedAt;
}

final class SessionCheckpoint {
  const SessionCheckpoint({
    required this.sessionId,
    required this.mode,
    required this.status,
    required this.players,
    required this.cards,
    required this.rounds,
    required this.snapshots,
    required this.createdAt,
    required this.updatedAt,
    this.interruptedRoundId,
  });

  final String sessionId;
  final SessionMode mode;
  final SessionPersistenceStatus status;
  final List<PersistedPlayerState> players;
  final List<PersistedCardState> cards;
  final List<PersistedRoundState> rounds;
  final List<PersistedCombatValueSnapshot> snapshots;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? interruptedRoundId;
}

final class PersistedCombatValueSnapshot {
  const PersistedCombatValueSnapshot({
    required this.roundId,
    required this.snapshot,
  });

  final String roundId;
  final CombatValueSnapshot snapshot;
}

final class StoredEvent {
  const StoredEvent({
    required this.sessionId,
    required this.eventId,
    required this.sequence,
    required this.type,
    required this.payload,
    required this.createdAt,
  });

  final String sessionId;
  final String eventId;
  final int sequence;
  final String type;
  final Map<String, Object?> payload;
  final DateTime createdAt;
}
