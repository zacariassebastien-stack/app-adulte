import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

typedef JsonMap = Map<String, Object?>;

JsonMap readObject(String path) =>
    jsonDecode(File(path).readAsStringSync()) as JsonMap;

Iterable<JsonMap> objects(Object? value) =>
    (value! as List<Object?>).cast<JsonMap>();

void main() {
  late JsonMap coverage;
  late JsonMap taxonomy;
  late JsonMap catalog;
  late JsonMap decisions;
  late JsonMap expansion;

  setUpAll(() {
    coverage = readObject('docs/catalog_v3_coverage.json');
    taxonomy = readObject('assets/catalog/source/catalog_v3_taxonomy.json');
    catalog = readObject('assets/catalog/source/cards.v2.fr.json');
    decisions = readObject('docs/catalog_v3_zero_coverage_plan.json');
    expansion = readObject('docs/catalog_v3_expansion_plan.json');
  });

  test('the plan classifies exactly the 48 current zero-coverage tags', () {
    final zeroTags = (coverage['zero_coverage_tags']! as List<Object?>)
        .cast<String>()
        .toSet();
    final classifications = objects(decisions['classifications']).toList();
    final classifiedIds = classifications
        .map((item) => item['stable_id']! as String)
        .toSet();

    expect(zeroTags, hasLength(48));
    expect(classifications, hasLength(48));
    expect(classifiedIds, zeroTags);
    expect(decisions['decision_counts'], {
      'NEW_CONTENT': 25,
      'EXTEND_EXISTING': 12,
      'KEEP_UNCOVERED': 4,
      'REMOVE_OR_RECLASSIFY': 7,
    });

    final canonicalTags = {
      for (final tag in objects(taxonomy['tags']))
        tag['stable_id']! as String: tag,
    };
    final existingCards = objects(
      catalog['cards'],
    ).map((card) => card['stable_id']! as String).toSet();
    for (final item in classifications) {
      final id = item['stable_id']! as String;
      expect(canonicalTags, contains(id), reason: id);
      expect(item['key'], canonicalTags[id]!['key'], reason: id);
      expect(item['category'], canonicalTags[id]!['category'], reason: id);
      expect((item['justification']! as String).trim(), isNotEmpty, reason: id);
      if (item['decision'] == 'NEW_CONTENT') {
        expect(item['proposed_family'], isA<String>(), reason: id);
      }
      if (item['decision'] == 'EXTEND_EXISTING') {
        final targets = (item['target_card_ids']! as List<Object?>)
            .cast<String>();
        expect(targets, isNotEmpty, reason: id);
        expect(targets, everyElement(isIn(existingCards)), reason: id);
      }
    }
  });

  test('the expansion covers only planned A/B tags and stays canonical', () {
    final classifications = objects(decisions['classifications']).toList();
    final expectedCoverage = classifications
        .where(
          (item) =>
              item['decision'] == 'NEW_CONTENT' ||
              item['decision'] == 'EXTEND_EXISTING',
        )
        .map((item) => item['stable_id']! as String)
        .toSet();
    final plannedCoverage =
        (expansion['planned_zero_tag_coverage']! as List<Object?>)
            .cast<String>()
            .toSet();
    expect(plannedCoverage, expectedCoverage);
    expect(plannedCoverage, hasLength(37));
    expect(expansion['remaining_zero_coverage_after_plan'], hasLength(11));

    final canonicalTagIds = objects(
      taxonomy['tags'],
    ).map((tag) => tag['stable_id']! as String).toSet();
    final variants = <JsonMap>[];
    for (final card in objects(expansion['proposed_cards'])) {
      expect(card['distance_excluded'], isA<bool>());
      expect(card['requirements'], isA<JsonMap>());
      variants.addAll(objects(card['variants']));
    }
    for (final extension in objects(expansion['existing_card_extensions'])) {
      variants.addAll(objects(extension['new_variants']));
    }

    expect(expansion['proposed_cards'], hasLength(18));
    expect(variants, hasLength(59));
    expect(
      variants.map((variant) => variant['stable_id']).toSet(),
      hasLength(variants.length),
    );
    for (final variant in variants) {
      final id = variant['stable_id']! as String;
      final tags = (variant['tags_v3']! as List<Object?>).cast<String>();
      expect(tags, everyElement(isIn(canonicalTagIds)), reason: id);
      expect(tags.toSet().length, tags.length, reason: id);
      expect(
        tags.contains('v3.direction.faire') &&
            tags.contains('v3.direction.recevoir'),
        isFalse,
        reason: id,
      );
      expect(variant['baseEngagementLevel'], inInclusiveRange(1, 5));
      expect(variant['requirements'], isA<JsonMap>());
    }
    final zeroTags = (coverage['zero_coverage_tags']! as List<Object?>)
        .cast<String>()
        .toSet();
    final coveredByVariants = variants
        .expand(
          (variant) => (variant['tags_v3']! as List<Object?>).cast<String>(),
        )
        .where(zeroTags.contains)
        .toSet();
    expect(coveredByVariants, plannedCoverage);
  });

  test('the plan records overlap review and unresolved product choices', () {
    expect(
      expansion['status'],
      'PLAN_ONLY_DO_NOT_IMPORT_INTO_PLAYABLE_CATALOG',
    );
    expect(expansion['similarity_review'], hasLength(greaterThanOrEqualTo(5)));
    expect(
      expansion['human_product_decisions'],
      hasLength(greaterThanOrEqualTo(5)),
    );
    expect(expansion['estimates'], {
      'new_cards': 18,
      'new_card_variants': 38,
      'extension_variants': 21,
      'total_new_variants': 59,
      'estimated_playable_cards': 103,
      'estimated_playable_variants': 207,
      'zero_tags_covered_by_plan': 37,
      'estimated_remaining_zero_coverage_tags': 11,
    });
  });
}
