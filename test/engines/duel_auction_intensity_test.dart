import 'package:couple_cards/domain/domain.dart';
import 'package:couple_cards/engines/engines.dart';
import 'package:test/test.dart';

UserPreference preference({
  int? general = 10,
  int? faire = 10,
  int? recevoir = 10,
  PreferenceStatus status = PreferenceStatus.ACCEPTED,
}) => UserPreference.fromJson({
  'profile_element_id': 'practice',
  'status': status.name,
  'general_value': general,
  'faire_value': faire,
  'recevoir_value': recevoir,
  'updated_at': '2026-09-28T10:00:00Z',
  'source': 'ONBOARDING',
});

DuelCommitment commitment(String player, int value, {bool invertible = true}) =>
    const DuelEngine().commit(
      playerId: player,
      cardId: 'card.$player',
      variantId: 'variant.$player',
      voluntaryRole: ProfileRole.FAIRE,
      preference: preference(faire: value),
      committedAt: DateTime.utc(2026, 9, 28),
      cardInvertible: invertible,
    );

void main() {
  test('33 CombatValueSnapshot is immutable', () {
    final snapshot = commitment('a', 12).snapshot;
    expect(
      () => snapshot.toJson()['personal_value'] = 1,
      throwsUnsupportedError,
    );
  });

  test('34 later preference change does not affect committed power', () {
    final committed = commitment('a', 12);
    preference(faire: 2);
    expect(committed.snapshot.personalValue, 12);
  });

  test('35 inversion never recalculates snapshot power', () {
    const engine = DuelEngine();
    final committed = commitment('a', 14);
    expect(
      identical(engine.inverted(committed).snapshot, committed.snapshot),
      isTrue,
    );
    expect(engine.inverted(committed).snapshot.personalValue, 14);
  });

  test('36 duel tie spends no PA and has no automatic winner', () {
    final result = const DuelEngine().resolve(
      first: commitment('a', 10),
      second: commitment('b', 10),
      actionPoints: const {'a': 50, 'b': 50},
    );
    expect(result.tied, isTrue);
    expect(result.actionPoints, {'a': 50, 'b': 50});
  });

  test('37 gap cost follows replaceable working curve', () {
    const config = BalanceConfig();
    expect(config.gapCost(1), 1);
    expect(config.gapCost(2), 2);
    expect(config.gapCost(3), greaterThan(2));
  });

  test('38 gap cost respects configured cap', () {
    const config = BalanceConfig(initialPa: 100, gapCostCapRatio: 0.20);
    expect(config.gapCost(20), 20);
  });

  test('39 duel PA never becomes negative', () {
    final result = const DuelEngine().resolve(
      first: commitment('a', 20),
      second: commitment('b', 1),
      actionPoints: const {'a': 2, 'b': 10},
    );
    expect(result.actionPoints['a'], 0);
  });

  test('40 strategic renunciation is distinct from consent STOP', () {
    const engine = DuelEngine();
    expect(
      engine.strategicRenunciation('a').type,
      GameEventType.STRATEGIC_RENUNCIATION,
    );
    expect(engine.consentStop('a', 'v').type, GameEventType.CONSENT_STOP);
  });

  test('41 counter bid must be strictly positive over previous offer', () {
    const engine = AuctionEngine();
    final state = engine.start(
      initialWinnerId: 'a',
      initialLoserId: 'b',
      actionPoints: const {'a': 10, 'b': 10},
    );
    expect(
      () => engine.counter(
        state,
        amount: 0,
        target: AuctionTarget.OWN_INITIAL_ACTION,
      ),
      throwsArgumentError,
    );
  });

  test('42 equal final defense bid is rejected', () {
    const engine = AuctionEngine();
    var state = engine.start(
      initialWinnerId: 'a',
      initialLoserId: 'b',
      actionPoints: const {'a': 10, 'b': 10},
    );
    state = engine.counter(
      state,
      amount: 3,
      target: AuctionTarget.OWN_INITIAL_ACTION,
    );
    expect(() => engine.defend(state, amount: 3), throwsArgumentError);
  });

  test('43 auction PA are spent permanently when committed', () {
    const engine = AuctionEngine();
    var state = engine.start(
      initialWinnerId: 'a',
      initialLoserId: 'b',
      actionPoints: const {'a': 10, 'b': 10},
    );
    state = engine.counter(
      state,
      amount: 3,
      target: AuctionTarget.OWN_INITIAL_ACTION,
    );
    state = engine.defend(state, amount: 4);
    expect(state.actionPoints, {'a': 6, 'b': 7});
  });

  test('44 auction permits exactly one counter and one defense', () {
    const engine = AuctionEngine();
    var state = engine.start(
      initialWinnerId: 'a',
      initialLoserId: 'b',
      actionPoints: const {'a': 10, 'b': 10},
    );
    state = engine.counter(
      state,
      amount: 2,
      target: AuctionTarget.OWN_INITIAL_ACTION,
    );
    expect(
      () => engine.counter(
        state,
        amount: 3,
        target: AuctionTarget.OWN_INITIAL_ACTION,
      ),
      throwsStateError,
    );
    state = engine.defend(state, amount: 3);
    expect(() => engine.defend(state, amount: 4), throwsStateError);
  });

  test('45 inversion auction target requires invertible card', () {
    const engine = AuctionEngine();
    final state = engine.start(
      initialWinnerId: 'a',
      initialLoserId: 'b',
      actionPoints: const {'a': 10, 'b': 10},
    );
    expect(
      () => engine.counter(
        state,
        amount: 2,
        target: AuctionTarget.INVERT_WINNING_ACTION,
      ),
      throwsStateError,
    );
  });

  test('46 intensity jump charges cumulative configured costs', () {
    const engine = IntensityEngine();
    const state = IntensityState(active: 1, unlocked: 1, maximum: 5);
    expect(engine.unlockCost(state, 4), 16);
  });

  test('47 lowering and returning to unlocked chili are free', () {
    const engine = IntensityEngine();
    const state = IntensityState(active: 4, unlocked: 4, maximum: 5);
    final down = engine.change(
      state: state,
      target: 2,
      mutualAgreement: true,
      actionPoints: const {'a': 10, 'b': 10},
    );
    final up = engine.change(
      state: down.state,
      target: 4,
      mutualAgreement: true,
      actionPoints: down.actionPoints,
    );
    expect(up.cost, 0);
    expect(up.actionPoints, {'a': 10, 'b': 10});
  });

  test('48 refused intensity change spends nothing', () {
    const engine = IntensityEngine();
    const points = {'a': 10, 'b': 10};
    expect(
      () => engine.change(
        state: const IntensityState(active: 1, unlocked: 1, maximum: 5),
        target: 2,
        mutualAgreement: false,
        actionPoints: points,
        payments: const {'a': 3},
      ),
      throwsStateError,
    );
    expect(points, {'a': 10, 'b': 10});
  });

  test('75 intensity model permits exactly five editorial levels', () {
    const engine = IntensityEngine();
    expect(
      () => engine.change(
        state: const IntensityState(active: 5, unlocked: 5, maximum: 5),
        target: 6,
        mutualAgreement: true,
        actionPoints: const {'a': 10},
      ),
      throwsArgumentError,
    );
  });

  test('76 intensity unlock cannot create PA debt', () {
    const engine = IntensityEngine();
    expect(
      () => engine.change(
        state: const IntensityState(active: 1, unlocked: 1, maximum: 5),
        target: 2,
        mutualAgreement: true,
        actionPoints: const {'a': 2},
        payments: const {'a': 3},
      ),
      throwsStateError,
    );
  });

  test('77 initial duel cost remains spent after auction reversal', () {
    final duel = const DuelEngine().resolve(
      first: commitment('a', 12),
      second: commitment('b', 10),
      actionPoints: const {'a': 10, 'b': 10},
    );
    const auction = AuctionEngine();
    var state = auction.start(
      initialWinnerId: 'a',
      initialLoserId: 'b',
      actionPoints: duel.actionPoints,
    );
    state = auction.counter(
      state,
      amount: 3,
      target: AuctionTarget.OWN_INITIAL_ACTION,
    );
    expect(state.actionPoints, {'a': 8, 'b': 7});
  });
}
