import '../commit_reveal/commit_reveal.dart';
import '../protocol/idempotency.dart';
import '../protocol/network_dtos.dart';

enum NetworkRoundPhase { commit, reveal, ready }

final class NetworkRoundStateDto {
  NetworkRoundStateDto({
    required this.roundId,
    required this.sessionId,
    required this.sessionRound,
    required this.roundNumber,
    required this.phase,
    required this.playerId,
    required Map<String, String> commits,
    this.ownReveal,
    this.opponentReveal,
  }) : commits = Map.unmodifiable(commits);

  final String roundId;
  final String sessionId;
  final String sessionRound;
  final int roundNumber;
  final NetworkRoundPhase phase;
  final String playerId;
  final Map<String, String> commits;
  final ChoiceRevealDto? ownReveal;
  final ChoiceRevealDto? opponentReveal;

  bool get ownCommitRecorded => commits.containsKey(playerId);
  bool get opponentCommitRecorded => commits.keys.any((id) => id != playerId);
  bool get ownRevealRecorded => ownReveal != null;

  Map<String, Object?> toJson() => {
    'schema_version': networkSchemaVersion,
    'round_id': roundId,
    'session_id': sessionId,
    'session_round': sessionRound,
    'round_number': roundNumber,
    'phase': phase.name.toUpperCase(),
    'player_id': playerId,
    'commits': commits,
    'own_reveal': ownReveal?.toJson(),
    'opponent_reveal': opponentReveal?.toJson(),
  };

  factory NetworkRoundStateDto.fromJson(Map<String, Object?> json) {
    if (json['schema_version'] != networkSchemaVersion) {
      throw const FormatException('Unsupported network schema version');
    }
    ChoiceRevealDto? reveal(String key) {
      final value = json[key];
      return value == null
          ? null
          : ChoiceRevealDto.fromJson(Map<String, Object?>.from(value as Map));
    }

    return NetworkRoundStateDto(
      roundId: json['round_id']! as String,
      sessionId: json['session_id']! as String,
      sessionRound: json['session_round']! as String,
      roundNumber: json['round_number']! as int,
      phase: NetworkRoundPhase.values.byName(
        (json['phase']! as String).toLowerCase(),
      ),
      playerId: json['player_id']! as String,
      commits: Map<String, String>.from(json['commits']! as Map),
      ownReveal: reveal('own_reveal'),
      opponentReveal: reveal('opponent_reveal'),
    );
  }
}

abstract interface class NetworkRoundRepository {
  Future<NetworkRoundStateDto> createRound({
    required NetworkCommandDto command,
    required int roundNumber,
  });

  Future<NetworkRoundStateDto> submitCommit({
    required NetworkCommandDto command,
    required ChoiceCommitmentDto commitment,
  });

  Future<NetworkRoundStateDto> submitReveal({
    required NetworkCommandDto command,
    required ChoiceRevealDto reveal,
  });

  Future<NetworkRoundStateDto> getRoundState({
    required String sessionId,
    required String roundId,
  });

  Stream<NetworkRoundStateDto> watchRoundState({
    required String sessionId,
    required String roundId,
  });
}

final class NetworkRoundException implements Exception {
  const NetworkRoundException(this.code);
  final String code;

  @override
  String toString() => code;
}
