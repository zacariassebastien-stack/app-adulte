import 'dart:convert';
import 'dart:io';

import 'package:couple_cards/data/catalog_loader/catalog_loader.dart';
import 'package:couple_cards/domain/domain.dart';

void main(List<String> args) {
  const source = 'assets/catalog/source';
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
  final report = const V3ConsolidationReportBuilder().build(
    catalog,
    taxonomy,
    scenarios,
  );
  final encoded = const JsonEncoder.withIndent('  ').convert(report);
  if (args.isNotEmpty) File(args.first).writeAsStringSync('$encoded\n');
  stdout.writeln(encoded);
}
