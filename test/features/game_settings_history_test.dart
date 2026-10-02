import 'dart:convert';

import 'package:couple_cards/card_themes/card_theme_models.dart';
import 'package:couple_cards/card_themes/card_theme_registry.dart';
import 'package:couple_cards/card_themes/card_theme_repository.dart';
import 'package:couple_cards/features/game/game_preferences.dart';
import 'package:couple_cards/features/game/ui/game_settings_panel.dart';
import 'package:couple_cards/features/lobby/game_history.dart';
import 'package:couple_cards/features/lobby/game_history_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'local game preferences persist independently and select theme',
    () async {
      final store = MemoryGamePreferencesStore();
      final controller = GamePreferencesController(
        store: store,
        themes: _Themes(),
      );
      await controller.load();
      await controller.setSound(false);
      await controller.setVibrations(false);
      await controller.setAnimations(false);

      expect(store.value.sound, isFalse);
      expect(store.value.vibrations, isFalse);
      expect(store.value.animations, isFalse);
      expect(CardThemeRegistry.selected.pack.id, 'classic_v1');
      controller.dispose();
    },
  );

  test(
    'history keeps only ten ended games and serializes no private data',
    () async {
      final store = MemoryGameHistoryStore();
      for (var index = 0; index < 12; index++) {
        await store.add(
          GameHistoryEntry.forRounds(
            index + 1,
            endedAt: DateTime.utc(2026, 10, index + 1),
          ),
        );
      }
      final entries = await store.load();
      expect(entries, hasLength(10));
      expect(entries.first.endedAt, DateTime.utc(2026, 10, 12));
      final wire = jsonEncode(entries.first.toJson());
      for (final privateName in [
        'partner',
        'action_points',
        'card',
        'preference',
        'nonce',
      ]) {
        expect(wire, isNot(contains(privateName)));
      }
    },
  );

  testWidgets('settings are opaque, closeable and quit requires confirmation', (
    tester,
  ) async {
    final controller = GamePreferencesController(
      store: MemoryGamePreferencesStore(),
      themes: _Themes(),
    );
    await controller.load();
    var quit = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GameSettingsPanel(
            preferences: controller,
            privateProfile: const Text('Profil local'),
            onQuit: () async => quit++,
          ),
        ),
      ),
    );
    expect(find.byType(Material), findsWidgets);
    await tester.tap(find.text('Son et vibrations'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('setting-sound')));
    await tester.pump();
    expect(controller.value.sound, isFalse);

    await tester.scrollUntilVisible(
      find.byKey(const Key('quit-network-game')),
      300,
    );
    await tester.tap(find.byKey(const Key('quit-network-game')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cancel-quit-game')));
    await tester.pumpAndSettle();
    expect(quit, 0);
    await tester.tap(find.byKey(const Key('quit-network-game')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-quit-game')));
    await tester.pumpAndSettle();
    expect(quit, 1);
    controller.dispose();
  });

  testWidgets('settings X closes the panel route', (tester) async {
    final controller = GamePreferencesController(
      store: MemoryGamePreferencesStore(),
      themes: _Themes(),
    );
    await controller.load();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (_) => GameSettingsPanel(
                preferences: controller,
                privateProfile: const Text('Profil local'),
                onQuit: () async {},
              ),
            ),
            child: const Text('Ouvrir'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Ouvrir'));
    await tester.pumpAndSettle();
    expect(find.text('Réglages'), findsOneWidget);
    await tester.tap(find.byKey(const Key('close-game-settings')));
    await tester.pumpAndSettle();
    expect(find.text('Réglages'), findsNothing);
    controller.dispose();
  });

  testWidgets('history displays only its concise local profile', (
    tester,
  ) async {
    final store = MemoryGameHistoryStore();
    await store.add(
      GameHistoryEntry.forRounds(8, endedAt: DateTime.utc(2026, 10, 2)),
    );
    await tester.pumpWidget(MaterialApp(home: GameHistoryScreen(store: store)));
    await tester.pumpAndSettle();
    expect(find.text('ENDURANT'), findsOneWidget);
    expect(find.textContaining('garde le rythme'), findsOneWidget);
  });
}

final class _Themes implements CardThemeRepository {
  @override
  Future<List<ThemeBundle>> loadAll() async => [CardThemeRegistry.classic];
  @override
  Future<void> delete(String packId) async {}
  @override
  String export(ThemeBundle bundle) => bundle.export();
  @override
  Future<ThemeBundle> import(String source) async => ThemeBundle.import(source);
  @override
  Future<void> save(ThemeBundle bundle) async {}
}
