import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/game/game_models.dart';
import '../../domain/session/session_state.dart';
import '../../engines/draw/draw_engine.dart';
import '../../engines/deck/session_deck_builder.dart';
import '../../sync/commit_reveal/commit_reveal.dart';
import '../../engines/usage/concept_usage_checkpoint.dart';
import '../../sync/protocol/network_usage_projection.dart';

final class NetworkPlayedCardRecord {
  const NetworkPlayedCardRecord({
    required this.cardId,
    required this.variantId,
    required this.occurrenceId,
    required this.roundNumber,
    this.usage,
  });

  final String cardId, variantId, occurrenceId;
  final int roundNumber;
  final NetworkUsageProjection? usage;

  Map<String, Object?> toJson() => {
    'card_id': cardId,
    'variant_id': variantId,
    'occurrence_id': occurrenceId,
    'round_number': roundNumber,
    'usage': usage?.toJson(),
  };

  factory NetworkPlayedCardRecord.fromJson(Map<String, Object?> json) =>
      NetworkPlayedCardRecord(
        cardId: json['card_id']! as String,
        variantId: json['variant_id']! as String,
        occurrenceId: json['occurrence_id']! as String,
        roundNumber: json['round_number']! as int,
        usage: json['usage'] == null
            ? null
            : NetworkUsageProjection.fromJson(
                Map<String, Object?>.from(json['usage']! as Map),
              ),
      );
}

final class NetworkPrivateGameState {
  NetworkPrivateGameState({
    required this.roundNumber,
    required List<CardRuntimeState> cards,
    required Map<String, CardHistoryState> history,
    this.activeReveal,
    this.nextRoundPrepared = false,
    Set<int> learningRecordedRounds = const {},
    this.deckCycle = 1,
    this.infiniteMode = false,
    this.deckStyle = PlayerStyle.SOFT,
    List<DeckShortage> deckShortages = const [],
    List<NetworkPlayedCardRecord> publicDiscards = const [],
    this.choiceVersion = 0,
    this.cancelCommitRequested = false,
    this.conceptCheckpoint,
    this.activeChili = 2,
    this.initialClothing = 5,
    List<ConceptUsageCheckpoint> priorCheckpoints = const [],
    Map<String, int> clothesByPlayer = const {},
    Map<String, int> clothingObservations = const {},
  }) : cards = List.unmodifiable(cards),
       history = Map.unmodifiable(history),
       learningRecordedRounds = Set.unmodifiable(learningRecordedRounds),
       deckShortages = List.unmodifiable(deckShortages),
       publicDiscards = List.unmodifiable(publicDiscards),
       clothesByPlayer = Map.unmodifiable(clothesByPlayer),
       priorCheckpoints = List.unmodifiable(priorCheckpoints),
       clothingObservations = Map.unmodifiable(clothingObservations);

  final int roundNumber;
  final List<CardRuntimeState> cards;
  final Map<String, CardHistoryState> history;
  final ChoiceRevealDto? activeReveal;
  final bool nextRoundPrepared;
  final Set<int> learningRecordedRounds;
  final int deckCycle;
  final bool infiniteMode;
  final PlayerStyle deckStyle;
  final List<DeckShortage> deckShortages;
  final List<NetworkPlayedCardRecord> publicDiscards;
  final int choiceVersion;
  final bool cancelCommitRequested;
  final ConceptUsageCheckpoint? conceptCheckpoint;
  final int activeChili;
  final int initialClothing;
  final List<ConceptUsageCheckpoint> priorCheckpoints;
  final Map<String, int> clothesByPlayer;
  final Map<String, int> clothingObservations;

  Map<String, Object?> toJson() => {
    'round_number': roundNumber,
    'cards': [
      for (final card in cards)
        {
          'card_id': card.cardId,
          'occurrence_id': card.occurrenceId,
          'variant_id': card.variantId,
          'zone': card.zone.name,
          'locked': card.locked,
          'native_direction': card.nativeDirection.name,
          'effective_direction': card.effectiveDirection.name,
        },
    ],
    'history': {
      for (final entry in history.entries) entry.key: entry.value.name,
    },
    'active_reveal': activeReveal?.toJson(),
    'next_round_prepared': nextRoundPrepared,
    'learning_recorded_rounds': learningRecordedRounds.toList()..sort(),
    'deck_cycle': deckCycle,
    'infinite_mode': infiniteMode,
    'deck_style': deckStyle.name,
    'deck_shortages': [
      for (final shortage in deckShortages)
        {
          'requested_spice': shortage.requestedSpice,
          'requested_count': shortage.requestedCount,
          'available_count': shortage.availableCount,
          'missing_count': shortage.missingCount,
          'replacements': {
            for (final entry in shortage.replacementsBySpice.entries)
              entry.key.toString(): entry.value,
          },
        },
    ],
    'public_discards': [for (final card in publicDiscards) card.toJson()],
    'choice_version': choiceVersion,
    'cancel_commit_requested': cancelCommitRequested,
    'concept_checkpoint': conceptCheckpoint?.toJson(),
    'active_chili': activeChili,
    'initial_clothing': initialClothing,
    'prior_checkpoints': [
      for (final checkpoint in priorCheckpoints) checkpoint.toJson(),
    ],
    'clothes_by_player': clothesByPlayer,
    'clothing_observations': clothingObservations,
  };

  factory NetworkPrivateGameState.fromJson(Map<String, Object?> json) =>
      NetworkPrivateGameState(
        roundNumber: json['round_number']! as int,
        cards: [
          for (final value in json['cards']! as List)
            if (Map<String, Object?>.from(value! as Map) case final card)
              CardRuntimeState(
                cardId: card['card_id']! as String,
                occurrenceId: card['occurrence_id'] as String?,
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
        history: {
          for (final entry in (json['history']! as Map).entries)
            entry.key as String: CardHistoryState.values.byName(
              entry.value! as String,
            ),
        },
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
        deckShortages: [
          for (final raw in (json['deck_shortages'] as List?) ?? const [])
            if (Map<String, Object?>.from(raw! as Map) case final shortage)
              DeckShortage(
                requestedSpice: shortage['requested_spice']! as int,
                requestedCount: shortage['requested_count']! as int,
                availableCount: shortage['available_count']! as int,
                missingCount: shortage['missing_count']! as int,
                replacementsBySpice: {
                  for (final entry in Map<String, Object?>.from(
                    (shortage['replacements'] as Map?) ?? const {},
                  ).entries)
                    int.parse(entry.key): entry.value! as int,
                },
              ),
        ],
        publicDiscards: [
          for (final raw in (json['public_discards'] as List?) ?? const [])
            NetworkPlayedCardRecord.fromJson(
              Map<String, Object?>.from(raw! as Map),
            ),
        ],
        choiceVersion: (json['choice_version'] as int?) ?? 0,
        cancelCommitRequested:
            (json['cancel_commit_requested'] as bool?) ?? false,
        conceptCheckpoint: json['concept_checkpoint'] == null
            ? null
            : ConceptUsageCheckpoint.fromJson(
                Map<String, Object?>.from(json['concept_checkpoint']! as Map),
              ),
        activeChili: (json['active_chili'] as int?) ?? 2,
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
        clothingObservations: Map<String, int>.from(
          (json['clothing_observations'] as Map?) ?? {},
        ),
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
}
