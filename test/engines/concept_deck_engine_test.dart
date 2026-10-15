import 'package:test/test.dart';

import 'support/concept_deck_checks.dart';

void main() {
  for (final check in conceptDeckChecks().entries) {
    test(check.key, check.value);
  }
}
