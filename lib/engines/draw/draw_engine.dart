import 'dart:math' as math;

import '../../domain/catalog/enums.dart';
import '../../domain/game/balance_config.dart';
import '../../domain/game/game_models.dart';
import '../eligibility/eligibility_engine.dart';

abstract interface class RandomSource {
  double nextDouble();
}

final class SeededRandomSource implements RandomSource {
  SeededRandomSource(int seed) : _random = math.Random(seed);
  final math.Random _random;
  @override
  double nextDouble() => _random.nextDouble();
}

enum CardHistoryState { unseen, seenUnplayed, playedOrDiscarded }

final class DrawHistory {
  DrawHistory({
    Map<String, CardHistoryState>? cards,
    Set<String>? recentTags,
    Set<Precision>? recentPrecisions,
  }) : cards = Map.unmodifiable(cards ?? const {}),
       recentTags = Set.unmodifiable(recentTags ?? const {}),
       recentPrecisions = Set.unmodifiable(recentPrecisions ?? const {});
  final Map<String, CardHistoryState> cards;
  final Set<String> recentTags;
  final Set<Precision> recentPrecisions;
  CardHistoryState stateOf(String cardId) =>
      cards[cardId] ?? CardHistoryState.unseen;
}

final class DrawCandidateScore {
  const DrawCandidateScore({required this.eligibility, required this.weight});
  final CardEligibility eligibility;
  final double weight;
}

final class DrawEngine {
  const DrawEngine({
    this.eligibilityEngine = const EligibilityEngine(),
    this.config = const BalanceConfig(),
  });
  final EligibilityEngine eligibilityEngine;
  final BalanceConfig config;

  List<DrawCandidateScore> candidates({
    required List<EngineCard> cards,
    required EngineSessionContext context,
    required PlayerGameProfile actor,
    required PlayerGameProfile partner,
    required ProfileHierarchy hierarchy,
    required PlayerStyle style,
    required DrawHistory history,
  }) {
    final eligible = <CardEligibility>[
      for (final card in cards)
        eligibilityEngine.evaluate(
          card: card,
          context: context,
          actor: actor,
          partner: partner,
          hierarchy: hierarchy,
        ),
    ].where((item) => item.eligible).toList();
    if (eligible.isEmpty) return const [];
    final bestTier = eligible
        .map((item) => history.stateOf(item.card.id).index)
        .reduce(math.min);
    final cycle = eligible.where(
      (item) => history.stateOf(item.card.id).index == bestTier,
    );
    return [
      for (final item in cycle)
        DrawCandidateScore(
          eligibility: item,
          weight: _weight(item, style, history),
        ),
    ];
  }

  EngineCard? drawOne({
    required List<EngineCard> cards,
    required EngineSessionContext context,
    required PlayerGameProfile actor,
    required PlayerGameProfile partner,
    required ProfileHierarchy hierarchy,
    required PlayerStyle style,
    required DrawHistory history,
    required RandomSource random,
  }) {
    final choices = candidates(
      cards: cards,
      context: context,
      actor: actor,
      partner: partner,
      hierarchy: hierarchy,
      style: style,
      history: history,
    );
    if (choices.isEmpty) return null;
    final total = choices.fold<double>(0, (sum, item) => sum + item.weight);
    var point = random.nextDouble() * total;
    for (final choice in choices) {
      point -= choice.weight;
      if (point <= 0) return choice.eligibility.card;
    }
    return choices.last.eligibility.card;
  }

  List<EngineCard> refill({
    required List<EngineCard> currentHand,
    required List<EngineCard> cards,
    required EngineSessionContext context,
    required PlayerGameProfile actor,
    required PlayerGameProfile partner,
    required ProfileHierarchy hierarchy,
    required PlayerStyle style,
    required DrawHistory history,
    required RandomSource random,
  }) {
    final hand = List<EngineCard>.from(currentHand);
    final states = Map<String, CardHistoryState>.from(history.cards);
    while (hand.length < config.handSize) {
      final available = cards
          .where((card) => !hand.any((held) => held.id == card.id))
          .toList(growable: false);
      final picked = drawOne(
        cards: available,
        context: context,
        actor: actor,
        partner: partner,
        hierarchy: hierarchy,
        style: style,
        history: DrawHistory(
          cards: states,
          recentTags: history.recentTags,
          recentPrecisions: history.recentPrecisions,
        ),
        random: random,
      );
      if (picked == null) break;
      hand.add(picked);
      states[picked.id] = CardHistoryState.seenUnplayed;
    }
    return List.unmodifiable(hand);
  }

  double _weight(CardEligibility item, PlayerStyle style, DrawHistory history) {
    final variant = item.eligibleVariants.reduce(
      (left, right) => left.chiliLevel >= right.chiliLevel ? left : right,
    );
    final cycleWeight = switch (history.stateOf(item.card.id)) {
      CardHistoryState.unseen => config.drawWeights.unseen,
      CardHistoryState.seenUnplayed => config.drawWeights.seenUnplayed,
      CardHistoryState.playedOrDiscarded =>
        config.drawWeights.played * config.antiRepeatDecay,
    };
    final styleFactor =
        config.styleDistributions[style]?[variant.chiliLevel] ?? 1;
    final newTags = item.card.tags
        .where((tag) => !history.recentTags.contains(tag))
        .length;
    final precisionNovelty =
        history.recentPrecisions.contains(item.card.precision) ? 0 : 1;
    final frequency = switch (item.card.frequency) {
      EditorialFrequency.COMMON => 1.0,
      EditorialFrequency.OCCASIONAL => 0.75,
      EditorialFrequency.RARE => 0.5,
    };
    return math.max(
      0.0001,
      cycleWeight +
          config.drawWeights.style * styleFactor +
          config.drawWeights.chili * variant.chiliLevel +
          config.drawWeights.tagDiversity * newTags +
          config.drawWeights.precisionDiversity * precisionNovelty +
          config.drawWeights.frequency * frequency,
    );
  }
}
