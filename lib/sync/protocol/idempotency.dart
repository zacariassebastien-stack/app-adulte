import 'dart:collection';

import 'network_dtos.dart';

final class NetworkCommandDto {
  NetworkCommandDto({
    required this.commandId,
    required this.sessionId,
    required this.playerId,
    required this.type,
    required Map<String, Object?> payload,
  }) : payload = Map.unmodifiable(payload) {
    if (commandId.trim().isEmpty) throw ArgumentError('commandId is required');
  }

  final String commandId;
  final String sessionId;
  final String playerId;
  final String type;
  final Map<String, Object?> payload;

  Map<String, Object?> toJson() => {
    'schema_version': networkSchemaVersion,
    'command_id': commandId,
    'session_id': sessionId,
    'player_id': playerId,
    'type': type,
    'payload': _canonicalMap(payload),
  };

  factory NetworkCommandDto.fromJson(Map<String, Object?> json) {
    if (json['schema_version'] != networkSchemaVersion) {
      throw FormatException('Unsupported network schema version');
    }
    return NetworkCommandDto(
      commandId: json['command_id']! as String,
      sessionId: json['session_id']! as String,
      playerId: json['player_id']! as String,
      type: json['type']! as String,
      payload: Map<String, Object?>.from(json['payload']! as Map),
    );
  }
}

/// In-memory contract for future command handlers. A persistent transport may
/// replace the backing set without changing command identity semantics.
final class CommandIdRegistry {
  final Set<String> _processed = {};

  bool accept(String commandId) => _processed.add(commandId);
  bool contains(String commandId) => _processed.contains(commandId);
}

Map<String, Object?> _canonicalMap(Map<String, Object?> source) =>
    SplayTreeMap<String, Object?>.from({
      for (final entry in source.entries)
        entry.key: entry.value is Map<String, Object?>
            ? _canonicalMap(entry.value! as Map<String, Object?>)
            : entry.value,
    });
