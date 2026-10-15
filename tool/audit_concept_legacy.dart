import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final reportFile = File('docs/concept_legacy_consumers.json');
  final report =
      jsonDecode(reportFile.readAsStringSync()) as Map<String, dynamic>;
  final prior = (report['references'] as List).cast<Map<String, dynamic>>();
  final templates = {for (final row in prior) row['file'] as String: row};
  final files =
      Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  final references = <Map<String, dynamic>>[];
  final pattern = RegExp(r'\boccurrence_id\b|\boccurrenceId\b');
  for (final file in files) {
    final path = file.path.replaceAll('\\', '/');
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      if (!pattern.hasMatch(lines[i])) continue;
      final template = templates[path];
      if (template == null) {
        throw StateError('Unclassified legacy consumer: $path:${i + 1}');
      }
      references.add({
        ...template,
        'file': path,
        'line': i + 1,
        'text': lines[i].trim(),
      });
    }
  }
  if (args.contains('--update')) {
    report['references'] = references;
    report['reference_count'] = references.length;
    reportFile.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(report)}\n',
    );
  }
  var checked = 0;
  void check(bool condition, String message) {
    if (!condition) throw StateError(message);
    checked++;
    stdout.writeln('PASS $message');
  }

  check(
    jsonEncode(report['references']) == jsonEncode(references),
    'Every remaining legacy identity reference under lib is located and classified (${references.length})',
  );
  final native = File('lib/sync/rounds/network_game.dart').readAsStringSync();
  check(
    !native.contains('occurrence_id') && !native.contains('occurrenceId'),
    'Native secondary DTOs contain no occurrence identity or legacy decoder',
  );
  final lib = files.map((f) => f.readAsStringSync()).join('\n');
  check(
    !RegExp(
      r'class (SessionDeckBuilderV3|HybridSessionDecks|HybridDrawWeighting|SessionDeckRuntime|DeckShortage)\b',
    ).hasMatch(lib),
    'Obsolete deck builders hybrid weighting and shortage substitution types are absent',
  );
  check(
    !File('lib/engines/deck/session_deck_builder.dart').existsSync() &&
        File('lib/engines/deck/deck_cycle_state.dart').existsSync(),
    'Only the still-consumed deck cycle definitions remain in their own file',
  );
  stdout.writeln('$checked structural checks passed');
}
