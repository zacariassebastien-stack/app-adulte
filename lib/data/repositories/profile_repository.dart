import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/catalog/enums.dart';
import '../../domain/profile/profile_state.dart';
import '../local/app_database.dart';
import '../local/media_guard.dart';

final class ProfileRepository {
  ProfileRepository(this.database);

  final AppDatabase database;

  Future<void> create(LocalProfile profile) => database
      .into(database.profiles)
      .insert(
        ProfilesCompanion.insert(
          id: profile.id,
          createdAt: profile.createdAt,
          updatedAt: profile.updatedAt,
        ),
        mode: InsertMode.insertOrFail,
      );

  Future<void> savePreference(StoredUserPreference preference) async {
    _validateRating(preference.generalValue);
    _validateRating(preference.faireValue);
    _validateRating(preference.recevoirValue);
    await database.transaction(() async {
      await database
          .into(database.userPreferences)
          .insertOnConflictUpdate(
            UserPreferencesCompanion.insert(
              profileId: preference.profileId,
              profileElementId: preference.profileElementId,
              status: preference.status.name,
              generalValue: Value(preference.generalValue),
              faireValue: Value(preference.faireValue),
              recevoirValue: Value(preference.recevoirValue),
              updatedAt: preference.updatedAt,
              source: preference.source.name,
            ),
          );
      await (database.update(database.profiles)
            ..where((p) => p.id.equals(preference.profileId)))
          .write(ProfilesCompanion(updatedAt: Value(preference.updatedAt)));
    });
  }

  Future<StoredUserPreference?> preference(
    String profileId,
    String elementId,
  ) async {
    final query = database.select(database.userPreferences)
      ..where(
        (p) =>
            p.profileId.equals(profileId) &
            p.profileElementId.equals(elementId),
      );
    final row = await query.getSingleOrNull();
    return row == null ? null : _preference(row);
  }

  Future<List<StoredUserPreference>> preferences(String profileId) async {
    final query = database.select(database.userPreferences)
      ..where((p) => p.profileId.equals(profileId))
      ..orderBy([(p) => OrderingTerm.asc(p.profileElementId)]);
    return (await query.get()).map(_preference).toList(growable: false);
  }

  Future<void> saveOverride(StoredCardPreferenceOverride override) async {
    _validateRating(override.faireValue);
    _validateRating(override.recevoirValue);
    await database
        .into(database.cardPreferenceOverrides)
        .insertOnConflictUpdate(
          CardPreferenceOverridesCompanion.insert(
            profileId: override.profileId,
            cardOrVariantId: override.cardOrVariantId,
            status: Value(override.status?.name),
            faireValue: Value(override.faireValue),
            recevoirValue: Value(override.recevoirValue),
            updatedAt: override.updatedAt,
          ),
        );
  }

  Future<List<StoredCardPreferenceOverride>> overrides(String profileId) async {
    final query = database.select(database.cardPreferenceOverrides)
      ..where((p) => p.profileId.equals(profileId))
      ..orderBy([(p) => OrderingTerm.asc(p.cardOrVariantId)]);
    return (await query.get())
        .map(
          (row) => StoredCardPreferenceOverride(
            profileId: row.profileId,
            cardOrVariantId: row.cardOrVariantId,
            status: row.status == null
                ? null
                : PreferenceStatus.values.byName(row.status!),
            faireValue: row.faireValue,
            recevoirValue: row.recevoirValue,
            updatedAt: row.updatedAt,
          ),
        )
        .toList(growable: false);
  }

  /// Records evolution evidence without reading or writing consent fields.
  Future<int> recordEvolution(ProfileEvolutionData evolution) async {
    evolution.validate();
    assertNoPersistedMedia(evolution.evidence);
    return database
        .into(database.profileEvolutionEntries)
        .insert(
          ProfileEvolutionEntriesCompanion.insert(
            profileId: evolution.profileId,
            profileElementId: evolution.profileElementId,
            generalValue: Value(evolution.generalValue),
            faireValue: Value(evolution.faireValue),
            recevoirValue: Value(evolution.recevoirValue),
            evidenceJson: jsonEncode(evolution.evidence),
            createdAt: evolution.createdAt,
          ),
        );
  }

  Future<int> evolutionCount(String profileId) async {
    final count = database.profileEvolutionEntries.id.count();
    final query = database.selectOnly(database.profileEvolutionEntries)
      ..addColumns([count])
      ..where(database.profileEvolutionEntries.profileId.equals(profileId));
    return (await query.getSingle()).read(count) ?? 0;
  }

  /// Separate deletion: preferences and overrides remain untouched.
  Future<void> deleteEvolutionData(String profileId) async {
    await (database.delete(
      database.profileEvolutionEntries,
    )..where((e) => e.profileId.equals(profileId))).go();
  }

  StoredUserPreference _preference(UserPreferenceRow row) =>
      StoredUserPreference(
        profileId: row.profileId,
        profileElementId: row.profileElementId,
        status: PreferenceStatus.values.byName(row.status),
        generalValue: row.generalValue,
        faireValue: row.faireValue,
        recevoirValue: row.recevoirValue,
        updatedAt: row.updatedAt,
        source: PreferenceSource.values.byName(row.source),
      );

  static void _validateRating(int? value) {
    if (value != null && (value < 1 || value > 20)) {
      throw ArgumentError.value(value, 'rating', 'must be between 1 and 20');
    }
  }
}
