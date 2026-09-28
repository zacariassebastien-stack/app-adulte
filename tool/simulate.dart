import 'dart:convert';
import 'dart:io';
import 'package:couple_cards/data/catalog_loader/catalog_loader.dart';
import 'package:couple_cards/domain/domain.dart';
import 'package:couple_cards/simulation/configuration.dart';
import 'package:couple_cards/simulation/experiment.dart';

Future<void> main(List<String> args) async {
  String option(String name, String fallback) {
    final i = args.indexOf('--$name');
    if (i < 0) return fallback;
    if (i + 1 >= args.length) throw ArgumentError('Missing --$name value');
    return args[i + 1];
  }

  final sessions = int.parse(option('sessions', '100'));
  final seed = int.parse(option('seed', '410000'));
  final rounds = int.parse(option('rounds', '50'));
  final maxActions = int.parse(option('actions', '5000'));
  final output = option('output', '.tooling/simulation.json');
  final filter = option('scenario', 'all');
  final catalog = await const CatalogLoader().load(
    (path) => File(path).readAsString(),
  );
  final scenarios = representativeScenarios()
      .where((s) => filter == 'all' || s.id == filter)
      .toList();
  final watch = Stopwatch()..start();
  final report =
      BalanceExperiment(name: 'BASELINE', config: const BalanceConfig()).run(
        catalog,
        sessions: sessions,
        seed: seed,
        scenarios: scenarios,
        limits: SimulationLimits(maxRounds: rounds, maxActions: maxActions),
        progress: (n) {
          if (n % 1000 == 0) stderr.writeln('$n / $sessions sessions');
        },
      );
  watch.stop();
  report['execution'] = {
    'elapsedMilliseconds': watch.elapsedMilliseconds,
    'runtime': Platform.version,
    'os': Platform.operatingSystem,
  };
  final file = File(output);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  stdout.writeln(
    jsonEncode({
      'sessions': sessions,
      'milliseconds': watch.elapsedMilliseconds,
      'report': output,
    }),
  );
}
