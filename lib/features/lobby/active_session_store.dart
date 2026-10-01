import 'package:shared_preferences/shared_preferences.dart';

abstract interface class ActiveSessionStore {
  Future<String?> load();
  Future<void> save(String sessionId);
  Future<void> clear();
}

final class SharedPreferencesActiveSessionStore implements ActiveSessionStore {
  const SharedPreferencesActiveSessionStore();

  static const _key = 'active_network_session_id';

  @override
  Future<String?> load() async {
    final value = (await SharedPreferences.getInstance()).getString(_key);
    return value == null || value.trim().isEmpty ? null : value;
  }

  @override
  Future<void> save(String sessionId) async {
    await (await SharedPreferences.getInstance()).setString(_key, sessionId);
  }

  @override
  Future<void> clear() async {
    await (await SharedPreferences.getInstance()).remove(_key);
  }
}
