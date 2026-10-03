import 'dart:convert';

import 'package:couple_cards/card_themes/card_renderer.dart';
import 'package:couple_cards/card_themes/card_theme_models.dart';
import 'package:couple_cards/card_themes/signature_theme.dart';
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
  oppositePa: 8,
  oppositeDirection: 'Faire',
  details: 'Précisions supplémentaires',
);

void main() {
  Future<void> render(
    WidgetTester tester, {
    required Size size,
    CardVisualState state = CardVisualState.normal,
    ThemeBundle? bundle,
    ImageProvider<Object>? Function(IllustrationAsset asset)?
    illustrationProvider,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox.expand(
            child: CardRenderer(
              definition: definition,
              state: state,
              bundle: bundle,
              playerName: 'SEB',
              illustrationProvider: illustrationProvider,
            ),
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
    expect(find.text('12 PA'), findsNothing);

    await render(
      tester,
      size: const Size(240, 360),
      state: CardVisualState.full,
    );
    expect(find.text('12 PA'), findsOneWidget);
    expect(find.text('Faire : 8 PA'), findsOneWidget);
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
    expect(find.text('12 PA'), findsNothing);
    expect(find.textContaining('titre de carte'), findsNothing);
  });

  testWidgets('compact state prioritizes active PA over opposite PA', (
    tester,
  ) async {
    await render(tester, size: const Size(180, 260));
    expect(find.text('12 PA'), findsOneWidget);
    expect(find.text('Faire : 8 PA'), findsNothing);
  });

  testWidgets('mutual card displays one PA value', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 320,
          height: 480,
          child: CardRenderer(
            state: CardVisualState.full,
            definition: CardRenderDefinition(
              cardId: 'mutual',
              title: 'Action mutuelle',
              direction: 'MUTUEL',
              personalPa: 8,
            ),
          ),
        ),
      ),
    );
    expect(find.text('8 PA'), findsOneWidget);
    expect(find.byKey(const Key('opposite-value-mutual')), findsNothing);
  });

  testWidgets('signature front renders texture, double frame and panels', (
    tester,
  ) async {
    await render(
      tester,
      size: const Size(330, 480),
      state: CardVisualState.full,
      bundle: EnchaireSignatureTheme.bundle,
    );

    expect(find.byKey(const Key('card-outer-frame')), findsOneWidget);
    expect(find.byKey(const Key('card-inner-border')), findsOneWidget);
    expect(find.byKey(const Key('card-texture')), findsOneWidget);
    expect(find.byKey(const Key('card-panel-pa')), findsOneWidget);
    expect(find.text('VALEUR PERSONNELLE'), findsOneWidget);
    expect(find.text('12 PA'), findsOneWidget);
    expect(find.text('Faire : 8 PA'), findsOneWidget);
    expect(find.text('ACTION'), findsOneWidget);
    expect(find.text('PRÉCISIONS'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('signature back stays sparse and uses canonical identity', (
    tester,
  ) async {
    await render(
      tester,
      size: const Size(330, 480),
      state: CardVisualState.hidden,
      bundle: EnchaireSignatureTheme.bundle,
    );

    expect(find.text('ENCHAIRE'), findsOneWidget);
    expect(find.text('En chair et en cartes.'), findsOneWidget);
    expect(find.text('SEB'), findsOneWidget);
    expect(find.byKey(const Key('card-ornament_top')), findsOneWidget);
    expect(find.byKey(const Key('card-ornament_bottom')), findsOneWidget);
    expect(find.text('12 PA'), findsNothing);
  });

  testWidgets(
    'signature long content and missing illustration do not overflow',
    (tester) async {
      await render(
        tester,
        size: const Size(280, 420),
        state: CardVisualState.full,
        bundle: EnchaireSignatureTheme.bundle,
      );

      expect(
        find.byKey(const Key('illustration-card.preview')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'illustration stays behind the frame and honors opacity and fit',
    (tester) async {
      final illustration = IllustrationAsset(
        illustrationId: 'preview',
        cardId: definition.cardId,
        styleId: 'signature',
        assetPath: 'assets/preview.png',
        fit: IllustrationFit.contain,
        opacity: .35,
      );
      final source = EnchaireSignatureTheme.bundle;
      final bundle = ThemeBundle(
        pack: source.pack,
        layout: source.layout,
        skin: source.skin,
        illustrations: [illustration],
      );
      final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
        '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      );

      await render(
        tester,
        size: const Size(330, 480),
        state: CardVisualState.full,
        bundle: bundle,
        illustrationProvider: (_) => MemoryImage(bytes),
      );

      final opacity = tester.widget<Opacity>(
        find.byKey(const Key('illustration-opacity-card.preview')),
      );
      final image = tester.widget<Image>(
        find.byKey(const Key('illustration-card.preview')),
      );
      expect(opacity.opacity, .35);
      expect(image.fit, BoxFit.contain);

      final stack = tester.widget<Stack>(find.byType(Stack).first);
      final illustrationIndex = stack.children.indexWhere(
        (child) => child.key == const Key('card-block-illustration'),
      );
      final borderIndex = stack.children.indexWhere((child) {
        if (child is! Positioned || child.child is! Padding) return false;
        final padding = child.child as Padding;
        if (padding.child is! IgnorePointer) return false;
        final ignored = padding.child as IgnorePointer;
        return ignored.child?.key == const Key('card-inner-border');
      });
      final titleIndex = stack.children.indexWhere(
        (child) => child.key == const Key('card-block-title'),
      );
      expect(illustrationIndex, greaterThanOrEqualTo(0));
      expect(borderIndex, greaterThan(illustrationIndex));
      expect(titleIndex, greaterThan(borderIndex));
      expect(tester.takeException(), isNull);
    },
  );

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
