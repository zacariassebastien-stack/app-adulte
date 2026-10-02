import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/catalog/definitions.dart';
import '../../domain/profile/adaptive_profile.dart';
import '../../engines/profile/profile_learning_engine.dart';

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

LearningCardDescriptor v3LearningDescriptor(
  CardDefinition card,
  CardVariantDefinition variant,
) {
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
}
