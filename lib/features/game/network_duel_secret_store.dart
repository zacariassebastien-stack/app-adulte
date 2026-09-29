import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../sync/commit_reveal/commit_reveal.dart';

abstract interface class NetworkDuelSecretStore {
  Future<void> save({
    required String sessionId,
    required String playerId,
    required ChoiceRevealDto reveal,
  });

  Future<ChoiceRevealDto?> load({
    required String sessionId,
    required String playerId,
  });

  Future<void> clear({required String sessionId, required String playerId});
}

final class SharedPreferencesNetworkDuelSecretStore
    implements NetworkDuelSecretStore {
  const SharedPreferencesNetworkDuelSecretStore();

  String _key(String sessionId, String playerId) =>
      'network_duel_secret.$sessionId.$playerId';

  @override
  Future<void> save({
    required String sessionId,
    required String playerId,
    required ChoiceRevealDto reveal,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _key(sessionId, playerId),
      jsonEncode(reveal.toJson()),
    );
  }

  @override
  Future<ChoiceRevealDto?> load({
    required String sessionId,
    required String playerId,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_key(sessionId, playerId));
    if (encoded == null) return null;
    return ChoiceRevealDto.fromJson(
      Map<String, Object?>.from(jsonDecode(encoded) as Map),
    );
  }

  @override
  Future<void> clear({
    required String sessionId,
    required String playerId,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_key(sessionId, playerId));
  }
}

final class MemoryNetworkDuelSecretStore implements NetworkDuelSecretStore {
  final Map<String, ChoiceRevealDto> _values = {};

  String _key(String sessionId, String playerId) => '$sessionId/$playerId';

  @override
  Future<void> save({
    required String sessionId,
    required String playerId,
    required ChoiceRevealDto reveal,
  }) async => _values[_key(sessionId, playerId)] = reveal;

  @override
  Future<ChoiceRevealDto?> load({
    required String sessionId,
    required String playerId,
  }) async => _values[_key(sessionId, playerId)];

  @override
  Future<void> clear({
    required String sessionId,
    required String playerId,
  }) async => _values.remove(_key(sessionId, playerId));
}
