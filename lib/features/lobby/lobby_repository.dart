import 'lobby_models.dart';
import '../../sync/rounds/network_round.dart';

abstract interface class LobbyRepository {
  Future<LobbySession> createSession({required String commandId});
  Future<LobbySession> joinSession({
    required String code,
    required String commandId,
  });
  Future<LobbySession> getSession(String sessionId);
  Stream<LobbySession> watchSession(String sessionId);
}

/// Capabilities available only when the real two-phone backend is configured.
abstract interface class NetworkLobbyRepository implements LobbyRepository {
  NetworkRoundRepository get roundRepository;
  Future<String> currentPlayerId();
}

final class UnavailableLobbyRepository implements LobbyRepository {
  const UnavailableLobbyRepository();

  Never _unavailable() => throw const LobbyConfigurationException();

  @override
  Future<LobbySession> createSession({required String commandId}) async =>
      _unavailable();
  @override
  Future<LobbySession> joinSession({
    required String code,
    required String commandId,
  }) async => _unavailable();
  @override
  Future<LobbySession> getSession(String sessionId) async => _unavailable();
  @override
  Stream<LobbySession> watchSession(String sessionId) =>
      Stream.error(const LobbyConfigurationException());
}
