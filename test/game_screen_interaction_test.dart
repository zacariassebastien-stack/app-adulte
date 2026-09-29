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
    GameCardView? partnerCard,
  }) => MaterialApp(
    home: GameScreen(
      data: data(),
      privacyTransition: privacyTransition,
      temporarilyUnavailableCardIds: unavailable,
      onCardSelected: onCardSelected,
      prototypePartnerCard: partnerCard,
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

  Future<void> chooseCard(WidgetTester tester, int index) async {
    await openCard(tester, index);
    await tester.ensureVisible(find.byKey(const Key('choose-card-button')));
    await tester.tap(find.byKey(const Key('choose-card-button')));
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

  testWidgets('choosing a card reports it and enters waiting state', (
    tester,
  ) async {
    GameCardView? selected;
    await tester.pumpWidget(subject(onCardSelected: (card) => selected = card));
    await chooseCard(tester, 2);

    expect(selected?.cardId, 'card-2');
    expect(find.byKey(const Key('waiting-for-partner')), findsOneWidget);
    expect(find.byKey(const Key('card-detail-scroll')), findsNothing);
  });

  testWidgets('engaged choice cannot be changed', (tester) async {
    var selections = 0;
    await tester.pumpWidget(subject(onCardSelected: (_) => selections++));
    await chooseCard(tester, 0);

    expect(find.byKey(const Key('player-hand')), findsNothing);
    expect(find.byKey(const Key('hand-card-1')), findsNothing);
    await tester.tapAt(const Offset(40, 700));
    await tester.pump();
    expect(find.byKey(const Key('card-detail-scroll')), findsNothing);
    expect(selections, 1);
  });

  testWidgets('engaged card stays private before reveal', (tester) async {
    await tester.pumpWidget(subject());
    await chooseCard(tester, 0);

    expect(find.text('Titre complet 0'), findsNothing);
    expect(find.text('10/20'), findsNothing);
    expect(find.text('Carte partenaire'), findsNothing);
    expect(
      find.text('Carte choisie — En attente de ton partenaire'),
      findsOneWidget,
    );
  });

  testWidgets('simulated partner choice triggers reveal', (tester) async {
    await tester.pumpWidget(subject());
    await chooseCard(tester, 0);

    await tester.tap(find.byKey(const Key('simulate-partner-choice')));
    await tester.pump();

    expect(find.byKey(const Key('round-reveal')), findsOneWidget);
    expect(find.byKey(const Key('waiting-for-partner')), findsNothing);
  });

  testWidgets('both cards appear after reveal', (tester) async {
    await tester.pumpWidget(subject());
    await chooseCard(tester, 0);
    await tester.tap(find.byKey(const Key('simulate-partner-choice')));
    await tester.pump();

    expect(find.byKey(const Key('revealed-local-card')), findsOneWidget);
    expect(find.byKey(const Key('revealed-partner-card')), findsOneWidget);
    expect(find.text('Titre complet 0'), findsOneWidget);
    expect(find.text('Carte partenaire'), findsOneWidget);
  });

  testWidgets('reveal never exposes personal values', (tester) async {
    final partner = GameCardView(
      cardId: 'partner',
      category: 'RECEVOIR',
      chiliLevels: const [2],
      locked: false,
      titleKey: 'Choix partenaire',
      personalValue: 19,
    );
    await tester.pumpWidget(subject(partnerCard: partner));
    await chooseCard(tester, 0);
    await tester.tap(find.byKey(const Key('simulate-partner-choice')));
    await tester.pump();

    expect(find.text('10/20'), findsNothing);
    expect(find.text('19/20'), findsNothing);
    expect(find.text('Choix partenaire'), findsOneWidget);
  });

  testWidgets('finishing round restores initial choosing state', (
    tester,
  ) async {
    await tester.pumpWidget(subject());
    await chooseCard(tester, 0);
    await tester.tap(find.byKey(const Key('simulate-partner-choice')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('finish-round-button')));
    await tester.pump();

    expect(find.byKey(const Key('player-hand')), findsOneWidget);
    expect(find.byKey(const Key('round-reveal')), findsNothing);
    expect(find.byKey(const Key('waiting-for-partner')), findsNothing);
    expect(find.byKey(const Key('hand-card-0')), findsOneWidget);
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
    await tester.tap(find.byKey(const Key('choose-card-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('simulate-partner-choice')));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('round-reveal')), findsOneWidget);
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
