import 'package:couple_cards/data/local/app_database.dart';
import 'package:couple_cards/data/repositories/profile_repository.dart';
import 'package:couple_cards/domain/domain.dart';
import 'package:test/test.dart';

void main() {
  late AppDatabase database;
  late ProfileRepository repository;
  final now = DateTime.utc(2026, 9, 28, 8);

  setUp(() async {
    database = AppDatabase.memory();
    repository = ProfileRepository(database);
    await repository.create(
      LocalProfile(id: 'profile.1', createdAt: now, updatedAt: now),
    );
  });
  tearDown(() => database.close());

  test(
    'persists every consent status and GENERAL/FAIRE/RECEVOIR values',
    () async {
      for (var index = 0; index < PreferenceStatus.values.length; index++) {
        final status = PreferenceStatus.values[index];
        await repository.savePreference(
          StoredUserPreference(
            profileId: 'profile.1',
            profileElementId: 'element.$index',
            status: status,
            generalValue: index + 1,
            faireValue: index + 2,
            recevoirValue: index + 3,
            updatedAt: now,
            source: PreferenceSource.ONBOARDING,
          ),
        );
      }
      final saved = await repository.preferences('profile.1');
      expect(saved.map((p) => p.status), PreferenceStatus.values);
      expect(saved.map((p) => p.generalValue), [1, 2, 3, 4]);
      expect(saved.map((p) => p.faireValue), [2, 3, 4, 5]);
      expect(saved.map((p) => p.recevoirValue), [3, 4, 5, 6]);
    },
  );

  test('persists CardPreferenceOverride', () async {
    await repository.saveOverride(
      StoredCardPreferenceOverride(
        profileId: 'profile.1',
        cardOrVariantId: 'variant.draw.precise',
        status: PreferenceStatus.EXCLUDED,
        faireValue: 4,
        recevoirValue: 8,
        updatedAt: now,
      ),
    );
    final saved = (await repository.overrides('profile.1')).single;
    expect(saved.status, PreferenceStatus.EXCLUDED);
    expect(saved.faireValue, 4);
    expect(saved.recevoirValue, 8);
  });

  test(
    'evolution never changes consent and can be deleted separately',
    () async {
      await repository.savePreference(
        StoredUserPreference(
          profileId: 'profile.1',
          profileElementId: 'element.draw',
          status: PreferenceStatus.EXCLUDED,
          generalValue: 3,
          updatedAt: now,
          source: PreferenceSource.SEARCH,
        ),
      );
      await repository.recordEvolution(
        ProfileEvolutionData(
          profileId: 'profile.1',
          profileElementId: 'element.draw',
          generalValue: 18,
          evidence: const {'reason': 'explicit player feedback'},
          createdAt: now,
        ),
      );
      expect(
        (await repository.preference('profile.1', 'element.draw'))!.status,
        PreferenceStatus.EXCLUDED,
      );
      expect(await repository.evolutionCount('profile.1'), 1);
      await repository.deleteEvolutionData('profile.1');
      expect(await repository.evolutionCount('profile.1'), 0);
      expect(
        (await repository.preference('profile.1', 'element.draw'))!.status,
        PreferenceStatus.EXCLUDED,
      );
    },
  );

  test('profile evolution rejects media fields', () async {
    expect(
      () => repository.recordEvolution(
        ProfileEvolutionData(
          profileId: 'profile.1',
          profileElementId: 'element.draw',
          evidence: const {'photo_url': 'file:///private.jpg'},
          createdAt: now,
        ),
      ),
      throwsArgumentError,
    );
  });
}
