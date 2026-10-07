import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/catalog/definitions.dart';
import '../../domain/catalog/enums.dart';
import '../../domain/game/game_models.dart';
import '../../domain/profile/adaptive_profile.dart';
import '../../domain/profile/v4_profile.dart';
import '../../engines/profile/profile_learning_engine.dart';
import '../../engines/profile/v4_card_rating_engine.dart';

abstract interface class NetworkProfileLearningStore {
  Future<AdaptiveProfileState?> load(String playerId);
  Future<void> save(AdaptiveProfileState state);
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
    await preferences.setString(
      'profile_preferences_v4.${profile.profileId}',
      jsonEncode(profile.toJson()),
    );
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
    await preferences.setString(
      'card_learning_v4.$playerId',
      jsonEncode(state.toJson()),
    );
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
      source: AdaptiveProfileSource.initialQuestionnaire,
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

LearningCardDescriptor v3LearningDescriptor(
  CardDefinition card,
  CardVariantDefinition variant, {
  String? occurrenceId,
}) {
  final editorial = variant.v3 ?? card.v3;
  return LearningCardDescriptor(
    cardId: card.stableId,
    variantId: variant.stableId,
    tags: editorial?.tags ?? const [],
    spiceLevel: editorial?.baseEngagementLevel ?? variant.chiliLevel,
    primaryPreferenceIds: [
      if (editorial != null)
        ...editorial.tags
            .where((tag) => tag.startsWith('v3.preference.'))
            .take(1),
    ],
    occurrenceId: occurrenceId,
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

  Future<AdaptiveProfileState> state() async => _state ??=
      await store.load(playerId) ?? AdaptiveProfileState(profileId: playerId);

  Future<void> recordHand({
    required List<LearningCardDescriptor> cards,
    Set<String> played = const {},
    Set<String> locked = const {},
  }) async {
    final current = await state();
    _state = engine.recordHand(
      current,
      HandLearningEvent(
        playerId: playerId,
        availableCards: cards,
        playedCardIdentities: played,
        lockedCardIdentities: locked,
      ),
    );
    await store.save(_state!);
  }

  Future<void> recordAccepted(List<ResolvedLearningCard> cards) async {
    final current = await state();
    _state = engine.recordRoundOutcome({
      playerId: current,
    }, RoundLearningOutcome(acceptedCards: cards))[playerId]!;
    await store.save(_state!);
  }

  Future<void> recordResistance(ResistanceLearningEvent event) async {
    final current = await state();
    _state = engine.recordResistance(current, event);
    await store.save(_state!);
  }

  Future<void> manuallyCustomize({
    required PreferenceLearningKey key,
    double? pa,
    bool excluded = false,
  }) async {
    final current = await state();
    _state = engine.manuallyCustomize(
      current,
      key: key,
      pa: pa,
      excluded: excluded,
    );
    await store.save(_state!);
  }
}
