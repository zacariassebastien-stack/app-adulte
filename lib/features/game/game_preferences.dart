import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../card_themes/card_theme_models.dart';
import '../../card_themes/card_theme_registry.dart';
import '../../card_themes/card_theme_repository.dart';

final class GamePreferences {
  const GamePreferences({
    this.sound = true,
    this.vibrations = true,
    this.animations = true,
    this.themeId = 'classic_v1',
  });

  final bool sound, vibrations, animations;
  final String themeId;

  GamePreferences copyWith({
    bool? sound,
    bool? vibrations,
    bool? animations,
    String? themeId,
  }) => GamePreferences(
    sound: sound ?? this.sound,
    vibrations: vibrations ?? this.vibrations,
    animations: animations ?? this.animations,
    themeId: themeId ?? this.themeId,
  );

  Map<String, Object?> toJson() => {
    'sound': sound,
    'vibrations': vibrations,
    'animations': animations,
    'theme_id': themeId,
  };

  factory GamePreferences.fromJson(Map<String, Object?> json) =>
      GamePreferences(
        sound: (json['sound'] as bool?) ?? true,
        vibrations: (json['vibrations'] as bool?) ?? true,
        animations: (json['animations'] as bool?) ?? true,
        themeId: (json['theme_id'] as String?) ?? 'classic_v1',
      );
}

abstract interface class GamePreferencesStore {
  Future<GamePreferences> load();
  Future<void> save(GamePreferences value);
}

final class SharedPreferencesGamePreferencesStore
    implements GamePreferencesStore {
  const SharedPreferencesGamePreferencesStore();
  static const _key = 'game_preferences_v1';

  @override
  Future<GamePreferences> load() async {
    final value = (await SharedPreferences.getInstance()).getString(_key);
    return value == null
        ? const GamePreferences()
        : GamePreferences.fromJson(
            Map<String, Object?>.from(jsonDecode(value) as Map),
          );
  }

  @override
  Future<void> save(GamePreferences value) async {
    await (await SharedPreferences.getInstance()).setString(
      _key,
      jsonEncode(value.toJson()),
    );
  }
}

final class MemoryGamePreferencesStore implements GamePreferencesStore {
  GamePreferences value = const GamePreferences();
  @override
  Future<GamePreferences> load() async => value;
  @override
  Future<void> save(GamePreferences value) async => this.value = value;
}

final class GamePreferencesController extends ChangeNotifier {
  GamePreferencesController({
    GamePreferencesStore? store,
    CardThemeRepository? themes,
  }) : store = store ?? const SharedPreferencesGamePreferencesStore(),
       themes = themes ?? const SharedPreferencesCardThemeRepository();

  final GamePreferencesStore store;
  final CardThemeRepository themes;
  GamePreferences value = const GamePreferences();
  List<ThemeBundle> availableThemes = [CardThemeRegistry.classic];

  Future<void> load() async {
    final loaded = await Future.wait<Object>([store.load(), themes.loadAll()]);
    value = loaded[0] as GamePreferences;
    availableThemes = loaded[1] as List<ThemeBundle>;
    final selected = availableThemes
        .where((theme) => theme.pack.id == value.themeId)
        .firstOrNull;
    CardThemeRegistry.select(selected ?? CardThemeRegistry.classic);
    notifyListeners();
  }

  Future<void> setSound(bool enabled) => _save(value.copyWith(sound: enabled));
  Future<void> setVibrations(bool enabled) =>
      _save(value.copyWith(vibrations: enabled));
  Future<void> setAnimations(bool enabled) =>
      _save(value.copyWith(animations: enabled));

  Future<void> setTheme(ThemeBundle theme) async {
    CardThemeRegistry.select(theme);
    await _save(value.copyWith(themeId: theme.pack.id));
  }

  Future<void> _save(GamePreferences next) async {
    value = next;
    notifyListeners();
    await store.save(next);
  }
}
