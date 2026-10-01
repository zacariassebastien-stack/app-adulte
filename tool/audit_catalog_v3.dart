import 'dart:convert';
import 'dart:io';

import 'package:couple_cards/data/catalog_loader/catalog_loader.dart';
import 'package:couple_cards/domain/domain.dart';

void main(List<String> args) {
  const source = 'assets/catalog/source';
  final outputPath = args.isEmpty ? null : args.first;
  final catalog = const CatalogLoader().loadJson(
    cardsJson: File('$source/cards.v2.fr.json').readAsStringSync(),
    profilesJson: File(
      '$source/profile_elements.v1.fr.json',
    ).readAsStringSync(),
    tagsJson: File('$source/tags.v1.json').readAsStringSync(),
  );
  final taxonomy = V3Taxonomy.decode(
    File('$source/catalog_v3_taxonomy.json').readAsStringSync(),
  );
  final scenarios = RoleplayScenarioLibrary.decode(
    File('$source/roleplay_scenarios.v1.fr.json').readAsStringSync(),
  );
  final report = const V3CoverageReportBuilder().build(
    catalog,
    taxonomy,
    scenarios,
  );
  final encoded = const JsonEncoder.withIndent('  ').convert(report);
  if (outputPath != null) File(outputPath).writeAsStringSync('$encoded\n');
  if (args.length > 1) {
    final scenarioReport = {
      'schema_version': 1,
      'scenario_count': scenarios.scenarios.length,
      'scenarios': [
        for (final scenario in scenarios.scenarios)
          {
            'stable_id': scenario.stableId,
            'title': scenario.title,
            'enabled': scenario.enabled,
            'roles': scenario.roles,
            'legacy_card_id': scenario.legacyCardId,
            'legacy_profile_id': scenario.legacyProfileId,
            'legacy_tag_id': scenario.legacyTagId,
          },
      ],
    };
    File(args[1]).writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(scenarioReport)}\n',
    );
  }
  stdout.writeln(encoded);
}
