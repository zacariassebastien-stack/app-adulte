import 'dart:async';

import 'package:flutter/foundation.dart';

import 'active_session_store.dart';
import 'join_code.dart';
import 'lobby_models.dart';
import 'lobby_repository.dart';

enum LobbyViewState { idle, creating, joining, waiting, ready, offline, error }

final class LobbyController extends ChangeNotifier {
  LobbyController({
    required this.repository,
    this.activeSessionStore,
    String Function()? commandIdFactory,
  }) : _commandIdFactory = commandIdFactory ?? _defaultCommandId;

  final LobbyRepository repository;
  final ActiveSessionStore? activeSessionStore;
  final String Function() _commandIdFactory;
  StreamSubscription<LobbySession>? _subscription;
  bool _busy = false;
  Future<bool>? _restoreFuture;
  String? _restoredSessionId;

  LobbyViewState state = LobbyViewState.idle;
  LobbySession? session;
  String? errorMessage;

  Future<bool> restoreActiveSession() {
    final active = _restoreFuture;
    if (active != null) return active;
    final restore = _restoreActiveSession();
    _restoreFuture = restore;
    return restore.whenComplete(() => _restoreFuture = null);
  }

  Future<bool> _restoreActiveSession() async {
    final store = activeSessionStore;
    if (store == null) return false;
    final sessionId = await store.load();
    if (sessionId == null || _busy) return false;
    _busy = true;
    try {
      if (_restoredSessionId == sessionId && session?.id == sessionId) {
        return true;
      }
      final restored = await repository.getSession(sessionId);
      if (!_isActive(restored) || !await _belongsToCurrentPlayer(restored)) {
        await store.clear();
        _resetToMenu();
        return false;
      }
      await _setSession(restored, persist: false);
      _restoredSessionId = sessionId;
      return true;
    } on InvalidJoinCodeException {
      await store.clear();
      _resetToMenu();
      return false;
    } on ExpiredLobbyException {
      await store.clear();
      _resetToMenu();
      return false;
    } catch (_) {
      _resetToMenu();
      return false;
    } finally {
      _busy = false;
    }
  }

  Future<void> create() async {
    if (_busy) return;
    _busy = true;
    state = LobbyViewState.creating;
    errorMessage = null;
    notifyListeners();
    try {
      await _setSession(
        await repository.createSession(commandId: _commandIdFactory()),
      );
    } catch (error) {
      _setError(error);
    } finally {
      _busy = false;
    }
  }

  Future<void> join(String rawCode) async {
    if (_busy) return;
    final code = JoinCode.normalize(rawCode);
    if (!JoinCode.isValid(code)) {
      _setError(const InvalidJoinCodeException());
      return;
    }
    _busy = true;
    state = LobbyViewState.joining;
    errorMessage = null;
    notifyListeners();
    try {
      await _setSession(
        await repository.joinSession(
          code: code,
          commandId: _commandIdFactory(),
        ),
      );
    } catch (error) {
      _setError(error);
    } finally {
      _busy = false;
    }
  }

  Future<void> retry() async {
    final current = session;
    if (_busy || current == null) return;
    _busy = true;
    try {
      await _setSession(await repository.getSession(current.id));
    } catch (error) {
      _setError(error, offline: true);
    } finally {
      _busy = false;
    }
  }

  Future<void> _setSession(LobbySession value, {bool persist = true}) async {
    if (!_isActive(value)) {
      await activeSessionStore?.clear();
      _resetToMenu();
      return;
    }
    session = value;
    state = value.ready ? LobbyViewState.ready : LobbyViewState.waiting;
    errorMessage = null;
    notifyListeners();
    await _subscription?.cancel();
    _subscription = repository
        .watchSession(value.id)
        .listen(
          (updated) {
            if (_sameSession(session, updated)) return;
            if (!_isActive(updated)) {
              activeSessionStore?.clear();
              _resetToMenu();
              return;
            }
            session = updated;
            state = updated.ready
                ? LobbyViewState.ready
                : LobbyViewState.waiting;
            errorMessage = null;
            notifyListeners();
          },
          onError: (Object _) {
            state = LobbyViewState.offline;
            errorMessage = const LobbyNetworkException().message;
            notifyListeners();
          },
        );
    if (persist) await activeSessionStore?.save(value.id);
  }

  void _setError(Object error, {bool offline = false}) {
    state = offline ? LobbyViewState.offline : LobbyViewState.error;
    errorMessage = error is LobbyException
        ? error.message
        : const LobbyNetworkException().message;
    notifyListeners();
  }

  Future<bool> _belongsToCurrentPlayer(LobbySession value) async {
    final network = repository;
    if (network is! NetworkLobbyRepository) return true;
    final playerId = await network.currentPlayerId();
    return value.players.any((player) => player.userId == playerId);
  }

  static bool _isActive(LobbySession value) =>
      value.status != LobbyStatus.closed &&
      value.expiresAt.isAfter(DateTime.now());

  void _resetToMenu() {
    session = null;
    state = LobbyViewState.idle;
    errorMessage = null;
    notifyListeners();
  }

  static String _defaultCommandId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${UniqueKey()}';

  static bool _sameSession(LobbySession? left, LobbySession right) =>
      left?.id == right.id &&
      left?.status == right.status &&
      left?.players.length == right.players.length;

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
