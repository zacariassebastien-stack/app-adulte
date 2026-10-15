import 'dart:io';

import '../test/engines/support/concept_deck_checks.dart';

/// Runs the same pure deck checks registered with package:test.
void main() {
  var failed = 0;
  final checks = conceptDeckChecks();
  for (final check in checks.entries) {
    try {
      check.value();
      stdout.writeln('PASS ${check.key}');
    } catch (error, stack) {
      failed++;
      stderr.writeln('FAIL ${check.key}: $error\n$stack');
    }
  }
  stdout.writeln('${checks.length - failed}/${checks.length} checks passed');
  if (failed > 0) exitCode = 1;
}
