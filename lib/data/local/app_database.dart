import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

part 'app_database.g.dart';

@DataClassName('ProfileRow')
class Profiles extends Table {
  @override
  String get tableName => 'profiles';
  TextColumn get id => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('UserPreferenceRow')
class UserPreferences extends Table {
  @override
  String get tableName => 'user_preferences';
  TextColumn get profileId => text()();
  TextColumn get profileElementId => text()();
  TextColumn get status => text()();
  IntColumn get generalValue => integer().nullable()();
  IntColumn get faireValue => integer().nullable()();
  IntColumn get recevoirValue => integer().nullable()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get source => text()();
  @override
  Set<Column<Object>> get primaryKey => {profileId, profileElementId};
}

@DataClassName('CardPreferenceOverrideRow')
class CardPreferenceOverrides extends Table {
  @override
  String get tableName => 'card_preference_overrides';
  TextColumn get profileId => text()();
  TextColumn get cardOrVariantId => text()();
  TextColumn get status => text().nullable()();
  IntColumn get faireValue => integer().nullable()();
  IntColumn get recevoirValue => integer().nullable()();
  DateTimeColumn get updatedAt => dateTime()();
  @override
  Set<Column<Object>> get primaryKey => {profileId, cardOrVariantId};
}

@DataClassName('ProfileEvolutionRow')
class ProfileEvolutionEntries extends Table {
  @override
  String get tableName => 'profile_evolution_entries';
  IntColumn get id => integer().autoIncrement()();
  TextColumn get profileId => text()();
  TextColumn get profileElementId => text()();
  IntColumn get generalValue => integer().nullable()();
  IntColumn get faireValue => integer().nullable()();
  IntColumn get recevoirValue => integer().nullable()();
  TextColumn get evidenceJson => text()();
  DateTimeColumn get createdAt => dateTime()();
}

@DataClassName('ProfileLearningStateRow')
class ProfileLearningStates extends Table {
  @override
  String get tableName => 'profile_learning_states';
  TextColumn get profileId => text()();
  TextColumn get stateJson => text()();
  DateTimeColumn get updatedAt => dateTime()();
  @override
  Set<Column<Object>> get primaryKey => {profileId};
}

@DataClassName('SessionRow')
class Sessions extends Table {
  @override
  String get tableName => 'sessions';
  TextColumn get id => text()();
  TextColumn get mode => text()();
  TextColumn get status => text()();
  TextColumn get interruptedRoundId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('SessionPlayerRow')
class SessionPlayers extends Table {
  @override
  String get tableName => 'session_players';
  TextColumn get sessionId => text()();
  TextColumn get playerId => text()();
  TextColumn get profileId => text().nullable()();
  IntColumn get actionPoints => integer()();
  IntColumn get chiliLevel => integer()();
  TextColumn get style => text().nullable()();
  @override
  Set<Column<Object>> get primaryKey => {sessionId, playerId};
}

@DataClassName('SessionCardRow')
class SessionCards extends Table {
  @override
  String get tableName => 'session_cards';
  TextColumn get sessionId => text()();
  TextColumn get playerId => text()();
  TextColumn get cardId => text()();
  TextColumn get variantId => text().nullable()();
  TextColumn get zone => text()();
  IntColumn get ordinal => integer()();
  BoolColumn get locked => boolean().withDefault(const Constant(false))();
  @override
  Set<Column<Object>> get primaryKey => {sessionId, playerId, cardId};
}

@DataClassName('RoundRow')
class Rounds extends Table {
  @override
  String get tableName => 'rounds';
  TextColumn get sessionId => text()();
  TextColumn get roundId => text()();
  IntColumn get ordinal => integer()();
  TextColumn get status => text()();
  TextColumn get stateJson => text()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  @override
  Set<Column<Object>> get primaryKey => {sessionId, roundId};
}

@DataClassName('CombatValueSnapshotRow')
class CombatValueSnapshots extends Table {
  @override
  String get tableName => 'combat_value_snapshots';
  TextColumn get sessionId => text()();
  TextColumn get roundId => text()();
  TextColumn get playerId => text()();
  TextColumn get cardId => text()();
  TextColumn get variantId => text()();
  TextColumn get roleAtCommit => text()();
  IntColumn get personalValue => integer()();
  DateTimeColumn get committedAt => dateTime()();
  @override
  Set<Column<Object>> get primaryKey => {sessionId, roundId, playerId};
}

@DataClassName('EventLogRow')
class EventLogs extends Table {
  @override
  String get tableName => 'event_logs';
  TextColumn get sessionId => text()();
  TextColumn get eventId => text()();
  IntColumn get sequence => integer()();
  TextColumn get type => text()();
  TextColumn get payloadJson => text()();
  DateTimeColumn get createdAt => dateTime()();
  @override
  Set<Column<Object>> get primaryKey => {sessionId, eventId};
  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {sessionId, sequence},
  ];
}

@DataClassName('CatalogDocumentRow')
class CatalogDocuments extends Table {
  @override
  String get tableName => 'catalog_documents';
  TextColumn get documentId => text()();
  IntColumn get schemaVersion => integer()();
  TextColumn get catalogVersion => text()();
  TextColumn get json => text()();
  DateTimeColumn get installedAt => dateTime()();
  @override
  Set<Column<Object>> get primaryKey => {documentId};
}

@DriftDatabase(
  tables: [
    Profiles,
    UserPreferences,
    CardPreferenceOverrides,
    ProfileEvolutionEntries,
    ProfileLearningStates,
    Sessions,
    SessionPlayers,
    SessionCards,
    Rounds,
    CombatValueSnapshots,
    EventLogs,
    CatalogDocuments,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  factory AppDatabase.memory() => AppDatabase(NativeDatabase.memory());

  factory AppDatabase.openFile(File file) => AppDatabase(
    LazyDatabase(() async => NativeDatabase.createInBackground(file)),
  );

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) => migrator.createAll(),
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        await customStatement(
          'ALTER TABLE user_preferences ADD COLUMN faire_value INTEGER NULL',
        );
        await customStatement(
          'ALTER TABLE user_preferences ADD COLUMN recevoir_value INTEGER NULL',
        );
        await customStatement(
          'ALTER TABLE session_players ADD COLUMN style TEXT NULL',
        );
        await migrator.createTable(profileEvolutionEntries);
      }
      if (from < 3) {
        await migrator.createTable(profileLearningStates);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
