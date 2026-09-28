import 'dart:convert';
import 'dart:io';
import 'package:couple_cards/data/catalog_loader/catalog_loader.dart';
import 'package:couple_cards/domain/domain.dart';
import 'package:couple_cards/engines/engines.dart';
import 'package:couple_cards/simulation/configuration.dart';
import 'package:couple_cards/simulation/experiment.dart';
import 'package:couple_cards/simulation/metrics.dart';
import 'package:couple_cards/simulation/runner.dart';
import 'package:test/test.dart';

void main() {
  late Catalog catalog;
  const scenario = SimulationScenario(
    id: 'test',
    first: {Strategy.BALANCED},
    second: {Strategy.BALANCED},
  );
  setUpAll(() async {
    catalog = await const CatalogLoader().load((p) => File(p).readAsString());
  });
  SimulationMetrics run(
    int seed, {
    SimulationLimits limits = const SimulationLimits(maxRounds: 8),
    DecisionPolicy policy = const DecisionPolicy(),
  }) => SimulationRunner(
    catalog,
    limits: limits,
    policy: policy,
  ).run(seed: seed, scenario: scenario);
  test(
    'same seed, catalogue, profiles and configuration reproduce all metrics',
    () {
      expect(jsonEncode(run(123).toJson()), jsonEncode(run(123).toJson()));
    },
  );
  test('different seeds produce variation', () {
    expect(jsonEncode(run(123).toJson()), isNot(jsonEncode(run(124).toJson())));
  });
  test(
    'representative short campaign uses real catalogue without invariant violations',
    () {
      final r =
          BalanceExperiment(
            name: 'BASELINE',
            config: const BalanceConfig(),
          ).run(
            catalog,
            sessions: 54,
            seed: 130,
            scenarios: representativeScenarios(),
            limits: const SimulationLimits(maxRounds: 6),
          );
      final metrics = r['metrics']! as Map;
      expect((metrics['counters'] as Map)['sessions'], 54);
      expect((metrics['counters'] as Map)['invariantViolations'] ?? 0, 0);
      expect(metrics['anomalies'], isEmpty);
      expect(catalog.cards.length, 100);
      final coverage = r['catalogCoverage']! as Map;
      expect((coverage['unusedTags'] as List).length, lessThan(105));
    },
  );
  test('maxRounds belongs to simulator and is respected', () {
    final r = run(123, limits: const SimulationLimits(maxRounds: 2));
    expect(r.counters['duels'] ?? 0, lessThanOrEqualTo(2));
    expect(r.frequencies['termination']!.values.fold(0, (a, b) => a + b), 1);
    expect(
      const LifecycleEngine().shouldEndSession(
        explicitHumanDecision: false,
        technicalClosure: false,
        actionPoints: 0,
        indicativeDurationReached: true,
      ),
      isFalse,
    );
  });
  test('maxActions interrupts deterministically even in a partial round', () {
    final r = run(1, limits: const SimulationLimits(maxActions: 1));
    expect(r.frequencies['termination']?['maxActions'], 1);
    expect(r.distributions['session.actions']!.histogram, {1: 1});
  });
  test('recovery budget can be zero', () {
    final r = run(
      42,
      limits: const SimulationLimits(maxRounds: 50, maxRecoveryCycles: 0),
    );
    expect(r.distributions['recovery.perSession']!.histogram, {0: 1});
  });
  test('baseline and source catalogue remain unchanged', () {
    const config = BalanceConfig();
    final before = jsonEncode(balanceJson(config));
    final source = jsonEncode(catalog.cardsDocument);
    run(15);
    expect(jsonEncode(balanceJson(config)), before);
    expect(jsonEncode(catalog.cardsDocument), source);
  });
  test('duel counts equal gap and cost observations and gaps are 0 to 19', () {
    final r = run(123);
    expect(r.distributions['duel.gap']!.count, r.counters['duels']);
    expect(r.distributions['duel.cost']!.count, r.counters['duels']);
    expect(
      r.distributions['duel.gap']!.histogram.keys.every(
        (g) => g >= 0 && g <= 19,
      ),
      isTrue,
    );
  });
  test('PA ledger reconciles for each player', () {
    final r = run(123, limits: const SimulationLimits(maxRounds: 50));
    for (final id in ['a', 'b']) {
      int n(String key) => r.counters['pa.$id.$key'] ?? 0;
      expect(
        r.distributions['pa.$id.final']!.histogram.keys.single,
        100 -
            n('duelSpent') -
            n('auctionSpent') -
            n('chiliSpent') +
            n('recoveryGain') +
            n('extensionGain'),
      );
    }
  });
  test(
    'STOP and refusals are only technical metrics, without action effects or PA penalty',
    () {
      final r = run(123, policy: const DecisionPolicy(stop: 1, renounce: 0));
      expect(r.counters['technicalStop'], greaterThan(0));
      expect(r.counters['actions.completed'] ?? 0, 0);
      expect(r.counters['invariantViolations'] ?? 0, 0);
      expect(
        r.counters.keys.any((k) => k.contains('negativeBehavior')),
        isFalse,
      );
    },
  );
  test(
    'synthetic nonaccepted preferences never become accepted through running',
    () {
      final p = syntheticProfile(
        catalog,
        'a',
        ConsentPool.CONSERVATIVE_POOL,
        SeededRandomSource(5),
      );
      final statuses = p.preferences.map((k, v) => MapEntry(k, v.status));
      expect(
        statuses.values.any((s) => s != PreferenceStatus.ACCEPTED),
        isTrue,
      );
      run(5);
      expect(p.preferences.map((k, v) => MapEntry(k, v.status)), statuses);
      expect(() => p.preferences.clear(), throwsUnsupportedError);
    },
  );
  test(
    'styles alter weights without granting permissions or drawing exhausted cards',
    () {
      final p = syntheticProfile(
        catalog,
        'a',
        ConsentPool.BROAD_POOL,
        SeededRandomSource(99),
      );
      final q = PlayerGameProfile(playerId: 'b', preferences: p.preferences);
      final cards = catalog.cards
          .map(const CatalogEngineAdapter().card)
          .toList();
      final hierarchy = ProfileHierarchy({
        for (final e in catalog.profileElements) e.stableId: e.parentId,
      });
      final context = EngineSessionContext(
        mode: SessionMode.face_to_face,
        proximity: ProximityState.TOGETHER,
        chiliActive: 5,
        chiliUnlocked: 5,
        exhaustedCardIds: {cards.first.id},
      );
      List<DrawCandidateScore> candidates(PlayerStyle style) =>
          const DrawEngine().candidates(
            cards: cards,
            context: context,
            actor: p,
            partner: q,
            hierarchy: hierarchy,
            style: style,
            history: DrawHistory(),
          );
      final soft = candidates(PlayerStyle.SOFT),
          bold = candidates(PlayerStyle.INTENABLE);
      expect(soft, isNotEmpty);
      expect(
        soft.map((c) => c.eligibility.card.id),
        bold.map((c) => c.eligibility.card.id),
      );
      expect(
        soft.map((c) => c.weight).toList(),
        isNot(bold.map((c) => c.weight).toList()),
      );
      expect(soft.any((c) => c.eligibility.card.id == cards.first.id), isFalse);
    },
  );
  test(
    'named BalanceConfig comparison is reproducible and baseline is preserved',
    () {
      Map<String, Object?> experiment(String name, BalanceConfig c) =>
          BalanceExperiment(name: name, config: c).run(
            catalog,
            sessions: 3,
            seed: 10,
            scenarios: [scenario],
            limits: const SimulationLimits(maxRounds: 4),
          );
      final b = experiment('BASELINE', const BalanceConfig());
      final e = experiment(
        'EXPERIMENTAL_TEST_ONLY',
        const BalanceConfig(initialPa: 150),
      );
      expect(experiment('BASELINE', const BalanceConfig()), b);
      expect(
        experiment(
          'EXPERIMENTAL_TEST_ONLY',
          const BalanceConfig(initialPa: 150),
        ),
        e,
      );
      expect(e['balance'], isNot(b['balance']));
    },
  );
  test('exact median and merging counters', () {
    final a = SimulationMetrics()
      ..sample('x', 1)
      ..sample('x', 5)
      ..increment('n', 2);
    final b = SimulationMetrics()
      ..sample('x', 3)
      ..sample('x', 7)
      ..increment('n');
    a.merge(b);
    expect(a.distributions['x']!.toJson()['median'], 4);
    expect(a.distributions['x']!.toJson()['mean'], 4);
    expect(a.counters['n'], 3);
  });
  test('invalid limits and probabilities are rejected', () {
    expect(
      () => run(1, limits: const SimulationLimits(maxRounds: 0)),
      throwsArgumentError,
    );
    expect(
      () => run(1, policy: const DecisionPolicy(stop: 1.1)),
      throwsArgumentError,
    );
  });
  test('strategies compose independently of consent', () {
    final profile = PlayerGameProfile(playerId: 'a');
    final p = SimulationPlayer(
      profile: profile,
      strategies: {Strategy.BOLD, Strategy.PA_SAVER},
      style: PlayerStyle.SOFT,
    );
    expect(p.has(Strategy.BOLD), isTrue);
    expect(p.probability('counter'), lessThan(.3));
    expect(profile.preferences, isEmpty);
  });
  test(
    'fully excluded synthetic pool cannot play a duel or change consent',
    () {
      final runner = SimulationRunner(
        catalog,
        profileSpecs: {
          for (final p in ConsentPool.values)
            p: const SyntheticProfileSpec(
              0,
              1,
              20,
              excludedShare: 1,
              discoverShare: 0,
            ),
        },
      );
      final r = runner.run(seed: 5, scenario: scenario);
      expect(r.counters['duels'] ?? 0, 0);
      expect(r.frequencies['termination']?['no_playable_hand'], 1);
      expect(r.counters['invariantViolations'] ?? 0, 0);
    },
  );
  test('recovery exhaustion is exercised without redrawing exhausted IDs', () {
    final r = run(123, limits: const SimulationLimits(maxRounds: 50));
    expect(r.counters['recovery.exhausted'] ?? 0, greaterThan(0));
    expect(r.counters['invariantViolations'] ?? 0, 0);
  });
  test('one normal round produces one close event, not one per player', () {
    final r = run(123, policy: const DecisionPolicy(renounce: 0));
    expect(
      r.frequencies['events']?['ROUND_CLOSED'],
      r.counters['roundsCompleted'],
    );
  });
  test('simulator remains pure Dart without storage, network or Flutter', () {
    for (final file in Directory(
      'lib/simulation',
    ).listSync().whereType<File>()) {
      final imports = file
          .readAsLinesSync()
          .where((line) => line.startsWith('import '))
          .join('\n');
      expect(imports, isNot(contains('package:flutter')));
      expect(imports, isNot(contains('drift')));
      expect(imports, isNot(contains('dart:io')));
      expect(imports, isNot(contains('http')));
    }
  });
}
