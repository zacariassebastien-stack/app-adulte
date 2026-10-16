import 'dart:io';
import 'package:test/test.dart';
import 'package:couple_cards/data/catalog_loader/catalog_loader.dart';
import 'package:couple_cards/engines/engines.dart';
import 'package:couple_cards/domain/domain.dart';
import 'support/concept_runtime_checks.dart';

void main(){
  for(final entry in conceptRuntimeChecks().entries){ test(entry.key,entry.value); }
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

    test('two 006 engaged uses cumulatively remove two clothes', () {
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

    test('two 007 engaged uses cumulatively remove four clothes', () {
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
