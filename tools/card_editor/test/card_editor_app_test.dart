import 'dart:io';

import 'package:couple_cards/app/asset_catalog.dart';
import 'package:couple_cards/card_themes/card_renderer.dart';
import 'package:couple_cards/card_themes/card_theme_models.dart';
import 'package:couple_cards/card_themes/project_card_theme_repository.dart';
import 'package:couple_cards/domain/catalog/catalog.dart';
import 'package:enchaire_card_editor/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('starts directly in the editor without a network dependency', (
    tester,
  ) async {
    late ProjectCardThemeRepository repository;
    late List<ThemeBundle> bundles;
    late Catalog catalog;
    await tester.runAsync(() async {
      final projectRoot = Directory.current.parent.parent;
      repository = ProjectCardThemeRepository(projectRoot: projectRoot);
      bundles = await repository.loadAll();
      catalog = await loadAssetCatalog(assetPrefix: 'packages/couple_cards/');
    });
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      CardEditorApp(repository: repository, bundles: bundles, catalog: catalog),
    );
    await tester.pump();

    expect(find.text('Card Theme Editor'), findsOneWidget);
    expect(find.byType(CardRenderer), findsOneWidget);
    expect(find.text('ENCHAIRE Signature V1'), findsWidgets);
    expect(find.byKey(const Key('card-inner-border')), findsOneWidget);
    expect(find.byKey(const Key('direction-preview-selector')), findsOneWidget);
    expect(find.text('8 PA'), findsOneWidget);
    expect(find.text('MUTUEL'), findsOneWidget);
    expect(find.textContaining('Recevoir :'), findsNothing);
    expect(find.textContaining('Supabase'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
