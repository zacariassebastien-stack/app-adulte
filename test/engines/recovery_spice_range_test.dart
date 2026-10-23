import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:couple_cards/data/catalog_loader/catalog_loader.dart';
import 'package:couple_cards/domain/domain.dart';
import 'package:couple_cards/engines/engines.dart';
import 'package:couple_cards/engines/eligibility/concept_action_options.dart';
import 'package:couple_cards/engines/eligibility/concept_runtime_catalog.dart';

void main() {
  late ConceptRuntimeCatalog runtime;
  late V4Profile profile;
  setUpAll(() async {
    final catalog = await const CatalogLoader().load(
      (path) => File(path).readAsString(),
      includeConcepts: true,
    );
    runtime = ConceptRuntimeCatalog(
      concepts: catalog.concepts!,
      source: catalog,
      rules: catalog.conceptRules!,
    );
    final questionnaire = ProfileQuestionnaire.decode(
      File(
        'assets/catalog/source/profile_questions.v1.fr.json',
      ).readAsStringSync(),
    );
    profile = const InitialQuestionnaireEngine().initialize(
      profileId: 'a',
      sex: ProfileSex.HOMME,
      questionnaire: questionnaire,
      responses: {
        for (final question in questionnaire.questions)
          for (final axis in question.axes)
            '${question.stableId}|${axis.axisId}': InitialQuestionResponse.like,
      },
    );
  });
  Map<String, List<ConceptActionOption>> options(
    int reference, {
    bool recovery = true,
    int privateChili = 1,
    int clothing = 6,
    V4Profile? vetoedProfile,
  }) => const ConceptActionOptions().evaluate(
    catalog: runtime,
    profile: vetoedProfile ?? profile,
    context: EngineSessionContext(
      mode: SessionMode.face_to_face,
      proximity: ProximityState.TOGETHER,
      chiliActive: privateChili,
      chiliUnlocked: privateChili,
      clothesByPlayer: {'a': clothing, 'b': clothing},
    ),
    actor: PlayerGameProfile(playerId: 'a', preferences: const {}),
    partner: PlayerGameProfile(playerId: 'b', preferences: const {}),
    hierarchy: ProfileHierarchy({}),
    recovery: recovery,
    recoveryMinimumChili: reference,
  );
  for (final reference in [1, 2, 3, 4]) {
    test(
      'Recovery spice range P$reference to P4 ignores private initial chili',
      () {
        final choices = options(reference).values.expand((v) => v).toList();
        expect(choices, isNotEmpty);
        expect(
          choices.every(
            (o) => o.choice.chili >= reference && o.choice.chili <= 4,
          ),
          isTrue,
        );
        expect(choices.any((o) => o.choice.chili == reference), isTrue);
        expect(choices.any((o) => o.choice.chili == 4), isTrue);
        if (reference < 4) {
          expect(choices.any((o) => o.choice.chili > reference), isTrue);
        }
      },
    );
  }
  test('Recovery spice exception does not change normal chili ceiling', () {
    expect(
      options(
        4,
        recovery: false,
      ).values.expand((v) => v).every((o) => o.choice.chili <= 1),
      isTrue,
    );
    expect(
      options(1).values.expand((v) => v).any((o) => o.choice.chili == 4),
      isTrue,
    );
  });
  test('Recovery spice range never bypasses veto or clothing context', () {
    final vetoed = profile.copyWith(
      stageVetoes: const [
        StageVeto(
          conceptId: '030',
          actionId: '*',
          role: ProfilePreferenceRole.general,
        ),
      ],
    );
    expect(options(1), contains('030'));
    expect(options(1, vetoedProfile: vetoed), isNot(contains('030')));
    expect(options(1, clothing: 1), contains('006'));
    expect(options(1, clothing: 0), isNot(contains('006')));
  });
}
