import 'dart:io';

import 'package:couple_cards/card_themes/card_theme_models.dart';
import 'package:couple_cards/card_themes/project_card_theme_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('enchaire-card-editor-');
    final target = Directory('${root.path}/assets/card_themes/classic_v1');
    await target.create(recursive: true);
    await File('${root.path}/pubspec.yaml').writeAsString('''
name: fixture
flutter:
  assets:
    - assets/card_themes/index.json
    - assets/card_themes/classic_v1/
''');
    await File(
      '${root.path}/assets/card_themes/index.json',
    ).writeAsString(await File('assets/card_themes/index.json').readAsString());
    for (final name in [
      'theme.json',
      'layout.json',
      'skin.json',
      'illustrations.json',
    ]) {
      await File(
        'assets/card_themes/classic_v1/$name',
      ).copy('${target.path}/$name');
    }
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
      final classic = (await repository.loadAll()).single;
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
      expect((await repository.loadAll()).map((theme) => theme.pack.id), [
        'classic_v1',
      ]);
      expect(
        await File('${root.path}/pubspec.yaml').readAsString(),
        isNot(contains('- assets/card_themes/studio_v1/')),
      );
    },
  );
}
