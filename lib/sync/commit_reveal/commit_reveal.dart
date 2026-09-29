import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../protocol/network_dtos.dart';

final class ChoicePayload {
  ChoicePayload({
    required this.cardId,
    required this.variantId,
    required Map<String, Object?> parameters,
  }) : parameters = Map.unmodifiable(parameters);

  final String cardId;
  final String variantId;
  final Map<String, Object?> parameters;

  Map<String, Object?> toJson() => {
    'card_id': cardId,
    'parameters': _canonicalObject(parameters),
    'variant_id': variantId,
  };

  factory ChoicePayload.fromJson(Map<String, Object?> json) => ChoicePayload(
    cardId: json['card_id']! as String,
    variantId: json['variant_id']! as String,
    parameters: Map<String, Object?>.from(json['parameters']! as Map),
  );

  String canonicalJson() => jsonEncode(_canonicalObject(toJson()));
}

final class ChoiceCommitmentDto {
  const ChoiceCommitmentDto({
    required this.sessionRound,
    required this.playerId,
    required this.digest,
  });

  final String sessionRound;
  final String playerId;
  final String digest;

  Map<String, Object?> toJson() => {
    'schema_version': networkSchemaVersion,
    'session_round': sessionRound,
    'player_id': playerId,
    'digest': digest,
  };

  factory ChoiceCommitmentDto.fromJson(Map<String, Object?> json) {
    if (json['schema_version'] != networkSchemaVersion) {
      throw FormatException('Unsupported network schema version');
    }
    return ChoiceCommitmentDto(
      sessionRound: json['session_round']! as String,
      playerId: json['player_id']! as String,
      digest: json['digest']! as String,
    );
  }
}

final class ChoiceRevealDto {
  const ChoiceRevealDto({
    required this.sessionRound,
    required this.playerId,
    required this.choice,
    required this.nonce,
  });

  final String sessionRound;
  final String playerId;
  final ChoicePayload choice;
  final String nonce;

  Map<String, Object?> toJson() => {
    'schema_version': networkSchemaVersion,
    'session_round': sessionRound,
    'player_id': playerId,
    'choice': choice.toJson(),
    'nonce': nonce,
  };

  factory ChoiceRevealDto.fromJson(Map<String, Object?> json) {
    if (json['schema_version'] != networkSchemaVersion) {
      throw FormatException('Unsupported network schema version');
    }
    return ChoiceRevealDto(
      sessionRound: json['session_round']! as String,
      playerId: json['player_id']! as String,
      choice: ChoicePayload.fromJson(
        Map<String, Object?>.from(json['choice']! as Map),
      ),
      nonce: json['nonce']! as String,
    );
  }
}

final class CommitRevealContract {
  const CommitRevealContract();

  ChoiceCommitmentDto commit({
    required String sessionRound,
    required String playerId,
    required ChoicePayload choice,
    required String nonce,
  }) => ChoiceCommitmentDto(
    sessionRound: sessionRound,
    playerId: playerId,
    digest: _digest(sessionRound, playerId, choice, nonce),
  );

  bool verify(ChoiceCommitmentDto commitment, ChoiceRevealDto reveal) {
    if (commitment.sessionRound != reveal.sessionRound ||
        commitment.playerId != reveal.playerId) {
      return false;
    }
    final actual = _digest(
      reveal.sessionRound,
      reveal.playerId,
      reveal.choice,
      reveal.nonce,
    );
    return _constantTimeEquals(commitment.digest, actual);
  }

  String _digest(
    String sessionRound,
    String playerId,
    ChoicePayload choice,
    String nonce,
  ) {
    if (sessionRound.isEmpty || playerId.isEmpty || nonce.isEmpty) {
      throw ArgumentError('Commit/reveal identifiers and nonce are required');
    }
    final envelope = jsonEncode([
      sessionRound,
      playerId,
      choice.canonicalJson(),
      nonce,
    ]);
    return sha256.convert(utf8.encode(envelope)).toString();
  }
}

Object? _canonicalObject(Object? value) {
  if (value is Map) {
    return SplayTreeMap<String, Object?>.from({
      for (final entry in value.entries)
        entry.key as String: _canonicalObject(entry.value),
    });
  }
  if (value is List) return [for (final item in value) _canonicalObject(item)];
  if (value == null || value is String || value is bool || value is num) {
    return value;
  }
  throw ArgumentError('Choice parameters must be JSON values');
}

bool _constantTimeEquals(String left, String right) {
  if (left.length != right.length) return false;
  var difference = 0;
  for (var index = 0; index < left.length; index++) {
    difference |= left.codeUnitAt(index) ^ right.codeUnitAt(index);
  }
  return difference == 0;
}
