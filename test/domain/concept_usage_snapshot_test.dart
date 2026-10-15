import 'package:test/test.dart';

import 'support/concept_usage_checks.dart';

void main() {
  for (final check in conceptUsageChecks().entries) {
    test(check.key, check.value);
  }
}
