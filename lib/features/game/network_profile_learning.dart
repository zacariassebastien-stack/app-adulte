import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/profile/adaptive_profile.dart';
import '../../engines/profile/profile_learning_engine.dart';
import '../../engines/profile/completed_round_learning.dart';

abstract interface class NetworkProfileLearningStore {
  Future<AdaptiveProfileState?> load(String playerId);
  Future<void> save(AdaptiveProfileState state);
}

enum PostGameProfileChoice { customize, trustGame, later }

abstract interface class PostGameProfileChoiceStore {
  Future<PostGameProfileChoice?> load(String playerId);
  Future<void> save(String playerId, PostGameProfileChoice choice);
}

final class SharedPreferencesPostGameProfileChoiceStore
    implements PostGameProfileChoiceStore {
  const SharedPreferencesPostGameProfileChoiceStore();
  @override
  Future<PostGameProfileChoice?> load(String playerId) async {
    final preferences = await SharedPreferences.getInstance();
    final value = preferences.getString('post_game_profile_choice.$playerId');
    return value == null ? null : PostGameProfileChoice.values.byName(value);
  }

  @override
  Future<void> save(String playerId, PostGameProfileChoice choice) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      'post_game_profile_choice.$playerId',
      choice.name,
    );
  }
}

final class MemoryPostGameProfileChoiceStore
    implements PostGameProfileChoiceStore {
  final Map<String, PostGameProfileChoice> values = {};
  @override
  Future<PostGameProfileChoice?> load(String playerId) async =>
      values[playerId];
  @override
  Future<void> save(String playerId, PostGameProfileChoice choice) async {
    values[playerId] = choice;
  }
}

final class SharedPreferencesNetworkProfileLearningStore
    implements NetworkProfileLearningStore {
  const SharedPreferencesNetworkProfileLearningStore();

  @override
  Future<AdaptiveProfileState?> load(String playerId) async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString('profile_learning_v1.$playerId');
    return encoded == null
        ? null
        : AdaptiveProfileState.fromJson(
            Map<String, Object?>.from(jsonDecode(encoded) as Map),
          );
  }

  @override
  Future<void> save(AdaptiveProfileState state) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      'profile_learning_v1.${state.profileId}',
      jsonEncode(state.toJson()),
    );
  }
}

final class MemoryNetworkProfileLearningStore
    implements NetworkProfileLearningStore {
  final Map<String, AdaptiveProfileState> values = {};
  @override
  Future<AdaptiveProfileState?> load(String playerId) async => values[playerId];
  @override
  Future<void> save(AdaptiveProfileState state) async {
    values[state.profileId] = state;
  }
}

/// Applies network events only to the local private aggregate. No learning
/// state or proposal is ever sent through the public round protocol.
final class NetworkProfileLearningCoordinator {
  NetworkProfileLearningCoordinator({
    required this.playerId,
    required this.store,
    this.engine = const ProfileLearningEngine(),
  });

  final String playerId;
  final NetworkProfileLearningStore store;
  final ProfileLearningEngine engine;
  AdaptiveProfileState? _state;
  Future<AdaptiveProfileState?>? _loading;
  Future<void> _writes = Future.value();

  Future<AdaptiveProfileState> state() async {
    if (_state != null) return _state!;
    final loaded = await (_loading ??= store.load(playerId));
    return _state ??= loaded ?? AdaptiveProfileState(profileId: playerId);
  }

  Future<void> _write(Future<void> Function() operation) {
    final next = _writes.then((_) => operation());
    _writes = next.catchError((Object _) {});
    return next;
  }

  Future<void> recordCompletedRound({
    required String eventId,
    required Set<String> expectedPlayers,
    required Set<String> completedPlayers,
    required HandLearningEvent hand,
    required List<ResolvedLearningCard> accepted,
    List<ResistanceLearningEvent> resistance = const [],
  }) => _write(() async {
    final current = await state();
    final next = recordCompletedUsageRound(
      state: current,
      eventId: eventId,
      expectedPlayers: expectedPlayers,
      completedPlayers: completedPlayers,
      hand: hand,
      accepted: accepted,
      resistance: resistance,
      engine: engine,
    );
    if (identical(next, current)) return;
    await store.save(next);
    _state = next;
  });

  Future<void> manuallyCustomize({
    required PreferenceLearningKey key,
    double? pa,
    bool excluded = false,
  }) => _write(() async {
    final current = await state();
    final next = engine.manuallyCustomize(
      current,
      key: key,
      pa: pa,
      excluded: excluded,
    );
    await store.save(next);
    _state = next;
  });
}
