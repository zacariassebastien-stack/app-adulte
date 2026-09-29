import 'dart:io';
import 'package:couple_cards/data/catalog_loader/catalog_loader.dart';
import 'package:couple_cards/domain/domain.dart';
import 'package:couple_cards/simulation/configuration.dart';
import 'package:couple_cards/simulation/runner.dart';
import 'package:test/test.dart';
import '../engines/engine_fixture.dart';

void main() {
  late Catalog catalog;
  final journal = <GameEvent>[];
  setUpAll(() async {
    catalog = await const CatalogLoader().load((p) => File(p).readAsString());
    final scenarios = representativeScenarios();
    final runner = SimulationRunner(
      catalog,
      onEvent: (e) => journal.add(GameEvent.fromStored(e)),
    );
    for (var i = 0; i < 30; i++) {
      runner.run(seed: 410000 + i, scenario: scenarios[i % scenarios.length]);
    }
  });
  Iterable<GameEvent> of(GameEventType type) =>
      journal.where((e) => e.type == type);
  test('instrumentation leaves every business metric unchanged', () {
    final scenario = representativeScenarios().first;
    final plain = SimulationRunner(
      catalog,
    ).run(seed: 410000, scenario: scenario);
    final recorded = SimulationRunner(
      catalog,
      onEvent: (_) {},
    ).run(seed: 410000, scenario: scenario);
    expect(recorded.toJson(), plain.toJson());
  });
  for (final type in [
    GameEventType.AUCTION_COMMITTED,
    GameEventType.AUCTION_RESOLVED,
    GameEventType.INVERSION_ATTEMPTED,
    GameEventType.INVERSION_RETAINED,
    GameEventType.RECOVERY_PROPOSED,
    GameEventType.RECOVERY_RESOLVED,
    GameEventType.STRATEGIC_RENUNCIATION,
    GameEventType.CORRUPTION_RESOLVED,
  ]) {
    test('simulator emits $type with private owner and round', () {
      expect(of(type), isNotEmpty);
      expect(
        of(type).every(
          (e) =>
              e.ownerPlayerId != null &&
              e.payload['round_id'] != null &&
              e.publicProjection().isEmpty,
        ),
        isTrue,
      );
    });
  }
  for (final target in ['OWN_CARD', 'INVERT_WINNER_CARD']) {
    test('counter target $target and success are explicit', () {
      final resolved = of(
        GameEventType.AUCTION_RESOLVED,
      ).where((e) => e.payload['target'] == target);
      expect(resolved, isNotEmpty);
      expect(resolved.every((e) => e.payload['success'] is bool), isTrue);
    });
  }
  test('used counter, unused opportunity and final defense are distinct', () {
    expect(
      of(
        GameEventType.AUCTION_COMMITTED,
      ).any((e) => e.payload['kind'] == 'COUNTER'),
      isTrue,
    );
    expect(
      of(
        GameEventType.AUCTION_COMMITTED,
      ).any((e) => e.payload['kind'] == 'FINAL_DEFENSE'),
      isTrue,
    );
    expect(of(GameEventType.DECISION_PASSED), isNotEmpty);
  });
  test('Recovery preserves source, chili exception and PA ledger', () {
    final resolved = of(GameEventType.RECOVERY_RESOLVED);
    expect(resolved.any((e) => e.payload['chili_exception'] == true), isTrue);
    for (final e in resolved) {
      expect(e.payload['card_source'], isIn(['CATALOG', 'HAND', 'DISCARD']));
      expect(
        e.payload['pa_after'],
        (e.payload['pa_before']! as int) + (e.payload['gain']! as int),
      );
      if (e.payload['response'] == 'REFUSE') {
        expect(
          e.analytics.every((c) => c.stage == ObservationStage.EXCLUDED),
          isTrue,
        );
      }
    }
  });
  test('accepted promises correlate to their executed action', () {
    final promised = of(GameEventType.CORRUPTION_PROPOSED)
        .expand((e) => e.payload['actions'] as List)
        .map((a) => (a as Map)['action_id'])
        .toSet();
    final executed = of(GameEventType.ACTION_EXECUTION_RECORDED).where(
      (e) =>
          e.payload['source'] == 'CORRUPTION' &&
          e.analytics.any((c) => c.axis == BehaviorAxis.PROMESSE),
    );
    expect(executed, isNotEmpty);
    expect(
      executed.every((e) => promised.contains(e.payload['action_id'])),
      isTrue,
    );
  });
  test('all execution sources are observed', () {
    expect(
      of(
        GameEventType.ACTION_EXECUTION_RECORDED,
      ).map((e) => e.payload['source']).toSet(),
      ActionSource.values.map((s) => s.name).toSet(),
    );
  });
  test('screen projection includes own data and hides it on transition', () {
    final a = catalog.cards[0].stableId, b = catalog.cards[1].stableId;
    final state = CompleteGameState(
      sessionId: 's',
      roundNumber: 1,
      actionPoints: {'a': 90, 'b': 80},
      hands: {
        'a': [a],
        'b': [b],
      },
      committedCards: {'a': a, 'b': b},
      revealed: true,
      publiclyRevealedCards: {'a': a},
    );
    GameScreenData project(bool hidden) =>
        const GameScreenProjection().forPlayer(
          state: state,
          playerId: 'a',
          context: gameContext(),
          catalog: catalog,
          cards: [
            PersistedCardState(
              playerId: 'a',
              cardId: a,
              zone: CardZone.HAND,
              ordinal: 0,
              locked: true,
            ),
            PersistedCardState(
              playerId: 'a',
              cardId: b,
              zone: CardZone.DISCARD,
              ordinal: 1,
            ),
          ],
          ownPersonalValues: {a: 17},
          sharedDeviceTransition: hidden,
          elapsedSeconds: 120,
          indicativeDurationMinutes: 30,
        );
    final own = project(false), hidden = project(true);
    expect(own.hand.single.personalValue, 17);
    expect(own.hand.single.locked, isTrue);
    expect(own.actionPoints, 90);
    expect(own.discard.single.cardId, b);
    expect(own.targetHandSize, 4);
    expect(own.settingsAvailable, isTrue);
    expect(own.elapsedSeconds, 120);
    expect(own.centralActions.single.personalValue, isNull);
    expect(hidden.hand, isEmpty);
    expect(hidden.discard, isEmpty);
    expect(hidden.actionPoints, isNull);
    expect(hidden.centralActions.single.personalValue, isNull);
    expect(
      const VisibilityProjection().publicState(state).visibleActionPoints,
      isEmpty,
    );
  });
  test('view lists cannot be mutated after creation', () {
    final levels = [1];
    final card = GameCardView(
      cardId: 'c',
      category: 'test',
      chiliLevels: levels,
      locked: false,
    );
    levels.add(2);
    expect(card.chiliLevels, [1]);
    expect(() => card.chiliLevels.add(3), throwsUnsupportedError);
  });
}
