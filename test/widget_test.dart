import 'package:couple_cards/app/app.dart';
import 'package:couple_cards/domain/game/game_screen_data.dart';
import 'package:couple_cards/features/game/game_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  GameCardView card(int index, {bool locked = false}) => GameCardView(
    cardId: 'card-$index',
    category: index.isEven ? 'FAIRE' : 'RECEVOIR',
    chiliLevels: [index % 3 + 1],
    locked: locked,
    titleKey: 'Titre $index',
    descriptionKey: 'Description courte $index',
    personalValue: 10 + index,
  );

  GameScreenData data() => GameScreenData(
    playerId: 'a',
    chiliActive: 3,
    elapsedSeconds: 754,
    actionPoints: 76,
    indicativeDurationMinutes: 30,
    privateDataHidden: false,
    hand: [card(0), card(1, locked: true), card(2), card(3)],
    discard: [card(4)],
    centralActions: [card(5)],
  );

  Widget subject({bool privacyTransition = false}) => MaterialApp(
    home: GameScreen(data: data(), privacyTransition: privacyTransition),
  );

  testWidgets('application renders the static game screen', (tester) async {
    await tester.pumpWidget(const CoupleCardsApp());
    expect(tester.takeException(), isNull);
    expect(find.byType(GameScreen), findsOneWidget);
  });

  testWidgets('four hand cards are visible', (tester) async {
    await tester.pumpWidget(subject());
    for (var index = 0; index < 4; index++) {
      expect(find.byKey(Key('hand-card-$index')), findsOneWidget);
    }
    expect(find.text('Ma main · 4/4'), findsOneWidget);
  });

  testWidgets('main game information is visible', (tester) async {
    await tester.pumpWidget(subject());
    expect(find.text('76'), findsOneWidget);
    expect(find.text('12:34'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('active-chili')),
        matching: find.text('🌶️ 3'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('settings-button')), findsOneWidget);
    expect(find.text('Défausse · 1 carte'), findsOneWidget);
    expect(find.text('Titre 5'), findsOneWidget);
  });

  testWidgets('a locked card displays its lock indicator', (tester) async {
    await tester.pumpWidget(subject());
    expect(find.byKey(const Key('card-lock-card-1')), findsOneWidget);
    expect(find.bySemanticsLabel('Carte verrouillée'), findsOneWidget);
  });

  testWidgets('privacy transition hides hand, PA and personal scores', (
    tester,
  ) async {
    await tester.pumpWidget(subject(privacyTransition: true));
    expect(find.byKey(const Key('privacy-placeholder')), findsOneWidget);
    expect(find.text('Passe le téléphone à ton partenaire'), findsOneWidget);
    expect(find.byKey(const Key('player-hand')), findsNothing);
    expect(find.text('76'), findsNothing);
    expect(find.byKey(const Key('personal-value-card-0')), findsNothing);
    expect(find.text('10/20'), findsNothing);
    expect(find.text('15/20'), findsNothing);
  });

  testWidgets('small Android screen has no overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(subject());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('discard-button')), findsOneWidget);
    expect(find.byKey(const Key('hand-card-3')), findsOneWidget);
  });
}
