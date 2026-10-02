import 'package:couple_cards/card_themes/card_renderer.dart';
import 'package:couple_cards/card_themes/card_theme_models.dart';
import 'package:couple_cards/features/game/ui/card_hand_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final cards = List.generate(
    4,
    (index) => CardHandItem(
      id: 'card-$index',
      definition: CardRenderDefinition(
        cardId: 'card-$index',
        title: 'Carte $index',
        spice: index + 1,
        personalPa: index + 5,
      ),
    ),
  );

  Future<void> pumpHand(
    WidgetTester tester, {
    List<CardHandItem>? items,
    CardHandItem? committed,
    bool canCancel = false,
    bool animations = true,
    ValueChanged<CardHandItem>? onPlay,
    ValueChanged<CardHandItem>? onLock,
    VoidCallback? onCancel,
    Size size = const Size(800, 800),
  }) async {
    await tester.binding.setSurfaceSize(size);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox.expand(
            child: CardHandSurface(
              cards: items ?? cards,
              committedCard: committed,
              canCancelCommitted: canCancel,
              animationsEnabled: animations,
              onPlay: onPlay,
              onLockChanged: onLock,
              onCancelCommitted: onCancel,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('four cards form a fan and taps move through states 1, 2, 3', (
    tester,
  ) async {
    await pumpHand(tester);
    for (var index = 0; index < 4; index++) {
      expect(find.byKey(Key('hand-card-card-$index')), findsOneWidget);
    }

    await tester.tapAt(const Offset(50, 650));
    await tester.pump();
    expect(
      tester.widget<CardRenderer>(find.byType(CardRenderer).first).state,
      CardVisualState.focused,
    );

    await tester.tapAt(const Offset(50, 650));
    await tester.pump();
    expect(
      tester.widget<CardRenderer>(find.byType(CardRenderer).first).state,
      CardVisualState.full,
    );
  });

  testWidgets('another card receives focus directly', (tester) async {
    await pumpHand(tester);
    await tester.tapAt(const Offset(50, 650));
    await tester.pump();
    await tester.tapAt(const Offset(750, 650));
    await tester.pump();
    final renderers = tester.widgetList<CardRenderer>(
      find.byType(CardRenderer),
    );
    expect(renderers.last.state, CardVisualState.focused);
    expect(renderers.first.state, CardVisualState.normal);
  });

  testWidgets('drag tracks focus without also opening the card', (
    tester,
  ) async {
    await pumpHand(tester);
    final gesture = await tester.startGesture(const Offset(50, 650));
    await gesture.moveTo(const Offset(350, 650));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(
      tester
          .widgetList<CardRenderer>(find.byType(CardRenderer))
          .where((card) => card.state == CardVisualState.focused),
      hasLength(1),
    );
    expect(
      tester
          .widgetList<CardRenderer>(find.byType(CardRenderer))
          .where((card) => card.state == CardVisualState.full),
      isEmpty,
    );
  });

  testWidgets('leaving the hand returns to state 1', (tester) async {
    await pumpHand(tester);
    final gesture = await tester.startGesture(const Offset(50, 650));
    await gesture.moveTo(const Offset(350, 650));
    await gesture.moveTo(const Offset(350, 100));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<CardRenderer>(find.byType(CardRenderer))
          .every((card) => card.state == CardVisualState.normal),
      isTrue,
    );
  });

  testWidgets('up swipe plays and long press toggles only focused card', (
    tester,
  ) async {
    CardHandItem? played;
    CardHandItem? locked;
    await pumpHand(
      tester,
      onPlay: (card) => played = card,
      onLock: (card) => locked = card,
    );
    await tester.tapAt(const Offset(50, 650));
    await tester.pumpAndSettle();
    await tester.longPress(find.byKey(const Key('card-hand-surface')));
    expect(locked?.id, 'card-0');

    final gesture = await tester.startGesture(const Offset(400, 480));
    await gesture.moveTo(const Offset(400, 250));
    await gesture.up();
    expect(played?.id, 'card-0');
  });

  testWidgets('locked play displays large lock and never validates', (
    tester,
  ) async {
    var played = false;
    final locked = [cards.first.copyWithLocked(), ...cards.skip(1)];
    await pumpHand(tester, items: locked, onPlay: (_) => played = true);
    await tester.tapAt(const Offset(50, 650));
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(const Offset(400, 480));
    await gesture.moveTo(const Offset(400, 250));
    await gesture.up();
    await tester.pump();
    expect(find.byKey(const Key('blocked-card-lock')), findsOneWidget);
    expect(played, isFalse);
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const Key('blocked-card-lock')), findsNothing);
  });

  testWidgets('committed card flips and cancels from either face', (
    tester,
  ) async {
    var cancellations = 0;
    await pumpHand(
      tester,
      committed: cards.first,
      canCancel: true,
      onCancel: () => cancellations++,
    );
    expect(
      tester.widget<CardRenderer>(find.byType(CardRenderer)).state,
      CardVisualState.waiting,
    );
    await tester.tap(find.byKey(const Key('committed-card')));
    await tester.pump();
    expect(
      tester.widget<CardRenderer>(find.byType(CardRenderer)).state,
      CardVisualState.hidden,
    );
    await tester.drag(
      find.byKey(const Key('committed-card')),
      const Offset(0, 250),
    );
    expect(cancellations, 1);
  });

  testWidgets('disabled animations use zero-duration hand transitions', (
    tester,
  ) async {
    await pumpHand(tester, animations: false);
    final positioned = tester.widget<AnimatedPositioned>(
      find.byType(AnimatedPositioned).first,
    );
    expect(positioned.duration, Duration.zero);
    final rotation = tester.widget<AnimatedRotation>(
      find.byType(AnimatedRotation).first,
    );
    expect(rotation.duration, Duration.zero);
  });

  testWidgets('enabled animations keep hand transitions', (tester) async {
    await pumpHand(tester);
    expect(
      tester
          .widget<AnimatedPositioned>(find.byType(AnimatedPositioned).first)
          .duration,
      isNot(Duration.zero),
    );
  });

  testWidgets('locked rest replaces PA while focus shows PA and small lock', (
    tester,
  ) async {
    final locked = [cards.first.copyWithLocked(), ...cards.skip(1)];
    await pumpHand(tester, items: locked);
    expect(find.byKey(const Key('personal-value-card-0')), findsNothing);
    await tester.tapAt(const Offset(50, 650));
    await tester.pump();
    expect(find.byKey(const Key('personal-value-card-0')), findsOneWidget);
    expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
  });

  for (final size in [
    const Size(320, 568),
    const Size(400, 800),
    const Size(600, 960),
  ]) {
    testWidgets('fan and full card fit ${size.width}x${size.height}', (
      tester,
    ) async {
      await pumpHand(tester, size: size);
      await tester.tapAt(Offset(size.width / 8, size.height - 30));
      await tester.pump();
      await tester.tapAt(Offset(size.width / 8, size.height - 30));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final renderer = tester.widget<CardRenderer>(
        find.byType(CardRenderer).first,
      );
      expect(renderer.state, CardVisualState.full);
    });
  }
}

extension on CardHandItem {
  CardHandItem copyWithLocked() => CardHandItem(
    id: id,
    definition: definition,
    locked: true,
    available: available,
  );
}
