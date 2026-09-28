import '../../domain/catalog/enums.dart';
import '../../domain/game/balance_config.dart';
import '../../domain/game/events.dart';
import '../../domain/profile/preferences.dart';
import '../../domain/round/combat_value_snapshot.dart';

final class DuelCommitment {
  const DuelCommitment({
    required this.snapshot,
    required this.cardInvertible,
    this.events = const [],
  });
  final CombatValueSnapshot snapshot;
  final bool cardInvertible;
  final List<GameEvent> events;
}

final class DuelResolution {
  const DuelResolution({
    required this.first,
    required this.second,
    required this.actionPoints,
    required this.events,
    this.winnerPlayerId,
    this.gapCost = 0,
  });
  final DuelCommitment first;
  final DuelCommitment second;
  final String? winnerPlayerId;
  final int gapCost;
  final Map<String, int> actionPoints;
  final List<GameEvent> events;
  bool get tied => winnerPlayerId == null;
}

final class DuelEngine {
  const DuelEngine({this.config = const BalanceConfig()});
  final BalanceConfig config;

  DuelCommitment commit({
    required String playerId,
    required String cardId,
    required String variantId,
    required ProfileRole voluntaryRole,
    required UserPreference preference,
    required DateTime committedAt,
    required bool cardInvertible,
  }) {
    if (preference.status != PreferenceStatus.ACCEPTED) {
      throw StateError('A committed action requires explicit ACCEPTED consent');
    }
    final value = switch (voluntaryRole) {
      ProfileRole.GENERAL => preference.generalValue,
      ProfileRole.FAIRE => preference.faireValue,
      ProfileRole.RECEVOIR => preference.recevoirValue,
    };
    if (value == null) {
      throw StateError('Missing personal value for $voluntaryRole');
    }
    return DuelCommitment(
      cardInvertible: cardInvertible,
      events: [
        GameEvent(GameEventType.CARD_SELECTED, {
          'player_id': playerId,
          'card_id': cardId,
          'variant_id': variantId,
        }),
        GameEvent(GameEventType.CARD_COMMITTED, {'player_id': playerId}),
      ],
      snapshot: CombatValueSnapshot.fromJson({
        'player_id': playerId,
        'card_id': cardId,
        'variant_id': variantId,
        'role_at_commit': voluntaryRole.name,
        'personal_value': value,
        'committed_at': committedAt.toUtc().toIso8601String(),
      }),
    );
  }

  DuelResolution resolve({
    required DuelCommitment first,
    required DuelCommitment second,
    required Map<String, int> actionPoints,
  }) {
    final firstValue = first.snapshot.personalValue;
    final secondValue = second.snapshot.personalValue;
    if (firstValue == secondValue) {
      return DuelResolution(
        first: first,
        second: second,
        actionPoints: Map.unmodifiable(actionPoints),
        events: [
          GameEvent(GameEventType.CARDS_REVEALED),
          GameEvent(GameEventType.DUEL_RESOLVED, {'tied': true}),
        ],
      );
    }
    final winner = firstValue > secondValue ? first : second;
    final gap = (firstValue - secondValue).abs();
    final cost = config.gapCost(gap);
    final points = Map<String, int>.from(actionPoints);
    final current = points[winner.snapshot.playerId] ?? 0;
    final spent = cost.clamp(0, current);
    points[winner.snapshot.playerId] = current - spent;
    return DuelResolution(
      first: first,
      second: second,
      winnerPlayerId: winner.snapshot.playerId,
      gapCost: spent,
      actionPoints: Map.unmodifiable(points),
      events: [
        GameEvent(GameEventType.CARDS_REVEALED),
        GameEvent(GameEventType.PA_SPENT, {
          'player_id': winner.snapshot.playerId,
          'amount': spent,
        }),
        GameEvent(GameEventType.DUEL_RESOLVED, {
          'winner_player_id': winner.snapshot.playerId,
        }),
      ],
    );
  }

  DuelCommitment inverted(DuelCommitment commitment) {
    if (!commitment.cardInvertible) throw StateError('Card is not invertible');
    return commitment;
  }

  GameEvent strategicRenunciation(String playerId) =>
      GameEvent(GameEventType.STRATEGIC_RENUNCIATION, {'player_id': playerId});

  GameEvent consentStop(String playerId, String variantId) => GameEvent(
    GameEventType.CONSENT_STOP,
    {'player_id': playerId, 'variant_id': variantId},
  );
}
