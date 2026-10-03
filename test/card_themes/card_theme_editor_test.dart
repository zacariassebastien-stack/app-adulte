import 'dart:convert';
import 'dart:io';

import 'package:couple_cards/card_themes/card_illustration_editor_adapter.dart';
import 'package:couple_cards/card_themes/card_theme_editor_screen.dart';
import 'package:couple_cards/card_themes/card_theme_models.dart';
import 'package:couple_cards/card_themes/card_theme_repository.dart';
import 'package:couple_cards/card_themes/classic_theme.dart';
import 'package:couple_cards/card_themes/signature_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fixtures/catalog_fixture.dart';

void main() {
  testWidgets('editor loads classic preview and duplicates before editing', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final repository = SharedPreferencesCardThemeRepository(
      preferences: await SharedPreferences.getInstance(),
    );
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: CardThemeEditorScreen(
          repository: repository,
          initialCatalog: loadFixture(fixture()),
          initialBundles: [ClassicCardTheme.bundle],
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Card Theme Editor'), findsOneWidget);
    expect(find.byKey(const Key('editor-card-preview')), findsOneWidget);
    expect(find.text('Classic V1'), findsWidgets);
    expect(find.byKey(const Key('direction-preview-selector')), findsOneWidget);
    expect(find.text('1 PA'), findsOneWidget);
    expect(find.text('Recevoir : 20 PA'), findsOneWidget);

    await tester.tap(find.text('Recevoir'));
    await tester.pump();
    expect(find.text('20 PA'), findsOneWidget);
    expect(find.text('Faire : 1 PA'), findsOneWidget);

    await tester.tap(find.text('Mutuel'));
    await tester.pump();
    expect(find.text('8 PA'), findsOneWidget);
    expect(find.textContaining('Faire :'), findsNothing);
    expect(find.textContaining('Recevoir :'), findsNothing);

    await tester.tap(find.text('Dupliquer layout'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('layout dupliqué.'), findsOneWidget);
    expect((await repository.loadAll()).length, 3);
    expect(tester.takeException(), isNull);
  });

  test('classic asset theme is parsed once and cached', () async {
    AssetCardThemeLoader.clearCacheForTesting();
    const loader = AssetCardThemeLoader();
    final assets = _FileAssetBundle();

    final first = await loader.loadClassic(bundle: assets);
    final second = await loader.loadClassic(bundle: assets);

    expect(first.pack.id, 'classic_v1');
    expect(identical(first, second), isTrue);
    expect(AssetCardThemeLoader.parseCount, 1);
  });

  testWidgets('editor exposes the signature theme and premium controls', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final repository = SharedPreferencesCardThemeRepository(
      preferences: await SharedPreferences.getInstance(),
    );
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: CardThemeEditorScreen(
          repository: repository,
          initialCatalog: loadFixture(fixture()),
          initialBundles: [
            EnchaireSignatureTheme.bundle,
            ClassicCardTheme.bundle,
          ],
        ),
      ),
    );
    await tester.pump();

    expect(find.text('ENCHAIRE Signature V1'), findsWidgets);
    expect(
      tester.widget<IconButton>(find.byKey(const Key('theme-save'))).onPressed,
      isNotNull,
    );
    expect(find.textContaining('Épaisseur bordure externe'), findsOneWidget);
    await tester.drag(find.byType(ListView).last, const Offset(0, -500));
    await tester.pump();
    expect(find.textContaining('Épaisseur bordure interne'), findsOneWidget);
    await tester.drag(find.byType(ListView).last, const Offset(0, -600));
    await tester.pump();
    expect(find.textContaining('Rayon du glow'), findsOneWidget);
    expect(find.textContaining('Rayon des panneaux'), findsOneWidget);
    await tester.drag(find.byType(ListView).last, const Offset(0, -1200));
    await tester.pump();
    expect(find.text('Police du titre'), findsOneWidget);
    expect(find.byKey(const Key('card-inner-border')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('asset loader exposes signature first and keeps classic', () async {
    AssetCardThemeLoader.clearCacheForTesting();
    final themes = await const AssetCardThemeLoader().loadAll(
      bundle: _FileAssetBundle(),
    );

    expect(themes.map((theme) => theme.pack.id), [
      'enchaire_signature_v1',
      'classic_v1',
    ]);
    expect(themes.first.skin.innerBorderWidth, greaterThan(0));
    expect(themes.first.skin.panelBorderWidth, greaterThan(0));
  });

  testWidgets('editor associates and removes an illustration with fallback', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final repository = SharedPreferencesCardThemeRepository(
      preferences: await SharedPreferences.getInstance(),
    );
    final adapter = _FakeIllustrationAdapter();
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: CardThemeEditorScreen(
          repository: repository,
          initialCatalog: loadFixture(fixture()),
          initialBundles: [EnchaireSignatureTheme.bundle],
          illustrationAdapter: adapter,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('associate-illustration')));
    await tester.pumpAndSettle();
    expect(find.text('Remplacer l’illustration'), findsOneWidget);
    expect(find.byKey(const Key('illustration-fit')), findsOneWidget);
    expect(
      find.byKey(const Key('illustration-opacity-card.draw')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('remove-illustration')));
    await tester.pumpAndSettle();
    expect(adapter.removed, isTrue);
    expect(find.text('Associer une illustration'), findsOneWidget);
    expect(find.byKey(const Key('illustration-card.draw')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

final class _FileAssetBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final bytes = await File(key).readAsBytes();
    return ByteData.sublistView(bytes);
  }
}

final class _FakeIllustrationAdapter implements CardIllustrationEditorAdapter {
  bool removed = false;
  final MemoryImage provider = MemoryImage(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
      '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    ),
  );

  @override
  Future<String?> chooseAndImport({
    required ThemeBundle bundle,
    required String cardId,
  }) async => 'assets/card_themes/${bundle.pack.id}/illustrations/test.png';

  @override
  ImageProvider<Object>? previewProvider(IllustrationAsset asset) => provider;

  @override
  Future<void> remove(IllustrationAsset asset) async {
    removed = true;
  }
}
