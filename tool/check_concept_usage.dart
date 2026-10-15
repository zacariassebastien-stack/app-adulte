import 'dart:io';

import '../test/domain/support/concept_usage_checks.dart';

void main() {
  final checks = conceptUsageChecks();
  var failed = 0;
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
