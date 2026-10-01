import 'dart:io';

import 'package:couple_cards/data/local/app_database.dart';
import 'package:couple_cards/data/repositories/profile_repository.dart';
import 'package:couple_cards/domain/domain.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

void main() {
  test(
    'v1 to v3 migration preserves consent and adds learning storage',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'couple_cards_migration_',
      );
      final file = File('${directory.path}${Platform.pathSeparator}v1.sqlite');
      final raw = sqlite.sqlite3.open(file.path);
      raw.execute('''
      CREATE TABLE user_preferences (
        profile_id TEXT NOT NULL,
        profile_element_id TEXT NOT NULL,
        status TEXT NOT NULL,
        general_value INTEGER NULL,
        updated_at INTEGER NOT NULL,
        source TEXT NOT NULL,
        PRIMARY KEY (profile_id, profile_element_id)
      );
      CREATE TABLE session_players (
        session_id TEXT NOT NULL,
        player_id TEXT NOT NULL,
        profile_id TEXT NULL,
        action_points INTEGER NOT NULL,
        chili_level INTEGER NOT NULL,
        PRIMARY KEY (session_id, player_id)
      );
      PRAGMA user_version = 1;
    ''');
      for (var index = 0; index < PreferenceStatus.values.length; index++) {
        raw.execute('INSERT INTO user_preferences VALUES (?, ?, ?, ?, ?, ?)', [
          'profile.1',
          'element.$index',
          PreferenceStatus.values[index].name,
          index + 1,
          1,
          'ONBOARDING',
        ]);
      }
      raw.dispose();

      final database = AppDatabase.openFile(file);
      final repository = ProfileRepository(database);
      final migrated = await repository.preferences('profile.1');
      expect(migrated.map((p) => p.status), PreferenceStatus.values);
      expect(migrated.map((p) => p.generalValue), [1, 2, 3, 4]);
      expect(
        migrated.every((p) => p.faireValue == null && p.recevoirValue == null),
        isTrue,
      );
      expect(
        await database
            .customSelect('PRAGMA user_version')
            .map((row) => row.read<int>('user_version'))
            .getSingle(),
        3,
      );
      expect(
        await database
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'profile_learning_states'",
            )
            .getSingleOrNull(),
        isNotNull,
      );
      await database.close();
      await directory.delete(recursive: true);
    },
  );
}
