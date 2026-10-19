import '../support/native_usage_fixture.dart';
import 'package:couple_cards/sync/projection/usage_learning_projection.dart';
import 'package:couple_cards/sync/protocol/network_usage_projection.dart';
import 'package:couple_cards/domain/profile/adaptive_profile.dart';
import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:couple_cards/core/json.dart';
import 'package:couple_cards/data/catalog_loader/catalog_loader.dart';
import 'package:couple_cards/domain/catalog/concept_catalog.dart';
import 'package:couple_cards/domain/catalog/v4_catalog.dart';
import 'package:couple_cards/domain/profile/v4_profile.dart';
import 'package:couple_cards/engines/eligibility/concept_runtime_catalog.dart';
import 'package:couple_cards/engines/eligibility/concept_action_options.dart';
import 'package:couple_cards/domain/game/game_models.dart';
import 'package:couple_cards/domain/catalog/enums.dart';
import 'package:couple_cards/engines/profile/initial_questionnaire_engine.dart';
import 'package:couple_cards/engines/profile/v4_card_rating_engine.dart';

void main() {
  String read(String name) => File('assets/catalog/$name').readAsStringSync();
  final source = const CatalogLoader().loadJson(
    cardsJson: read('source/cards.v4.fr.json'),
    profilesJson: read('source/profile_elements.v1.fr.json'),
    tagsJson: read('source/tags.v1.json'),
  );
  final catalog = ConceptRuntimeCatalog(
    concepts: ConceptCatalog.fromJson(
      jsonDecode(read('concepts/active.fr.json')) as JsonMap,
    ),
    source: source,
    rules: jsonDecode(read('concepts/runtime_rules.fr.json')) as JsonMap,
  );
  final questionnaire = ProfileQuestionnaire.decode(
    read('source/profile_questions.v1.fr.json'),
  );
  V4Profile profile([
    Map<String, InitialQuestionResponse> overrides = const {},
  ]) => const InitialQuestionnaireEngine().initialize(
    profileId: 'p',
    questionnaire: questionnaire,
    responses: {
      for (final q in questionnaire.questions)
        for (final a in q.axes)
          '${q.stableId}|${a.axisId}': InitialQuestionResponse.like,
      ...overrides,
    },
  );
  V4RatingResult rate(
    String id,
    V4Profile p, {
    String direction = 'FAIRE',
    String? action,
  }) => const V4CardRatingEngine().initializeForDirection(
    profile: p,
    variant: catalog.ratingFor(
      id,
      action ?? catalog.definitions[id]!.variants.first.stableId,
    ),
    conceptId: id,
    direction: direction,
    vetoTags: catalog.vetoTags(id),
  );
  V4Profile withExcluded(V4Profile p, String tag, ProfilePreferenceRole role) {
    final key = ProfilePreferenceKey(tagId: tag, role: role);
    return V4Profile(
      profileId: p.profileId,
      preferences: {
        ...p.preferences,
        key.storageKey: ProfilePreference(
          profileId: p.profileId,
          key: key,
          pa: null,
          excluded: true,
          source: ProfilePreferenceSource.manualCustomized,
        ),
      },
    );
  }

  test('Q15 retains compound mutual priors and initializes unsure at 18', () {
    final p = profile({
      'question.v1.15|montrer': InitialQuestionResponse.love,
      'question.v1.15|regarder': InitialQuestionResponse.unsure,
    });
    for (final id in ['045', '047']) {
      expect(rate(id, p, direction: 'MUTUEL').rawScore, 18);
      final tags = catalog.ratingFor(id, '$id.stage.1');
      expect(tags.primaryPreferenceTags, [
        id == '045' ? 'photo_mutuelle' : 'video_mutuelle',
      ]);
      expect(tags.secondaryPreferenceTags, isEmpty);
      expect(catalog.vetoTags(id), isNot(contains('etre_regarde')));
    }
  });
  test(
    'mutual media do not reconstruct their priors from FAIRE and RECEVOIR',
    () {
      final p = profile();
      final missing = V4Profile(
        profileId: 'p',
        preferences: {
          for (final e in p.preferences.entries)
            if (e.value.key.tagId != 'photo_mutuelle') e.key: e.value,
        },
      );
      expect(
        rate('045', missing, direction: 'MUTUEL').kind,
        V4RatingResultKind.unknown,
      );
    },
  );
  test('013 uses Q05 Moi only and keeps SOI-specific learned preference', () {
    final p = profile({
      'question.v1.05|moi': InitialQuestionResponse.love,
      'question.v1.05|partenaire': InitialQuestionResponse.unsure,
    });
    expect(rate('013', p, direction: 'SOLO').rawScore, 5);
    const key = ProfilePreferenceKey(
      tagId: 'tenue',
      role: ProfilePreferenceRole.soi,
    );
    final learned = V4Profile(
      profileId: 'p',
      preferences: {
        ...p.preferences,
        key.storageKey: const ProfilePreference(
          profileId: 'p',
          key: key,
          pa: 9,
          excluded: false,
          source: ProfilePreferenceSource.autoLearned,
        ),
      },
    );
    expect(rate('013', learned, direction: 'SOLO').rawScore, 9);
  });
  test('022 uses penetration prior weight 1 and fingers weight .5', () {
    final p = profile({'question.v1.08|faire': InitialQuestionResponse.love});
    expect(rate('022', p).rawScore, 7);
    expect(
      rate(
        '022',
        withExcluded(p, 'vaginal', ProfilePreferenceRole.recevoir),
      ).kind,
      V4RatingResultKind.excluded,
    );
  });
  test('veto is global across directions and inaccessible stages', () {
    final p = withExcluded(
      profile(),
      'immobiliser',
      ProfilePreferenceRole.recevoir,
    );
    expect(
      rate('034', p, action: '034.stage.1').kind,
      V4RatingResultKind.excluded,
    );
    expect(
      rate('034', profile(), action: '034.stage.1').kind,
      V4RatingResultKind.rated,
    );
  });
  test(
    'zone vetoes remain while obsolete mouth techniques do not veto 004',
    () {
      expect(
        rate(
          '004',
          withExcluded(profile(), 'sucer', ProfilePreferenceRole.recevoir),
        ).kind,
        V4RatingResultKind.rated,
      );
      expect(
        rate(
          '002',
          withExcluded(profile(), 'anus', ProfilePreferenceRole.general),
        ).kind,
        V4RatingResultKind.excluded,
      );
    },
  );
  test(
    '013 role exception does not create a general SOI to FAIRE fallback',
    () {
      final result = const V4CardRatingEngine().initialize(
        profile: profile(),
        variant: catalog.ratingFor('013', '013.action'),
        effectiveRole: ProfilePreferenceRole.soi,
      );
      expect(result.kind, V4RatingResultKind.unknown);
    },
  );
  test(
    'historical 20 is changed only with certain questionnaire provenance',
    () {
      final sample = profile({
        'question.v1.02|faire': InitialQuestionResponse.unsure,
      }).preferences['embrasser|faire']!.toJson();
      expect(ProfilePreference.fromJson({...sample, 'pa': 20}).pa, 18);
      expect(
        ProfilePreference.fromJson(
          {...sample, 'pa': 20}..remove('initial_response'),
        ).pa,
        20,
      );
      expect(
        ProfilePreference.fromJson({
          ...sample,
          'pa': 20,
          'source': 'autoLearned',
        }).pa,
        20,
      );
    },
  );
  test(
    'catalogue preserves stage-specific classifications and P2 non-rated feet',
    () {
      expect(catalog.ratingFor('034', '034.stage.3').primaryPreferenceTags, [
        'immobiliser',
      ]);
      expect(catalog.ratingFor('034', '034.stage.3').secondaryPreferenceTags, [
        'attacher',
        'controle',
      ]);
      expect(catalog.ratingFor('065', '065.action').primaryPreferenceTags, [
        'masturbation',
      ]);
      expect(
        catalog.ratingFor('065', '065.action').nonPreferenceData,
        contains('pieds'),
      );
    },
  );
  test(
    'production options use classified priors and ban a whole concept across directions',
    () {
      Map<String, List<ConceptActionOption>> options(
        V4Profile p,
      ) => const ConceptActionOptions().evaluate(
        catalog: catalog,
        profile: p,
        context: EngineSessionContext(
          mode: SessionMode.face_to_face,
          proximity: ProximityState.TOGETHER,
          chiliActive: 4,
          chiliUnlocked: 4,
          clothesByPlayer: const {'p': 6, 'other': 6},
          mediaCapabilitiesByPlayer: {
            for (final id in ['p', 'other']) id: MediaCapability.values.toSet(),
          },
        ),
        actor: PlayerGameProfile(playerId: 'p', preferences: const {}),
        partner: PlayerGameProfile(playerId: 'other', preferences: const {}),
        hierarchy: ProfileHierarchy(const {}),
      );
      final eligible = options(profile());
      expect(
        eligible.keys,
        containsAll(['001', '004', '013', '022', '045', '047']),
      );
      expect(eligible.keys, isNot(contains(anyOf('049', '050', '051', '052'))));
      final banned = options(
        withExcluded(profile(), 'embrasser', ProfilePreferenceRole.recevoir),
      );
      expect(banned.containsKey('002'), isFalse);
      expect(banned.containsKey('003'), isFalse);
    },
  );
  test('SOI learning role is frozen without reinterpreting an older usage', () {
    final old = nativeUsageFixture(conceptId: '013', direction: 'SOLO');
    final wire = old.toJson();
    final action = Map<String, Object?>.from(wire['resolved_action']! as Map);
    action['parameters'] = {
      ...Map<String, Object?>.from(old.resolvedAction['parameters']! as Map),
      'learning_role': 'soi',
    };
    final current = NetworkUsageProjection.fromJson({
      ...wire,
      'resolved_action': action,
    });
    expect(usageLearningOutcome(current).soloRole, LearningRole.soi);
    expect(
      usageLearningOutcome(
        NetworkUsageProjection.fromJson(current.toJson()),
      ).soloRole,
      LearningRole.soi,
    );
    expect(usageLearningOutcome(old).soloRole, LearningRole.solo);
  });
}
