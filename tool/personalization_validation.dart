// Small reproducible validation harness, not a production calibration/search.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:couple_cards/domain/domain.dart';
import 'package:couple_cards/data/catalog_loader/catalog_loader.dart';
import 'package:couple_cards/engines/profile/card_personalization_engine.dart';
import 'package:couple_cards/engines/profile/v4_card_rating_engine.dart';
import 'package:couple_cards/engines/profile/initial_questionnaire_engine.dart';
import 'package:couple_cards/engines/eligibility/concept_runtime_catalog.dart';
import 'package:couple_cards/engines/eligibility/concept_action_options.dart';
import 'package:couple_cards/engines/deck/concept_deck_engine.dart';

const key = CardRatingKey(
  profileId: 'p',
  cardId: 'probe',
  variantId: 'probe.action',
  role: ProfilePreferenceRole.faire,
);
const candidate = PersonalizationConfig(); // Validate the production defaults.
Map<String, Object?> trajectories(
  PersonalizationConfig config,
  double probability, {
  required int sessionLength,
}) {
  final engine = CardPersonalizationEngine(config: config);
  var sum = 0.0, positive = 0, negative = 0, proposals = 0;
  for (var seed = 0; seed < 200; seed++) {
    final random = Random(270000 + seed);
    final store = CardSpecificLearningStore();
    String? previous;
    var up = false, down = false;
    for (var i = 0; i < 240; i++) {
      final chosen = random.nextDouble() < probability;
      engine.observe(
        store: store,
        key: key,
        prior: 7.5,
        tags: const {'primary': 1, 'secondary': .5},
        eventId: '$seed/$i',
        signal: chosen
            ? PersonalizationSignal.chosen
            : PersonalizationSignal.nonChoice,
        enabled: true,
        exposureEpisode: chosen ? null : 'session-${i ~/ sessionLength}',
      );
      final pending = store.read(key)!.personalization['pending'] as String?;
      if (pending != null && pending != previous) proposals++;
      final value = (store.read(key)!.personalization['internal']! as num)
          .toDouble();
      if (pending != null) {
        if (value < 7.5) {
          up = true;
        } else {
          down = true;
        }
      }
      previous = pending;
    }
    sum += (store.read(key)!.personalization['internal']! as num).toDouble();
    if (up) {
      positive++;
    }
    if (down) {
      negative++;
    }
    if (store.referenceEstimate(key) != 7.5) {
      throw StateError('Silent official change');
    }
  }
  return {
    'trajectories': 200,
    'decisions_per_trajectory': 240,
    'session_length': sessionLength,
    'choice_probability': probability,
    'mean_internal': sum / 200,
    'positive_proposal_pct': positive / 2,
    'negative_proposal_pct': negative / 2,
    'new_pending_transitions': proposals,
  };
}

Map<String, Object?> reversal() {
  const engine = CardPersonalizationEngine(config: candidate);
  final store = CardSpecificLearningStore();
  for (var i = 0; i < 200; i++) {
    engine.observe(
      store: store,
      key: key,
      prior: 7.5,
      tags: const {'a': 1},
      eventId: 'positive-$i',
      signal: PersonalizationSignal.chosen,
      enabled: true,
    );
  }
  final saturated = store.read(key)!.personalization['internal'];
  int? recovered;
  for (var i = 0; i < 1000; i++) {
    engine.observe(
      store: store,
      key: key,
      prior: 7.5,
      tags: const {'a': 1},
      eventId: 'negative-$i',
      signal: PersonalizationSignal.nonChoice,
      enabled: true,
      exposureEpisode: 'long-session',
    );

    if (recovered == null &&
        (store.read(key)!.personalization['internal']! as num) > 7.5) {
      recovered = i + 1;
    }
  }
  return {
    'saturated': saturated,
    'final_internal': store.read(key)!.personalization['internal'],
    'negative_observations_to_cross_reference': recovered,
    'official': store.referenceEstimate(key),
  };
}

Map<String, Object?> repeatedPreference(int choicesPerGame) {
  const engine = CardPersonalizationEngine(config: candidate);
  final store = CardSpecificLearningStore();
  var proposed = false;
  for (var game = 0; game < 40; game++) {
    for (var choice = 0; choice < choicesPerGame; choice++) {
      engine.observe(
        store: store,
        key: key,
        prior: 7.5,
        tags: const {'a': 1},
        eventId: '$game/$choice',
        signal: PersonalizationSignal.chosen,
        enabled: true,
      );
      proposed =
          proposed || store.read(key)!.personalization['pending'] != null;
    }
  }
  return {
    'games': 40,
    'choices_per_game': choicesPerGame,
    'internal': store.read(key)!.personalization['internal'],
    'ever_proposed': proposed,
    'official': store.referenceEstimate(key),
  };
}

Future<Map<String, Object?>> drawCheck() async {
  final catalog = await const CatalogLoader().load(
    (p) => File(p).readAsString(),
    includeConcepts: true,
  );
  final questionnaire = ProfileQuestionnaire.decode(
    File(
      'assets/catalog/source/profile_questions.v1.fr.json',
    ).readAsStringSync(),
  );
  final profile = const InitialQuestionnaireEngine().initialize(
    profileId: 'p',
    sex: ProfileSex.HOMME,
    questionnaire: questionnaire,
    responses: {
      for (final q in questionnaire.questions)
        for (final a in q.axes)
          '${q.stableId}|${a.axisId}': InitialQuestionResponse.like,
    },
  );
  final runtime = ConceptRuntimeCatalog(
    concepts: catalog.concepts!,
    source: catalog,
    rules: catalog.conceptRules!,
  );
  final options = const ConceptActionOptions().evaluate(
    catalog: runtime,
    profile: profile,
    context: EngineSessionContext(
      mode: SessionMode.face_to_face,
      proximity: ProximityState.TOGETHER,
      chiliActive: 4,
      chiliUnlocked: 4,
      clothesByPlayer: const {'p': 6, 'other': 6},
      flags: const {
        'hasConstraintAccessory': true,
        'hasRoleplayScenario': true,
      },
      mediaCapabilitiesByPlayer: {
        'p': MediaCapability.values.toSet(),
        'other': MediaCapability.values.toSet(),
      },
    ),
    actor: PlayerGameProfile(playerId: 'p'),
    partner: PlayerGameProfile(playerId: 'other'),
    hierarchy: ProfileHierarchy({
      for (final e in catalog.profileElements) e.stableId: e.parentId,
    }),
  );
  final pool = const ConceptDeckEngine().prepare(
    catalog: catalog.concepts!,
    stock: ConceptDeckStock.startCycle(
      catalog: catalog.concepts!,
      initialClothing: 6,
    ),
    globalChili: 4,
    style: PlayerStyle.EPICE,
    eligibility: ConceptDeckEligibility(
      actionIdsByConcept: {
        for (final e in options.entries)
          e.key: e.value.map((o) => o.choice.actionId).toSet(),
      },
      zoneIdsByConcept: {
        for (final e in options.entries)
          e.key: catalog.concepts!.zones.map((z) => z.id).toSet(),
      },
    ),
  );
  final baseline = <String, int>{}, weighted = <String, int>{};
  final classes = <int, int>{};
  final rng = Random(271234);
  const engine = CardPersonalizationEngine();
  for (var i = 0; i < 24000; i++) {
    final c = pool.draw(rng)!;
    baseline.update(c.concept.id, (n) => n + 1, ifAbsent: () => 1);
    final w = pool.draw(
      rng,
      preferenceWeight: (c) => engine.drawWeight(
        CardSpecificLearningStore(),
        key,
        1 + (int.parse(c.concept.id) % 20).toDouble(),
        const {},
      ),
    )!;
    weighted.update(w.concept.id, (n) => n + 1, ifAbsent: () => 1);
    classes.update(w.drawClass, (n) => n + 1, ifAbsent: () => 1);
  }
  return {
    'note':
        'synthetic favorable context; not a replacement for network eligibility tests',
    'draws_per_arm': 24000,
    'eligible_concepts': pool.candidates.length,
    'baseline_seen': baseline.length,
    'weighted_seen': weighted.length,
    'minimum_weighted_count': weighted.values.reduce(min),
    'class_frequencies': {
      for (final e in classes.entries) e.key.toString(): e.value / 24000,
    },
    'class_targets': {
      for (final e in pool.probabilities.entries) e.key.toString(): e.value,
    },
  };
}

Future<void> main() async {
  final result = <String, Object?>{
    'seed': 270000,
    'production_defaults_changed': true,
    'production_config': {
      'choice': candidate.choice,
      'nonChoice': candidate.nonChoice,
      'decay': candidate.repeatDecay,
      'floor': candidate.repeatFloor,
    },
    'controlled': <Object?>[
      for (final length in [240, 20])
        for (final p in [0.0, .25, .5, .95])
          trajectories(candidate, p, sessionLength: length),
    ],
    'reversal': reversal(),
    'repeated_preference': [repeatedPreference(2), repeatedPreference(10)],
    'draw': await drawCheck(),
  };
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(result));
}
