import 'dart:io';

import 'package:couple_cards/card_themes/card_theme_editor_screen.dart';
import 'package:couple_cards/card_themes/card_theme_repository.dart';
import 'package:couple_cards/card_themes/classic_theme.dart';
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
    expect((await repository.loadAll()).length, 2);
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
}

final class _FileAssetBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final bytes = await File(key).readAsBytes();
    return ByteData.sublistView(bytes);
  }
}
