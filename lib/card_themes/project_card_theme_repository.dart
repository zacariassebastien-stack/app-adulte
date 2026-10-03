import 'dart:convert';
import 'dart:io';

import 'card_theme_models.dart';
import 'card_theme_repository.dart';
import 'card_theme_validator.dart';

/// Stores editor output in the repository so the mobile build consumes it as
/// an ordinary bundled theme on its next build.
final class ProjectCardThemeRepository implements CardThemeRepository {
  ProjectCardThemeRepository({required this.projectRoot});

  final Directory projectRoot;

  Directory get themesDirectory => Directory(
    '${projectRoot.path}${Platform.pathSeparator}assets'
    '${Platform.pathSeparator}card_themes',
  );

  File get indexFile =>
      File('${themesDirectory.path}${Platform.pathSeparator}index.json');

  /// Copies an editor-selected image into the theme asset directory and
  /// returns the stable path that mobile builds bundle on their next build.
  Future<String> importIllustration({
    required String packId,
    required String cardId,
    required String sourcePath,
  }) async {
    _validateId(packId);
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw FileSystemException('Illustration introuvable', sourcePath);
    }
    final extension = source.uri.pathSegments.last
        .split('.')
        .last
        .toLowerCase();
    if (!const {'png', 'jpg', 'jpeg', 'webp'}.contains(extension)) {
      throw const FormatException(
        'Format non pris en charge. Utilisez PNG, JPG, JPEG ou WebP.',
      );
    }
    final slug = cardId
        .replaceFirst(RegExp(r'^card\.'), '')
        .replaceAll(RegExp('[^a-zA-Z0-9_-]+'), '_')
        .toLowerCase();
    final relativePath =
        'assets/card_themes/$packId/illustrations/$slug.$extension';
    final target = File(
      relativePath
          .replaceAll('/', Platform.pathSeparator)
          .replaceFirst(
            'assets',
            '${projectRoot.path}${Platform.pathSeparator}assets',
          ),
    );
    await target.parent.create(recursive: true);
    if (source.absolute.path != target.absolute.path) {
      await source.copy(target.path);
    }
    return relativePath;
  }

  File illustrationFile(IllustrationAsset asset) => File(
    '${projectRoot.path}${Platform.pathSeparator}'
    '${_validatedAssetPath(asset.assetPath)}',
  );

  Future<void> removeIllustrationFile(IllustrationAsset asset) async {
    final file = illustrationFile(asset);
    if (await file.exists()) await file.delete();
  }

  static Directory locateProjectRoot({
    Directory? startDirectory,
    List<String> arguments = const [],
  }) {
    const prefix = '--project-root=';
    final explicit = arguments
        .where((value) => value.startsWith(prefix))
        .map((value) => value.substring(prefix.length))
        .firstOrNull;
    if (explicit != null) {
      final root = Directory(explicit).absolute;
      if (_isProjectRoot(root)) return root;
      throw FileSystemException(
        'Dossier de projet ENCHAIRE invalide',
        root.path,
      );
    }

    final starts = <Directory>{
      (startDirectory ?? Directory.current).absolute,
      File(Platform.resolvedExecutable).parent.absolute,
    };
    for (final start in starts) {
      var current = start;
      while (true) {
        if (_isProjectRoot(current)) return current;
        final parent = current.parent;
        if (parent.path == current.path) break;
        current = parent;
      }
    }
    throw const FileSystemException(
      'Projet ENCHAIRE introuvable. Lancez l’outil depuis le dépôt ou utilisez '
      '--project-root=<dossier>.',
    );
  }

  static bool _isProjectRoot(Directory directory) =>
      File(
        '${directory.path}${Platform.pathSeparator}pubspec.yaml',
      ).existsSync() &&
      Directory(
        '${directory.path}${Platform.pathSeparator}assets'
        '${Platform.pathSeparator}card_themes${Platform.pathSeparator}classic_v1',
      ).existsSync();

  @override
  Future<List<ThemeBundle>> loadAll() async {
    final index =
        jsonDecode(await indexFile.readAsString()) as Map<String, Object?>;
    if (index['schema_version'] != 1) {
      throw const FormatException('Unsupported card theme index version');
    }
    final ids = (index['themes']! as List).cast<String>();
    return Future.wait(ids.map(_load));
  }

  Future<ThemeBundle> _load(String id) async {
    _validateId(id);
    final directory = Directory(
      '${themesDirectory.path}${Platform.pathSeparator}$id',
    );
    final values = await Future.wait([
      File(
        '${directory.path}${Platform.pathSeparator}theme.json',
      ).readAsString(),
      File(
        '${directory.path}${Platform.pathSeparator}layout.json',
      ).readAsString(),
      File(
        '${directory.path}${Platform.pathSeparator}skin.json',
      ).readAsString(),
      File(
        '${directory.path}${Platform.pathSeparator}illustrations.json',
      ).readAsString(),
    ]);
    return ThemeBundle(
      pack: CardThemePack.fromJson(jsonDecode(values[0]) as ThemeJson),
      layout: CardLayout.fromJson(jsonDecode(values[1]) as ThemeJson),
      skin: CardSkin.fromJson(jsonDecode(values[2]) as ThemeJson),
      illustrations: (jsonDecode(values[3]) as List<Object?>)
          .map((item) => IllustrationAsset.fromJson(item! as ThemeJson))
          .toList(),
    );
  }

  @override
  Future<void> save(ThemeBundle bundle) async {
    if (bundle.pack.system && bundle.pack.id != 'enchaire_signature_v1') {
      throw StateError('Les ressources système doivent être dupliquées.');
    }
    _validateId(bundle.pack.id);
    final issues = const CardThemeValidator().validate(bundle);
    if (issues.any((issue) => issue.severity == ThemeIssueSeverity.error)) {
      throw FormatException(issues.map((issue) => issue.message).join('\n'));
    }
    final directory = Directory(
      '${themesDirectory.path}${Platform.pathSeparator}${bundle.pack.id}',
    );
    await directory.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await Future.wait([
      File(
        '${directory.path}${Platform.pathSeparator}theme.json',
      ).writeAsString('${encoder.convert(bundle.pack.toJson())}\n'),
      File(
        '${directory.path}${Platform.pathSeparator}layout.json',
      ).writeAsString('${encoder.convert(bundle.layout.toJson())}\n'),
      File(
        '${directory.path}${Platform.pathSeparator}skin.json',
      ).writeAsString('${encoder.convert(bundle.skin.toJson())}\n'),
      File(
        '${directory.path}${Platform.pathSeparator}illustrations.json',
      ).writeAsString(
        '${encoder.convert(bundle.illustrations.map((item) => item.toJson()).toList())}\n',
      ),
    ]);
    final ids = (await loadAll()).map((theme) => theme.pack.id).toSet()
      ..add(bundle.pack.id);
    await _writeIndex(ids);
    await _registerAssetDirectory(bundle.pack.id);
  }

  @override
  Future<void> delete(String packId) async {
    _validateId(packId);
    final themes = await loadAll();
    final target = themes.where((theme) => theme.pack.id == packId).firstOrNull;
    if (target == null) return;
    if (target.pack.system) {
      throw StateError('Le thème système ne peut pas être supprimé.');
    }
    final directory = Directory(
      '${themesDirectory.path}${Platform.pathSeparator}$packId',
    );
    if (await directory.exists()) await directory.delete(recursive: true);
    await _writeIndex(
      themes.map((theme) => theme.pack.id).where((id) => id != packId),
    );
    await _unregisterAssetDirectory(packId);
  }

  @override
  Future<ThemeBundle> import(String source) async {
    final bundle = ThemeBundle.import(source);
    if ((await loadAll()).any((theme) => theme.pack.id == bundle.pack.id)) {
      throw const FormatException(
        'Collision d’ID : dupliquez ou renommez le thème.',
      );
    }
    await save(bundle);
    return bundle;
  }

  @override
  String export(ThemeBundle bundle) => bundle.export();

  Future<void> _writeIndex(Iterable<String> ids) async {
    final sorted = ids.toSet().toList()
      ..sort((left, right) {
        int priority(String id) => switch (id) {
          'enchaire_signature_v1' => 0,
          'classic_v1' => 1,
          _ => 2,
        };
        final order = priority(left).compareTo(priority(right));
        return order != 0 ? order : left.compareTo(right);
      });
    const encoder = JsonEncoder.withIndent('  ');
    await indexFile.writeAsString(
      '${encoder.convert({'schema_version': 1, 'themes': sorted})}\n',
    );
  }

  Future<void> _registerAssetDirectory(String id) async {
    final pubspec = File(
      '${projectRoot.path}${Platform.pathSeparator}pubspec.yaml',
    );
    final lines = await pubspec.readAsLines();
    final asset = 'assets/card_themes/$id/';
    if (lines.any((line) => line.trim() == '- $asset')) return;
    final index = lines.lastIndexWhere(
      (line) => line.trim().startsWith('- assets/card_themes/'),
    );
    if (index < 0) {
      throw const FormatException(
        'La section assets/card_themes est absente de pubspec.yaml.',
      );
    }
    lines.insert(index + 1, '    - $asset');
    await pubspec.writeAsString('${lines.join('\n')}\n');
  }

  Future<void> _unregisterAssetDirectory(String id) async {
    final pubspec = File(
      '${projectRoot.path}${Platform.pathSeparator}pubspec.yaml',
    );
    final lines = await pubspec.readAsLines();
    final asset = 'assets/card_themes/$id/';
    lines.removeWhere((line) => line.trim() == '- $asset');
    await pubspec.writeAsString('${lines.join('\n')}\n');
  }

  void _validateId(String id) {
    if (!RegExp(r'^[a-z0-9][a-z0-9_-]*$').hasMatch(id)) {
      throw FormatException('Identifiant de thème invalide : $id');
    }
  }

  String _validatedAssetPath(String assetPath) {
    final normalized = assetPath.replaceAll('/', Platform.pathSeparator);
    final prefix =
        'assets${Platform.pathSeparator}card_themes'
        '${Platform.pathSeparator}';
    if (!normalized.startsWith(prefix) ||
        normalized.split(Platform.pathSeparator).contains('..')) {
      throw FormatException('Chemin d’illustration invalide : $assetPath');
    }
    return normalized;
  }
}
