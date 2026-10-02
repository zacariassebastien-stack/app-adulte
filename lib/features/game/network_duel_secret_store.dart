import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/game/game_models.dart';
import '../../domain/session/session_state.dart';
import '../../engines/draw/draw_engine.dart';
import '../../engines/deck/session_deck_builder.dart';
import '../../sync/commit_reveal/commit_reveal.dart';

final class NetworkPrivateGameState {
  NetworkPrivateGameState({
    required this.roundNumber,
    required List<CardRuntimeState> cards,
    required Map<String, CardHistoryState> history,
    this.activeReveal,
    this.nextRoundPrepared = false,
    Set<int> learningRecordedRounds = const {},
    List<DeckCandidateV3> faceToFaceDeck = const [],
    List<DeckCandidateV3> distanceDeck = const [],
    this.deckCycle = 1,
    this.infiniteMode = false,
  }) : cards = List.unmodifiable(cards),
       history = Map.unmodifiable(history),
       learningRecordedRounds = Set.unmodifiable(learningRecordedRounds),
       faceToFaceDeck = List.unmodifiable(faceToFaceDeck),
       distanceDeck = List.unmodifiable(distanceDeck);

  final int roundNumber;
  final List<CardRuntimeState> cards;
  final Map<String, CardHistoryState> history;
  final ChoiceRevealDto? activeReveal;
  final bool nextRoundPrepared;
  final Set<int> learningRecordedRounds;
  final List<DeckCandidateV3> faceToFaceDeck;
  final List<DeckCandidateV3> distanceDeck;
  final int deckCycle;
  final bool infiniteMode;

  Map<String, Object?> toJson() => {
    'round_number': roundNumber,
    'cards': [
      for (final card in cards)
        {'card_id': card.cardId, 'zone': card.zone.name, 'locked': card.locked},
    ],
    'history': {
      for (final entry in history.entries) entry.key: entry.value.name,
    },
    'active_reveal': activeReveal?.toJson(),
    'next_round_prepared': nextRoundPrepared,
    'learning_recorded_rounds': learningRecordedRounds.toList()..sort(),
    'face_to_face_deck': [for (final card in faceToFaceDeck) _deckJson(card)],
    'distance_deck': [for (final card in distanceDeck) _deckJson(card)],
    'deck_cycle': deckCycle,
    'infinite_mode': infiniteMode,
  };

  factory NetworkPrivateGameState.fromJson(Map<String, Object?> json) =>
      NetworkPrivateGameState(
        roundNumber: json['round_number']! as int,
        cards: [
          for (final value in json['cards']! as List)
            if (Map<String, Object?>.from(value! as Map) case final card)
              CardRuntimeState(
                cardId: card['card_id']! as String,
                zone: CardZone.values.byName(card['zone']! as String),
                locked: card['locked']! as bool,
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
        faceToFaceDeck: _deckList(json['face_to_face_deck']),
        distanceDeck: _deckList(json['distance_deck']),
        deckCycle: (json['deck_cycle'] as int?) ?? 1,
        infiniteMode: (json['infinite_mode'] as bool?) ?? false,
      );

  static Map<String, Object?> _deckJson(DeckCandidateV3 card) => {
    'card_id': card.cardId,
    'variant_id': card.variantId,
    'spice_level': card.spiceLevel,
    'distance_excluded': card.distanceExcluded,
  };

  static List<DeckCandidateV3> _deckList(Object? value) => [
    for (final raw in (value as List?) ?? const [])
      if (Map<String, Object?>.from(raw! as Map) case final card)
        DeckCandidateV3(
          cardId: card['card_id']! as String,
          variantId: card['variant_id']! as String,
          spiceLevel: card['spice_level']! as int,
          distanceExcluded: card['distance_excluded']! as bool,
        ),
  ];
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
