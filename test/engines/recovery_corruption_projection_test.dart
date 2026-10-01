import 'dart:io';

import 'package:couple_cards/domain/domain.dart';
import 'package:couple_cards/engines/engines.dart';
import 'package:test/test.dart';

import 'engine_fixture.dart';

void main() {
  test('49 Recovery bypasses chili ceiling but not other filters', () {
    const engine = RecoveryEngine();
    final result = engine.actionEligibility(
      card: gameCard(chili: 5),
      context: gameContext(chiliActive: 1, chiliUnlocked: 1),
      actor: gameProfile('a'),
      partner: gameProfile('b'),
      hierarchy: emptyHierarchy,
    );
    expect(result.eligible, isTrue);
  });

  test('50 Recovery is available only at fixed 10 PA threshold', () {
    const engine = RecoveryEngine();
    const gate = RecoveryGate(
      betweenRounds: true,
      usedSinceLastNormalDuel: false,
    );
    expect(engine.available(currentPa: 10, gate: gate), isTrue);
    expect(engine.available(currentPa: 11, gate: gate), isFalse);
  });

  test('51 Recovery is only available between rounds', () {
    expect(
      const RecoveryEngine().available(
        currentPa: 0,
        gate: const RecoveryGate(
          betweenRounds: false,
          usedSinceLastNormalDuel: false,
        ),
      ),
      isFalse,
    );
  });

  test('52 Recovery can repeat while the player remains eligible', () {
    expect(
      const RecoveryEngine().available(
        currentPa: 0,
        gate: const RecoveryGate(
          betweenRounds: true,
          usedSinceLastNormalDuel: true,
        ),
      ),
      isTrue,
    );
  });

  test('53 Recovery gain uses recovering player role values', () {
    final result = const RecoveryEngine().resolve(
      currentPa: 10,
      response: RecoveryResponse.ACCEPT,
      performedRoles: [
        (accepted(faire: 7, recevoir: 3), ProfileRole.FAIRE, true),
      ],
    );
    expect(result.gain, 11);
    expect(result.actionPoints, 21);
  });

  test('54 non-completed Recovery action gives no PA', () {
    final result = const RecoveryEngine().resolve(
      currentPa: 10,
      response: RecoveryResponse.ACCEPT,
      performedRoles: [(accepted(faire: 20), ProfileRole.FAIRE, false)],
    );
    expect(result.gain, 0);
  });

  test('55 Recovery gain may exceed initial PA', () {
    final result = const RecoveryEngine().resolve(
      currentPa: 95,
      response: RecoveryResponse.ACCEPT,
      performedRoles: [(accepted(faire: 20), ProfileRole.FAIRE, true)],
    );
    expect(result.actionPoints, 125);
  });

  test('56 refused Recovery has no cost or negative event', () {
    final result = const RecoveryEngine().resolve(
      currentPa: 5,
      response: RecoveryResponse.REFUSE,
      performedRoles: const [],
    );
    expect(result.actionPoints, 5);
    expect(result.events, isEmpty);
  });

  test('57 MUTUAL_PA_EXTENSION adds an equal amount', () {
    final result = const RecoveryEngine().mutualExtension(
      actionPoints: const {'a': 2, 'b': 7},
      amount: 10,
      mutualAgreement: true,
    );
    expect(result.actionPoints, {'a': 12, 'b': 17});
    expect(result.event.type, GameEventType.MUTUAL_PA_EXTENSION);
  });

  test('58 mutual extension is repeatable by explicit agreement', () {
    const engine = RecoveryEngine();
    final first = engine.mutualExtension(
      actionPoints: const {'a': 0, 'b': 0},
      amount: 4,
      mutualAgreement: true,
    );
    final second = engine.mutualExtension(
      actionPoints: first.actionPoints,
      amount: 4,
      mutualAgreement: true,
    );
    expect(second.actionPoints, {'a': 8, 'b': 8});
  });

  test('59 corruption has no numeric power', () {
    final offer = CorruptionOffer(
      offeredBy: 'a',
      objective: CorruptionObjective.OWN_INITIAL_ACTION,
      actions: const [],
    );
    expect(const CorruptionEngine().power(offer), 0);
  });

  test('60 refused corruption leaves discard cards untouched', () {
    final offer = CorruptionOffer(
      offeredBy: 'a',
      objective: CorruptionObjective.OWN_INITIAL_ACTION,
      actions: const [ActionPromise(cardId: 'c', source: CardZone.DISCARD)],
    );
    final result = const CorruptionEngine().resolve(
      offer: offer,
      accepted: false,
      cards: const [CardRuntimeState(cardId: 'c', zone: CardZone.DISCARD)],
    );
    expect(result.cards.single.zone, CardZone.DISCARD);
  });

  test('61 completed corruption discard action becomes EXHAUSTED', () {
    final offer = CorruptionOffer(
      offeredBy: 'a',
      objective: CorruptionObjective.OWN_INITIAL_ACTION,
      actions: const [
        ActionPromise(
          cardId: 'c',
          source: CardZone.DISCARD,
          status: ActionExecutionStatus.COMPLETED,
        ),
      ],
    );
    final result = const CorruptionEngine().resolve(
      offer: offer,
      accepted: true,
      cards: const [CardRuntimeState(cardId: 'c', zone: CardZone.DISCARD)],
    );
    expect(result.cards.single.zone, CardZone.EXHAUSTED);
    expect(
      result.events.map((event) => event.type),
      contains(GameEventType.ACTION_COMPLETED),
    );
  });

  test('62 promised but unperformed corruption card remains DISCARD', () {
    final offer = CorruptionOffer(
      offeredBy: 'a',
      objective: CorruptionObjective.OWN_INITIAL_ACTION,
      actions: const [ActionPromise(cardId: 'c', source: CardZone.DISCARD)],
    );
    final result = const CorruptionEngine().resolve(
      offer: offer,
      accepted: true,
      cards: const [CardRuntimeState(cardId: 'c', zone: CardZone.DISCARD)],
    );
    expect(result.cards.single.zone, CardZone.DISCARD);
  });

  test('63 sequence preserves order and skipped item does not exhaust', () {
    final offer = CorruptionOffer(
      offeredBy: 'a',
      objective: CorruptionObjective.OWN_INITIAL_ACTION,
      actions: const [
        ActionPromise(
          cardId: 'skip',
          source: CardZone.DISCARD,
          status: ActionExecutionStatus.SKIPPED,
        ),
        ActionPromise(
          cardId: 'done',
          source: CardZone.DISCARD,
          status: ActionExecutionStatus.COMPLETED,
        ),
      ],
    );
    final result = const CorruptionEngine().resolve(
      offer: offer,
      accepted: true,
      cards: const [
        CardRuntimeState(cardId: 'skip', zone: CardZone.DISCARD),
        CardRuntimeState(cardId: 'done', zone: CardZone.DISCARD),
      ],
    );
    expect(result.cards.map((card) => card.zone), [
      CardZone.DISCARD,
      CardZone.EXHAUSTED,
    ]);
  });

  test('64 engaged cards are rejected from corruption offer', () {
    expect(
      () => CorruptionOffer(
        offeredBy: 'a',
        objective: CorruptionObjective.OWN_INITIAL_ACTION,
        actions: const [ActionPromise(cardId: 'c', source: CardZone.ENGAGED)],
      ),
      throwsArgumentError,
    );
  });

  test(
    '65 consent STOP is neutral and removes variant from future proposals',
    () {
      final result = const LifecycleEngine().consentStop(
        gameContext(),
        'variant.x',
      );
      expect(result.$1.removedVariantIds, contains('variant.x'));
      expect(result.$2.type, GameEventType.CONSENT_STOP);
      expect(result.$2.payload, isNot(contains('pa_cost')));
    },
  );

  test('66 PublicState contains no hands, PA, or unrevealed cards', () {
    final complete = CompleteGameState(
      sessionId: 's',
      roundNumber: 1,
      actionPoints: const {'a': 10, 'b': 20},
      hands: const {
        'a': ['a1'],
        'b': ['secret'],
      },
      committedCards: const {'a': 'a1', 'b': 'secret'},
    );
    final public = const VisibilityProjection().publicState(complete);
    expect(public.revealedCards, isEmpty);
    expect(public.selectionMade, {'a': true, 'b': true});
  });

  test('67 PrivatePlayerState projection contains only owner secrets', () {
    final complete = CompleteGameState(
      sessionId: 's',
      roundNumber: 1,
      actionPoints: const {'a': 10, 'b': 20},
      hands: const {
        'a': ['mine'],
        'b': ['other'],
      },
      committedCards: const {'a': 'mine', 'b': 'other'},
    );
    final private = const VisibilityProjection().privateState(complete, 'a');
    expect(private.hand, ['mine']);
    expect(private.committedCardId, 'mine');
    expect(private.actionPoints, 10);
  });

  test('68 events reject media payloads', () {
    expect(
      () => GameEvent(GameEventType.ACTION_COMPLETED, {'video': 'secret'}),
      throwsArgumentError,
    );
  });

  test('69 engines import neither Flutter, Drift, Supabase nor dart:ui', () {
    for (final file
        in Directory('lib/engines')
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))) {
      final source = file.readAsStringSync();
      expect(
        source,
        isNot(
          matches(
            RegExp(
              r'''(?:import|export)\s+['"](?:package:flutter|package:drift|package:supabase|dart:ui)''',
            ),
          ),
        ),
        reason: file.path,
      );
    }
  });

  test('78 Recovery lifecycle follows HAND DISCARD and CATALOG sources', () {
    const engine = RecoveryEngine();
    final hand = engine.applyLifecycle(
      cards: const [CardRuntimeState(cardId: 'h', zone: CardZone.HAND)],
      cardId: 'h',
      source: RecoverySource.HAND,
      completed: true,
    );
    final discard = engine.applyLifecycle(
      cards: const [CardRuntimeState(cardId: 'd', zone: CardZone.DISCARD)],
      cardId: 'd',
      source: RecoverySource.DISCARD,
      completed: true,
    );
    final catalog = engine.applyLifecycle(
      cards: const [],
      cardId: 'new',
      source: RecoverySource.CATALOG,
      completed: true,
    );
    expect(hand.single.zone, CardZone.DISCARD);
    expect(discard.single.zone, CardZone.EXHAUSTED);
    expect(catalog, isEmpty);
  });

  test('79 conditional Recovery accepts exactly one discard condition', () {
    const engine = RecoveryEngine();
    expect(
      () => engine.resolve(
        currentPa: 5,
        response: RecoveryResponse.ACCEPT_WITH_ONE_DISCARD_CONDITION,
        performedRoles: const [],
        conditionCount: 2,
      ),
      throwsArgumentError,
    );
  });

  test('83 public reveal exposes only explicitly authorized cards and PA', () {
    final complete = CompleteGameState(
      sessionId: 's',
      roundNumber: 3,
      actionPoints: const {'a': 5, 'b': 9},
      hands: const {
        'a': ['winner'],
        'b': ['loser'],
      },
      committedCards: const {'a': 'winner', 'b': 'loser'},
      publiclyRevealedCards: const {'a': 'winner'},
      revealed: true,
    );
    const projection = VisibilityProjection();
    expect(projection.publicState(complete).revealedCards, {'a': 'winner'});
    expect(projection.publicState(complete).visibleActionPoints, isEmpty);
    expect(
      projection
          .publicState(complete, revealActionPoints: true)
          .visibleActionPoints,
      {'a': 5, 'b': 9},
    );
  });

  test('84 global consent STOP halts a corruption sequence neutrally', () {
    final offer = CorruptionOffer(
      offeredBy: 'a',
      objective: CorruptionObjective.OWN_INITIAL_ACTION,
      actions: const [
        ActionPromise(
          cardId: 'stop',
          source: CardZone.DISCARD,
          status: ActionExecutionStatus.STOPPED,
        ),
        ActionPromise(
          cardId: 'later',
          source: CardZone.DISCARD,
          status: ActionExecutionStatus.COMPLETED,
        ),
      ],
    );
    final result = const CorruptionEngine().resolve(
      offer: offer,
      accepted: true,
      cards: const [
        CardRuntimeState(cardId: 'stop', zone: CardZone.DISCARD),
        CardRuntimeState(cardId: 'later', zone: CardZone.DISCARD),
      ],
    );

    expect(result.stoppedByConsent, isTrue);
    expect(result.cards.every((card) => card.zone == CardZone.DISCARD), isTrue);
    expect(
      result.events.where((event) => event.type == GameEventType.CONSENT_STOP),
      hasLength(1),
    );
    expect(
      result.events.where(
        (event) => event.type == GameEventType.ACTION_COMPLETED,
      ),
      isEmpty,
    );
  });
}
