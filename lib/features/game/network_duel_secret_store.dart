import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/game/game_models.dart';
import '../../domain/catalog/v4_catalog.dart';
import '../../engines/runtime/v4_runtime_engine.dart';
import '../../core/json.dart';
import '../../domain/round/concept_usage_snapshot.dart';
import '../../domain/session/session_state.dart';
import '../../sync/commit_reveal/commit_reveal.dart';
import '../../engines/usage/concept_usage_checkpoint.dart';
import '../../sync/protocol/network_usage_projection.dart';

final class NetworkPlayedCardRecord {
  const NetworkPlayedCardRecord({
    required this.usage,
    required this.roundNumber,
  });
  final NetworkUsageProjection usage;
  final int roundNumber;
  String get cardId => usage.conceptId;
  String get variantId =>
      (usage.resolvedAction['stage_id'] ?? usage.resolvedAction['variant_id'])!
          as String;
  String get usageId => usage.usageId;
  Map<String, Object?> toJson() => {
    'round_number': roundNumber,
    'usage': usage.toJson(),
  };
  factory NetworkPlayedCardRecord.fromJson(Map<String, Object?> json) =>
      NetworkPlayedCardRecord(
        usage: NetworkUsageProjection.fromJson(
          Map<String, Object?>.from(json['usage']! as Map),
        ),
        roundNumber: json['round_number']! as int,
      );
}

final class NetworkPrivateGameState {
  NetworkPrivateGameState({
    required this.roundNumber,
    required List<CardRuntimeState> cards,
    Map<String, String> displayedHandActions = const {},
    this.activeReveal,
    this.roundCardRatings,
    this.nextRoundPrepared = false,
    Set<int> learningRecordedRounds = const {},
    this.deckCycle = 1,
    this.infiniteMode = false,
    this.deckStyle = PlayerStyle.SOFT,
    List<NetworkPlayedCardRecord> publicDiscards = const [],
    this.choiceVersion = 0,
    this.cancelCommitRequested = false,
    this.conceptCheckpoint,
    Map<String, ConceptUsageSnapshot> reservedChoices = const {},
    JsonMap? pendingSecondaryCommand,
    JsonMap? pendingLearning,
    this.activeChili = 1,
    this.sessionMode = V4SessionMode.presentiel,
    this.presence = V4SessionPresence.presentiel,
    List<V4PersistentEffect> persistentEffects = const [],
    V4SessionAccessoryPool? accessoryPool,
    this.initialClothing = 5,
    List<ConceptUsageCheckpoint> priorCheckpoints = const [],
    Map<String, int> clothesByPlayer = const {},
    Map<String, int> clothingObservations = const {},
    Map<String, int> actionClothingConfirmations = const {},
    Map<String, JsonMap> personalizationEvents = const {},
  }) : pendingLearning = pendingLearning == null
           ? null
           : freezeJson(pendingLearning) as JsonMap,
       reservedChoices = Map.unmodifiable(reservedChoices),
       pendingSecondaryCommand = pendingSecondaryCommand == null
           ? null
           : freezeJson(pendingSecondaryCommand) as JsonMap,
       cards = List.unmodifiable(cards),
       personalizationEvents = Map.unmodifiable({
         for (final e in personalizationEvents.entries)
           e.key: freezeJson(e.value) as JsonMap,
       }),
       displayedHandActions = Map.unmodifiable(displayedHandActions),
       learningRecordedRounds = Set.unmodifiable(learningRecordedRounds),
       publicDiscards = List.unmodifiable(publicDiscards),
       clothesByPlayer = Map.unmodifiable(clothesByPlayer),
       priorCheckpoints = List.unmodifiable(priorCheckpoints),
       clothingObservations = Map.unmodifiable(clothingObservations),
       actionClothingConfirmations = Map.unmodifiable(
         actionClothingConfirmations,
       ),
       persistentEffects = List.unmodifiable(persistentEffects),
       accessoryPool =
           accessoryPool ??
           V4SessionAccessoryPool(profileAccessories: const []);

  final int roundNumber;
  final List<CardRuntimeState> cards;
  final Map<String, String> displayedHandActions;
  // Private round input snapshot; the profile remains the learning source of truth.
  final List<Object?>? roundCardRatings;
  final ChoiceRevealDto? activeReveal;
  final bool nextRoundPrepared;
  final Set<int> learningRecordedRounds;
  final int deckCycle;
  final bool infiniteMode;
  final PlayerStyle deckStyle;
  final List<NetworkPlayedCardRecord> publicDiscards;
  final int choiceVersion;
  final bool cancelCommitRequested;
  final ConceptUsageCheckpoint? conceptCheckpoint;
  // Draft choices are not engaged usages. The quota journal remains canonical.
  final Map<String, ConceptUsageSnapshot> reservedChoices;
  final JsonMap? pendingSecondaryCommand;
  final JsonMap? pendingLearning;
  final int activeChili;
  final V4SessionMode sessionMode;
  final V4SessionPresence presence;
  final List<V4PersistentEffect> persistentEffects;
  final V4SessionAccessoryPool accessoryPool;
  final int initialClothing;
  final List<ConceptUsageCheckpoint> priorCheckpoints;
  final Map<String, int> clothesByPlayer;
  final Map<String, int> clothingObservations;
  final Map<String, int> actionClothingConfirmations;
  final Map<String, JsonMap> personalizationEvents;

  Map<String, Object?> toJson() => {
    'round_number': roundNumber,
    'displayed_hand_actions': displayedHandActions,
    'cards': [
      for (final card in cards)
        {
          'concept_id': card.cardId,
          'usage_id': card.zone == CardZone.HAND ? null : card.occurrenceId,
          'variant_id': card.variantId,
          'zone': card.zone.name,
          'locked': card.locked,
          'native_direction': card.nativeDirection.name,
          'effective_direction': card.effectiveDirection.name,
        },
    ],
    'active_reveal': activeReveal?.toJson(),
    'round_card_ratings': roundCardRatings,
    'next_round_prepared': nextRoundPrepared,
    'learning_recorded_rounds': learningRecordedRounds.toList()..sort(),
    'deck_cycle': deckCycle,
    'infinite_mode': infiniteMode,
    'deck_style': deckStyle.name,
    'public_discards': [for (final card in publicDiscards) card.toJson()],
    'choice_version': choiceVersion,
    'cancel_commit_requested': cancelCommitRequested,
    'concept_checkpoint': conceptCheckpoint?.toJson(),
    'reserved_choices': {
      for (final e in reservedChoices.entries) e.key: e.value.toJson(),
    },
    'pending_secondary_command': pendingSecondaryCommand,
    'pending_learning': pendingLearning,
    'active_chili': activeChili,
    'session_mode': sessionMode.name,
    'presence': presence.name,
    'persistent_effects': [for (final e in persistentEffects) e.toJson()],
    'accessory_pool': accessoryPool.toJson(),
    'initial_clothing': initialClothing,
    'prior_checkpoints': [
      for (final checkpoint in priorCheckpoints) checkpoint.toJson(),
    ],
    'clothes_by_player': clothesByPlayer,
    'clothing_observations': clothingObservations,
    'action_clothing_confirmations': actionClothingConfirmations,
    'personalization_events': personalizationEvents,
  };

  factory NetworkPrivateGameState.fromJson(
    Map<String, Object?> json,
  ) => NetworkPrivateGameState(
    roundNumber: json['round_number']! as int,
    roundCardRatings: (json['round_card_ratings'] as List?)?.cast<Object?>(),
    displayedHandActions: Map<String, String>.from(
      (json['displayed_hand_actions'] as Map?) ?? const {},
    ),
    cards: [
      for (final value in json['cards']! as List)
        if (Map<String, Object?>.from(value! as Map) case final card)
          CardRuntimeState(
            cardId: (card['concept_id'] ?? card['card_id'])! as String,
            occurrenceId:
                (card['usage_id'] ?? card['occurrence_id']) as String?,
            variantId: card['variant_id'] as String?,
            zone: CardZone.values.byName(card['zone']! as String),
            locked: card['locked']! as bool,
            nativeDirection: CardOccurrenceDirection.values.byName(
              (card['native_direction'] as String?) ?? 'GENERAL',
            ),
            effectiveDirection: CardOccurrenceDirection.values.byName(
              (card['effective_direction'] as String?) ??
                  (card['native_direction'] as String?) ??
                  'GENERAL',
            ),
          ),
    ],
    activeReveal: json['active_reveal'] == null
        ? null
        : ChoiceRevealDto.fromJson(
            Map<String, Object?>.from(json['active_reveal']! as Map),
          ),
    nextRoundPrepared: json['next_round_prepared']! as bool,
    learningRecordedRounds:
        ((json['learning_recorded_rounds'] as List?) ?? const [])
            .cast<int>()
            .toSet(),
    deckCycle: (json['deck_cycle'] as int?) ?? 1,
    infiniteMode: (json['infinite_mode'] as bool?) ?? false,
    deckStyle: PlayerStyle.values.byName(
      (json['deck_style'] as String?) ?? PlayerStyle.SOFT.name,
    ),
    publicDiscards: [
      for (final raw in (json['public_discards'] as List?) ?? const [])
        NetworkPlayedCardRecord.fromJson(
          Map<String, Object?>.from(raw! as Map),
        ),
    ],
    choiceVersion: (json['choice_version'] as int?) ?? 0,
    cancelCommitRequested: (json['cancel_commit_requested'] as bool?) ?? false,
    conceptCheckpoint: json['concept_checkpoint'] == null
        ? null
        : ConceptUsageCheckpoint.fromJson(
            Map<String, Object?>.from(json['concept_checkpoint']! as Map),
          ),
    reservedChoices: {
      for (final e in ((json['reserved_choices'] as Map?) ?? {}).entries)
        e.key as String: ConceptUsageSnapshot.fromJson(
          Map<String, Object?>.from(e.value as Map),
        ),
    },
    pendingSecondaryCommand: json['pending_secondary_command'] == null
        ? null
        : Map<String, Object?>.from(json['pending_secondary_command'] as Map),
    activeChili: (json['active_chili'] as int?) ?? 1,
    sessionMode: V4SessionMode.values.byName(
      (json['session_mode'] as String?) ?? 'presentiel',
    ),
    presence: V4SessionPresence.values.byName(
      (json['presence'] as String?) ?? 'presentiel',
    ),
    persistentEffects: [
      for (final raw in (json['persistent_effects'] as List?) ?? const [])
        V4PersistentEffect.fromJson(Map<String, Object?>.from(raw as Map)),
    ],
    accessoryPool: json['accessory_pool'] == null
        ? null
        : V4SessionAccessoryPool.fromJson(
            Map<String, Object?>.from(json['accessory_pool'] as Map),
          ),
    initialClothing: (json['initial_clothing'] as int?) ?? 5,
    priorCheckpoints: [
      for (final value in (json['prior_checkpoints'] as List?) ?? [])
        ConceptUsageCheckpoint.fromJson(
          Map<String, Object?>.from(value as Map),
        ),
    ],
    clothesByPlayer: Map<String, int>.from(
      (json['clothes_by_player'] as Map?) ?? {},
    ),
    actionClothingConfirmations: Map<String, int>.from(
      (json['action_clothing_confirmations'] as Map?) ?? const {},
    ),
    clothingObservations: Map<String, int>.from(
      (json['clothing_observations'] as Map?) ?? {},
    ),
    personalizationEvents: {
      for (final e
          in ((json['personalization_events'] as Map?) ?? const {}).entries)
        e.key as String: Map<String, Object?>.from(e.value as Map),
    },
  );
}

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

  Future<void> saveGame({
    required String sessionId,
    required String playerId,
    required NetworkPrivateGameState state,
  });

  Future<NetworkPrivateGameState?> loadGame({
    required String sessionId,
    required String playerId,
  });
  Future<void> clearGame({required String sessionId, required String playerId});
}

final class SharedPreferencesNetworkDuelSecretStore
    implements NetworkDuelSecretStore {
  const SharedPreferencesNetworkDuelSecretStore();

  String _key(String sessionId, String playerId) =>
      'network_duel_secret.$sessionId.$playerId';
  String _gameKey(String sessionId, String playerId) =>
      'network_game_private.$sessionId.$playerId';

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

  @override
  Future<void> saveGame({
    required String sessionId,
    required String playerId,
    required NetworkPrivateGameState state,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _gameKey(sessionId, playerId),
      jsonEncode(state.toJson()),
    );
  }

  @override
  Future<NetworkPrivateGameState?> loadGame({
    required String sessionId,
    required String playerId,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_gameKey(sessionId, playerId));
    return encoded == null
        ? null
        : NetworkPrivateGameState.fromJson(
            Map<String, Object?>.from(jsonDecode(encoded) as Map),
          );
  }

  @override
  Future<void> clearGame({
    required String sessionId,
    required String playerId,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_gameKey(sessionId, playerId));
  }
}

final class MemoryNetworkDuelSecretStore implements NetworkDuelSecretStore {
  final Map<String, ChoiceRevealDto> _values = {};
  final Map<String, NetworkPrivateGameState> _games = {};

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

  @override
  Future<void> saveGame({
    required String sessionId,
    required String playerId,
    required NetworkPrivateGameState state,
  }) async => _games[_key(sessionId, playerId)] = state;

  @override
  Future<NetworkPrivateGameState?> loadGame({
    required String sessionId,
    required String playerId,
  }) async => _games[_key(sessionId, playerId)];
  @override
  Future<void> clearGame({
    required String sessionId,
    required String playerId,
  }) async {
    _games.remove(_key(sessionId, playerId));
  }
}
