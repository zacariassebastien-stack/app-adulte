import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/catalog/enums.dart';
import '../../domain/game/game_models.dart';
import '../../domain/profile/adaptive_profile.dart';
import '../../domain/profile/v4_profile.dart';
import '../../engines/profile/profile_learning_engine.dart';
import '../../engines/profile/completed_round_learning.dart';
import '../../engines/profile/v4_card_rating_engine.dart';

abstract interface class NetworkProfileLearningStore {
  Future<AdaptiveProfileState?> load(String playerId);
  Future<void> save(AdaptiveProfileState state);
  Future<NetworkLearningEventWrite> applyEventOnce({
    required String playerId,
    required String eventId,
    required AdaptiveProfileState Function(AdaptiveProfileState state) update,
  });
}

final class NetworkLearningEventWrite {
  const NetworkLearningEventWrite({required this.state, required this.applied});

  final AdaptiveProfileState state;
  final bool applied;
}

final class _AsyncWriteQueue {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}

abstract interface class V4ProfileStore {
  Future<V4Profile?> load(String playerId);
  Future<void> save(V4Profile profile);
}

final class SharedPreferencesV4ProfileStore implements V4ProfileStore {
  const SharedPreferencesV4ProfileStore();

  @override
  Future<V4Profile?> load(String playerId) async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString('profile_preferences_v4.$playerId');
    return encoded == null
        ? null
        : V4Profile.fromJson(
            Map<String, Object?>.from(jsonDecode(encoded) as Map),
          );
  }

  @override
  Future<void> save(V4Profile profile) async {
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(
      'profile_preferences_v4.${profile.profileId}',
      jsonEncode(profile.toJson()),
    );
    if (!saved) throw StateError('Profile persistence failed');
  }
}

final class MemoryV4ProfileStore implements V4ProfileStore {
  final Map<String, V4Profile> values = {};
  @override
  Future<V4Profile?> load(String playerId) async => values[playerId];
  @override
  Future<void> save(V4Profile profile) async {
    values[profile.profileId] = profile;
  }
}

abstract interface class V4CardLearningStore {
  Future<CardSpecificLearningStore> load(String playerId);
  Future<void> save(String playerId, CardSpecificLearningStore state);
}

final class SharedPreferencesV4CardLearningStore
    implements V4CardLearningStore {
  const SharedPreferencesV4CardLearningStore();

  @override
  Future<CardSpecificLearningStore> load(String playerId) async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString('card_learning_v4.$playerId');
    final state = CardSpecificLearningStore();
    if (encoded != null) {
      state.restore(jsonDecode(encoded) as List);
    }
    return state;
  }

  @override
  Future<void> save(String playerId, CardSpecificLearningStore state) async {
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(
      'card_learning_v4.$playerId',
      jsonEncode(state.toJson()),
    );
    if (!saved) throw StateError('Card appreciation persistence failed');
  }
}

final class MemoryV4CardLearningStore implements V4CardLearningStore {
  final Map<String, List<Map<String, Object?>>> values = {};

  @override
  Future<CardSpecificLearningStore> load(String playerId) async {
    final state = CardSpecificLearningStore();
    state.restore(values[playerId] ?? const []);
    return state;
  }

  @override
  Future<void> save(String playerId, CardSpecificLearningStore state) async {
    values[playerId] = state.toJson();
  }
}

AdaptiveProfileState adaptiveProfileFromV4Profile(V4Profile profile) {
  final entries = <String, PreferenceLearningEntry>{};
  for (final preference in profile.preferences.values) {
    final role = LearningRole.values.byName(preference.key.role.name);
    final key = PreferenceLearningKey(
      preferenceId: 'v3.preference.${preference.key.tagId}',
      role: role,
      zoneId: preference.key.zoneId,
    );
    entries[key.storageKey] = PreferenceLearningEntry(
      key: key,
      source: AdaptiveProfileSource.values.byName(preference.source.name),
      currentPa: preference.pa,
      estimatedPa: preference.pa,
      excluded: preference.excluded,
    );
  }
  return AdaptiveProfileState(profileId: profile.profileId, entries: entries);
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

  static final Map<String, _AsyncWriteQueue> _queues = {};

  String _key(String playerId) => 'profile_learning_v1.$playerId';

  ({AdaptiveProfileState? state, Set<String> eventIds}) _decode(
    String? encoded,
  ) {
    if (encoded == null) return (state: null, eventIds: <String>{});
    final decoded = Map<String, Object?>.from(jsonDecode(encoded) as Map);
    final storedState = decoded['state'];
    if (storedState is Map) {
      return (
        state: AdaptiveProfileState.fromJson(
          Map<String, Object?>.from(storedState),
        ),
        eventIds: ((decoded['applied_event_ids'] as List?) ?? const [])
            .cast<String>()
            .toSet(),
      );
    }
    return (
      state: AdaptiveProfileState.fromJson(decoded),
      eventIds: <String>{},
    );
  }

  String _encode(AdaptiveProfileState state, Set<String> eventIds) =>
      jsonEncode({
        'schema_version': 1,
        'state': state.toJson(),
        'applied_event_ids': eventIds.toList()..sort(),
      });

  Future<T> _serialized<T>(String playerId, Future<T> Function() action) =>
      (_queues[playerId] ??= _AsyncWriteQueue()).run(action);

  @override
  Future<AdaptiveProfileState?> load(String playerId) async {
    final preferences = await SharedPreferences.getInstance();
    return _decode(preferences.getString(_key(playerId))).state;
  }

  @override
  Future<void> save(AdaptiveProfileState state) =>
      _serialized(state.profileId, () async {
        final preferences = await SharedPreferences.getInstance();
        final stored = _decode(preferences.getString(_key(state.profileId)));
        await preferences.setString(
          _key(state.profileId),
          _encode(state, stored.eventIds),
        );
      });

  @override
  Future<NetworkLearningEventWrite> applyEventOnce({
    required String playerId,
    required String eventId,
    required AdaptiveProfileState Function(AdaptiveProfileState state) update,
  }) => _serialized(playerId, () async {
    final preferences = await SharedPreferences.getInstance();
    final stored = _decode(preferences.getString(_key(playerId)));
    final current = stored.state ?? AdaptiveProfileState(profileId: playerId);
    if (stored.eventIds.contains(eventId)) {
      return NetworkLearningEventWrite(state: current, applied: false);
    }
    final updated = update(current);
    final eventIds = {...stored.eventIds, eventId};
    await preferences.setString(_key(playerId), _encode(updated, eventIds));
    return NetworkLearningEventWrite(state: updated, applied: true);
  });
}

final class MemoryNetworkProfileLearningStore
    implements NetworkProfileLearningStore {
  final Map<String, AdaptiveProfileState> values = {};
  final Map<String, Set<String>> appliedEventIds = {};
  final Map<String, _AsyncWriteQueue> _queues = {};

  @override
  Future<AdaptiveProfileState?> load(String playerId) async => values[playerId];

  @override
  Future<void> save(AdaptiveProfileState state) =>
      (_queues[state.profileId] ??= _AsyncWriteQueue()).run(() async {
        values[state.profileId] = state;
      });

  @override
  Future<NetworkLearningEventWrite> applyEventOnce({
    required String playerId,
    required String eventId,
    required AdaptiveProfileState Function(AdaptiveProfileState state) update,
  }) => (_queues[playerId] ??= _AsyncWriteQueue()).run(() async {
    final current =
        values[playerId] ?? AdaptiveProfileState(profileId: playerId);
    final events = appliedEventIds.putIfAbsent(playerId, () => <String>{});
    if (events.contains(eventId)) {
      return NetworkLearningEventWrite(state: current, applied: false);
    }
    final updated = update(current);
    events.add(eventId);
    values[playerId] = updated;
    return NetworkLearningEventWrite(state: updated, applied: true);
  });
}

PlayerGameProfile playerGameProfileFromLearningState(
  AdaptiveProfileState state,
) {
  final grouped = <String, List<PreferenceLearningEntry>>{};
  for (final entry in state.entries.values) {
    if (entry.key.zoneId != null) continue;
    grouped.putIfAbsent(entry.key.preferenceId, () => []).add(entry);
  }
  return PlayerGameProfile(
    playerId: state.profileId,
    preferences: {
      for (final group in grouped.entries)
        group.key: _preferenceValue(group.value),
    },
  );
}

PreferenceValue _preferenceValue(List<PreferenceLearningEntry> entries) {
  PreferenceLearningEntry? roleEntry(LearningRole role) =>
      entries.where((entry) => entry.key.role == role).firstOrNull;
  final general =
      roleEntry(LearningRole.general) ??
      roleEntry(LearningRole.mutuel) ??
      roleEntry(LearningRole.soi) ??
      roleEntry(LearningRole.solo) ??
      roleEntry(LearningRole.simultane) ??
      roleEntry(LearningRole.observer);
  if (general?.excluded ?? false) {
    return const PreferenceValue(status: PreferenceStatus.EXCLUDED);
  }
  int? value(LearningRole role) {
    final specific = roleEntry(role);
    final source = specific ?? general;
    if (source == null || source.excluded || source.currentPa == null) {
      return null;
    }
    return source.currentPa!.round().clamp(1, 20).toInt();
  }

  final generalValue = value(LearningRole.general);
  return PreferenceValue(
    status: PreferenceStatus.ACCEPTED,
    general: generalValue,
    faire: value(LearningRole.faire) ?? generalValue,
    recevoir: value(LearningRole.recevoir) ?? generalValue,
  );
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
    if (expectedPlayers.length != 2 ||
        !completedPlayers.containsAll(expectedPlayers))
      return;
    final write = await store.applyEventOnce(
      playerId: playerId,
      eventId: eventId,
      update: (current) => recordCompletedUsageRound(
        state: current,
        eventId: eventId,
        expectedPlayers: expectedPlayers,
        completedPlayers: completedPlayers,
        hand: hand,
        accepted: accepted,
        resistance: resistance,
        engine: engine,
      ),
    );
    _state = write.state;
  });

  Future<bool> recordResolvedRoundOnce({
    required String eventId,
    required List<LearningCardDescriptor> handCards,
    required Set<String> played,
    required Set<String> locked,
    required List<List<ResolvedLearningCard>> acceptedBatches,
    required List<ResistanceLearningEvent> resistanceEvents,
  }) async {
    final write = await store.applyEventOnce(
      playerId: playerId,
      eventId: eventId,
      update: (initial) {
        var updated = engine.recordHand(
          initial,
          HandLearningEvent(
            playerId: playerId,
            availableCards: handCards,
            playedCardIdentities: played,
            lockedCardIdentities: locked,
          ),
        );
        for (final accepted in acceptedBatches) {
          if (accepted.isEmpty) continue;
          updated = engine.recordRoundOutcome({
            playerId: updated,
          }, RoundLearningOutcome(acceptedCards: accepted))[playerId]!;
        }
        for (final resistance in resistanceEvents) {
          updated = engine.recordResistance(updated, resistance);
        }
        return updated;
      },
    );
    _state = write.state;
    return write.applied;
  }

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

V4Profile mergeV4ProfileLearning(
  V4Profile base,
  AdaptiveProfileState? learnedState,
) {
  final preferences = {...base.preferences};
  for (final entry
      in learnedState?.entries.values ?? <PreferenceLearningEntry>[]) {
    if (entry.source != AdaptiveProfileSource.autoLearned &&
        entry.source != AdaptiveProfileSource.manualCustomized)
      continue;
    final key = ProfilePreferenceKey(
      tagId: entry.key.preferenceId.replaceFirst('v3.preference.', ''),
      role: ProfilePreferenceRole.values.byName(entry.key.role.name),
      zoneId: entry.key.zoneId,
    );
    preferences[key.storageKey] = ProfilePreference(
      profileId: base.profileId,
      key: key,
      pa: entry.currentPa,
      excluded: entry.excluded,
      source: entry.source == AdaptiveProfileSource.manualCustomized
          ? ProfilePreferenceSource.manualCustomized
          : ProfilePreferenceSource.autoLearned,
    );
  }
  return V4Profile(
    profileId: base.profileId,
    sex: base.sex,
    gameNickname: base.gameNickname,
    preferences: preferences,
    consents: base.consents,
    accessories: base.accessories,
    stageVetoes: base.stageVetoes,
  );
}
