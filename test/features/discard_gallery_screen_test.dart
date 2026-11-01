import 'package:couple_cards/card_themes/card_renderer.dart';
import 'package:couple_cards/card_themes/card_theme_models.dart';
import 'package:couple_cards/features/game/ui/discard_gallery_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('appreciation keeps the exact discard item from grid and zoom', (tester) async {
    final item = DiscardGalleryItem(
      id: 'played-stage',
      definition: const CardRenderDefinition(cardId: '056', variantId: '056.stage.2',
        direction: 'RECEVOIR', title: 'Carte consultée'),
      playedAt: DateTime.utc(2026),
    );
    final selected = <DiscardGalleryItem>[];
    await tester.pumpWidget(MaterialApp(home: DiscardGalleryScreen(
      cards: [item], onRate: selected.add)));
    await tester.longPress(find.byKey(const Key('discard-card-played-stage')));
    expect(selected, [same(item)]);
    await tester.tap(find.byKey(const Key('discard-card-played-stage')));
    await tester.pump();
    await tester.longPress(find.byKey(const Key('discard-readonly-zoom')));
    expect(selected, [same(item), same(item)]);
  });
  testWidgets('gallery is three columns, newest first, and zoom is readonly', (
    tester,
  ) async {
    final old = DiscardGalleryItem(
      id: 'old',
      definition: const CardRenderDefinition(
        cardId: 'old',
        title: 'Ancienne',
        personalPa: 6,
      ),
      playedAt: DateTime.utc(2026),
    );
    final recent = DiscardGalleryItem(
      id: 'recent',
      definition: const CardRenderDefinition(
        cardId: 'recent',
        title: 'Récente',
        personalPa: 8,
      ),
      playedAt: DateTime.utc(2026, 1, 2),
    );
    await tester.pumpWidget(
      MaterialApp(home: DiscardGalleryScreen(cards: [old, recent])),
    );
    final grid = tester.widget<GridView>(find.byKey(const Key('discard-grid')));
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 3);
    expect(
      tester.getTopLeft(find.byKey(const Key('discard-card-recent'))).dy,
      lessThanOrEqualTo(
        tester.getTopLeft(find.byKey(const Key('discard-card-old'))).dy,
      ),
    );

    await tester.tap(find.byKey(const Key('discard-card-recent')));
    await tester.pump();
    final renderer = tester.widget<CardRenderer>(find.byType(CardRenderer));
    expect(renderer.state, CardVisualState.readonly);
    expect(renderer.definition.personalPa, isNull);
    await tester.tap(find.byKey(const Key('discard-readonly-zoom')));
    await tester.pump();
    expect(find.byKey(const Key('discard-grid')), findsOneWidget);
  });
}
