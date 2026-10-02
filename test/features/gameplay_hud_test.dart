import 'package:couple_cards/engines/deck/session_deck_builder.dart';
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
    expect(find.text('🌶️🌶️🌶️'), findsOneWidget);
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
    expect(find.byKey(const Key('active-spice')), findsNothing);
    expect(find.byKey(const Key('switch-hybrid-orientation')), findsNothing);
    expect(find.byKey(const Key('open-discard-gallery')), findsNothing);
  });

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
