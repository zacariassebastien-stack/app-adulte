import 'package:couple_cards/domain/domain.dart';
import 'package:couple_cards/engines/engines.dart';
import 'package:couple_cards/features/game/game_screen.dart';
import 'package:couple_cards/features/game/local_game_controller.dart';
import 'package:couple_cards/features/game/local_game_fixture.dart';
import 'package:couple_cards/features/game/local_recovery_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  void reachBetweenRounds(LocalGameController controller) {
    final preferred = controller.screenData.hand
        .where((card) => card.cardId == 'local-card-1')
        .firstOrNull;
    final card = preferred ?? controller.screenData.hand.first;
    final choice = controller.choicesForLocalCard(card.cardId).first;
    controller.selectLocalCard(card.cardId, choice.variant.id);
    controller.simulatePartnerChoice();
    controller.continueAfterDuel();
    if (controller.phase == LocalRoundPhase.counterAuction) {
      controller.renounceCounterBid();
      controller.skipCorruption();
    }
    controller.continueToNextRound();
    expect(controller.phase, LocalRoundPhase.betweenRounds);
  }

  LocalGameController lowController({
    int localPa = 20,
    int partnerPa = 100,
    int localFaire = 16,
    int chiliActive = 2,
    Set<String> removedVariantIds = const {},
  }) {
    final controller = createLocalGameFixture(
      localPa: localPa,
      partnerPa: partnerPa,
      localFaire: localFaire,
      localRecevoir: 5,
      partnerRecevoir: 9,
      chiliActive: chiliActive,
      removedVariantIds: removedVariantIds,
    );
    reachBetweenRounds(controller);
    return controller;
  }

  LocalRecoveryOption option(
    LocalGameController controller,
    String cardId, {
    int chili = 1,
  }) => controller
      .recoveryOptionsFor(controller.local.playerId)
      .singleWhere(
        (item) => item.card.id == cardId && item.variant.chiliLevel == chili,
      );

  void select(LocalGameController controller, String cardId, {int chili = 1}) {
    final selected = option(controller, cardId, chili: chili);
    controller.startRecovery(controller.local.playerId);
    controller.selectRecoveryAction(selected.card.id, selected.variant.id);
  }

  void acceptAndFinish(
    LocalGameController controller,
    ActionExecutionStatus status,
  ) {
    controller.answerRecovery(RecoveryResponse.ACCEPT);
    controller.recordRecoveryAction(status);
    controller.finishRecoveryExecution();
  }

  test('Recovery cannot start during a normal round', () {
    final controller = createLocalGameFixture(localPa: 0);

    expect(
      () => controller.startRecovery(controller.local.playerId),
      throwsStateError,
    );
  });

  test('Recovery is unavailable above the configured threshold', () {
    final controller = lowController(localPa: 50);

    expect(controller.recoveryAvailableFor(controller.local.playerId), isFalse);
    expect(
      () => controller.startRecovery(controller.local.playerId),
      throwsStateError,
    );
  });

  test('Recovery is available at exactly 20 percent', () {
    final controller = lowController();

    expect(controller.actionPoints[controller.local.playerId], 20);
    expect(controller.recoveryAvailableFor(controller.local.playerId), isTrue);
  });

  test('only one Recovery is allowed before another normal duel', () {
    final controller = lowController();
    select(controller, 'local-card-4');
    controller.answerRecovery(RecoveryResponse.REFUSE);
    controller.finishBetweenRoundAction();

    expect(controller.recoveryAvailableFor(controller.local.playerId), isFalse);
    expect(
      () => controller.startRecovery(controller.local.playerId),
      throwsStateError,
    );
  });

  test('Recovery can select a catalog card outside the hand', () {
    final controller = lowController();
    final selected = option(controller, 'local-card-4');

    expect(selected.source, RecoverySource.CATALOG);
    expect(
      controller.screenData.hand.map((card) => card.cardId),
      isNot(contains(selected.card.id)),
    );
  });

  test('Recovery still enforces consent and eligibility', () {
    final controller = lowController(
      removedVariantIds: const {
        'local-card-4.variant.1',
        'local-card-4.variant.2',
      },
    );

    expect(
      controller
          .recoveryOptionsFor(controller.local.playerId)
          .where((item) => item.card.id == 'local-card-4'),
      isEmpty,
    );
  });

  test('Recovery chili exception does not unlock or change active chili', () {
    final controller = lowController(chiliActive: 1);
    final high = option(controller, 'local-card-4', chili: 2);

    expect(high.variant.chiliLevel, 2);
    select(controller, 'local-card-4', chili: 2);
    acceptAndFinish(controller, ActionExecutionStatus.SKIPPED);
    expect(controller.context.chiliActive, 1);
    expect(controller.context.chiliUnlocked, 1);
  });

  test('refusal is neutral and changes no PA or consent', () {
    final controller = lowController();
    final before = controller.actionPoints;
    final preferences = controller.local.profile.preferences;
    select(controller, 'local-card-4');
    controller.answerRecovery(RecoveryResponse.REFUSE);

    expect(controller.actionPoints, before);
    expect(controller.local.profile.preferences, same(preferences));
    expect(controller.recoveryController.lastGain, 0);
  });

  test('simple acceptance gains recovering player own role value', () {
    final controller = lowController(localFaire: 17);
    final partnerBefore = controller.actionPoints[controller.partner.playerId];
    select(controller, 'local-card-4');
    acceptAndFinish(controller, ActionExecutionStatus.COMPLETED);

    expect(controller.recoveryController.lastGain, 17);
    expect(controller.actionPoints[controller.local.playerId], 37);
    expect(controller.actionPoints[controller.partner.playerId], partnerBefore);
  });

  test('conditional acceptance executes one compatible discard condition', () {
    final controller = lowController();
    select(controller, 'local-card-4');
    controller.answerRecovery(
      RecoveryResponse.ACCEPT_WITH_ONE_DISCARD_CONDITION,
    );
    final condition = controller.recoveryController.conditionOptions.firstWhere(
      (item) => item.card.id == 'local-card-6',
    );
    controller.selectRecoveryCondition(condition.card.id, condition.variant.id);
    controller.recordRecoveryAction(ActionExecutionStatus.COMPLETED);
    controller.recordRecoveryAction(ActionExecutionStatus.COMPLETED);
    controller.finishRecoveryExecution();

    expect(controller.recoveryController.lastGain, 32);
    expect(
      controller.recoveryController.runtime[controller.local.playerId]!
          .singleWhere((card) => card.cardId == 'local-card-6')
          .zone,
      CardZone.EXHAUSTED,
    );
  });

  test('unperformed Recovery action grants no PA', () {
    final controller = lowController();
    select(controller, 'local-card-4');
    acceptAndFinish(controller, ActionExecutionStatus.SKIPPED);

    expect(controller.recoveryController.lastGain, 0);
    expect(controller.actionPoints[controller.local.playerId], 20);
  });

  test('Recovery lifecycle handles hand, discard and catalog sources', () {
    final fromHand = lowController();
    select(fromHand, 'local-card-0');
    acceptAndFinish(fromHand, ActionExecutionStatus.COMPLETED);
    fromHand.finishBetweenRoundAction();
    expect(
      fromHand.localCards
          .singleWhere((card) => card.cardId == 'local-card-0')
          .zone,
      CardZone.DISCARD,
    );
    expect(fromHand.screenData.hand, hasLength(4));

    final fromDiscard = lowController();
    select(fromDiscard, 'local-card-6');
    acceptAndFinish(fromDiscard, ActionExecutionStatus.COMPLETED);
    fromDiscard.finishBetweenRoundAction();
    expect(
      fromDiscard.localCards
          .singleWhere((card) => card.cardId == 'local-card-6')
          .zone,
      CardZone.EXHAUSTED,
    );

    final fromCatalog = lowController();
    select(fromCatalog, 'local-card-4');
    acceptAndFinish(fromCatalog, ActionExecutionStatus.COMPLETED);
    fromCatalog.finishBetweenRoundAction();
    expect(
      fromCatalog.localCards.where((card) => card.cardId == 'local-card-4'),
      isEmpty,
    );
  });

  test('successive Recoveries preserve the first player refill', () {
    final controller = lowController(partnerPa: 20);
    final localOption = controller
        .recoveryOptionsFor(controller.local.playerId)
        .firstWhere((item) => item.source == RecoverySource.HAND);
    controller.startRecovery(controller.local.playerId);
    controller.selectRecoveryAction(
      localOption.card.id,
      localOption.variant.id,
    );
    acceptAndFinish(controller, ActionExecutionStatus.COMPLETED);
    controller.finishBetweenRoundAction();
    final localHandAfterRefill = controller.screenData.hand
        .map((card) => card.cardId)
        .toSet();
    expect(localHandAfterRefill, hasLength(4));

    final partnerOption = controller
        .recoveryOptionsFor(controller.partner.playerId)
        .firstWhere((item) => item.source == RecoverySource.HAND);
    controller.startRecovery(controller.partner.playerId);
    controller.selectRecoveryAction(
      partnerOption.card.id,
      partnerOption.variant.id,
    );
    controller.answerRecovery(RecoveryResponse.ACCEPT);
    controller.recordRecoveryAction(ActionExecutionStatus.COMPLETED);
    controller.finishRecoveryExecution();
    controller.finishBetweenRoundAction();

    expect(
      controller.screenData.hand.map((card) => card.cardId).toSet(),
      localHandAfterRefill,
    );
    expect(
      controller.partnerCards.where((card) => card.zone == CardZone.HAND),
      hasLength(4),
    );
  });

  test('STOP is free, neutral and grants no gain for stopped action', () {
    final controller = lowController();
    select(controller, 'local-card-4');
    controller.answerRecovery(RecoveryResponse.ACCEPT);
    final before = controller.actionPoints;
    controller.stopRecovery();

    expect(controller.actionPoints, before);
    expect(controller.recoveryController.lastGain, 0);
    final stop = controller.recoveryController.events.singleWhere(
      (event) => event.type == GameEventType.CONSENT_STOP,
    );
    expect(stop.payload, isNot(contains('pa_cost')));
  });

  test('a completed normal duel reopens the Recovery gate', () {
    final controller = lowController();
    select(controller, 'local-card-4');
    controller.answerRecovery(RecoveryResponse.REFUSE);
    controller.finishBetweenRoundAction();
    expect(controller.recoveryAvailableFor(controller.local.playerId), isFalse);
    controller.startNextRound();

    reachBetweenRounds(controller);
    expect(controller.recoveryAvailableFor(controller.local.playerId), isTrue);
  });

  test(
    'mutual extension applies the exact same amount after two approvals',
    () {
      final controller = lowController(partnerPa: 20);
      final before = controller.actionPoints;
      controller.startMutualExtension(7);
      controller.confirmExtensionFirst();
      expect(controller.actionPoints, before);
      controller.showExtensionToSecondPlayer();
      expect(controller.actionPoints, before);
      controller.answerExtensionSecond(accepted: true);

      expect(
        controller.actionPoints[controller.local.playerId],
        before[controller.local.playerId]! + 7,
      );
      expect(
        controller.actionPoints[controller.partner.playerId],
        before[controller.partner.playerId]! + 7,
      );
      expect(
        controller.recoveryController.events.map((event) => event.type),
        contains(GameEventType.MUTUAL_PA_EXTENSION),
      );
    },
  );

  test('refused mutual extension changes no PA and emits no action event', () {
    final controller = lowController(partnerPa: 20);
    final before = controller.actionPoints;
    controller.startMutualExtension(8);
    controller.confirmExtensionFirst();
    controller.showExtensionToSecondPlayer();
    controller.answerExtensionSecond(accepted: false);

    expect(controller.actionPoints, before);
    expect(
      controller.recoveryController.events.map((event) => event.type),
      isNot(contains(GameEventType.MUTUAL_PA_EXTENSION)),
    );
    expect(
      controller.recoveryController.events.map((event) => event.type),
      isNot(contains(GameEventType.ACTION_COMPLETED)),
    );
  });

  test('mutual extension can be used again while both players remain low', () {
    final controller = lowController(localPa: 0, partnerPa: 0);
    for (var index = 0; index < 2; index++) {
      controller.startMutualExtension(5);
      controller.confirmExtensionFirst();
      controller.showExtensionToSecondPlayer();
      controller.answerExtensionSecond(accepted: true);
      controller.finishBetweenRoundAction();
    }

    expect(controller.actionPoints[controller.local.playerId], 10);
    expect(controller.actionPoints[controller.partner.playerId], 10);
    expect(
      controller.recoveryController.events.where(
        (event) => event.type == GameEventType.MUTUAL_PA_EXTENSION,
      ),
      hasLength(2),
    );
  });

  testWidgets('between-round UI completes a simple Recovery', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = lowController();
    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(data: controller.screenData, controller: controller),
      ),
    );

    expect(find.text('PA faibles — Recovery disponible'), findsOneWidget);
    await tester.tap(
      find.byKey(Key('start-recovery-${controller.local.playerId}')),
    );
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const Key('propose-recovery-action')),
    );
    await tester.tap(find.byKey(const Key('propose-recovery-action')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('accept-recovery')));
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const Key('complete-recovery-action')),
    );
    await tester.tap(find.byKey(const Key('complete-recovery-action')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('finish-recovery-sequence')));
    await tester.pump();

    expect(find.textContaining('Recovery terminé · +'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mutual extension hides PA during phone transition', (
    tester,
  ) async {
    final controller = lowController(partnerPa: 20);
    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(data: controller.screenData, controller: controller),
      ),
    );

    await tester.ensureVisible(find.byKey(const Key('start-mutual-extension')));
    await tester.tap(find.byKey(const Key('start-mutual-extension')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('confirm-extension-first')));
    await tester.pump();

    expect(find.text('Passe le téléphone à ton partenaire'), findsWidgets);
    expect(find.byKey(const Key('between-round-pa')), findsNothing);
    expect(find.text('20'), findsNothing);
    expect(find.text('16'), findsNothing);
    expect(find.byKey(const Key('confirm-extension-second')), findsNothing);

    await tester.tap(find.byKey(const Key('show-extension-second')));
    await tester.pump();
    expect(find.byKey(const Key('confirm-extension-second')), findsOneWidget);
  });
}
