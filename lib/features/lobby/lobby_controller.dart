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
  int _sessionGeneration = 0;
  Future<void> _pendingSessionSave = Future.value();

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
    final generation = _sessionGeneration;
    final store = activeSessionStore;
    if (store == null) return false;
    final sessionId = await store.load();
    if (generation != _sessionGeneration || sessionId == null || _busy) {
      return false;
    }
    _busy = true;
    try {
      if (_restoredSessionId == sessionId && session?.id == sessionId) {
        return true;
      }
      final restored = await repository.getSession(sessionId);
      final belongs =
          _isActive(restored) && await _belongsToCurrentPlayer(restored);
      if (generation != _sessionGeneration) {
        return false;
      }
      if (!belongs) {
        await store.clear();
        _resetToMenu();
        return false;
      }
      await _setSession(restored, persist: false, generation: generation);
      if (generation != _sessionGeneration) {
        return false;
      }
      _restoredSessionId = sessionId;
      return true;
    } on InvalidJoinCodeException {
      if (generation != _sessionGeneration) {
        return false;
      }
      await store.clear();
      _resetToMenu();
      return false;
    } on ExpiredLobbyException {
      if (generation != _sessionGeneration) {
        return false;
      }
      await store.clear();
      _resetToMenu();
      return false;
    } catch (_) {
      if (generation != _sessionGeneration) {
        return false;
      }
      _resetToMenu();
      return false;
    } finally {
      if (generation == _sessionGeneration) {
        _busy = false;
      }
    }
  }

  Future<void> create() async {
    if (_busy) return;
    final generation = _sessionGeneration;
    _busy = true;
    state = LobbyViewState.creating;
    errorMessage = null;
    notifyListeners();
    try {
      await _setSession(
        await repository.createSession(commandId: _commandIdFactory()),
        generation: generation,
      );
    } catch (error) {
      if (generation == _sessionGeneration) {
        _setError(error);
      }
    } finally {
      if (generation == _sessionGeneration) {
        _busy = false;
      }
    }
  }

  Future<void> join(String rawCode) async {
    if (_busy) return;
    final generation = _sessionGeneration;
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
        generation: generation,
      );
    } catch (error) {
      if (generation == _sessionGeneration) {
        _setError(error);
      }
    } finally {
      if (generation == _sessionGeneration) {
        _busy = false;
      }
    }
  }

  Future<void> retry() async {
    final current = session;
    if (_busy || current == null) return;
    final generation = _sessionGeneration;
    _busy = true;
    try {
      await _setSession(
        await repository.getSession(current.id),
        generation: generation,
      );
    } catch (error) {
      if (generation == _sessionGeneration) {
        _setError(error, offline: true);
      }
    } finally {
      if (generation == _sessionGeneration) {
        _busy = false;
      }
    }
  }

  Future<void> clearActiveSession() async {
    final generation = ++_sessionGeneration;
    final subscription = _subscription;
    _subscription = null;
    _restoredSessionId = null;
    _busy = true;
    _resetToMenu();
    // Detachment must not wait for a realtime/RPC cancellation acknowledgement.
    // cancel() suppresses further deliveries immediately; the generation also
    // invalidates any restore/retry already awaiting its response.
    if (subscription != null) {
      unawaited(subscription.cancel().catchError((Object _) {}));
    }
    try {
      // A save already in flight must finish before the explicit quit erases it.
      await _pendingSessionSave.catchError((Object _) {});
      await activeSessionStore?.clear();
    } finally {
      if (generation == _sessionGeneration) {
        _busy = false;
      }
    }
  }

  Future<void> _setSession(
    LobbySession value, {
    bool persist = true,
    required int generation,
  }) async {
    if (generation != _sessionGeneration) {
      return;
    }
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
    if (generation != _sessionGeneration) {
      return;
    }
    _subscription = repository
        .watchSession(value.id)
        .listen(
          (updated) {
            if (generation != _sessionGeneration) {
              return;
            }
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
            if (generation != _sessionGeneration) {
              return;
            }
            state = LobbyViewState.offline;
            errorMessage = const LobbyNetworkException().message;
            notifyListeners();
          },
        );
    if (persist) {
      _pendingSessionSave =
          activeSessionStore?.save(value.id) ?? Future.value();
      await _pendingSessionSave;
    }
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
    // Invalidate restores/retries still awaiting their network response.
    _sessionGeneration++;
    _subscription?.cancel();
    super.dispose();
  }
}
