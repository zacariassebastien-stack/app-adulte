import 'dart:io';
import 'dart:convert';

import 'package:couple_cards/domain/domain.dart';
import 'package:couple_cards/engines/profile/initial_questionnaire_engine.dart';
import 'package:couple_cards/features/game/network_profile_learning.dart';
import 'package:test/test.dart';

void main() {
  late ProfileQuestionnaire questionnaire;

  setUpAll(() {
    questionnaire = ProfileQuestionnaire.decode(
      File(
        'assets/catalog/source/profile_questions.v1.fr.json',
      ).readAsStringSync(),
    );
  });

  test('editorial changes preserve every functional field', () {
    final actual =
        jsonDecode(
              File(
                'assets/catalog/source/profile_questions.v1.fr.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final questions = (actual['questions'] as List)
        .cast<Map<String, dynamic>>();
    expect(questions[1]['label'], 'Embrasser');
    expect(
      questions[1]['help_text'],
      'Embrasser son partenaire, des baisers tendres aux baisers plus intenses.',
    );
    expect(questions[7]['label'], 'Pénétration vaginale');
    for (final question in questions) {
      if (question['stable_id'] == 'question.v1.08') {
        expect(question['help_text'], isNull);
      } else {
        expect((question['help_text'] as String).trim(), isNotEmpty);
      }
      question.remove('label');
      question.remove('help_text');
    }
    expect(
      actual,
      jsonDecode(
        File(
          'test/fixtures/questionnaire_functional_contract.json',
        ).readAsStringSync(),
      ),
    );
  });

  test(
    'manual UX corrections describe themes without changing questionnaire bindings',
    () {
      final expected = {
        'question.v1.06':
            'Stimulation des zones intimes par différents moyens.',
        'question.v1.10':
            'Pratique ne nécessitant pas forcément la participation du partenaire.',
        'question.v1.12':
            'Exploration tactile pouvant inclure des sensations physiques plus intenses.',
        'question.v1.13':
            'Jeux autour du contrôle, de l’abandon et de la dynamique de pouvoir.',
        'question.v1.15':
            'Partager et explorer son intimité avec l’autre, notamment à travers différents médias.',
      };
      for (final question in questionnaire.questions) {
        if (expected.containsKey(question.stableId)) {
          expect(question.helpText, expected[question.stableId]);
        }
      }
      expect(
        questionnaire.questions
            .singleWhere((q) => q.stableId == 'question.v1.08')
            .helpText,
        isNull,
      );
    },
  );

  test('V1 contains exactly 17 data-driven questions', () {
    expect(questionnaire.version, 1);
    expect(questionnaire.questions, hasLength(17));
    expect(
      questionnaire.questions.map((item) => item.order),
      orderedEquals(List.generate(17, (index) => index + 1)),
    );
  });

  test('new profile uses 5, 12, 18 and exclusion without numeric PA', () {
    final responses = _responses(questionnaire, InitialQuestionResponse.unsure);
    responses['question.v1.02|faire'] = InitialQuestionResponse.love;
    responses['question.v1.02|recevoir'] = InitialQuestionResponse.like;
    responses['question.v1.09|faire'] = InitialQuestionResponse.excluded;
    final profile = const InitialQuestionnaireEngine().initialize(
      sex: ProfileSex.HOMME,
      profileId: 'p',
      questionnaire: questionnaire,
      responses: responses,
    );

    expect(
      _preference(profile, 'embrasser', ProfilePreferenceRole.faire).pa,
      5,
    );
    expect(
      _preference(profile, 'embrasser', ProfilePreferenceRole.recevoir).pa,
      12,
    );
    expect(
      _preference(profile, 'nourriture', ProfilePreferenceRole.general).pa,
      18,
    );
    final excluded = _preference(profile, 'anal', ProfilePreferenceRole.faire);
    expect(excluded.excluded, isTrue);
    expect(excluded.pa, isNull);
  });

  test('FAIRE never fills RECEVOIR and MUTUEL has one entry', () {
    final responses = _responses(questionnaire, InitialQuestionResponse.like);
    responses['question.v1.02|faire'] = InitialQuestionResponse.love;
    responses['question.v1.02|recevoir'] = InitialQuestionResponse.excluded;
    final profile = const InitialQuestionnaireEngine().initialize(
      sex: ProfileSex.HOMME,
      profileId: 'p',
      questionnaire: questionnaire,
      responses: responses,
    );
    expect(
      _preference(profile, 'embrasser', ProfilePreferenceRole.faire).pa,
      5,
    );
    expect(
      _preference(
        profile,
        'embrasser',
        ProfilePreferenceRole.recevoir,
      ).excluded,
      isTrue,
    );
    expect(profile.preferences.keys.where((key) => key.startsWith('calin|')), [
      'calin|mutuel',
    ]);
  });

  test('Q15 uses MOST_RESTRICTIVE for mutual media priors', () {
    final responses = _responses(questionnaire, InitialQuestionResponse.like);
    responses['question.v1.15|montrer'] = InitialQuestionResponse.love;
    responses['question.v1.15|regarder'] = InitialQuestionResponse.unsure;
    var profile = const InitialQuestionnaireEngine().initialize(
      sex: ProfileSex.HOMME,
      profileId: 'p',
      questionnaire: questionnaire,
      responses: responses,
    );
    expect(
      _preference(profile, 'photo_mutuelle', ProfilePreferenceRole.mutuel).pa,
      18,
    );
    responses['question.v1.15|regarder'] = InitialQuestionResponse.excluded;
    profile = const InitialQuestionnaireEngine().initialize(
      sex: ProfileSex.HOMME,
      profileId: 'p',
      questionnaire: questionnaire,
      responses: responses,
    );
    expect(
      _preference(
        profile,
        'video_mutuelle',
        ProfilePreferenceRole.mutuel,
      ).excluded,
      isTrue,
    );
  });

  test('expanded priors match the normative Q05/Q06/Q12/Q13 mappings', () {
    Set<String> writes(int order) => questionnaire.questions
        .singleWhere((question) => question.order == order)
        .axes
        .expand((axis) => axis.writes)
        .map((write) => write.tagId)
        .toSet();

    expect(
      writes(5),
      containsAll(<String>{
        'nudite',
        'enlever',
        'sous_vetements',
        'striptease',
        'tenue',
      }),
    );
    expect(
      writes(6),
      containsAll(<String>{
        'jeu_intime',
        'masturbation',
        'doigts',
        'facesitting',
        'ejaculation',
        'pieds',
      }),
    );
    expect(
      writes(6).intersection({'oral', 'anal', 'vaginal', 'sextoy'}),
      isEmpty,
    );
    expect(
      writes(12),
      containsAll(<String>{
        'frapper',
        'tirer',
        'maintien_cou',
        'temperature',
        'texture',
      }),
    );
    expect(
      writes(13),
      containsAll(<String>{
        'controle',
        'ordres',
        'position',
        'attacher',
        'immobiliser',
        'privation_sensorielle',
        'privation_parole',
        'supplier',
        'degradant',
      }),
    );
  });

  test('Q16 and Q17 keep their alternatives independently initialized', () {
    final profile = const InitialQuestionnaireEngine().initialize(
      sex: ProfileSex.HOMME,
      profileId: 'p',
      questionnaire: questionnaire,
      responses: _responses(questionnaire, InitialQuestionResponse.like),
    );
    for (final tag in const [
      'nourriture',
      'boisson',
      'douche_partagee',
      'bain_partage',
    ]) {
      expect(
        profile.preferences.values.any(
          (preference) => preference.key.tagId == tag && preference.pa == 12,
        ),
        isTrue,
        reason: tag,
      );
    }
  });

  test(
    'MUTUEL remains usable through the current gameplay profile adapter',
    () {
      final profile = const InitialQuestionnaireEngine().initialize(
        sex: ProfileSex.HOMME,
        profileId: 'p',
        questionnaire: questionnaire,
        responses: _responses(questionnaire, InitialQuestionResponse.love),
      );
      final gameplay = playerGameProfileFromLearningState(
        adaptiveProfileFromV4Profile(profile),
      );

      expect(gameplay.preference('v3.preference.calin').general, 5);
    },
  );

  test('preference initialization never creates PracticeConsent', () {
    for (final response in const [
      InitialQuestionResponse.love,
      InitialQuestionResponse.like,
      InitialQuestionResponse.unsure,
    ]) {
      final profile = const InitialQuestionnaireEngine().initialize(
        sex: ProfileSex.HOMME,
        profileId: 'p',
        questionnaire: questionnaire,
        responses: _responses(questionnaire, response),
      );
      expect(profile.consents, isEmpty, reason: response.name);
    }
  });

  test('preferences and explicit consents round-trip independently', () {
    final preference = _value(
      'embrasser',
      5,
      role: ProfilePreferenceRole.faire,
    );
    const consent = PracticeConsent(
      profileId: 'p',
      practiceTagId: 'embrasser',
      role: ProfilePreferenceRole.recevoir,
      status: PracticeConsentStatus.excluded,
      source: PracticeConsentSource.manualExplicit,
    );
    final restored = V4Profile.fromJson(
      V4Profile(
        sex: ProfileSex.HOMME,
        profileId: 'p',
        preferences: {preference.key.storageKey: preference},
        consents: {consent.storageKey: consent},
      ).toJson(),
    );

    expect(
      restored
          .preference(
            const ProfilePreferenceKey(
              tagId: 'embrasser',
              role: ProfilePreferenceRole.faire,
            ),
          )
          ?.pa,
      5,
    );
    expect(
      restored
          .consent(
            practiceTagId: 'embrasser',
            role: ProfilePreferenceRole.recevoir,
          )
          ?.status,
      PracticeConsentStatus.excluded,
    );
  });
}

Map<String, InitialQuestionResponse> _responses(
  ProfileQuestionnaire questionnaire,
  InitialQuestionResponse value,
) => {
  for (final question in questionnaire.questions)
    for (final axis in question.axes)
      '${question.stableId}|${axis.axisId}': value,
};

ProfilePreference _preference(
  V4Profile profile,
  String tag,
  ProfilePreferenceRole role,
) => profile.preference(ProfilePreferenceKey(tagId: tag, role: role))!;

ProfilePreference _value(
  String tag,
  double pa, {
  required ProfilePreferenceRole role,
}) => ProfilePreference(
  profileId: 'p',
  key: ProfilePreferenceKey(tagId: tag, role: role),
  pa: pa,
  excluded: false,
  source: ProfilePreferenceSource.initialQuestionnaire,
);
