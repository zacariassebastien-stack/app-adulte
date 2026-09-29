import '../domain/domain.dart';
import 'configuration.dart';
import 'metrics.dart';
import 'runner.dart';

/// Configurations are named and isolated. Running never writes BalanceConfig.
final class BalanceExperiment {
  BalanceExperiment({required this.name, required this.config});
  final String name;
  final BalanceConfig config;
  Map<String, Object?> run(
    Catalog catalog, {
    required int sessions,
    required int seed,
    required List<SimulationScenario> scenarios,
    SimulationLimits limits = const SimulationLimits(),
    DecisionPolicy policy = const DecisionPolicy(),
    Map<ConsentPool, SyntheticProfileSpec> profileSpecs = defaultProfileSpecs,
    void Function(int)? progress,
    void Function(StoredEvent)? onEvent,
  }) {
    if (sessions < 1 || scenarios.isEmpty) {
      throw ArgumentError('A campaign requires sessions and scenarios');
    }
    final runner = SimulationRunner(
      catalog,
      config: config,
      limits: limits,
      policy: policy,
      profileSpecs: profileSpecs,
      onEvent: onEvent,
    );
    final aggregate = SimulationMetrics(),
        groups = <String, SimulationMetrics>{};
    for (var n = 0; n < sessions; n++) {
      final scenario = scenarios[n % scenarios.length];
      final result = runner.run(seed: seed + n, scenario: scenario);
      aggregate.merge(result);
      groups.putIfAbsent(scenario.id, SimulationMetrics.new).merge(result);
      if ((n + 1) % 100 == 0) progress?.call(n + 1);
    }
    return {
      'schemaVersion': 1,
      'experiment': name,
      'engineCommit': 'dcffdc82e7965122b634c75ef4555178a1289ba7',
      'sessions': sessions,
      'seedStart': seed,
      'seedEndInclusive': seed + sessions - 1,
      'allocation':
          'scenario = sessionIndex % scenarioCount; seed = seedStart + sessionIndex',
      'limits': limits.toJson(),
      'balance': balanceJson(config),
      'policy': policy.toJson(),
      'profileSpecs': {
        for (final e in profileSpecs.entries) e.key.name: e.value.toJson(),
      },
      'scenarios': scenarios.map((s) => s.toJson()).toList(),
      'metrics': aggregate.toJson(),
      'byScenario': {for (final e in groups.entries) e.key: e.value.toJson()},
      'catalogCoverage': {
        'neverEligibleCards': catalog.cards
            .map((c) => c.stableId)
            .where((id) => !aggregate.eligibleCards.contains(id))
            .toList(),
        'neverEligibleVariants': catalog.cards
            .expand((c) => c.variants)
            .map((v) => v.stableId)
            .where((id) => !aggregate.eligibleVariants.contains(id))
            .toList(),
        'neverDrawnCards': catalog.cards
            .map((c) => c.stableId)
            .where(
              (id) =>
                  !(aggregate.frequencies['draw.card'] ?? {}).containsKey(id),
            )
            .toList(),
        'unusedTags': catalog.tags
            .map((t) => t.stableId)
            .where(
              (id) =>
                  !(aggregate.frequencies['draw.tag'] ?? {}).containsKey(id) &&
                  !(aggregate.frequencies['draw.tag'] ?? {}).containsKey(
                    id.startsWith('tag.') ? id.substring(4) : id,
                  ),
            )
            .toList(),
      },
    };
  }
}
