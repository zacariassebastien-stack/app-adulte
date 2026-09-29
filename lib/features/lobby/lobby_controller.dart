import 'dart:async';

import 'package:flutter/foundation.dart';

import 'join_code.dart';
import 'lobby_models.dart';
import 'lobby_repository.dart';

enum LobbyViewState { idle, creating, joining, waiting, ready, offline, error }

final class LobbyController extends ChangeNotifier {
  LobbyController({
    required this.repository,
    String Function()? commandIdFactory,
  }) : _commandIdFactory = commandIdFactory ?? _defaultCommandId;

  final LobbyRepository repository;
  final String Function() _commandIdFactory;
  StreamSubscription<LobbySession>? _subscription;
  bool _busy = false;

  LobbyViewState state = LobbyViewState.idle;
  LobbySession? session;
  String? errorMessage;

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

  Future<void> _setSession(LobbySession value) async {
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
  }

  void _setError(Object error, {bool offline = false}) {
    state = offline ? LobbyViewState.offline : LobbyViewState.error;
    errorMessage = error is LobbyException
        ? error.message
        : const LobbyNetworkException().message;
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
