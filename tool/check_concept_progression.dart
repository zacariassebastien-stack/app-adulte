import 'dart:io';
import '../test/engines/support/concept_progression_checks.dart';

void main() {
  var failed = 0;
  final checks = conceptProgressionChecks();
  for (final entry in checks.entries) {
    try {
      entry.value();
      stdout.writeln('PASS ${entry.key}');
    } catch (error) {
      failed++;
      stderr.writeln('FAIL ${entry.key}: $error');
    }
  }
  stdout.writeln('${checks.length - failed}/${checks.length} checks passed');
  if (failed > 0) exitCode = 1;
}
