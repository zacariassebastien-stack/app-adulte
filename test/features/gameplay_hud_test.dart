import 'package:couple_cards/engines/deck/deck_cycle_state.dart';
import 'package:couple_cards/features/game/ui/card_hand_surface.dart';
import 'package:couple_cards/features/game/ui/gameplay_hud.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget hud({
    int pa = 127,
    CardHandStage stage = CardHandStage.resting,
    ValueChanged<HybridDeckOrientation>? onOrientation,
  }) => MaterialApp(
    home: Scaffold(
      body: GameplayHud(
        actionPoints: pa,
        status: 'À toi de jouer',
        roundNumber: 3,
        spice: 3,
        orientation: HybridDeckOrientation.faceToFace,
        stage: stage,
        onSettings: () {},
        onOrientationChanged: onOrientation ?? (_) {},
        discardVisible: true,
        onDiscard: () {},
        child: const SizedBox.expand(),
      ),
    ),
  );

  testWidgets('HUD exposes own PA only and clamps fill above 100', (
    tester,
  ) async {
    await tester.pumpWidget(hud());
    expect(find.text('127 PA'), findsNWidgets(2));
    expect(find.byKey(const Key('own-action-points-fill-100')), findsOneWidget);
    expect(find.textContaining('Partenaire'), findsNothing);
    expect(find.text('🌶️🌶️🌶️○'), findsOneWidget);
  });

  testWidgets('state 3 hides secondary HUD and keeps PA/settings/status', (
    tester,
  ) async {
    await tester.pumpWidget(hud(stage: CardHandStage.open));
    expect(find.byKey(const Key('own-action-points')), findsOneWidget);
    expect(find.byKey(const Key('game-status')), findsOneWidget);
    expect(
      find.byKey(const Key('open-private-profile-settings')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('game-round')), findsNothing);
    expect(find.byKey(const Key('active-spice')), findsOneWidget);
    expect(find.byKey(const Key('switch-hybrid-orientation')), findsNothing);
    expect(find.byKey(const Key('open-discard-gallery')), findsNothing);
  });

  for (final spice in [1, 2, 3, 4]) {
    for (final stage in CardHandStage.values) {
      testWidgets(
        'four graphic slots P$spice ${stage.name} reserve body space',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(320, 420));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          var tapped = false;
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: GameplayHud(
                  actionPoints: 100,
                  status: 'Résolution du tour',
                  roundNumber: 2,
                  spice: spice,
                  orientation: HybridDeckOrientation.faceToFace,
                  stage: stage,
                  onSettings: () {},
                  child: TextButton(
                    key: const Key('body-control'),
                    onPressed: () => tapped = true,
                    child: const Text('Action'),
                  ),
                ),
              ),
            ),
          );
          final indicator = find.byKey(const Key('active-spice'));
          expect(
            tester.widget<Text>(indicator).data,
            List.generate(4, (i) => i < spice ? '🌶️' : '○').join(),
          );
          expect(
            tester.getBottomLeft(indicator).dy,
            lessThanOrEqualTo(
              tester.getTopLeft(find.byKey(const Key('body-control'))).dy,
            ),
          );
          await tester.tap(find.byKey(const Key('body-control')));
          expect(tapped, isTrue);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('orientation changes only after card flip', (tester) async {
    HybridDeckOrientation? orientation;
    await tester.pumpWidget(hud(onOrientation: (value) => orientation = value));
    await tester.tap(find.byKey(const Key('switch-hybrid-orientation')));
    await tester.pump(const Duration(milliseconds: 150));
    expect(orientation, isNull);
    await tester.pumpAndSettle();
    expect(orientation, HybridDeckOrientation.distance);
  });
}
