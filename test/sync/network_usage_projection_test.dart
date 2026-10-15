import 'package:test/test.dart';

import 'support/network_usage_checks.dart';

void main() {
  for (final check in networkUsageChecks().entries) {
    test(check.key, check.value);
  }
}
