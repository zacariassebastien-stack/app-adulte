import 'lobby_models.dart';

abstract interface class LobbyRepository {
  Future<LobbySession> createSession({required String commandId});
  Future<LobbySession> joinSession({
    required String code,
    required String commandId,
  });
  Future<LobbySession> getSession(String sessionId);
  Stream<LobbySession> watchSession(String sessionId);
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
