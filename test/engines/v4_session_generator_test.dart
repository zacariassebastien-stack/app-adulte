import 'dart:math';

import 'package:couple_cards/domain/domain.dart';
import 'package:couple_cards/engines/engines.dart';
import 'package:couple_cards/features/game/network_duel_secret_store.dart';
import 'package:flutter_test/flutter_test.dart';

DeckCandidateV3 candidate(
  String variantId,
  int spice, {
  String? cardId,
  int stage = 1,
  String? sequenceKey,
  V4PresenceCompatibility presence = V4PresenceCompatibility.presentiel,
  List<String> accessories = const [],
  V4PoolMultiplicity multiplicity = V4PoolMultiplicity.standard,
}) => DeckCandidateV3(
  cardId: cardId ?? 'card.$variantId',
  variantId: variantId,
  spiceLevel: spice,
  distanceExcluded: false,
  stage: stage,
  sequenceKey: sequenceKey,
  presence: presence,
  requiredAccessoriesAnyOf: accessories,
  poolMultiplicity: multiplicity,
);

void main() {
  const generator = V4HandGenerator();

  group('V4 style generation', () {
    test('configures the three exact spice distributions', () {
      final distributions = const BalanceConfig().styleDistributions;
      expect(distributions[PlayerStyle.SOFT], {1: .45, 2: .40, 3: .13, 4: .02});
      expect(distributions[PlayerStyle.EPICE], {
        1: .20,
        2: .40,
        3: .30,
        4: .10,
      });
      expect(distributions[PlayerStyle.INTENABLE], {
        1: .10,
        2: .25,
        3: .40,
        4: .25,
      });
    });

    for (final value in <(PlayerStyle, Set<int>)>[
      (PlayerStyle.SOFT, {1, 2}),
      (PlayerStyle.EPICE, {2, 3}),
      (PlayerStyle.INTENABLE, {3, 4}),
    ]) {
      test('${value.$1.name} guarantees one of ${value.$2}', () {
        final pool = [
          candidate('v1', 1),
          candidate('v2', 2),
          candidate('v3', 3),
          candidate('v4', 4),
          candidate('v5', 4),
        ];
        final result = generator.refill(
          currentHand: const [],
          pool: pool,
          allCandidates: pool,
          progression: V4SpiceProgression.fromCandidates(pool),
          style: value.$1,
          random: Random(7),
        );
        expect(
          result.hand.any((card) => value.$2.contains(card.spiceLevel)),
          isTrue,
        );
        expect(result.hand, hasLength(4));
      });
    }

    test('falls back without reroll when the guarantee is impossible', () {
      final pool = [
        candidate('v1', 1),
        candidate('v2', 1),
        candidate('v3', 1),
        candidate('v4', 1),
      ];
      final result = generator.refill(
        currentHand: const [],
        pool: pool,
        allCandidates: pool,
        progression: V4SpiceProgression.fromCandidates(pool),
        style: PlayerStyle.INTENABLE,
        random: Random(4),
      );
      expect(result.hand, hasLength(4));
      expect(result.hand.every((card) => card.spiceLevel == 1), isTrue);
    });

    test('distribution is independent from current playability', () {
      final hot = candidate('hot', 4);
      final progression = V4SpiceProgression.fromCandidates([hot]);
      final result = generator.refill(
        currentHand: const [],
        pool: [hot],
        allCandidates: [hot],
        progression: progression,
        style: PlayerStyle.INTENABLE,
        random: Random(1),
        targetSize: 1,
      );
      expect(result.hand.single, same(hot));
      expect(progression.isPlayable(4), isFalse);
      expect(progression.isPlayable(1), isTrue);
    });

    test('normal refill keeps a playable option when the pool permits it', () {
      final pool = [
        candidate('low', 1),
        candidate('hot-a', 4),
        candidate('hot-b', 4),
        candidate('hot-c', 4),
      ];
      final progression = V4SpiceProgression.fromCandidates(pool);
      final result = generator.refill(
        currentHand: const [],
        pool: pool,
        allCandidates: pool,
        progression: progression,
        style: PlayerStyle.INTENABLE,
        random: Random(1),
      );
      expect(result.hand.any((card) => card.spiceLevel == 4), isTrue);
      expect(
        result.hand.any((card) => progression.isPlayable(card.spiceLevel)),
        isTrue,
      );
    });

    test('a retained locked card is neither replaced nor consumed', () {
      final locked = candidate('locked-hot', 4);
      final pool = [candidate('fresh-1', 1), candidate('fresh-2', 2)];
      final all = [locked, ...pool];
      final progression = V4SpiceProgression.fromCandidates(all);
      final result = generator.refill(
        currentHand: [locked],
        pool: pool,
        allCandidates: all,
        progression: progression,
        style: PlayerStyle.SOFT,
        random: Random(2),
        targetSize: 2,
      );
      expect(result.hand.first, same(locked));
      expect(progression.consumedOccurrenceIds, isEmpty);
    });
  });

  group('V4 spice progression', () {
    test('uses each level initial stock and compares percentages', () {
      final all = [
        candidate('one-a', 1),
        candidate('one-b', 1),
        for (var i = 0; i < 4; i++) candidate('two-$i', 2),
      ];
      final before = V4SpiceProgression.fromCandidates(all);
      final after = before.consume('one-a', all);
      expect(before.initialUnits(1), 2);
      expect(before.initialUnits(2), 4);
      expect(after.remainingRatio(1, all), .5);
      expect(after.remainingRatio(2, all), 1);
      expect(after.unlockedLevel, 2);
    });

    test('percentage comparison differs from raw count comparison', () {
      final all = [
        for (var i = 0; i < 10; i++) candidate('one-$i', 1),
        candidate('two-a', 2),
        candidate('two-b', 2),
      ];
      final after = V4SpiceProgression.fromCandidates(
        all,
      ).consume('one-0', all);
      expect(after.remainingUnits(1, all), 9);
      expect(after.remainingUnits(2, all), 2);
      expect(after.unlockedLevel, 2);
    });

    test('unlock is irreversible and lower levels remain playable', () {
      final all = [candidate('one', 1), candidate('two', 2)];
      final unlocked = V4SpiceProgression.fromCandidates(
        all,
      ).consume('one', all);
      expect(unlocked.unlockedLevel, 2);
      expect(unlocked.consume('two', all).unlockedLevel, 2);
      expect(unlocked.isPlayable(1), isTrue);
      expect(unlocked.isPlayable(2), isTrue);
      expect(unlocked.isPlayable(3), isFalse);
      final fullyUnlocked = V4SpiceProgression(
        initialUnitsBySpice: unlocked.initialUnitsBySpice,
        consumedOccurrenceIds: unlocked.consumedOccurrenceIds,
        unlockedLevel: 4,
      );
      expect(fullyUnlocked.isPlayable(4), isTrue);
      expect(fullyUnlocked.isPlayable(1), isTrue);
    });

    test('one consumption can unlock successive coherent levels', () {
      final all = [
        candidate('one-a', 1),
        candidate('one-b', 1),
        candidate('two-a', 2),
        candidate('two-b', 2),
        candidate('three-a', 3),
        candidate('three-b', 3),
      ];
      final state = V4SpiceProgression.fromCandidates(
        all,
      ).consume('two-a', all).consume('one-a', all);
      expect(state.unlockedLevel, 1);
      final unlocked = state.consume('one-b', all);
      expect(unlocked.unlockedLevel, 3);
    });

    test('zero denominators are handled without division errors', () {
      final all = [candidate('two', 2), candidate('three', 3)];
      final state = V4SpiceProgression.fromCandidates(
        all,
      ).consume('three', all);
      expect(state.remainingRatio(1, all), isNull);
      expect(state.unlockedLevel, 2);
    });

    test('a distributed variant is not consumed', () {
      final one = candidate('one', 1);
      final progression = V4SpiceProgression.fromCandidates([one]);
      generator.refill(
        currentHand: const [],
        pool: [one],
        allCandidates: [one],
        progression: progression,
        style: PlayerStyle.SOFT,
        random: Random(1),
        targetSize: 1,
      );
      expect(progression.consumedOccurrenceIds, isEmpty);
      expect(progression.remainingUnits(1, [one]), 1);
    });
  });

  group('V4 sequential variants', () {
    final stages = [
      candidate('evo.s1', 1, cardId: 'evo', stage: 1, sequenceKey: 'evo'),
      candidate('evo.s2', 2, cardId: 'evo', stage: 2, sequenceKey: 'evo'),
      candidate('evo.s3', 3, cardId: 'evo', stage: 3, sequenceKey: 'evo'),
    ];

    V4HandGenerationResult draw(V4SpiceProgression progression) =>
        generator.refill(
          currentHand: const [],
          pool: stages,
          allCandidates: stages,
          progression: progression,
          style: PlayerStyle.SOFT,
          random: Random(1),
          targetSize: 1,
        );

    test('offers only the lowest unconsumed stage', () {
      expect(
        draw(V4SpiceProgression.fromCandidates(stages)).drawn.single.variantId,
        'evo.s1',
      );
      expect(
        draw(
          V4SpiceProgression.fromCandidates(stages).consume('evo.s1', stages),
        ).drawn.single.variantId,
        'evo.s2',
      );
    });

    test(
      'cannot skip a lower unconsumed stage even when spice is unlocked',
      () {
        final progression = V4SpiceProgression(
          initialUnitsBySpice: const {1: 1, 2: 1, 3: 1},
          unlockedLevel: 4,
        );
        expect(draw(progression).drawn.single.variantId, 'evo.s1');
      },
    );

    test('consuming one stage does not consume later stages', () {
      final progression = V4SpiceProgression.fromCandidates(
        stages,
      ).consume('evo.s1', stages);
      expect(progression.consumedOccurrenceIds, {'evo::evo.s1'});
      expect(progression.remainingUnits(2, stages), 1);
      expect(progression.remainingUnits(3, stages), 1);
    });

    test('fully consumed evolution is absent from normal generation', () {
      var progression = V4SpiceProgression.fromCandidates(stages);
      for (final stage in stages) {
        progression = progression.consume(stage.variantId, stages);
      }
      expect(draw(progression).drawn, isEmpty);
    });

    test('drawing removes a unit without recycling it into the pool', () {
      final single = candidate('single', 1);
      final result = generator.refill(
        currentHand: const [],
        pool: [single],
        allCandidates: [single],
        progression: V4SpiceProgression.fromCandidates([single]),
        style: PlayerStyle.SOFT,
        random: Random(1),
        targetSize: 1,
      );
      expect(result.remainingPool, isEmpty);
      expect(result.drawn, [single]);
    });
  });

  test(
    'private reconnect state preserves progression and candidate stages',
    () {
      final deckCard = candidate(
        'evo.s2',
        2,
        cardId: 'evo',
        stage: 2,
        sequenceKey: 'evo',
        presence: V4PresenceCompatibility.both,
        accessories: const ['REMOTE_CONTROL_TOY'],
      );
      final state = NetworkPrivateGameState(
        roundNumber: 3,
        cards: const [],
        history: const {},
        faceToFaceDeck: [deckCard],
        distanceDeck: [deckCard],
        spiceProgression: V4SpiceProgression(
          initialUnitsBySpice: const {1: 3, 2: 4, 3: 2, 4: 1},
          consumedOccurrenceIds: const {'evo::evo.s1'},
          unlockedLevel: 2,
        ),
        availableAccessories: const {'REMOTE_CONTROL_TOY'},
        clothesByPlayer: const {'alice': 3, 'bob': 5},
      );
      final restored = NetworkPrivateGameState.fromJson(state.toJson());
      expect(restored.spiceProgression.unlockedLevel, 2);
      expect(restored.spiceProgression.consumedOccurrenceIds, {'evo::evo.s1'});
      expect(restored.spiceProgression.initialUnits(2), 4);
      expect(restored.faceToFaceDeck.single.stage, 2);
      expect(restored.faceToFaceDeck.single.sequenceKey, 'evo');
      expect(
        restored.faceToFaceDeck.single.presence,
        V4PresenceCompatibility.both,
      );
      expect(restored.faceToFaceDeck.single.requiredAccessoriesAnyOf, [
        'REMOTE_CONTROL_TOY',
      ]);
      expect(restored.availableAccessories, {'REMOTE_CONTROL_TOY'});
      expect(restored.clothesByPlayer, {'alice': 3, 'bob': 5});
    },
  );
}
