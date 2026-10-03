import 'package:couple_cards/domain/game/game_models.dart';
import 'package:couple_cards/domain/session/session_state.dart';
import 'package:couple_cards/engines/deck/card_direction_engine.dart';
import 'package:couple_cards/features/game/network_duel_secret_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const engine = CardDirectionEngine();

  test('reversible occurrences follow a controlled 50/50 draw', () {
    final directions = [
      for (var index = 0; index < 100; index++)
        engine
            .select(
              reversible: true,
              fixedDirection: CardOccurrenceDirection.FAIRE,
              faireAllowed: true,
              recevoirAllowed: true,
              chooseFaire: index.isEven,
            )
            .nativeDirection,
    ];
    expect(
      directions.where((value) => value == CardOccurrenceDirection.FAIRE),
      hasLength(50),
    );
    expect(
      directions.where((value) => value == CardOccurrenceDirection.RECEVOIR),
      hasLength(50),
    );
  });

  test('direction exclusions force the remaining direction', () {
    expect(
      engine
          .select(
            reversible: true,
            fixedDirection: CardOccurrenceDirection.FAIRE,
            faireAllowed: false,
            recevoirAllowed: true,
            chooseFaire: true,
          )
          .nativeDirection,
      CardOccurrenceDirection.RECEVOIR,
    );
    expect(
      engine
          .select(
            reversible: true,
            fixedDirection: CardOccurrenceDirection.RECEVOIR,
            faireAllowed: true,
            recevoirAllowed: false,
            chooseFaire: false,
          )
          .nativeDirection,
      CardOccurrenceDirection.FAIRE,
    );
    expect(
      () => engine.select(
        reversible: true,
        fixedDirection: CardOccurrenceDirection.FAIRE,
        faireAllowed: false,
        recevoirAllowed: false,
        chooseFaire: true,
      ),
      throwsStateError,
    );
  });

  test('two occurrences of the same concept may have different directions', () {
    final first = engine.select(
      reversible: true,
      fixedDirection: CardOccurrenceDirection.FAIRE,
      faireAllowed: true,
      recevoirAllowed: true,
      chooseFaire: true,
    );
    final second = engine.select(
      reversible: true,
      fixedDirection: CardOccurrenceDirection.FAIRE,
      faireAllowed: true,
      recevoirAllowed: true,
      chooseFaire: false,
    );

    expect(first.nativeDirection, CardOccurrenceDirection.FAIRE);
    expect(second.nativeDirection, CardOccurrenceDirection.RECEVOIR);
  });

  test('mutual occurrences never receive a random opposite direction', () {
    for (final chooseFaire in [true, false]) {
      final result = engine.select(
        reversible: false,
        fixedDirection: CardOccurrenceDirection.MUTUEL,
        faireAllowed: true,
        recevoirAllowed: true,
        chooseFaire: chooseFaire,
      );
      expect(result.nativeDirection, CardOccurrenceDirection.MUTUEL);
      expect(result.effectiveDirection, CardOccurrenceDirection.MUTUEL);
      expect(
        engine.invert(result.effectiveDirection),
        CardOccurrenceDirection.MUTUEL,
      );
    }
  });

  test(
    'native direction is stable while official inversion changes effective',
    () {
      final initial = CardRuntimeState(
        cardId: 'card.kiss',
        occurrenceId: 'card.kiss::1',
        variantId: 'variant.kiss.base',
        zone: CardZone.ENGAGED,
        nativeDirection: CardOccurrenceDirection.RECEVOIR,
      );
      final inverted = initial.copyWith(
        effectiveDirection: engine.invert(initial.effectiveDirection),
      );
      expect(inverted.nativeDirection, CardOccurrenceDirection.RECEVOIR);
      expect(inverted.effectiveDirection, CardOccurrenceDirection.FAIRE);
    },
  );

  test('private-state round trip preserves occurrence directions', () {
    final state = NetworkPrivateGameState(
      roundNumber: 2,
      cards: const [
        CardRuntimeState(
          cardId: 'card.kiss',
          occurrenceId: 'card.kiss::1',
          variantId: 'variant.kiss.base',
          zone: CardZone.HAND,
          nativeDirection: CardOccurrenceDirection.RECEVOIR,
          effectiveDirection: CardOccurrenceDirection.FAIRE,
        ),
      ],
      history: const {},
    );
    final restored = NetworkPrivateGameState.fromJson(state.toJson());
    expect(
      restored.cards.single.nativeDirection,
      CardOccurrenceDirection.RECEVOIR,
    );
    expect(
      restored.cards.single.effectiveDirection,
      CardOccurrenceDirection.FAIRE,
    );
  });

  test('legacy private state defaults safely to GENERAL', () {
    final restored = NetworkPrivateGameState.fromJson({
      'round_number': 1,
      'cards': [
        {
          'card_id': 'legacy',
          'occurrence_id': 'legacy::1',
          'variant_id': 'legacy.base',
          'zone': 'HAND',
          'locked': false,
        },
      ],
      'history': <String, Object?>{},
      'next_round_prepared': false,
    });
    expect(
      restored.cards.single.nativeDirection,
      CardOccurrenceDirection.GENERAL,
    );
    expect(
      restored.cards.single.effectiveDirection,
      CardOccurrenceDirection.GENERAL,
    );
  });
}
