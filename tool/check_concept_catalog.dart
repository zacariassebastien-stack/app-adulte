import 'dart:io';

import '../test/catalog/support/concept_catalog_checks.dart';

/// Run from the repository root. Uses the exact same pure checks as package:test.
void main() {
  var failed = 0;
  final checks = conceptCatalogChecks();
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
