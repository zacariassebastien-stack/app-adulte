import 'package:couple_cards/domain/domain.dart';
import 'package:couple_cards/engines/engines.dart';
import 'package:couple_cards/features/game/game_screen.dart';
import 'package:couple_cards/features/game/local_game_controller.dart';
import 'package:couple_cards/features/game/local_game_fixture.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const firstCard = 'local-card-0';
  const firstVariant = '$firstCard.variant.1';

  void commitAndResolve(LocalGameController controller) {
    controller.selectLocalCard(firstCard, firstVariant);
    controller.simulatePartnerChoice();
  }

  void completePostDuel(LocalGameController controller) {
    controller.continueAfterDuel();
    if (controller.phase == LocalRoundPhase.counterAuction) {
      controller.renounceCounterBid();
      controller.skipCorruption();
    }
  }

  test('selection creates an immutable role-specific snapshot', () {
    final controller = createLocalGameFixture();
    controller.selectLocalCard(firstCard, '$firstCard.variant.2');
    final snapshot = controller.localCommitment!.snapshot;

    expect(snapshot.cardId, firstCard);
    expect(snapshot.variantId, '$firstCard.variant.2');
    expect(snapshot.roleAtCommit, ProfileRole.FAIRE);
    expect(snapshot.personalValue, 16);
    expect(snapshot.committedAt, DateTime.utc(2026, 9, 29, 12));
    expect(
      () => snapshot.toJson()['personal_value'] = 1,
      throwsUnsupportedError,
    );
  });

  test('partner deterministically skips ineligible cards', () {
    final controller = createLocalGameFixture(
      removedVariantIds: const {
        'local-card-2.variant.1',
        'local-card-2.variant.2',
      },
    );
    controller.selectLocalCard(firstCard, firstVariant);
    controller.simulatePartnerChoice();

    expect(controller.selectedPartnerCardId, 'local-card-3');
    final selected = controller.cards[controller.selectedPartnerCardId]!.engine;
    final eligibility = const EligibilityEngine().evaluate(
      card: selected,
      context: controller.context,
      actor: controller.partner.profile,
      partner: controller.local.profile,
      hierarchy: controller.hierarchy,
      requirePersonalValue: true,
    );
    expect(eligibility.eligible, isTrue);
  });

  test('DuelEngine result drives winner cost and PA', () {
    final controller = createLocalGameFixture();
    commitAndResolve(controller);
    final actual = controller.resolution!;
    final expected = const DuelEngine().resolve(
      first: controller.localCommitment!,
      second: controller.partnerCommitment!,
      actionPoints: controller.actionPointsBeforeResolution!,
    );

    expect(
      actual.events.map((event) => event.type),
      contains(GameEventType.DUEL_RESOLVED),
    );
    expect(actual.winnerPlayerId, controller.local.playerId);
    expect(actual.gap, 5);
    expect(actual.gapCost, expected.gapCost);
    expect(controller.actionPoints, expected.actionPoints);
    expect(controller.actionPoints[controller.local.playerId], 90);
  });

  test('existing duel tie behavior is preserved', () {
    final controller = createLocalGameFixture(localFaire: 11, partnerFaire: 11);
    commitAndResolve(controller);

    expect(controller.resolution!.tied, isTrue);
    expect(controller.resolution!.gap, 0);
    expect(controller.resolution!.gapCost, 0);
    expect(controller.actionPoints.values, everyElement(100));
  });

  test('closing round discards engagements, refills and preserves lock', () {
    final controller = createLocalGameFixture();
    expect(
      controller.localCards.where((card) => card.locked).single.cardId,
      'local-card-1',
    );
    commitAndResolve(controller);
    completePostDuel(controller);
    controller.continueToNextRound();

    expect(
      controller.localCards
          .where((card) => card.cardId == firstCard)
          .single
          .zone,
      CardZone.DISCARD,
    );
    expect(
      controller.screenData.discard.map((card) => card.cardId),
      contains(firstCard),
    );
    expect(controller.screenData.hand.length, 4);
    expect(
      controller.localCards.where((card) => card.locked).single.cardId,
      'local-card-1',
    );
    expect(controller.phase, LocalRoundPhase.choosing);
  });

  test('a second deterministic round can complete', () {
    final controller = createLocalGameFixture();
    commitAndResolve(controller);
    completePostDuel(controller);
    controller.continueToNextRound();
    final next = controller.screenData.hand
        .where((card) => controller.choicesForLocalCard(card.cardId).isNotEmpty)
        .first;
    final choice = controller.choicesForLocalCard(next.cardId).first;
    controller.selectLocalCard(next.cardId, choice.variant.id);
    controller.simulatePartnerChoice();

    expect(controller.roundNumber, 2);
    expect(controller.phase, LocalRoundPhase.revealed);
    expect(controller.resolution, isNotNull);
  });

  test('ineligible local card cannot be selected', () {
    final controller = createLocalGameFixture(
      removedVariantIds: const {'$firstCard.variant.1', '$firstCard.variant.2'},
    );

    expect(controller.choicesForLocalCard(firstCard), isEmpty);
    expect(
      () => controller.selectLocalCard(firstCard, firstVariant),
      throwsStateError,
    );
    expect(controller.phase, LocalRoundPhase.choosing);
  });

  testWidgets(
    'local loop renders result privately and continues on small phone',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = createLocalGameFixture();
      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(data: controller.screenData, controller: controller),
        ),
      );

      await tester.tap(find.byKey(const Key('hand-card-0')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('variant-selector')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('variant-selector')));
      await tester.tap(find.byKey(const Key('variant-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('🌶️ 2').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('choose-card-button')));
      await tester.tap(find.byKey(const Key('choose-card-button')));
      await tester.pumpAndSettle();
      expect(
        controller.localCommitment!.snapshot.variantId,
        '$firstCard.variant.2',
      );
      await tester.tap(find.byKey(const Key('simulate-partner-choice')));
      await tester.pump();

      expect(find.text('Tu remportes le duel'), findsOneWidget);
      expect(find.text('Écart : 5 · Coût : 10 PA'), findsOneWidget);
      expect(find.text('PA : 100 → 90'), findsOneWidget);
      expect(find.text('11/20'), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.byKey(const Key('continue-after-duel')));
      await tester.tap(find.byKey(const Key('continue-after-duel')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('renounce-counter')));
      await tester.tap(find.byKey(const Key('renounce-counter')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('skip-corruption')));
      await tester.tap(find.byKey(const Key('skip-corruption')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('finish-round-button')));
      await tester.tap(find.byKey(const Key('finish-round-button')));
      await tester.pump();
      expect(find.text('90'), findsOneWidget);
      expect(find.text('Ma main · 4/4'), findsOneWidget);
      expect(find.text('Défausse · 2 cartes'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
