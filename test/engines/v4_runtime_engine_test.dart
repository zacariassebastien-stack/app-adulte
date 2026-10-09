import 'dart:math';

import 'package:couple_cards/domain/domain.dart';
import 'package:couple_cards/engines/engines.dart';
import 'package:test/test.dart';

void main() {
  group('V4 turn context', () {
    test('fixed modes cannot change and hybrid changes only at boundary', () {
      const presentiel = V4TurnContext(
        mode: V4SessionMode.presentiel,
        presence: V4SessionPresence.presentiel,
      );
      expect(
        () => presentiel.changePresence(V4SessionPresence.distance),
        throwsStateError,
      );

      const hybrid = V4TurnContext(
        mode: V4SessionMode.hybrid,
        presence: V4SessionPresence.presentiel,
      );
      expect(
        hybrid.changePresence(V4SessionPresence.distance).presence,
        V4SessionPresence.distance,
      );
      expect(
        () => hybrid.startTurn().changePresence(V4SessionPresence.distance),
        throwsStateError,
      );
    });
  });

  group('cycle availability', () {
    const guard = V4CycleGuard();

    test('hands of 3, 2 or 1 continue while occurrences remain', () {
      for (final remaining in [3, 2, 1]) {
        expect(
          guard.evaluate(
            mode: V4SessionMode.presentiel,
            activeOccurrencesByPlayer: {'a': remaining, 'b': 4},
          ),
          V4CycleAvailability.continueCurrent,
        );
      }
    });

    test('the first player at zero ends the common cycle', () {
      expect(
        guard.evaluate(
          mode: V4SessionMode.distance,
          activeOccurrencesByPlayer: const {'a': 0, 'b': 9},
        ),
        V4CycleAvailability.endCommon,
      );
    });

    test('hybrid can switch context instead of ending at the boundary', () {
      expect(
        guard.evaluate(
          mode: V4SessionMode.hybrid,
          activeOccurrencesByPlayer: const {'a': 0, 'b': 3},
          alternateContextOccurrencesByPlayer: const {'a': 2, 'b': 1},
        ),
        V4CycleAvailability.switchHybridContext,
      );
    });
  });

  test('the first Terminé closes the shared action exactly once', () {
    final gate = V4ActionCompletionGate();
    expect(gate.complete(), isTrue);
    expect(gate.complete(), isFalse);
  });

  test('next cycle preserves session state but resets occurrence stock', () {
    final state = V4ContinuationState(
      clothingCounts: const {'a': 2},
      accessoryPool: V4SessionAccessoryPool(
        profileAccessories: [
          V4Accessory(
            id: 'x',
            name: 'X',
            ownerPlayerId: 'a',
            tags: const {V4AccessoryTag.externe},
          ),
        ],
      ),
      presence: V4SessionPresence.distance,
      effects: const [
        V4PersistentEffect(
          cardId: '033',
          targetPlayerId: 'b',
          remainingActions: 2,
        ),
      ],
      unlockedSpice: 3,
      consumedOccurrenceIds: const {'o1'},
    );
    final next = state.nextCycle();
    expect(next.clothingCounts, {'a': 2});
    expect(next.accessoryPool.available.single.id, 'x');
    expect(next.presence, V4SessionPresence.distance);
    expect(next.effects.single.remainingActions, 2);
    expect(next.unlockedSpice, 3);
    expect(next.consumedOccurrenceIds, isEmpty);
  });

  test('new customized game resets temporary session state', () {
    final reset = V4ContinuationState.newCustomizedGame();
    expect(reset.clothingCounts, isEmpty);
    expect(reset.accessoryPool.available, isEmpty);
    expect(reset.effects, isEmpty);
    expect(reset.unlockedSpice, 1);
  });

  group('occurrence reservation', () {
    test('commit is idempotent and consumption happens exactly once', () {
      final ledger = V4OccurrenceLedger();
      expect(ledger.moveToHand('o1'), isTrue);
      expect(ledger.reserve('o1'), isTrue);
      expect(ledger.reserve('o1'), isTrue);
      expect(ledger.consume('o1'), isTrue);
      expect(ledger.consume('o1'), isFalse);
      expect(ledger.statusOf('o1'), V4OccurrenceStatus.consumed);
    });

    test('technical cancellation restores the same occurrence to hand', () {
      final ledger = V4OccurrenceLedger()
        ..moveToHand('o1')
        ..reserve('o1');
      expect(ledger.cancelReservation('o1'), isTrue);
      expect(ledger.statusOf('o1'), V4OccurrenceStatus.hand);
    });
  });

  test('effective spice applies only to a game imposed intimate zone', () {
    const chosen = V4ResolvedParameters(
      zoneSelectionSource: V4ZoneSelectionSource.players,
      sexualOrIntimateZone: true,
    );
    const imposed = V4ResolvedParameters(
      zoneSelectionSource: V4ZoneSelectionSource.game,
      sexualOrIntimateZone: true,
    );
    expect(chosen.effectiveSpice(2), 2);
    expect(imposed.effectiveSpice(2), 3);
    expect(imposed.effectiveSpice(4), 4);
  });

  test('anti-soft-lock replaces without consuming the returned card', () {
    final first = _playable('first', false);
    final locked = _playable('locked', false, locked: true);
    final possible = _playable('possible', true);
    final result = const V4PlayableHandGuard().ensurePlayable(
      hand: [first, locked],
      availablePool: [possible],
      random: Random(1),
    );
    expect(result.map((item) => item.candidate.occurrenceId), [
      'first',
      'possible',
    ]);
    expect(locked.candidate.occurrenceId, 'locked');
  });

  group('clothing integer source of truth', () {
    test('006 then 007 is cumulative and never negative', () {
      final clothing = V4ClothingCounter({'a': 6});
      expect(clothing.remove('a', 1), 5);
      expect(clothing.remove('a', 2), 3);
      expect(clothing.remove('a', 99), 0);
    });

    test('actual count can resynchronize after a clothing action', () {
      final clothing = V4ClothingCounter({'a': 6})..remove('a', 2);
      clothing.resynchronize('a', 5);
      expect(clothing.countFor('a'), 5);
      expect(() => clothing.resynchronize('a', -1), throwsArgumentError);
    });
  });

  group('persistent effects', () {
    const engine = V4PersistentEffectEngine();

    test('RECEVOIR targets owner and FAIRE targets partner', () {
      const resolver = V4ActionTargetResolver();
      final receiveTargets = resolver.resolve(
        ownerPlayerId: 'alice',
        playerIds: const ['alice', 'bob'],
        direction: CardOccurrenceDirection.RECEVOIR,
      );
      final receiveEffects = engine.createForAction(
        cardId: '033',
        targetPlayerIds: receiveTargets,
        durationActions: 3,
      );
      expect(receiveEffects.single.targetPlayerId, 'alice');

      final doTargets = resolver.resolve(
        ownerPlayerId: 'alice',
        playerIds: const ['alice', 'bob'],
        direction: CardOccurrenceDirection.FAIRE,
      );
      final doEffects = engine.createForAction(
        cardId: '033',
        targetPlayerIds: doTargets,
        durationActions: 3,
      );
      expect(doEffects.single.targetPlayerId, 'bob');
    });

    test('activation action is not counted and three next actions expire', () {
      var effects = engine.closeAction(
        activeBeforeAction: const [],
        producedEffect: const V4PersistentEffect(
          cardId: '033',
          targetPlayerId: 'b',
          remainingActions: 3,
        ),
      );
      expect(effects.single.remainingActions, 3);
      effects = engine.closeAction(activeBeforeAction: effects);
      expect(effects.single.remainingActions, 2);
      effects = engine.closeAction(activeBeforeAction: effects);
      expect(effects.single.remainingActions, 1);
      effects = engine.closeAction(activeBeforeAction: effects);
      expect(effects, isEmpty);
    });

    test('same effect and target renews after old effects decrement', () {
      final result = engine.closeAction(
        activeBeforeAction: const [
          V4PersistentEffect(
            cardId: '033',
            targetPlayerId: 'b',
            remainingActions: 1,
          ),
        ],
        producedEffect: const V4PersistentEffect(
          cardId: '033',
          targetPlayerId: 'b',
          remainingActions: 3,
        ),
      );
      expect(result.single.remainingActions, 3);
    });

    test('different targets remain independent', () {
      final result = engine.closeAction(
        activeBeforeAction: const [
          V4PersistentEffect(
            cardId: '033',
            targetPlayerId: 'a',
            remainingActions: 3,
          ),
        ],
        producedEffect: const V4PersistentEffect(
          cardId: '033',
          targetPlayerId: 'b',
          remainingActions: 3,
        ),
      );
      expect(result, hasLength(2));
      expect(
        result
            .firstWhere((item) => item.targetPlayerId == 'a')
            .remainingActions,
        2,
      );
    });

    test('all duration effects in a compromise start together', () {
      final result = engine.closeAction(
        activeBeforeAction: const [],
        producedEffects: const [
          V4PersistentEffect(
            cardId: '033',
            targetPlayerId: 'a',
            remainingActions: 3,
          ),
          V4PersistentEffect(
            cardId: '034',
            targetPlayerId: 'b',
            remainingActions: 2,
          ),
        ],
      );
      expect(result, hasLength(2));
      expect(result.map((effect) => effect.remainingActions), [3, 2]);
    });
  });

  group('accessories', () {
    final profileAccessory = V4Accessory(
      id: 'a',
      name: 'A',
      ownerPlayerId: 'p1',
      tags: const {V4AccessoryTag.anal, V4AccessoryTag.vibrant},
    );
    final temporary = V4Accessory(
      id: 'temp',
      name: 'Temp',
      ownerPlayerId: 'p2',
      tags: const {V4AccessoryTag.externe},
      temporary: true,
    );

    test('required tags use AND and empty compatibility is ineligible', () {
      final pool = V4SessionAccessoryPool(
        profileAccessories: [profileAccessory],
      );
      expect(
        pool.selectCompatible(const {
          V4AccessoryTag.anal,
          V4AccessoryTag.vibrant,
        }, Random(1))?.id,
        'a',
      );
      expect(
        pool.selectCompatible(const {
          V4AccessoryTag.anal,
          V4AccessoryTag.buccal,
        }, Random(1)),
        isNull,
      );
    });

    test('runtime requirement tokens require one matching accessory', () {
      final requirements = V4AccessoryRequirements.fromTokens(const [
        'ANAL',
        'VIBRANT',
      ]);
      expect(
        requirements.accepts(
          V4Accessory(
            id: 'anal',
            name: 'Anal',
            ownerPlayerId: 'p1',
            tags: const {V4AccessoryTag.anal},
          ),
        ),
        isFalse,
      );
      expect(requirements.accepts(profileAccessory), isTrue);
    });

    test('temporary disable does not mutate profile and round-trips', () {
      final pool = V4SessionAccessoryPool(
        profileAccessories: [profileAccessory],
        disabledIds: const ['a'],
        temporaryAccessories: [temporary],
      );
      expect(pool.available.map((item) => item.id), ['temp']);
      expect(profileAccessory.normallyActive, isTrue);
      final restored = V4SessionAccessoryPool.fromJson(pool.toJson());
      expect(restored.available.single.id, 'temp');
      expect(restored.available.single.temporary, isTrue);
    });

    test('unknown exact tag-set preference defaults to 18', () {
      final book = V4AccessoryPreferenceBook({
        V4AccessoryPreferenceBook.key(const {V4AccessoryTag.anal}, 'FAIRE'): 7,
      });
      expect(book.value(const {V4AccessoryTag.anal}, 'FAIRE'), 7);
      expect(
        book.value(const {
          V4AccessoryTag.anal,
          V4AccessoryTag.vibrant,
        }, 'FAIRE'),
        18,
      );
    });
  });

  group('multi-component PA', () {
    const calculator = V4PaCalculator();
    test('one component stays unchanged', () {
      expect(calculator.combine(const [7]), 7);
    });
    test('two components are their rounded mean', () {
      expect(calculator.combine(const [5, 12]), 9);
    });
    test('highest half plus other mean half', () {
      expect(calculator.combine(const [4, 8, 20]), 13);
    });
  });
}

V4PlayableOccurrence _playable(
  String id,
  bool playable, {
  bool locked = false,
}) => V4PlayableOccurrence(
  candidate: DeckCandidateV3(
    cardId: 'card.$id',
    variantId: 'variant.$id',
    spiceLevel: 1,
    distanceExcluded: false,
    occurrenceId: id,
  ),
  parameters: const V4ResolvedParameters(),
  playable: playable,
  locked: locked,
);
