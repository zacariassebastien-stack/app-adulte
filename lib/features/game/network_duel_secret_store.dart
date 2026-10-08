import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/catalog/v4_catalog.dart';
import '../../domain/game/game_models.dart';
import '../../domain/session/session_state.dart';
import '../../engines/draw/draw_engine.dart';
import '../../engines/deck/session_deck_builder.dart';
import '../../sync/commit_reveal/commit_reveal.dart';

final class NetworkPlayedCardRecord {
  const NetworkPlayedCardRecord({
    required this.cardId,
    required this.variantId,
    required this.occurrenceId,
    required this.roundNumber,
  });

  final String cardId, variantId, occurrenceId;
  final int roundNumber;

  Map<String, Object?> toJson() => {
    'card_id': cardId,
    'variant_id': variantId,
    'occurrence_id': occurrenceId,
    'round_number': roundNumber,
  };

  factory NetworkPlayedCardRecord.fromJson(Map<String, Object?> json) =>
      NetworkPlayedCardRecord(
        cardId: json['card_id']! as String,
        variantId: json['variant_id']! as String,
        occurrenceId: json['occurrence_id']! as String,
        roundNumber: json['round_number']! as int,
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
    List<DeckCandidateV3> faceToFaceDeck = const [],
    List<DeckCandidateV3> distanceDeck = const [],
    this.deckCycle = 1,
    this.infiniteMode = false,
    this.deckStyle = PlayerStyle.SOFT,
    List<DeckShortage> deckShortages = const [],
    List<String> recentCardIds = const [],
    List<NetworkPlayedCardRecord> publicDiscards = const [],
    this.choiceVersion = 0,
    V4SpiceProgression? spiceProgression,
    Set<String> availableAccessories = const {},
    Map<String, int> clothesByPlayer = const {},
  }) : cards = List.unmodifiable(cards),
       history = Map.unmodifiable(history),
       learningRecordedRounds = Set.unmodifiable(learningRecordedRounds),
       faceToFaceDeck = List.unmodifiable(faceToFaceDeck),
       distanceDeck = List.unmodifiable(distanceDeck),
       deckShortages = List.unmodifiable(deckShortages),
       recentCardIds = List.unmodifiable(recentCardIds),
       publicDiscards = List.unmodifiable(publicDiscards),
       availableAccessories = Set.unmodifiable(availableAccessories),
       clothesByPlayer = Map.unmodifiable(clothesByPlayer),
       spiceProgression =
           spiceProgression ??
           V4SpiceProgression(initialUnitsBySpice: const {});

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
  final PlayerStyle deckStyle;
  final List<DeckShortage> deckShortages;
  final List<String> recentCardIds;
  final List<NetworkPlayedCardRecord> publicDiscards;
  final int choiceVersion;
  final V4SpiceProgression spiceProgression;
  final Set<String> availableAccessories;
  final Map<String, int> clothesByPlayer;

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
    'face_to_face_deck': [for (final card in faceToFaceDeck) _deckJson(card)],
    'distance_deck': [for (final card in distanceDeck) _deckJson(card)],
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
    'recent_card_ids': recentCardIds,
    'public_discards': [for (final card in publicDiscards) card.toJson()],
    'choice_version': choiceVersion,
    'available_accessories': availableAccessories.toList()..sort(),
    'clothes_by_player': clothesByPlayer,
    'v4_spice_progression': {
      'initial_units_by_spice': {
        for (final entry in spiceProgression.initialUnitsBySpice.entries)
          entry.key.toString(): entry.value,
      },
      'consumed_occurrence_ids': spiceProgression.consumedOccurrenceIds.toList()
        ..sort(),
      'unlocked_level': spiceProgression.unlockedLevel,
    },
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
        faceToFaceDeck: _deckList(json['face_to_face_deck']),
        distanceDeck: _deckList(json['distance_deck']),
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
        recentCardIds: ((json['recent_card_ids'] as List?) ?? const [])
            .cast<String>(),
        publicDiscards: [
          for (final raw in (json['public_discards'] as List?) ?? const [])
            NetworkPlayedCardRecord.fromJson(
              Map<String, Object?>.from(raw! as Map),
            ),
        ],
        choiceVersion: (json['choice_version'] as int?) ?? 0,
        availableAccessories:
            ((json['available_accessories'] as List?) ?? const [])
                .cast<String>()
                .toSet(),
        clothesByPlayer: {
          for (final entry in Map<String, Object?>.from(
            (json['clothes_by_player'] as Map?) ?? const {},
          ).entries)
            entry.key: entry.value! as int,
        },
        spiceProgression: _progression(json['v4_spice_progression']),
      );

  static Map<String, Object?> _deckJson(DeckCandidateV3 card) => {
    'card_id': card.cardId,
    'variant_id': card.variantId,
    'spice_level': card.spiceLevel,
    'distance_excluded': card.distanceExcluded,
    'occurrence_id': card.occurrenceId,
    'stage': card.stage,
    'sequence_key': card.sequenceKey,
    'presence': card.presence.wireName,
    'required_accessories_any_of': card.requiredAccessoriesAnyOf,
    'pool_multiplicity': card.poolMultiplicity.name,
  };

  static V4SpiceProgression _progression(Object? value) {
    if (value == null) {
      return V4SpiceProgression(initialUnitsBySpice: const {});
    }
    final json = Map<String, Object?>.from(value as Map);
    final rawCounts = Map<String, Object?>.from(
      (json['initial_units_by_spice'] as Map?) ?? const {},
    );
    return V4SpiceProgression(
      initialUnitsBySpice: {
        for (final entry in rawCounts.entries)
          int.parse(entry.key): entry.value! as int,
      },
      consumedOccurrenceIds:
          ((json['consumed_occurrence_ids'] as List?) ??
                  (json['consumed_variant_ids'] as List?) ??
                  const [])
              .cast<String>()
              .toSet(),
      unlockedLevel: (json['unlocked_level'] as int?) ?? 1,
    );
  }

  static List<DeckCandidateV3> _deckList(Object? value) {
    final result = <DeckCandidateV3>[];
    final legacyOrdinals = <String, int>{};
    for (final raw in (value as List?) ?? const []) {
      final card = Map<String, Object?>.from(raw! as Map);
      final cardId = card['card_id']! as String;
      final variantId = card['variant_id']! as String;
      final contentKey = '$cardId::$variantId';
      final legacyOrdinal = legacyOrdinals.update(
        contentKey,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
      result.add(
        DeckCandidateV3(
          cardId: cardId,
          variantId: variantId,
          spiceLevel: card['spice_level']! as int,
          distanceExcluded: card['distance_excluded']! as bool,
          stage: (card['stage'] as int?) ?? 1,
          sequenceKey: card['sequence_key'] as String?,
          presence: V4PresenceCompatibility.parse(
            (card['presence'] as String?) ?? 'PRESENTIEL',
          ),
          requiredAccessoriesAnyOf:
              ((card['required_accessories_any_of'] as List?) ?? const [])
                  .cast<String>(),
          poolMultiplicity: V4PoolMultiplicity.values.byName(
            (card['pool_multiplicity'] as String?) ?? 'standard',
          ),
          occurrenceId:
              card['occurrence_id'] as String? ??
              '$contentKey::legacy-$legacyOrdinal',
        ),
      );
    }
    return result;
  }
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
