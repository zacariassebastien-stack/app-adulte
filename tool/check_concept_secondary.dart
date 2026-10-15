import 'dart:io';
import '../test/engines/support/concept_secondary_checks.dart';

void main() {
  final checks = conceptSecondaryChecks();
  var failed = 0;
  for (final entry in checks.entries) {
    try {
      entry.value();
      stdout.writeln('PASS ${entry.key}');
    } catch (error, stack) {
      failed++;
      stderr.writeln('FAIL ${entry.key}: $error\n$stack');
    }
  }
  stdout.writeln('${checks.length - failed}/${checks.length} checks passed');
  if (failed > 0) exitCode = 1;
}
