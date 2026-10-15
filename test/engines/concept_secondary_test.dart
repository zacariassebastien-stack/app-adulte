import 'package:test/test.dart';
import 'support/concept_secondary_checks.dart';

void main() {
  for (final entry in conceptSecondaryChecks().entries) {
    test(entry.key, entry.value);
  }
}
