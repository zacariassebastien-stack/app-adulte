import 'dart:io';
import 'dart:math';

import 'package:couple_cards/data/catalog_loader/catalog_loader.dart';
import 'package:couple_cards/domain/domain.dart';
import 'package:couple_cards/engines/engines.dart';
import 'package:test/test.dart';

DeckCandidateV3 unit(
  String id, {
  V4PresenceCompatibility presence = V4PresenceCompatibility.presentiel,
  List<String> accessories = const [],
  V4PoolMultiplicity multiplicity = V4PoolMultiplicity.standard,
  int spice = 1,
  int stage = 1,
  String? sequence,
  String? occurrence,
}) => DeckCandidateV3(
  cardId: 'card.$id',
  variantId: 'variant.$id',
  spiceLevel: spice,
  distanceExcluded: presence == V4PresenceCompatibility.presentiel,
  presence: presence,
  requiredAccessoriesAnyOf: accessories,
  poolMultiplicity: multiplicity,
  stage: stage,
  sequenceKey: sequence,
  occurrenceId: occurrence,
);

void main() {
  const projector = V4ContextualPool();

  V4ContextualPoolSnapshot project(
    List<DeckCandidateV3> candidates,
    V4SessionPresence presence, {
    V4SpiceProgression? progression,
    Set<String> accessories = const {},
    Set<String> excludedCards = const {},
    Set<String> hand = const {},
  }) => projector.project(
    allCandidates: candidates,
    progression: progression ?? V4SpiceProgression.fromCandidates(candidates),
    context: V4PoolContext(
      presence: presence,
      availableAccessories: accessories,
      excludedCardIds: excludedCards,
    ),
    inHandOccurrenceIds: hand,
  );

  group('global and active V4 pools', () {
    final present = unit('present');
    final remote = unit('remote', presence: V4PresenceCompatibility.distance);
    final both = unit('both', presence: V4PresenceCompatibility.both);
    final all = [present, remote, both];

    test('PRESENTIEL excludes distance-only units', () {
      expect(
        project(all, V4SessionPresence.presentiel).active.map((e) => e.cardId),
        containsAll(<String>['card.present', 'card.both']),
      );
      expect(
        project(all, V4SessionPresence.presentiel).active,
        isNot(contains(remote)),
      );
    });

    test('DISTANCE excludes present-only units', () {
      expect(project(all, V4SessionPresence.distance).active, [remote, both]);
    });

    test('BOTH works in both states', () {
      expect(project(all, V4SessionPresence.presentiel).active, contains(both));
      expect(project(all, V4SessionPresence.distance).active, contains(both));
    });

    test('hybrid state changes recompute active pool in both directions', () {
      expect(project(all, V4SessionPresence.distance).active, [remote, both]);
      expect(project(all, V4SessionPresence.presentiel).active, [
        present,
        both,
      ]);
    });

    test('an unconsumed unit returns after a round trip', () {
      final first = project(all, V4SessionPresence.presentiel);
      final away = project(all, V4SessionPresence.distance);
      final back = project(all, V4SessionPresence.presentiel);
      expect(first.active, contains(present));
      expect(away.active, isNot(contains(present)));
      expect(back.active, contains(present));
    });

    test('a consumed occurrence never returns', () {
      final progression = V4SpiceProgression.fromCandidates(
        all,
      ).consume(present.occurrenceId, all);
      expect(
        project(
          all,
          V4SessionPresence.presentiel,
          progression: progression,
        ).globalRemaining,
        isNot(contains(present)),
      );
    });

    test('context changes alone do not change spice progression', () {
      final progression = V4SpiceProgression.fromCandidates(all);
      project(all, V4SessionPresence.distance, progression: progression);
      project(all, V4SessionPresence.presentiel, progression: progression);
      expect(progression.unlockedLevel, 1);
      expect(progression.consumedOccurrenceIds, isEmpty);
      expect(progression.initialUnits(1), 3);
    });

    test(
      'an incompatible hand unit stays global but is not active/drawable',
      () {
        final snapshot = project(
          all,
          V4SessionPresence.distance,
          hand: {present.occurrenceId},
        );
        expect(snapshot.globalRemaining, contains(present));
        expect(snapshot.active, isNot(contains(present)));
        expect(snapshot.drawable, isNot(contains(present)));
      },
    );

    test('a locked-compatible hand unit is retained and not redrawn', () {
      final snapshot = project(
        all,
        V4SessionPresence.presentiel,
        hand: {both.occurrenceId},
      );
      expect(snapshot.active, contains(both));
      expect(snapshot.drawable, isNot(contains(both)));
    });

    test('accessory requirement filters only when none is available', () {
      final toy = unit('toy', accessories: const ['SEXTOY', 'VIBRATING_TOY']);
      expect(project([toy], V4SessionPresence.presentiel).active, isEmpty);
      expect(
        project(
          [toy],
          V4SessionPresence.presentiel,
          accessories: const {'VIBRATING_TOY'},
        ).active,
        [toy],
      );
    });

    test('Exclu is a hard veto without a PA weight', () {
      final lowPa = unit('pa-1');
      final highPa = unit('pa-20');
      final snapshot = project(
        [lowPa, highPa],
        V4SessionPresence.presentiel,
        excludedCards: {highPa.cardId},
      );
      expect(snapshot.active, [lowPa]);
      // Candidate and projection APIs intentionally contain no PA field.
      expect(snapshot.active.single.spiceLevel, lowPa.spiceLevel);
    });

    test('sequential content cannot skip an unconsumed lower stage', () {
      final first = unit('stage-1', stage: 1, sequence: 'sequence');
      final second = unit(
        'stage-2',
        stage: 2,
        sequence: 'sequence',
        presence: V4PresenceCompatibility.both,
      );
      expect(
        project([first, second], V4SessionPresence.distance).active,
        isEmpty,
      );
      final consumed = V4SpiceProgression.fromCandidates([
        first,
        second,
      ]).consume(first.occurrenceId, [first, second]);
      expect(
        project(
          [first, second],
          V4SessionPresence.distance,
          progression: consumed,
        ).active,
        [second],
      );
    });
  });

  group('V4 clothing and multiplicity', () {
    const naked = V4ClothingSnapshot(
      state: V4ClothingState.nu,
      removableClothing: 0,
    );
    const engine = V4ClothingEngine();

    V4ClothingSnapshot remove(
      V4ClothingSnapshot current,
      V4ClothingBehavior behavior,
    ) => engine.apply(current: current, behavior: behavior, fullOutfitCount: 6);

    const dressedSix = V4ClothingSnapshot(
      state: V4ClothingState.habille,
      removableClothing: 6,
    );

    test('two 006 occurrences cumulatively remove two clothes', () {
      final afterFirst = remove(dressedSix, V4ClothingBehavior.removeOne);
      final afterSecond = remove(afterFirst, V4ClothingBehavior.removeOne);
      expect(afterFirst.removableClothing, 5);
      expect(afterSecond.removableClothing, 4);
    });

    test('006 then 007 cumulatively remove three clothes', () {
      final afterOne = remove(dressedSix, V4ClothingBehavior.removeOne);
      final afterTwo = remove(afterOne, V4ClothingBehavior.removeTwo);
      expect(afterTwo.removableClothing, 3);
    });

    test('two 007 occurrences cumulatively remove four clothes', () {
      final afterFirst = remove(dressedSix, V4ClothingBehavior.removeTwo);
      final afterSecond = remove(afterFirst, V4ClothingBehavior.removeTwo);
      expect(afterFirst.removableClothing, 4);
      expect(afterSecond.removableClothing, 2);
    });

    test('available 006/007 combinations can reach NU without redressing', () {
      var current = dressedSix;
      for (final behavior in [
        V4ClothingBehavior.removeTwo,
        V4ClothingBehavior.removeOne,
        V4ClothingBehavior.removeTwo,
        V4ClothingBehavior.removeOne,
      ]) {
        current = remove(current, behavior);
      }
      expect(current.removableClothing, 0);
      expect(current.state, V4ClothingState.nu);
    });

    test('006/007 clamp at zero and never trigger automatic redressing', () {
      final afterOne = remove(naked, V4ClothingBehavior.removeOne);
      final afterTwo = remove(naked, V4ClothingBehavior.removeTwo);
      expect(afterOne.removableClothing, 0);
      expect(afterTwo.removableClothing, 0);
      expect(afterOne.state, V4ClothingState.nu);
      expect(afterTwo.state, V4ClothingState.nu);
    });

    test('008 from NU ends in underwear', () {
      final result = engine.apply(
        current: naked,
        behavior: V4ClothingBehavior.resetThenUnderwear,
        fullOutfitCount: 5,
      );
      expect(result.state, V4ClothingState.sousVetements);
      expect(result.removableClothing, 1);
    });

    test('009 and 011 end nude after their reset', () {
      for (final behavior in [
        V4ClothingBehavior.resetThenNude,
        V4ClothingBehavior.resetThenStripComplete,
      ]) {
        expect(
          engine
              .apply(current: naked, behavior: behavior, fullOutfitCount: 5)
              .state,
          V4ClothingState.nu,
        );
      }
    });

    test('010 resets before applying its strip action', () {
      final result = engine.apply(
        current: naked,
        behavior: V4ClothingBehavior.resetThenStrip,
        fullOutfitCount: 5,
      );
      expect(result.state, V4ClothingState.habille);
      expect(result.removableClothing, 4);
    });

    test('012 and 013 can recreate or increase clothing', () {
      const dressed = V4ClothingSnapshot(
        state: V4ClothingState.habille,
        removableClothing: 6,
      );
      for (final behavior in [
        V4ClothingBehavior.chooseOutfit,
        V4ClothingBehavior.changeOutfit,
      ]) {
        expect(
          engine.apply(
            current: naked,
            behavior: behavior,
            fullOutfitCount: 5,
            chosenOutcome: dressed,
          ),
          same(dressed),
        );
      }
    });

    test(
      '006/007 multiplicity covers ten removable items deterministically',
      () {
        final one = unit(
          '006',
          multiplicity: V4PoolMultiplicity.removableClothingOne,
        );
        final two = unit(
          '007',
          multiplicity: V4PoolMultiplicity.removableClothingTwo,
        );
        final materialized = const V4PoolMaterializer().materialize(
          candidates: [one, two],
          totalRemovableClothing: 10,
        );
        expect(materialized.where((e) => e.cardId == one.cardId), hasLength(2));
        expect(materialized.where((e) => e.cardId == two.cardId), hasLength(4));
        expect(materialized.map((e) => e.occurrenceId).toSet(), hasLength(6));
      },
    );

    test('occurrences are independently consumed and counted for spice', () {
      final copies = const V4PoolMaterializer().materialize(
        candidates: [
          unit('006', multiplicity: V4PoolMultiplicity.removableClothingOne),
        ],
        totalRemovableClothing: 4,
      );
      final initial = V4SpiceProgression.fromCandidates(copies);
      final consumed = initial.consume(copies.first.occurrenceId, copies);
      expect(initial.initialUnits(1), 2);
      expect(consumed.remainingUnits(1, copies), 1);
      expect(consumed.consumedOccurrenceIds, {copies.first.occurrenceId});
    });

    test('draw consumes no occurrence and recycling is absent', () {
      final copies = const V4PoolMaterializer().materialize(
        candidates: [
          unit('006', multiplicity: V4PoolMultiplicity.removableClothingOne),
        ],
        totalRemovableClothing: 4,
      );
      final progression = V4SpiceProgression.fromCandidates(copies);
      final drawn = const V4HandGenerator().refill(
        currentHand: const [],
        pool: copies,
        allCandidates: copies,
        progression: progression,
        style: PlayerStyle.SOFT,
        random: Random(1),
        targetSize: 1,
      );
      expect(progression.consumedOccurrenceIds, isEmpty);
      expect(drawn.remainingPool, hasLength(1));
      expect(
        drawn.remainingPool.map((item) => item.occurrenceId),
        isNot(contains(drawn.drawn.single.occurrenceId)),
      );
    });
  });

  test('canonical V4 catalog classifies all 65 cards explicitly', () async {
    final catalog = await const CatalogLoader().load(
      (path) => File(path).readAsString(),
    );
    expect(catalog.cards, hasLength(65));
    expect(catalog.cards.every((card) => card.v4 != null), isTrue);
    final byNumber = {for (final card in catalog.cards) card.v4!.number: card};
    for (final number in const [
      '042',
      '043',
      '044',
      '045',
      '046',
      '047',
      '053',
      '058',
    ]) {
      expect(byNumber[number]!.v4!.presence, V4PresenceCompatibility.both);
    }
    expect(
      catalog.cards.where(
        (card) => card.v4!.presence == V4PresenceCompatibility.distance,
      ),
      isEmpty,
    );
    expect(byNumber['006']!.v4!.clothingBehavior, V4ClothingBehavior.removeOne);
    expect(byNumber['007']!.v4!.clothingBehavior, V4ClothingBehavior.removeTwo);
  });
}
