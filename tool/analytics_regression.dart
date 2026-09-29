import 'dart:convert';
import 'dart:io';
import 'package:couple_cards/data/catalog_loader/catalog_loader.dart';
import 'package:couple_cards/domain/domain.dart';
import 'package:couple_cards/engines/engines.dart';
import 'package:couple_cards/simulation/configuration.dart';
import 'package:couple_cards/simulation/experiment.dart';

Object? canonical(Object? value) {
  if (value is Map<String, Object?>) {
    final keys = value.keys.toList()..sort();
    return {for (final key in keys) key: canonical(value[key])};
  }
  if (value is List<Object?>) return value.map(canonical).toList();
  return value;
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    throw ArgumentError(
      'Provide Phase 4 JSON for seeds 410000..410999 (1000 sessions)',
    );
  }
  final reference =
      jsonDecode(File(args.first).readAsStringSync()) as Map<String, Object?>;
  if (reference['sessions'] != 1000 || reference['seedStart'] != 410000) {
    throw ArgumentError('Wrong reference campaign');
  }
  final catalog = await const CatalogLoader().load(
    (p) => File(p).readAsString(),
  );
  final types = <String, int>{};
  final analyticsSamples = <String, int>{};
  final buffered = <GameEvent>[];
  String? currentSession;
  var totalEvents = 0, sessionsAnalyzed = 0;
  void flush() {
    if (buffered.isEmpty) return;
    for (final player in ['a', 'b']) {
      final metrics = const AnalyticsEngine().compute(player, buffered);
      for (final e in metrics.axes.entries) {
        analyticsSamples.update(
          e.key.name,
          (v) => v + e.value.opportunities,
          ifAbsent: () => e.value.opportunities,
        );
      }
    }
    sessionsAnalyzed++;
    buffered.clear();
  }

  final watch = Stopwatch()..start();
  final result =
      BalanceExperiment(name: 'BASELINE', config: const BalanceConfig()).run(
        catalog,
        sessions: 1000,
        seed: 410000,
        scenarios: representativeScenarios(),
        onEvent: (stored) {
          if (stored.sessionId != currentSession) {
            flush();
            currentSession = stored.sessionId;
          }
          final event = GameEvent.fromStored(stored);
          buffered.add(event);
          totalEvents++;
          types.update(event.type.name, (v) => v + 1, ifAbsent: () => 1);
          if (event.publicProjection().keys.any(
            {
              'snapshot',
              'style',
              'private_analytics',
              'card_id',
              'personal_value',
            }.contains,
          )) {
            throw StateError('Private evidence escaped');
          }
        },
        progress: (n) {
          if (n % 100 == 0) stderr.writeln('$n / 1000');
        },
      );
  flush();
  watch.stop();
  final comparisons = {
    for (final key in [
      'metrics',
      'byScenario',
      'balance',
      'scenarios',
      'limits',
      'policy',
      'profileSpecs',
    ])
      key:
          jsonEncode(canonical(reference[key])) ==
          jsonEncode(canonical(result[key])),
  };
  final passed = comparisons.values.every((v) => v);
  final metrics = result['metrics']! as Map<String, Object?>;
  final d = metrics['distributions']! as Map<String, Object?>;
  final counters = metrics['counters']! as Map<String, Object?>;
  Object? mean(String name) => (d[name]! as Map<String, Object?>)['mean'];
  final hand = d['hand.size']! as Map<String, Object?>;
  final report = {
    'reference_commit': '27f5acb94532408631e2bb2c64ff2232a3a32514',
    'reference_file': args.first,
    'sessions': 1000,
    'seed_start': 410000,
    'seed_end': 410999,
    'exact_business_equality': passed,
    'comparisons': comparisons,
    'elapsed_milliseconds': watch.elapsedMilliseconds,
    'events': totalEvents,
    'sessions_analyzed': sessionsAnalyzed,
    'event_types': types,
    'analytics_opportunities': analyticsSamples,
    'business': {
      'duels': counters['duels'],
      'duels_to_50_a': mean('pa.a.duelsTo50'),
      'duels_to_50_b': mean('pa.b.duelsTo50'),
      'counter_auction_percent':
          100 *
          (counters['auction.counter']! as num) /
          (counters['duels']! as num),
      'recovery_per_session': mean('recovery.perSession'),
      'full_hand_percent':
          100 *
          ((hand['distribution']! as Map<String, Object?>)['4']! as num) /
          (hand['count']! as num),
    },
  };
  File('docs/phase45_regression.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  stdout.writeln(jsonEncode(report));
  if (!passed) exitCode = 1;
}
