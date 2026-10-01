import 'dart:math';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:couple_cards/data/catalog_loader/catalog_loader.dart';
import 'package:couple_cards/domain/domain.dart';
import 'package:couple_cards/engines/engines.dart';

void main() {
  test('runtime adapter uses exactly the playable V3 catalogue', () async {
    final catalog = await const CatalogLoader().load(
      (path) => File(path).readAsString(),
    );
    final runtime = catalog.cards
        .map(const CatalogEngineAdapter.v3().card)
        .toList();
    expect(runtime.where((card) => card.enabled), hasLength(104));
    expect(
      runtime
          .where((card) => card.enabled)
          .expand((card) => card.variants.where((variant) => variant.enabled)),
      hasLength(206),
    );
    expect(
      runtime
          .where((card) => card.enabled)
          .expand((card) => card.variants)
          .expand((variant) => variant.consentRules),
      everyElement(
        predicate<ConsentRule>(
          (rule) => rule.elementId.startsWith('v3.preference.'),
        ),
      ),
    );
    final toy = runtime
        .expand((card) => card.variants)
        .firstWhere((variant) => variant.tags.contains('v3.preference.sextoy'));
    expect(
      toy.technicalRules.any(
        (rule) =>
            rule.kind == TechnicalRuleKind.SESSION_FLAG &&
            rule.values.contains('hasSextoy'),
      ),
      isTrue,
    );
    expect(
      toy.consentRules.any((rule) => rule.elementId == 'hasSextoy'),
      isFalse,
    );
  });

  test('V3 balance uses 100 PA, exact gap and fixed recovery threshold 10', () {
    const config = BalanceConfig();
    expect(config.initialPa, 100);
    expect(config.gapCost(5), 5);
    expect(config.recoveryThresholdPa, 10);
  });

  test('recovery is repeatable, rounds 1.5 upward and has no upper cap', () {
    const engine = RecoveryEngine();
    const gate = RecoveryGate(
      betweenRounds: true,
      usedSinceLastNormalDuel: true,
    );
    expect(engine.available(currentPa: 10, gate: gate), isTrue);
    expect(engine.available(currentPa: 11, gate: gate), isFalse);
    final result = engine.resolve(
      currentPa: 99,
      response: RecoveryResponse.ACCEPT,
      performedRoles: const [
        (
          PreferenceValue(status: PreferenceStatus.ACCEPTED, general: 5),
          ProfileRole.GENERAL,
          true,
        ),
      ],
    );
    expect(result.gain, 8);
    expect(result.actionPoints, 107);
  });

  test('Supabase corrective migration uses threshold 10 and V3 gain range', () {
    final sql = File(
      'supabase/migrations/202610010001_gameplay_v3_recovery.sql',
    ).readAsStringSync();
    expect(sql, contains('v_current>10'));
    expect(sql, contains('not between 0 and 30'));
    expect(sql, isNot(contains('v_current>20')));
  });

  group('bounded ABA negotiation', () {
    NegotiationState initial({int loserPa = 100}) => NegotiationState(
      initialWinnerId: 'A',
      initialLoserId: 'B',
      initialHighValue: 12,
      initialGapCost: 5,
      actionPoints: {'A': 100, 'B': loserPa},
    );

    test('B proposes, A answers, B adapts and A validates', () {
      const engine = NegotiationEngineV3();
      var state = engine.propose(
        initial(),
        NegotiationOffer(
          inversionRequested: true,
          personalPa: 3,
          cardIds: const ['card.bid'],
          cardValues: const {'card.bid': 4},
        ),
      );
      state = engine.respond(
        state,
        const NegotiationResponse(acceptInversion: true, acceptAuction: true),
      );
      state = engine.adapt(
        state,
        NegotiationOffer(
          inversionRequested: true,
          personalPa: 3,
          cardIds: const ['card.bid'],
          cardValues: const {'card.bid': 4},
        ),
      );
      state = engine.validate(state, accepted: true);
      expect(state.phase, NegotiationPhase.resolved);
      expect(state.finalWinnerId, 'B');
      expect(state.inversionApplied, isTrue);
      expect(state.actionPoints, {'A': 100, 'B': 85});
    });

    test('no counter-inversion and low PA only permits card resources', () {
      const engine = NegotiationEngineV3();
      expect(
        () => engine.propose(
          initial(loserPa: 9),
          NegotiationOffer(personalPa: 1),
        ),
        throwsStateError,
      );
      final state = engine.propose(
        initial(loserPa: 9),
        NegotiationOffer(
          cardIds: const ['card.bid'],
          cardValues: const {'card.bid': 6},
        ),
      );
      expect(state.proposal!.totalPa, 6);
    });

    test('unchanged result charges exact gap only after validation', () {
      const engine = NegotiationEngineV3();
      var state = engine.propose(initial(), NegotiationOffer());
      state = engine.respond(
        state,
        const NegotiationResponse(acceptInversion: false, acceptAuction: false),
      );
      state = engine.adapt(state, NegotiationOffer());
      state = engine.validate(state, accepted: true);
      expect(state.finalWinnerId, 'A');
      expect(state.actionPoints, {'A': 95, 'B': 100});
    });
  });

  group('session deck V3', () {
    DeckCandidateV3 card(String id, int spice, {bool physical = false}) =>
        DeckCandidateV3(
          cardId: id,
          variantId: '$id.v',
          spiceLevel: spice,
          distanceExcluded: physical,
        );

    test('distinct cards have priority and no card reaches half a group', () {
      final result = const SessionDeckBuilderV3().build(
        eligible: [card('a', 3), card('b', 3), card('c', 3)],
        targetBySpice: const {3: 6},
        style: PlayerStyle.EPICE,
      );
      final counts = <String, int>{};
      for (final item in result.cards) {
        counts[item.cardId] = (counts[item.cardId] ?? 0) + 1;
      }
      expect(result.cards, hasLength(6));
      expect(counts.values.every((count) => count * 2 < 6), isTrue);
    });

    test('soft substitutes downward while spicy substitutes upward', () {
      final pool = [card('low', 2), card('high', 4)];
      final soft = const SessionDeckBuilderV3().build(
        eligible: pool,
        targetBySpice: const {3: 1},
        style: PlayerStyle.SOFT,
      );
      final spicy = const SessionDeckBuilderV3().build(
        eligible: pool,
        targetBySpice: const {3: 1},
        style: PlayerStyle.EPICE,
      );
      expect(soft.cards.single.spiceLevel, 2);
      expect(spicy.cards.single.spiceLevel, 4);
      expect(soft.adjusted, isTrue);
    });

    test('hybrid draw removes one mirrored occurrence only', () {
      final a = card('a', 2, physical: true);
      final b = card('b', 2);
      final runtime = SessionDeckRuntime(
        faceToFace: [a, a, a, b],
        distance: [a, a],
        random: Random(1),
      );
      expect(runtime.draw(HybridDeckOrientation.distance)!.cardId, 'a');
      expect(
        runtime.distance.where((item) => item.cardId == 'a'),
        hasLength(1),
      );
      expect(
        runtime.faceToFace.where((item) => item.cardId == 'a'),
        hasLength(2),
      );
    });

    test('orientation composition approximates complementary 70/30 decks', () {
      final source = [
        for (var i = 0; i < 5; i++) card('p$i', 2, physical: true),
        for (var i = 0; i < 5; i++) card('r$i', 2),
      ];
      final decks = HybridSessionDecks(source: source);
      expect(decks.faceToFace.where((c) => c.distanceExcluded), hasLength(7));
      expect(decks.distance.where((c) => c.distanceExcluded), hasLength(3));
    });
  });
}
