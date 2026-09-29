enum LobbyStatus { waiting, ready, closed }

enum LobbyPlayerRole { player1, player2 }

final class LobbyPlayer {
  const LobbyPlayer({required this.userId, required this.role});

  final String userId;
  final LobbyPlayerRole role;
}

final class LobbySession {
  LobbySession({
    required this.id,
    required this.joinCode,
    required this.status,
    required this.expiresAt,
    required List<LobbyPlayer> players,
  }) : players = List.unmodifiable(players);

  final String id;
  final String joinCode;
  final LobbyStatus status;
  final DateTime expiresAt;
  final List<LobbyPlayer> players;

  bool get ready => status == LobbyStatus.ready && players.length == 2;

  factory LobbySession.fromSupabaseJson(Map<String, Object?> json) {
    final playersJson = json['players'] as List? ?? const [];
    return LobbySession(
      id: json['id']! as String,
      joinCode: json['join_code']! as String,
      status: LobbyStatus.values.byName(json['status']! as String),
      expiresAt: DateTime.parse(json['expires_at']! as String),
      players: [
        for (final value in playersJson)
          if (Map<String, Object?>.from(value! as Map) case final player)
            LobbyPlayer(
              userId: player['user_id']! as String,
              role: switch (player['role']! as String) {
                'PLAYER_1' => LobbyPlayerRole.player1,
                'PLAYER_2' => LobbyPlayerRole.player2,
                final role => throw FormatException(
                  'Unknown lobby role: $role',
                ),
              },
            ),
      ],
    );
  }
}

sealed class LobbyException implements Exception {
  const LobbyException(this.message);
  final String message;
  @override
  String toString() => message;
}

final class InvalidJoinCodeException extends LobbyException {
  const InvalidJoinCodeException() : super('Code de partie introuvable.');
}

final class ExpiredLobbyException extends LobbyException {
  const ExpiredLobbyException() : super('Cette partie a expiré.');
}

final class FullLobbyException extends LobbyException {
  const FullLobbyException() : super('Cette partie est déjà complète.');
}

final class LobbyNetworkException extends LobbyException {
  const LobbyNetworkException()
    : super('Connexion perdue. Vérifiez le réseau puis réessayez.');
}

final class LobbyConfigurationException extends LobbyException {
  const LobbyConfigurationException()
    : super('Supabase doit être configuré pour jouer à deux.');
}
