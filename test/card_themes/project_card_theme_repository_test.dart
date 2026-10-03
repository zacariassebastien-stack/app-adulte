import 'dart:io';

import 'package:couple_cards/card_themes/card_theme_models.dart';
import 'package:couple_cards/card_themes/project_card_theme_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('enchaire-card-editor-');
    for (final id in ['classic_v1', 'enchaire_signature_v1']) {
      final target = Directory('${root.path}/assets/card_themes/$id');
      await target.create(recursive: true);
      for (final name in [
        'theme.json',
        'layout.json',
        'skin.json',
        'illustrations.json',
      ]) {
        await File('assets/card_themes/$id/$name').copy('${target.path}/$name');
      }
    }
    await File('${root.path}/pubspec.yaml').writeAsString('''
name: fixture
flutter:
  assets:
    - assets/card_themes/index.json
    - assets/card_themes/classic_v1/
    - assets/card_themes/enchaire_signature_v1/
''');
    await File(
      '${root.path}/assets/card_themes/index.json',
    ).writeAsString(await File('assets/card_themes/index.json').readAsString());
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test(
    'detects the project root from a nested Windows tool directory',
    () async {
      final nested = Directory('${root.path}/tools/card_editor/build/Release');
      await nested.create(recursive: true);
      expect(
        ProjectCardThemeRepository.locateProjectRoot(
          startDirectory: nested,
        ).path,
        root.absolute.path,
      );
    },
  );

  test(
    'saves and reloads layout, skin and theme files in the project',
    () async {
      final repository = ProjectCardThemeRepository(projectRoot: root);
      final classic = (await repository.loadAll()).singleWhere(
        (theme) => theme.pack.id == 'classic_v1',
      );
      final layout = classic.layout.duplicate(
        id: 'studio_layout',
        name: 'Studio',
      );
      final skin = classic.skin.duplicate(id: 'studio_skin', name: 'Studio');
      final bundle = ThemeBundle(
        pack: CardThemePack(
          id: 'studio_v1',
          name: 'Studio V1',
          version: 1,
          layoutId: layout.id,
          skinId: skin.id,
        ),
        layout: layout,
        skin: skin,
        illustrations: classic.illustrations,
      );

      await repository.save(bundle);
      final reloaded = (await repository.loadAll()).singleWhere(
        (theme) => theme.pack.id == 'studio_v1',
      );
      expect(reloaded.layout.name, 'Studio');
      expect(reloaded.skin.name, 'Studio');
      for (final name in [
        'theme.json',
        'layout.json',
        'skin.json',
        'illustrations.json',
      ]) {
        expect(
          File('${root.path}/assets/card_themes/studio_v1/$name').existsSync(),
          isTrue,
        );
      }
      expect(
        await File('${root.path}/assets/card_themes/index.json').readAsString(),
        contains('studio_v1'),
      );
      expect(
        await File('${root.path}/pubspec.yaml').readAsString(),
        contains('- assets/card_themes/studio_v1/'),
      );

      await repository.delete('studio_v1');
      expect(
        (await repository.loadAll()).map((theme) => theme.pack.id).toSet(),
        {'classic_v1', 'enchaire_signature_v1'},
      );
      expect(
        await File('${root.path}/pubspec.yaml').readAsString(),
        isNot(contains('- assets/card_themes/studio_v1/')),
      );
    },
  );

  test(
    'signature system theme can be edited and saved by Windows tool',
    () async {
      final repository = ProjectCardThemeRepository(projectRoot: root);
      final signature = (await repository.loadAll()).singleWhere(
        (theme) => theme.pack.id == 'enchaire_signature_v1',
      );
      final changed = ThemeBundle(
        pack: signature.pack,
        layout: signature.layout,
        skin: signature.skin.copyWith(glowOpacity: .2),
        illustrations: signature.illustrations,
      );

      await repository.save(changed);
      final reloaded = (await repository.loadAll()).singleWhere(
        (theme) => theme.pack.id == 'enchaire_signature_v1',
      );
      expect(reloaded.skin.glowOpacity, .2);
    },
  );

  test('imports, saves, reloads and removes a card illustration', () async {
    final repository = ProjectCardThemeRepository(projectRoot: root);
    final signature = (await repository.loadAll()).singleWhere(
      (theme) => theme.pack.id == 'enchaire_signature_v1',
    );
    final source = File('${root.path}/selected image.png');
    await source.writeAsBytes([137, 80, 78, 71]);

    final assetPath = await repository.importIllustration(
      packId: signature.pack.id,
      cardId: 'card.hug',
      sourcePath: source.path,
    );
    final asset = IllustrationAsset(
      illustrationId: 'enchaire_signature_v1.card.hug.illustration',
      cardId: 'card.hug',
      styleId: 'default',
      assetPath: assetPath,
      focusX: .2,
      focusY: .8,
      fit: IllustrationFit.contain,
      opacity: .45,
      preserveAspectRatio: false,
    );
    await repository.save(
      ThemeBundle(
        pack: signature.pack,
        layout: signature.layout,
        skin: signature.skin,
        illustrations: [asset],
      ),
    );

    final reloaded = (await repository.loadAll()).singleWhere(
      (theme) => theme.pack.id == signature.pack.id,
    );
    final restored = reloaded.illustrationFor('card.hug', 'default')!;
    expect(restored.assetPath, assetPath);
    expect(restored.focusX, .2);
    expect(restored.focusY, .8);
    expect(restored.fit, IllustrationFit.contain);
    expect(restored.opacity, .45);
    expect(restored.preserveAspectRatio, isFalse);
    expect(repository.illustrationFile(restored).existsSync(), isTrue);

    await repository.removeIllustrationFile(restored);
    expect(repository.illustrationFile(restored).existsSync(), isFalse);
  });
}
