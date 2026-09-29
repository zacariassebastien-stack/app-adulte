import 'package:couple_cards/domain/game/game_screen_data.dart';
import 'package:couple_cards/features/game/game_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  GameCardView card(int index, {bool locked = false}) => GameCardView(
    cardId: 'card-$index',
    category: index.isEven ? 'FAIRE' : 'RECEVOIR',
    chiliLevels: [index + 1, index + 2],
    locked: locked,
    titleKey: 'Titre complet $index',
    descriptionKey: 'Description complète de la carte $index.',
    personalValue: 10 + index,
    instructionKeys: index == 0
        ? const ['Information complémentaire de test.']
        : const [],
  );

  GameScreenData data() => GameScreenData(
    playerId: 'a',
    chiliActive: 3,
    elapsedSeconds: 754,
    actionPoints: 76,
    privateDataHidden: false,
    hand: [card(0), card(1, locked: true), card(2), card(3)],
    discard: const [],
    centralActions: const [],
  );

  Widget subject({
    bool privacyTransition = false,
    Set<String> unavailable = const {},
    ValueChanged<GameCardView>? onCardSelected,
  }) => MaterialApp(
    home: GameScreen(
      data: data(),
      privacyTransition: privacyTransition,
      temporarilyUnavailableCardIds: unavailable,
      onCardSelected: onCardSelected,
    ),
  );

  Future<void> openCard(WidgetTester tester, int index) async {
    await tester.tap(find.byKey(Key('hand-card-$index')));
    await tester.pumpAndSettle();
  }

  Future<void> closeDetail(WidgetTester tester) async {
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
  }

  testWidgets('tapping a hand card opens its detail without leaving the game', (
    tester,
  ) async {
    await tester.pumpWidget(subject());
    await openCard(tester, 0);

    expect(find.byKey(const Key('card-detail-scroll')), findsOneWidget);
    expect(find.byType(GameScreen), findsOneWidget);
  });

  testWidgets('detail shows complete card information', (tester) async {
    await tester.pumpWidget(subject());
    await openCard(tester, 0);

    expect(find.text('FAIRE'), findsWidgets);
    expect(find.byKey(const Key('detail-illustration')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('detail-title'))).data,
      'Titre complet 0',
    );
    expect(find.text('Description complète de la carte 0.'), findsOneWidget);
    expect(find.text('🌶️ 1  🌶️ 2'), findsOneWidget);
    expect(find.text('10/20'), findsWidgets);
    expect(find.text('Déverrouillée'), findsWidgets);
    expect(find.text('En savoir plus'), findsOneWidget);
    expect(find.text('Information complémentaire de test.'), findsOneWidget);
  });

  testWidgets('card can be locked then unlocked from detail', (tester) async {
    await tester.pumpWidget(subject());
    await openCard(tester, 0);

    await tester.ensureVisible(find.byKey(const Key('lock-card-button')));
    await tester.tap(find.byKey(const Key('lock-card-button')));
    await tester.pump();
    expect(find.text('Déverrouiller la carte'), findsOneWidget);

    await tester.tap(find.byKey(const Key('lock-card-button')));
    await tester.pump();
    expect(find.text('Verrouiller la carte'), findsOneWidget);
    await closeDetail(tester);
    expect(find.byKey(const Key('card-lock-card-0')), findsNothing);
  });

  testWidgets('locking a card unlocks the previously locked card', (
    tester,
  ) async {
    await tester.pumpWidget(subject());
    expect(find.byKey(const Key('card-lock-card-1')), findsOneWidget);

    await openCard(tester, 0);
    await tester.ensureVisible(find.byKey(const Key('lock-card-button')));
    await tester.tap(find.byKey(const Key('lock-card-button')));
    await tester.pump();
    await closeDetail(tester);

    expect(find.byKey(const Key('card-lock-card-0')), findsOneWidget);
    expect(find.byKey(const Key('card-lock-card-1')), findsNothing);
  });

  testWidgets('choosing a card reports and highlights the selection', (
    tester,
  ) async {
    GameCardView? selected;
    await tester.pumpWidget(subject(onCardSelected: (card) => selected = card));
    await openCard(tester, 2);

    await tester.ensureVisible(find.byKey(const Key('choose-card-button')));
    await tester.tap(find.byKey(const Key('choose-card-button')));
    await tester.pumpAndSettle();

    expect(selected?.cardId, 'card-2');
    expect(find.byKey(const Key('card-selected-card-2')), findsOneWidget);
    expect(find.byKey(const Key('card-detail-scroll')), findsNothing);
  });

  testWidgets('unavailable card remains readable but cannot be selected', (
    tester,
  ) async {
    await tester.pumpWidget(subject(unavailable: const {'card-3'}));
    await openCard(tester, 3);

    expect(find.byKey(const Key('unavailable-explanation')), findsOneWidget);
    expect(
      find.text("Cette carte n'est pas disponible dans la situation actuelle."),
      findsOneWidget,
    );
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('choose-card-button')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('detail scrolls without overflow on a small phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(subject());
    await openCard(tester, 0);

    await tester.ensureVisible(find.byKey(const Key('choose-card-button')));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('choose-card-button')), findsOneWidget);
  });

  testWidgets('privacy transition closes detail and blocks private actions', (
    tester,
  ) async {
    late StateSetter setHostState;
    var privacy = false;
    GameCardView? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            setHostState = setState;
            return GameScreen(
              data: data(),
              privacyTransition: privacy,
              onCardSelected: (card) => selected = card,
            );
          },
        ),
      ),
    );
    await openCard(tester, 0);
    expect(find.byKey(const Key('card-detail-scroll')), findsOneWidget);

    setHostState(() => privacy = true);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('card-detail-scroll')), findsNothing);
    expect(find.byKey(const Key('privacy-placeholder')), findsOneWidget);
    expect(find.byKey(const Key('player-hand')), findsNothing);
    expect(find.byKey(const Key('lock-card-button')), findsNothing);
    expect(find.byKey(const Key('choose-card-button')), findsNothing);
    expect(find.text('10/20'), findsNothing);
    expect(selected, isNull);
  });
}
