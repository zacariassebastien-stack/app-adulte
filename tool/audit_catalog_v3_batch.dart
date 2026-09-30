import 'dart:convert';
import 'dart:io';

import 'package:couple_cards/data/catalog_loader/catalog_loader.dart';
import 'package:couple_cards/domain/domain.dart';

void main(List<String> args) {
  const source = 'assets/catalog/source';
  final outputPath = args.isEmpty
      ? 'docs/catalog_v3_cards_1_30.json'
      : args.first;
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
  final tags = {for (final tag in taxonomy.tags) tag.stableId: tag};

  Map<String, Object?> entry(
    String id,
    V3EditorialData data,
    Map<String, Object?> raw,
  ) => {
    'id': id,
    'tags': data.tags,
    'directions': [
      for (final id in data.tags)
        if (tags[id]?.category == V3TagCategory.DIRECTION) tags[id]!.key,
    ],
    'baseEngagementLevel': data.baseEngagementLevel,
    'distanceExcluded': data.requirements.distanceExcluded,
    'requirements': raw['requirements']! as Map<String, Object?>,
    'clothingDelta': raw['clothingDelta'],
    'mergeCandidateWith': data.mergeCandidateWith,
    'ambiguities': data.ambiguities,
  };

  final cards = <Map<String, Object?>>[];
  for (final card in catalog.cards.where(
    (card) => card.order != null && card.order! <= 30,
  )) {
    final data = card.v3!;
    final raw = card.toJson()['v3']! as Map<String, Object?>;
    cards.add({
      'order': card.order,
      'title': card.title,
      ...entry(card.stableId, data, raw),
      'variants': [
        for (final variant in card.variants)
          entry(
            variant.stableId,
            variant.v3!,
            variant.toJson()['v3']! as Map<String, Object?>,
          ),
      ],
    });
  }
  final report = {
    'schema_version': 1,
    'catalogue_taxonomy_version': 3,
    'range': {'from': 1, 'to': 30},
    'cards': cards,
  };
  final encoded = const JsonEncoder.withIndent('  ').convert(report);
  File(outputPath).writeAsStringSync('$encoded\n');
  stdout.writeln(encoded);
}
