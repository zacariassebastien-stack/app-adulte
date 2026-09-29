import '../catalog/catalog.dart';
import '../catalog/definitions.dart';
import '../session/session_state.dart';
import 'game_models.dart';
import 'projection.dart';

/// Pure view data only. No widget, navigation, illustration generation or timer.
final class GameCardView {
  GameCardView({
    required this.cardId,
    required this.category,
    required List<int> chiliLevels,
    required this.locked,
    this.titleKey,
    this.descriptionKey,
    this.illustrationKey,
    this.personalValue,
    List<String> instructionKeys = const [],
  }) : chiliLevels = List.unmodifiable(chiliLevels),
       instructionKeys = List.unmodifiable(instructionKeys);
  final String cardId, category;
  final String? titleKey, descriptionKey, illustrationKey;
  final List<int> chiliLevels;
  final List<String> instructionKeys;
  final int? personalValue;
  final bool locked;
  Map<String, Object?> toJson() => {
    'card_id': cardId,
    'category': category,
    'title_key': titleKey,
    'description_key': descriptionKey,
    'illustration_key': illustrationKey,
    'personal_value': personalValue,
    'chili_levels': chiliLevels,
    'instruction_keys': instructionKeys,
    'locked': locked,
  };
}

final class GameScreenData {
  GameScreenData({
    required this.playerId,
    required this.chiliActive,
    required this.elapsedSeconds,
    required List<GameCardView> hand,
    required List<GameCardView> discard,
    required List<GameCardView> centralActions,
    required this.privateDataHidden,
    this.actionPoints,
    this.indicativeDurationMinutes,
  }) : hand = List.unmodifiable(hand),
       discard = List.unmodifiable(discard),
       centralActions = List.unmodifiable(centralActions);
  final String playerId;
  final int chiliActive, elapsedSeconds;
  final int? actionPoints, indicativeDurationMinutes;
  final List<GameCardView> hand, discard, centralActions;
  final bool privateDataHidden;
  int get targetHandSize => 4;
  bool get settingsAvailable => true;
  Map<String, Object?> toJson() => {
    'player_id': playerId,
    'chili_active': chiliActive,
    'elapsed_seconds': elapsedSeconds,
    'indicative_duration_minutes': indicativeDurationMinutes,
    'action_points': actionPoints,
    'target_hand_size': targetHandSize,
    'settings_available': settingsAvailable,
    'private_data_hidden': privateDataHidden,
    'hand': hand.map((c) => c.toJson()).toList(),
    'discard': discard.map((c) => c.toJson()).toList(),
    'central_actions': centralActions.map((c) => c.toJson()).toList(),
  };
}

final class GameScreenProjection {
  const GameScreenProjection();
  GameScreenData forPlayer({
    required CompleteGameState state,
    required String playerId,
    required EngineSessionContext context,
    required Catalog catalog,
    required Iterable<PersistedCardState> cards,
    Map<String, int> ownPersonalValues = const {},
    bool sharedDeviceTransition = false,
    int elapsedSeconds = 0,
    int? indicativeDurationMinutes,
  }) {
    if (!state.hands.containsKey(playerId)) throw StateError('Unknown player');
    if (elapsedSeconds < 0 || (indicativeDurationMinutes ?? 0) < 0) {
      throw ArgumentError('Invalid duration');
    }
    final definitions = {for (final c in catalog.cards) c.stableId: c};
    final owned = cards.where((c) => c.playerId == playerId).toList();
    GameCardView view(CardDefinition card, {bool private = false}) {
      final value = private ? ownPersonalValues[card.stableId] : null;
      if (value != null && (value < 1 || value > 20)) {
        throw ArgumentError('Personal value outside 1..20');
      }
      return GameCardView(
        cardId: card.stableId,
        category: card.directionality?.name ?? card.precision.name,
        titleKey: card.titleKey,
        descriptionKey: card.descriptionKey,
        illustrationKey: card.illustrationKey,
        personalValue: value,
        locked:
            private && owned.any((c) => c.cardId == card.stableId && c.locked),
        chiliLevels: List.unmodifiable(
          card.variants.map((v) => v.chiliLevel).toSet(),
        ),
        instructionKeys: List.unmodifiable(
          card.variants.map((v) => v.instructionKey).whereType<String>(),
        ),
      );
    }

    List<GameCardView> views(Iterable<String> ids, {bool private = false}) =>
        List.unmodifiable([
          for (final id in ids)
            if (definitions.containsKey(id))
              view(definitions[id]!, private: private),
        ]);
    final public = const VisibilityProjection().publicState(state);
    return GameScreenData(
      playerId: playerId,
      chiliActive: context.chiliActive,
      elapsedSeconds: elapsedSeconds,
      indicativeDurationMinutes: indicativeDurationMinutes,
      privateDataHidden: sharedDeviceTransition,
      actionPoints: sharedDeviceTransition
          ? null
          : state.actionPoints[playerId],
      hand: sharedDeviceTransition
          ? const []
          : views(state.hands[playerId]!, private: true),
      discard: sharedDeviceTransition
          ? const []
          : views(
              owned
                  .where((c) => c.zone == CardZone.DISCARD)
                  .map((c) => c.cardId),
              private: true,
            ),
      centralActions: views(public.revealedCards.values),
    );
  }
}
