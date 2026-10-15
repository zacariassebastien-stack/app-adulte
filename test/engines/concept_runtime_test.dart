import 'package:test/test.dart';
import 'support/concept_runtime_checks.dart';

void main() {
  for (final entry in conceptRuntimeChecks().entries) {
    test(entry.key, entry.value);
  }
}
