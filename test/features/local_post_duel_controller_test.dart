import 'package:couple_cards/domain/domain.dart';
import 'package:couple_cards/engines/engines.dart';
import 'package:couple_cards/features/game/game_screen.dart';
import 'package:couple_cards/features/game/local_game_controller.dart';
import 'package:couple_cards/features/game/local_game_fixture.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const localCard = 'local-card-0';

  LocalGameController reveal({bool invertible = true}) {
    final controller = createLocalGameFixture();
    controller.selectLocalCard(
      localCard,
      '$localCard.variant.${invertible ? 2 : 1}',
    );
    controller.simulatePartnerChoice();
    return controller;
  }

  LocalGameController atCounter({bool invertible = true}) {
    final controller = reveal(invertible: invertible)..continueAfterDuel();
    expect(controller.phase, LocalRoundPhase.counterAuction);
    return controller;
  }

  LocalGameController atCorruption() {
    final controller = atCounter()..renounceCounterBid();
    expect(controller.phase, LocalRoundPhase.corruption);
    return controller;
  }

  test('renouncing counter auction keeps duel PA spent', () {
    final controller = atCounter();
    final afterDuel = controller.actionPoints;

    controller.renounceCounterBid();

    expect(controller.phase, LocalRoundPhase.corruption);
    expect(controller.actionPoints, afterDuel);
    expect(controller.actionPoints[controller.local.playerId], 90);
    expect(
      controller.roundEvents.map((event) => event.type),
      contains(GameEventType.STRATEGIC_RENUNCIATION),
    );
  });

  test('valid counter spends PA and opens one final defense', () {
    final controller = atCounter();

    controller.submitCounterBid(2, AuctionTarget.OWN_INITIAL_ACTION);

    expect(controller.phase, LocalRoundPhase.finalDefense);
    expect(controller.actionPoints[controller.partner.playerId], 98);
    expect(controller.minimumBid, 3);
    expect(controller.finalWinnerId, controller.partner.playerId);
  });

  test('insufficient counter is rejected without spending PA', () {
    final controller = atCounter();
    final before = controller.actionPoints;

    expect(
      () => controller.submitCounterBid(0, AuctionTarget.OWN_INITIAL_ACTION),
      throwsArgumentError,
    );
    expect(controller.phase, LocalRoundPhase.counterAuction);
    expect(controller.actionPoints, before);
    expect(
      () => controller.submitCounterBid(101, AuctionTarget.OWN_INITIAL_ACTION),
      throwsStateError,
    );
    expect(controller.actionPoints, before);
  });

  test('final defense spends PA and prevents a third bid', () {
    final controller = atCounter()
      ..submitCounterBid(2, AuctionTarget.OWN_INITIAL_ACTION)
      ..submitFinalDefense(3);

    expect(controller.phase, LocalRoundPhase.corruption);
    expect(controller.actionPoints[controller.local.playerId], 87);
    expect(controller.actionPoints[controller.partner.playerId], 98);
    expect(controller.finalWinnerId, controller.local.playerId);
    expect(() => controller.submitFinalDefense(4), throwsStateError);
    expect(
      () => controller.submitCounterBid(4, AuctionTarget.OWN_INITIAL_ACTION),
      throwsStateError,
    );
  });

  test('inversion is offered only for an invertible committed variant', () {
    final blocked = atCounter(invertible: false);
    expect(blocked.inversionAllowed, isFalse);
    expect(
      () => blocked.submitCounterBid(2, AuctionTarget.INVERT_WINNING_ACTION),
      throwsStateError,
    );

    final allowed = atCounter();
    expect(allowed.inversionAllowed, isTrue);
    allowed.submitCounterBid(2, AuctionTarget.INVERT_WINNING_ACTION);
    allowed.renounceFinalDefense();
    expect(allowed.inversionRetained, isTrue);
  });

  test('inversion preserves the original combat snapshot', () {
    final controller = atCounter();
    final snapshot = controller.localCommitment!.snapshot;
    controller.submitCounterBid(2, AuctionTarget.INVERT_WINNING_ACTION);
    controller.renounceFinalDefense();

    expect(
      identical(controller.finalActionCommitment!.snapshot, snapshot),
      isTrue,
    );
    expect(controller.finalActionCommitment!.snapshot.personalValue, 16);
  });

  test('corruption accepts only the proposer discard', () {
    final controller = atCorruption();

    expect(controller.corruptionAvailableCards.map((card) => card.cardId), [
      'local-card-7',
    ]);
    expect(
      () => controller.proposeCorruption(const [
        'local-card-2',
      ], CorruptionObjective.OWN_INITIAL_ACTION),
      throwsStateError,
    );
  });

  test('refused corruption leaves the proposed discard card untouched', () {
    final controller = atCorruption();
    controller.proposeCorruption(const [
      'local-card-7',
    ], CorruptionObjective.OWN_INITIAL_ACTION);
    controller.respondToCorruption(accepted: false);

    expect(controller.phase, LocalRoundPhase.roundComplete);
    expect(
      controller.partnerCards
          .singleWhere((card) => card.cardId == 'local-card-7')
          .zone,
      CardZone.DISCARD,
    );
  });

  test('completed corruption action exhausts the replayed discard', () {
    final controller = atCorruption();
    controller.proposeCorruption(const [
      'local-card-7',
    ], CorruptionObjective.OWN_INITIAL_ACTION);
    controller.respondToCorruption(accepted: true);
    controller.recordCurrentAction(ActionExecutionStatus.COMPLETED);
    controller.finishCorruptionActions();

    expect(
      controller.partnerCards
          .singleWhere((card) => card.cardId == 'local-card-7')
          .zone,
      CardZone.EXHAUSTED,
    );
    expect(
      controller.roundEvents.map((event) => event.type),
      contains(GameEventType.CARD_EXHAUSTED),
    );
  });

  test('skipped corruption action stays in discard', () {
    final controller = atCorruption();
    controller.proposeCorruption(const [
      'local-card-7',
    ], CorruptionObjective.OWN_INITIAL_ACTION);
    controller.respondToCorruption(accepted: true);
    controller.recordCurrentAction(ActionExecutionStatus.SKIPPED);
    controller.finishCorruptionActions();

    expect(
      controller.partnerCards
          .singleWhere((card) => card.cardId == 'local-card-7')
          .zone,
      CardZone.DISCARD,
    );
  });

  test('STOP is neutral, free and leaves the action in discard', () {
    final controller = atCorruption();
    controller.proposeCorruption(const [
      'local-card-7',
    ], CorruptionObjective.OWN_INITIAL_ACTION);
    controller.respondToCorruption(accepted: true);
    final before = controller.actionPoints;
    controller.consentStop();

    expect(controller.actionPoints, before);
    expect(controller.phase, LocalRoundPhase.roundComplete);
    expect(
      controller.partnerCards
          .singleWhere((card) => card.cardId == 'local-card-7')
          .zone,
      CardZone.DISCARD,
    );
    final stop = controller.roundEvents.singleWhere(
      (event) => event.type == GameEventType.CONSENT_STOP,
    );
    expect(stop.payload, isNot(contains('pa_cost')));
  });

  test('tie bypasses auction and can close the prototype round', () {
    final controller = createLocalGameFixture(localFaire: 11, partnerFaire: 11);
    controller.selectLocalCard(localCard, '$localCard.variant.1');
    controller.simulatePartnerChoice();
    controller.continueAfterDuel();

    expect(controller.phase, LocalRoundPhase.roundComplete);
    expect(
      controller.roundEvents.map((event) => event.type),
      isNot(contains(GameEventType.AUCTION_STARTED)),
    );
  });

  test('completed post-duel flow returns cleanly to next round', () {
    final controller = atCorruption()..skipCorruption();
    controller.continueToNextRound();

    expect(controller.phase, LocalRoundPhase.choosing);
    expect(controller.roundNumber, 2);
    expect(controller.screenData.hand, hasLength(4));
    expect(controller.postDuel, isNull);
  });

  testWidgets('auction UI rejects low bid then opens final defense', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = atCounter();
    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(data: controller.screenData, controller: controller),
      ),
    );

    await tester.ensureVisible(find.byKey(const Key('auction-amount')));
    await tester.enterText(find.byKey(const Key('auction-amount')), '0');
    await tester.tap(find.byKey(const Key('confirm-counter')));
    await tester.pump();
    expect(find.byKey(const Key('post-duel-error')), findsOneWidget);
    expect(controller.actionPoints[controller.partner.playerId], 100);

    await tester.enterText(find.byKey(const Key('auction-amount')), '2');
    await tester.tap(find.byKey(const Key('confirm-counter')));
    await tester.pump();
    expect(find.byKey(const Key('final-defense-panel')), findsOneWidget);
    expect(controller.actionPoints[controller.partner.playerId], 98);
    expect(tester.takeException(), isNull);
  });

  testWidgets('corruption UI accepts an offer and STOP remains neutral', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = atCorruption();
    final before = controller.actionPoints;
    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(data: controller.screenData, controller: controller),
      ),
    );

    final card = find.byKey(const Key('corruption-card-local-card-7'));
    await tester.ensureVisible(card);
    await tester.tap(card);
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('propose-corruption')));
    await tester.tap(find.byKey(const Key('propose-corruption')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('accept-corruption')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('consent-stop')));
    await tester.tap(find.byKey(const Key('consent-stop')));
    await tester.pump();

    expect(controller.phase, LocalRoundPhase.roundComplete);
    expect(controller.actionPoints, before);
    expect(find.byKey(const Key('round-complete-panel')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('privacy transition hides post-duel PA and actions', (
    tester,
  ) async {
    final controller = atCounter();
    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(
          data: controller.screenData,
          controller: controller,
          privacyTransition: true,
        ),
      ),
    );

    expect(find.text('Passe le téléphone à ton partenaire'), findsWidgets);
    expect(find.byKey(const Key('post-duel-pa')), findsNothing);
    expect(find.byKey(const Key('confirm-counter')), findsNothing);
    expect(find.text('90'), findsNothing);
    expect(find.text('100'), findsNothing);
  });
}
