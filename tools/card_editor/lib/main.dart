import 'package:couple_cards/app/asset_catalog.dart';
import 'package:couple_cards/card_themes/card_theme_editor_screen.dart';
import 'package:couple_cards/card_themes/card_theme_models.dart';
import 'package:couple_cards/card_themes/card_theme_repository.dart';
import 'package:couple_cards/card_themes/project_card_theme_repository.dart';
import 'package:couple_cards/domain/catalog/catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final repository = ProjectCardThemeRepository(
      projectRoot: ProjectCardThemeRepository.locateProjectRoot(
        arguments: arguments,
      ),
    );
    final values = await Future.wait<Object>([
      repository.loadAll(),
      loadAssetCatalog(assetPrefix: 'packages/couple_cards/'),
    ]);
    runApp(
      CardEditorApp(
        repository: repository,
        bundles: values[0] as List<ThemeBundle>,
        catalog: values[1] as Catalog,
      ),
    );
  } on Object catch (error) {
    runApp(CardEditorStartupError(error: error));
  }
}

class CardEditorApp extends StatelessWidget {
  const CardEditorApp({
    required this.repository,
    required this.bundles,
    required this.catalog,
    super.key,
  });

  final CardThemeRepository repository;
  final List<ThemeBundle> bundles;
  final Catalog catalog;

  @override
  Widget build(BuildContext context) => DefaultAssetBundle(
    bundle: PackageFallbackAssetBundle(rootBundle),
    child: MaterialApp(
      title: 'ENCHAIRE Card Editor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF73546F)),
        useMaterial3: true,
      ),
      home: CardThemeEditorScreen(
        repository: repository,
        initialCatalog: catalog,
        initialBundles: bundles,
      ),
    ),
  );
}

class CardEditorStartupError extends StatelessWidget {
  const CardEditorStartupError({required this.error, super.key});
  final Object error;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'ENCHAIRE Card Editor',
    home: Scaffold(
      appBar: AppBar(title: const Text('ENCHAIRE Card Editor')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Impossible d’ouvrir le projet ENCHAIRE.\n\n$error',
              key: const Key('card-editor-startup-error'),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    ),
  );
}

final class PackageFallbackAssetBundle extends CachingAssetBundle {
  PackageFallbackAssetBundle(this.delegate);
  final AssetBundle delegate;

  @override
  Future<ByteData> load(String key) async {
    try {
      return await delegate.load(key);
    } on Object {
      if (key.startsWith('packages/')) rethrow;
      return delegate.load('packages/couple_cards/$key');
    }
  }
}
