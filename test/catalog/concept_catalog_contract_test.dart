import 'package:test/test.dart';

import 'support/concept_catalog_checks.dart';

void main() {
  for (final entry in conceptCatalogChecks().entries) {
    test(entry.key, entry.value);
  }
}
