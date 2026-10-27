import 'dart:math';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:couple_cards/features/game/network_profile_learning.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:couple_cards/domain/profile/v4_profile.dart';
import 'package:couple_cards/domain/profile/adaptive_profile.dart';
import 'package:couple_cards/engines/profile/card_personalization_engine.dart';
import 'package:couple_cards/engines/profile/v4_card_rating_engine.dart';
import 'package:couple_cards/engines/deck/concept_deck_engine.dart';
import 'package:couple_cards/domain/catalog/v4_catalog.dart';

void main() {
  const engine = CardPersonalizationEngine();
  const key = CardRatingKey(
    profileId: 'a',
    cardId: '002',
    variantId: '002.zone.neck_nape',
    role: ProfilePreferenceRole.faire,
  );
  const tags = {'embrasser': 1.0};
  bool observe(
    CardSpecificLearningStore store,
    String id,
    PersonalizationSignal signal, {
    bool enabled = true,
    String? episode,
  }) => engine.observe(
    store: store,
    key: key,
    prior: 7.5,
    tags: tags,
    eventId: id,
    signal: signal,
    enabled: enabled,
    exposureEpisode: episode,
  );

  test('manual mode has no behavioral writes', () {
    final store = CardSpecificLearningStore();
    expect(
      observe(store, 'e', PersonalizationSignal.chosen, enabled: false),
      false,
    );
    expect(store.values, isEmpty);
  });
  test(
    'manual mode preserves a rated presentation despite subsequent behavior',
    () {
      final store = CardSpecificLearningStore();
      engine.seed(store, key, 7.5, tags);
      store.write(store.read(key)!.withOwnEstimate(3.5));
      final before = jsonEncode(store.toJson());
      observe(
        store,
        'ignored',
        PersonalizationSignal.nonChoice,
        enabled: false,
      );
      observe(store, 'played', PersonalizationSignal.chosen, enabled: false);
      expect(jsonEncode(store.toJson()), before);
    },
  );
  test('continuous estimate never silently changes official PA', () {
    final store = CardSpecificLearningStore();
    observe(store, 'lock', PersonalizationSignal.locked);
    observe(store, 'play', PersonalizationSignal.chosen);
    expect(store.referenceEstimate(key), 7.5);
    expect(
      store.read(key)!.personalization['internal'],
      closeTo(7.375, .000001),
    );
    expect(store.read(key)!.observationCount, 2);
  });
  test('an unassessed marker gets its first official reference on valid exposure', () {
    final store = CardSpecificLearningStore();
    store.write(const CardRatingStateV4(key: key, initialScore: null, currentEstimate: null,
      observationCount: 0, acceptanceCount: 0, resistanceCount: 0, source: 'EXCLUSION_MARKER'));
    engine.seed(store, key, 12, tags);
    expect(store.referenceEstimate(key), 12);
    observe(store, 'played', PersonalizationSignal.chosen);
    expect(store.referenceEstimate(key), 12);
  });
  test('event receipt survives serialization and retry', () {
    final store = CardSpecificLearningStore();
    observe(store, 'e', PersonalizationSignal.chosen);
    final restored = CardSpecificLearningStore()..restore(store.toJson());
    expect(observe(restored, 'e', PersonalizationSignal.chosen), false);
    expect(restored.toJson(), store.toJson());
  });
  test(
    'continuous exposure non choice decays across rounds and reconstruction',
    () {
      final store = CardSpecificLearningStore();
      observe(
        store,
        'round1',
        PersonalizationSignal.nonChoice,
        episode: 'held',
      );
      final restored = CardSpecificLearningStore()..restore(store.toJson());
      observe(
        restored,
        'round2',
        PersonalizationSignal.nonChoice,
        episode: 'held',
      );
      expect(
        restored.read(key)!.personalization['internal'],
        closeTo(7.5475, .000001),
      );
    },
  );
  test(
    'crossing a tier proposes but acceptance adopts its official centre',
    () {
      final store = CardSpecificLearningStore();
      for (var i = 0; i < 32; i++) {
        observe(store, '$i', PersonalizationSignal.chosen);
      }
      expect(store.referenceEstimate(key), 7.5);
      expect(store.read(key)!.personalization['pending'], 'likeALot');
      expect(engine.decide(store, key, accept: true, expectedCategory: 'love'), false);
      expect(store.referenceEstimate(key), 7.5);
      expect(engine.decide(store, key, accept: true), true);
      expect(
        store.referenceEstimate(key),
        DetailedPreferenceCategory.likeALot.personalPa,
      );
      expect(engine.decide(store, key, accept: true), false);
    },
  );
  test(
    'decline retains reference and does not immediately repeat same proposal',
    () {
      final store = CardSpecificLearningStore();
      for (var i = 0; i < 32; i++) {
        observe(store, '$i', PersonalizationSignal.chosen);
      }
      engine.decide(store, key, accept: false);
      observe(store, 'next', PersonalizationSignal.chosen);
      expect(store.referenceEstimate(key), 7.5);
      expect(store.read(key)!.personalization['pending'], isNull);
    },
  );
  test('manual estimate clears pending and preserves receipts', () {
    final store = CardSpecificLearningStore();
    observe(store, 'e', PersonalizationSignal.chosen);
    store.write(store.read(key)!.withOwnEstimate(3.5));
    expect(store.referenceEstimate(key), 3.5);
    expect(store.read(key)!.personalization['events'], ['e']);
    expect(store.read(key)!.personalization['internal'], 3.5);
  });
  test('roles and stages do not share a precise estimate', () {
    // 013's existing frozen learning_role is SOI even though its presentation
    // direction is SOLO. Legacy SOLO keys restore to that same identity.
    const self = CardRatingKey(profileId: 'a', cardId: '013',
      variantId: '013.action', role: ProfilePreferenceRole.solo);
    expect(self.role, ProfilePreferenceRole.soi);
    expect(CardRatingKey.fromJson({...self.toJson(), 'role': 'SOLO'}).storageKey, self.storageKey);
    final store = CardSpecificLearningStore();
    observe(store, 'e', PersonalizationSignal.chosen);
    expect(
      store.read(
        const CardRatingKey(
          profileId: 'a',
          cardId: '002',
          variantId: '002.zone.neck_nape',
          role: ProfilePreferenceRole.recevoir,
        ),
      ),
      isNull,
    );
    expect(
      store.read(
        const CardRatingKey(
          profileId: 'a',
          cardId: '002',
          variantId: '002.zone.free',
          role: ProfilePreferenceRole.faire,
        ),
      ),
      isNull,
    );
  });
  test(
    'tag hypothesis influences discovery, not an already seeded reference',
    () {
      final store = CardSpecificLearningStore();
      engine.seed(store, key, 18, tags);
      const other = CardRatingKey(
        profileId: 'a',
        cardId: '003',
        variantId: '003.action',
        role: ProfilePreferenceRole.faire,
      );
      engine.seed(store, other, 18, tags);
      store.write(store.read(other)!.withOwnEstimate(3.5));
      expect(store.referenceEstimate(key), 18);
      const unseen = CardRatingKey(
        profileId: 'a',
        cardId: '004',
        variantId: '004.action',
        role: ProfilePreferenceRole.faire,
      );
      final weight = engine.drawWeight(store, unseen, 20, tags);
      expect(
        weight,
        greaterThan(
          engine.drawWeight(CardSpecificLearningStore(), unseen, 20, tags),
        ),
      );
      expect(store.read(unseen), isNull);
    },
  );
  test('preference weights are bounded and inverse to PA', () {
    final store = CardSpecificLearningStore();
    expect(engine.drawWeight(store, key, 1, tags), closeTo(1.2, .00001));
    expect(engine.drawWeight(store, key, 20, tags), closeTo(.8, .00001));
    expect(
      engine.drawWeight(store, key, 3.5, tags),
      greaterThan(engine.drawWeight(store, key, 18, tags)),
    );
  });
  test('weighted chooser is deterministic and rejects invalid weights', () {
    expect(weightedChoice([1, 2], _FixedRandom(.2), (v) => v.toDouble()), 1);
    expect(weightedChoice([1, 2], _FixedRandom(.4), (v) => v.toDouble()), 2);
    expect(() => weightedChoice([1], Random(1), (_) => 0), throwsArgumentError);
  });
  test(
    '039 receiving reads regarder and ignores etre_regarde receiving veto',
    () {
      ProfilePreference pref(String tag, double? score) => ProfilePreference(
        profileId: 'a',
        key: ProfilePreferenceKey(
          tagId: tag,
          role: ProfilePreferenceRole.recevoir,
        ),
        pa: score,
        excluded: score == null,
        source: ProfilePreferenceSource.initialQuestionnaire,
      );
      final values = [
        pref('regarder', 5),
        pref('controle', 12),
        pref('etre_regarde', null),
      ];
      final profile = V4Profile(
        profileId: 'a',
        sex: ProfileSex.HOMME,
        preferences: {for (final p in values) p.key.storageKey: p},
      );
      final result = const V4CardRatingEngine().initializeForDirection(
        profile: profile,
        conceptId: '039',
        direction: 'RECEVOIR',
        variant: V4VariantRatingDefinition(
          variantId: '039.action',
          primaryPreferenceTags: const ['etre_regarde'],
          secondaryPreferenceTags: const ['controle'],
          nonPreferenceData: const [],
          stage: null,
          scope: 'concept',
        ),
      );
      expect(result.kind, V4RatingResultKind.rated);
      expect(result.rawScore, 7);
    },
  );

  for (final excluded in [false, true]) {
    test('021 bootstrap MUTUEL once, excluded=$excluded', () {
      ProfilePreference pref(
        ProfilePreferenceRole role,
        double value,
        bool veto,
      ) => ProfilePreference(
        profileId: 'a',
        key: ProfilePreferenceKey(tagId: 'masturbation', role: role),
        pa: veto ? null : value,
        excluded: veto,
        source: ProfilePreferenceSource.initialQuestionnaire,
      );
      final solo = pref(ProfilePreferenceRole.solo, 5, excluded);
      final observer = pref(ProfilePreferenceRole.observer, 18, false);
      final profile = V4Profile(
        profileId: 'a',
        sex: ProfileSex.HOMME,
        preferences: {
          solo.key.storageKey: solo,
          observer.key.storageKey: observer,
        },
      );
      expect(profile.preferences['masturbation|mutuel']!.excluded, excluded);
      expect(
        profile.preferences['masturbation|mutuel']!.pa,
        excluded ? null : 11.5,
      );
      final json = profile.toJson();
      (json['preferences'] as List).removeWhere(
        (p) => (p as Map)['role'] == 'SOLO',
      );
      expect(
        V4Profile.fromJson(json).preferences['masturbation|mutuel']!.pa,
        excluded ? null : 11.5,
      );
    });
  }
  test(
    'existing profile persists MUTUEL bootstrap once and retains precise rating',
    () async {
      Map<String, Object?> preference(String role, double pa) => {
        'profile_id': 'a',
        'tag_id': 'masturbation',
        'role': role,
        'pa': pa,
        'excluded': false,
        'source': 'initialQuestionnaire',
      };
      final legacy = {
        'schema_version': 1,
        'profile_id': 'a',
        'sex': 'HOMME',
        'preferences': [preference('SOLO', 5), preference('OBSERVER', 18)],
      'consents': <Object?>[],
      'accessories': <Object?>[],
      'stage_vetoes': <Object?>[],
      };
      const preciseKey = CardRatingKey(
        profileId: 'a',
        cardId: '021',
        variantId: '021.action',
        role: ProfilePreferenceRole.mutuel,
      );
      final ratings = CardSpecificLearningStore();
      engine.seed(ratings, preciseKey, 7.5, const {'masturbation': 1});
      ratings.write(ratings.read(preciseKey)!.withOwnEstimate(3.5));
      SharedPreferences.setMockInitialValues({
        'profile_preferences_v4.a': jsonEncode(legacy),
        'card_learning_v4.a': jsonEncode(ratings.toJson()),
      });
      final store = const SharedPreferencesV4ProfileStore();
      expect(
        (await store.load('a'))!.preferences['masturbation|mutuel']!.pa,
        11.5,
      );
      final prefs = await SharedPreferences.getInstance();
      final persisted =
          jsonDecode(prefs.getString('profile_preferences_v4.a')!)
              as Map<String, dynamic>;
      final values = (persisted['preferences'] as List)
          .cast<Map<String, dynamic>>();
      expect(values.where((p) => p['role'] == 'MUTUEL'), hasLength(1));
      values.singleWhere((p) => p['role'] == 'SOLO')['pa'] = 18;
      await prefs.setString('profile_preferences_v4.a', jsonEncode(persisted));
      expect(
        (await store.load('a'))!.preferences['masturbation|mutuel']!.pa,
        11.5,
      );
      expect(
        (await const SharedPreferencesV4CardLearningStore().load(
          'a',
        )).referenceEstimate(preciseKey),
        3.5,
      );
    },
  );
}

class _FixedRandom implements Random {
  _FixedRandom(this.value);
  final double value;
  @override
  double nextDouble() => value;
  @override
  int nextInt(int max) => (value * max).floor();
  @override
  bool nextBool() => value < .5;
}
