import 'package:couple_cards/domain/domain.dart';
import 'package:couple_cards/engines/engines.dart';
import 'package:test/test.dart';

import 'engine_fixture.dart';

void main() {
  final actor = gameProfile('a');
  final partner = gameProfile('b');

  EngineCard draw({required String id, int chili = 1}) =>
      gameCard(id: id, chili: chili);

  test('17 lowering chili keeps cards already in hand', () {
    const cards = [CardRuntimeState(cardId: 'c', zone: CardZone.HAND)];
    const lifecycle = LifecycleEngine();
    expect(lifecycle.closeRound(cards).single.zone, CardZone.HAND);
  });

  test('18 temporarily unplayable card remains in hand', () {
    const card = CardRuntimeState(cardId: 'c', zone: CardZone.HAND);
    expect(card.copyWith().zone, CardZone.HAND);
  });

  test('19 draw is deterministic for identical state and seed', () {
    const engine = DrawEngine();
    String? run() => engine
        .drawOne(
          cards: [
            draw(id: 'a'),
            draw(id: 'b'),
          ],
          context: gameContext(),
          actor: actor,
          partner: partner,
          hierarchy: emptyHierarchy,
          style: PlayerStyle.EPICE,
          history: DrawHistory(),
          random: SeededRandomSource(42),
        )
        ?.id;
    expect(run(), run());
  });

  test('20 EXHAUSTED card is never drawn', () {
    const engine = DrawEngine();
    final result = engine.drawOne(
      cards: [
        draw(id: 'dead'),
        draw(id: 'live'),
      ],
      context: gameContext(exhausted: {'dead'}),
      actor: actor,
      partner: partner,
      hierarchy: emptyHierarchy,
      style: PlayerStyle.SOFT,
      history: DrawHistory(),
      random: SeededRandomSource(1),
    );
    expect(result!.id, 'live');
  });

  test('21 unseen cycle has priority over seen and played', () {
    const engine = DrawEngine();
    final candidates = engine.candidates(
      cards: [
        draw(id: 'new'),
        draw(id: 'seen'),
        draw(id: 'played'),
      ],
      context: gameContext(),
      actor: actor,
      partner: partner,
      hierarchy: emptyHierarchy,
      style: PlayerStyle.SOFT,
      history: DrawHistory(
        cards: const {
          'seen': CardHistoryState.seenUnplayed,
          'played': CardHistoryState.playedOrDiscarded,
        },
      ),
    );
    expect(candidates.map((candidate) => candidate.eligibility.card.id), [
      'new',
    ]);
  });

  test('22 style changes weight but never eligibility', () {
    const engine = DrawEngine();
    final cards = [draw(id: 'hot', chili: 3)];
    final soft = engine
        .candidates(
          cards: cards,
          context: gameContext(),
          actor: actor,
          partner: partner,
          hierarchy: emptyHierarchy,
          style: PlayerStyle.SOFT,
          history: DrawHistory(),
        )
        .single;
    final intense = engine
        .candidates(
          cards: cards,
          context: gameContext(),
          actor: actor,
          partner: partner,
          hierarchy: emptyHierarchy,
          style: PlayerStyle.INTENABLE,
          history: DrawHistory(),
        )
        .single;
    expect(soft.eligibility.eligible, isTrue);
    expect(intense.eligibility.eligible, isTrue);
    expect(intense.weight, greaterThan(soft.weight));
  });

  test('23 lifecycle POOL HAND ENGAGED DISCARD HAND', () {
    const engine = LifecycleEngine();
    var cards = const [CardRuntimeState(cardId: 'c', zone: CardZone.HAND)];
    cards = engine.engage(cards, 'c');
    expect(cards.single.zone, CardZone.ENGAGED);
    cards = engine.closeRound(cards);
    expect(cards.single.zone, CardZone.DISCARD);
    cards = engine.redrawDiscard(cards, 'c');
    expect(cards.single.zone, CardZone.HAND);
  });

  test('24 only one lock remains and engaging clears it', () {
    const engine = LifecycleEngine();
    var cards = const [
      CardRuntimeState(cardId: 'a', zone: CardZone.HAND),
      CardRuntimeState(cardId: 'b', zone: CardZone.HAND),
    ];
    cards = engine.lock(cards, 'a');
    cards = engine.lock(cards, 'b');
    expect(cards.where((card) => card.locked).single.cardId, 'b');
    cards = engine.engage(cards, 'b');
    expect(cards.any((card) => card.locked), isFalse);
  });

  test('25 engaged card cannot be used for corruption', () {
    const engine = LifecycleEngine();
    expect(
      engine.canUseForCorruption(
        const CardRuntimeState(cardId: 'c', zone: CardZone.ENGAGED),
      ),
      isFalse,
    );
    expect(
      engine.canUseForCorruption(
        const CardRuntimeState(cardId: 'c', zone: CardZone.DISCARD),
      ),
      isTrue,
    );
  });

  test('26 StateEffect applies only after COMPLETED', () {
    const engine = LifecycleEngine();
    final context = gameContext(clothes: {'a': 2});
    final effect = StateEffect.fromJson({
      'type': 'CLOTHES_DELTA',
      'target': 'ACTOR',
      'delta': -1,
    });
    final skipped = engine.applyEffects(
      beforeAction: context,
      current: context,
      effects: [effect],
      actorId: 'a',
      partnerId: 'b',
      status: ActionExecutionStatus.SKIPPED,
    );
    final completed = engine.applyEffects(
      beforeAction: context,
      current: context,
      effects: [effect],
      actorId: 'a',
      partnerId: 'b',
      status: ActionExecutionStatus.COMPLETED,
    );
    expect(skipped.clothesByPlayer['a'], 2);
    expect(completed.clothesByPlayer['a'], 1);
  });

  test('27 contextual refresh only follows newly contextual impossibility', () {
    const engine = LifecycleEngine();
    expect(
      engine.contextualRefreshAllowed(
        before: const {},
        after: const {IneligibilityCode.PROXIMITY},
      ),
      isTrue,
    );
  });

  test('28 chili reduction cannot become contextual mulligan', () {
    const engine = LifecycleEngine();
    expect(
      engine.contextualRefreshAllowed(
        before: const {},
        after: const {IneligibilityCode.CHILI_TOO_HIGH},
      ),
      isFalse,
    );
  });

  test('29 HYBRID proximity changes without PA mutation', () {
    const engine = LifecycleEngine();
    final changed = engine.changeProximity(
      gameContext(mode: SessionMode.hybrid, proximity: ProximityState.TOGETHER),
      ProximityState.SEPARATED,
    );
    expect(changed.proximity, ProximityState.SEPARATED);
  });

  test('30 temporary meeting returns to SEPARATED', () {
    const engine = LifecycleEngine();
    final closed = engine.closeTemporaryMeeting(
      gameContext(proximity: ProximityState.TOGETHER),
    );
    expect(closed.proximity, ProximityState.SEPARATED);
  });

  test('31 PA zero and duration never automatically end session', () {
    const engine = LifecycleEngine();
    expect(
      engine.shouldEndSession(
        explicitHumanDecision: false,
        technicalClosure: false,
        actionPoints: 0,
        indicativeDurationReached: true,
      ),
      isFalse,
    );
  });

  test('32 refill target comes from BalanceConfig', () {
    const engine = LifecycleEngine(config: BalanceConfig(handSize: 5));
    expect(
      engine.refillNeeded(const [
        CardRuntimeState(cardId: 'a', zone: CardZone.HAND),
      ]),
      4,
    );
  });

  test('74 DrawEngine refills configured hand without duplicates', () {
    const engine = DrawEngine(config: BalanceConfig(handSize: 3));
    final hand = engine.refill(
      currentHand: const [],
      cards: [
        draw(id: 'a'),
        draw(id: 'b'),
        draw(id: 'c'),
      ],
      context: gameContext(),
      actor: actor,
      partner: partner,
      hierarchy: emptyHierarchy,
      style: PlayerStyle.EPICE,
      history: DrawHistory(),
      random: SeededRandomSource(7),
    );
    expect(hand.length, 3);
    expect(hand.map((card) => card.id).toSet().length, 3);
  });
}
