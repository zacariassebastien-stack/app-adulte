import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'card_theme_models.dart';
import 'card_theme_validator.dart';
import 'classic_theme.dart';

abstract interface class CardThemeRepository {
  Future<List<ThemeBundle>> loadAll();
  Future<void> save(ThemeBundle bundle);
  Future<void> delete(String packId);
  Future<ThemeBundle> import(String source);
  String export(ThemeBundle bundle);
}

final class SharedPreferencesCardThemeRepository
    implements CardThemeRepository {
  const SharedPreferencesCardThemeRepository({this.preferences, this.assets});
  static const _key = 'card_theme_editor_bundles_v1';
  final SharedPreferences? preferences;
  final AssetBundle? assets;

  Future<SharedPreferences> get _prefs async =>
      preferences ?? SharedPreferences.getInstance();

  @override
  Future<List<ThemeBundle>> loadAll() async {
    late List<ThemeBundle> bundled;
    try {
      bundled = await const AssetCardThemeLoader().loadAll(bundle: assets);
    } on FlutterError {
      // Pure Dart consumers have no Flutter services binding. The classic
      // theme also keeps the app usable if bundled theme assets are damaged.
      bundled = [ClassicCardTheme.bundle];
    }
    final encoded = (await _prefs).getStringList(_key) ?? const [];
    final custom = <ThemeBundle>[];
    for (final source in encoded) {
      try {
        custom.add(ThemeBundle.import(source));
      } on FormatException {
        // One invalid local draft must not hide the canonical theme.
      }
    }
    final byId = {for (final theme in bundled) theme.pack.id: theme};
    for (final theme in custom) {
      byId[theme.pack.id] = theme;
    }
    return byId.values.toList(growable: false);
  }

  @override
  Future<void> save(ThemeBundle bundle) async {
    if (bundle.pack.system) {
      throw StateError('Les ressources système doivent être dupliquées.');
    }
    final issues = const CardThemeValidator().validate(bundle);
    if (issues.any((issue) => issue.severity == ThemeIssueSeverity.error)) {
      throw FormatException(issues.map((issue) => issue.message).join('\n'));
    }
    final bundles = await loadAll();
    final custom = bundles.where((item) => !item.pack.system).toList();
    final index = custom.indexWhere((item) => item.pack.id == bundle.pack.id);
    if (index >= 0) {
      custom[index] = bundle;
    } else {
      custom.add(bundle);
    }
    await (await _prefs).setStringList(
      _key,
      custom.map((item) => item.export()).toList(),
    );
  }

  @override
  Future<void> delete(String packId) async {
    if (packId == ClassicCardTheme.pack.id) {
      throw StateError('Le thème système ne peut pas être supprimé.');
    }
    final custom = (await loadAll())
        .where((item) => !item.pack.system && item.pack.id != packId)
        .map((item) => item.export())
        .toList();
    await (await _prefs).setStringList(_key, custom);
  }

  @override
  Future<ThemeBundle> import(String source) async {
    final bundle = ThemeBundle.import(source);
    final existing = await loadAll();
    if (existing.any((item) => item.pack.id == bundle.pack.id)) {
      throw const FormatException(
        'Collision d’ID : dupliquez ou renommez le thème.',
      );
    }
    for (final illustration in bundle.illustrations) {
      try {
        await (assets ?? rootBundle).load(illustration.assetPath);
      } on Object {
        throw FormatException(
          'Asset d’illustration absent : ${illustration.assetPath}.',
        );
      }
    }
    await save(bundle);
    return bundle;
  }

  @override
  String export(ThemeBundle bundle) => bundle.export();
}

final class AssetCardThemeLoader {
  const AssetCardThemeLoader();
  static ThemeBundle? _cache;
  static List<ThemeBundle>? _allCache;
  static int parseCount = 0;

  Future<ThemeBundle> loadClassic({AssetBundle? bundle}) async {
    if (_cache case final cached?) return cached;
    final assets = bundle ?? rootBundle;
    final values = await Future.wait([
      assets.loadString('assets/card_themes/classic_v1/theme.json'),
      assets.loadString('assets/card_themes/classic_v1/layout.json'),
      assets.loadString('assets/card_themes/classic_v1/skin.json'),
      assets.loadString('assets/card_themes/classic_v1/illustrations.json'),
    ]);
    parseCount++;
    final pack = CardThemePack.fromJson(jsonDecode(values[0]) as ThemeJson);
    final layout = CardLayout.fromJson(jsonDecode(values[1]) as ThemeJson);
    final skin = CardSkin.fromJson(jsonDecode(values[2]) as ThemeJson);
    final illustrations = (jsonDecode(values[3]) as List<Object?>)
        .map((item) => IllustrationAsset.fromJson(item! as ThemeJson))
        .toList();
    return _cache = ThemeBundle(
      pack: pack,
      layout: layout,
      skin: skin,
      illustrations: illustrations,
    );
  }

  Future<List<ThemeBundle>> loadAll({
    AssetBundle? bundle,
    String assetPrefix = '',
  }) async {
    final useCache = bundle == null && assetPrefix.isEmpty;
    if (useCache && _allCache != null) return _allCache!;
    final assets = bundle ?? rootBundle;
    final index =
        jsonDecode(
              await assets.loadString(
                '${assetPrefix}assets/card_themes/index.json',
              ),
            )
            as Map<String, Object?>;
    final ids = (index['themes']! as List).cast<String>();
    final themes = <ThemeBundle>[];
    for (final id in ids) {
      final base = '${assetPrefix}assets/card_themes/$id';
      final values = await Future.wait([
        assets.loadString('$base/theme.json'),
        assets.loadString('$base/layout.json'),
        assets.loadString('$base/skin.json'),
        assets.loadString('$base/illustrations.json'),
      ]);
      themes.add(
        ThemeBundle(
          pack: CardThemePack.fromJson(jsonDecode(values[0]) as ThemeJson),
          layout: CardLayout.fromJson(jsonDecode(values[1]) as ThemeJson),
          skin: CardSkin.fromJson(jsonDecode(values[2]) as ThemeJson),
          illustrations: (jsonDecode(values[3]) as List<Object?>)
              .map((item) => IllustrationAsset.fromJson(item! as ThemeJson))
              .toList(),
        ),
      );
    }
    if (useCache) _allCache = List.unmodifiable(themes);
    return List.unmodifiable(themes);
  }

  static void clearCacheForTesting() {
    _cache = null;
    _allCache = null;
    parseCount = 0;
  }
}
