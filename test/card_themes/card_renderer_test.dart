import 'package:couple_cards/card_themes/card_renderer.dart';
import 'package:couple_cards/card_themes/card_theme_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const definition = CardRenderDefinition(
  cardId: 'card.preview',
  title: 'Un titre de carte volontairement très long pour vérifier le rendu',
  subtitle: 'Accroche',
  action:
      'Une description détaillée qui peut occuper plusieurs lignes sans sortir de la carte.',
  direction: 'RECEVOIR',
  zones: ['DOS', 'COU'],
  spice: 5,
  personalPa: 12,
  details: 'Précisions supplémentaires',
);

void main() {
  Future<void> render(
    WidgetTester tester, {
    required Size size,
    CardVisualState state = CardVisualState.normal,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox.expand(
            child: CardRenderer(definition: definition, state: state),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('renders standard and long content without overflow', (
    tester,
  ) async {
    await render(tester, size: const Size(320, 480));

    expect(find.textContaining('titre de carte'), findsOneWidget);
    expect(find.textContaining('description détaillée'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('locked rest replaces PA and focused lock keeps PA visible', (
    tester,
  ) async {
    await render(
      tester,
      size: const Size(240, 360),
      state: CardVisualState.locked,
    );
    expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
    expect(find.text('12/20'), findsNothing);

    await render(
      tester,
      size: const Size(240, 360),
      state: CardVisualState.full,
    );
    expect(find.text('12/20'), findsOneWidget);
  });

  testWidgets('hidden state renders canonical back and hides private value', (
    tester,
  ) async {
    await render(
      tester,
      size: const Size(320, 480),
      state: CardVisualState.hidden,
    );

    expect(find.text('ENCHAIRE'), findsOneWidget);
    expect(find.text('12/20'), findsNothing);
    expect(find.textContaining('titre de carte'), findsNothing);
  });

  testWidgets('readonly state is explicit', (tester) async {
    await render(
      tester,
      size: const Size(320, 480),
      state: CardVisualState.readonly,
    );
    expect(find.text('LECTURE'), findsOneWidget);
  });

  for (final size in [
    const Size(180, 260),
    const Size(430, 700),
    const Size(800, 600),
  ]) {
    testWidgets('remains responsive at ${size.width}x${size.height}', (
      tester,
    ) async {
      await render(tester, size: size);
      expect(tester.takeException(), isNull);
    });
  }
}
