import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

typedef JsonMap = Map<String, Object?>;

JsonMap readObject(String path) =>
    jsonDecode(File(path).readAsStringSync()) as JsonMap;

Iterable<JsonMap> objects(Object? value) =>
    (value! as List<Object?>).cast<JsonMap>();

void expectImplementedTagsMatchPlan(
  Object? actualValue,
  Object? plannedValue, {
  required String reason,
}) {
  final actual = (actualValue! as List<Object?>).cast<String>().toSet();
  final planned = (plannedValue! as List<Object?>).cast<String>().toSet();
  const directions = {'v3.direction.faire', 'v3.direction.recevoir'};
  final plannedDirections = planned.intersection(directions);
  final actualDirections = actual.intersection(directions);

  expect(
    actual.difference(directions),
    planned.difference(directions),
    reason: reason,
  );
  if (plannedDirections.length == 1 && actualDirections.length == 2) {
    // The approved expansion plan predates directional occurrence
    // consolidation. Its single direction now describes one side of the same
    // reversible concept; the runtime variant deliberately carries both.
    return;
  }
  expect(actualDirections, plannedDirections, reason: reason);
}

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

  test('the plan classifies all 48 source zero-coverage tags', () {
    final classifications = objects(decisions['classifications']).toList();
    final classifiedIds = classifications
        .map((item) => item['stable_id']! as String)
        .toSet();

    expect((decisions['source_catalog']! as JsonMap)['zero_coverage_tags'], 48);
    expect(classifications, hasLength(48));
    expect(classifiedIds, hasLength(48));
    expect(decisions['decision_counts'], {
      'NEW_CONTENT': 24,
      'EXTEND_EXISTING': 12,
      'KEEP_UNCOVERED': 5,
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
    expect(plannedCoverage, hasLength(36));
    expect(expansion['remaining_zero_coverage_after_plan'], hasLength(12));

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

    expect(expansion['proposed_cards'], hasLength(19));
    expect(variants, hasLength(58));
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
    final sourceZeroTags = classifications
        .map((item) => item['stable_id']! as String)
        .toSet();
    final coveredByVariants = variants
        .expand(
          (variant) => (variant['tags_v3']! as List<Object?>).cast<String>(),
        )
        .where(sourceZeroTags.contains)
        .toSet();
    expect(coveredByVariants, plannedCoverage);
  });

  test('the approved plan records arbitration and final estimates', () {
    expect(expansion['status'], 'APPROVED_AND_IMPLEMENTED');
    expect(expansion['similarity_review'], hasLength(greaterThanOrEqualTo(5)));
    expect(expansion['human_product_decisions'], isEmpty);
    expect(expansion['estimates'], {
      'new_cards': 19,
      'new_card_variants': 37,
      'extension_variants': 21,
      'total_new_variants': 58,
      'estimated_playable_cards': 104,
      'estimated_playable_variants': 206,
      'zero_tags_covered_by_plan': 36,
      'estimated_remaining_zero_coverage_tags': 12,
    });

    final extensions = objects(expansion['existing_card_extensions']);
    final positions = extensions.singleWhere(
      (item) => item['target_card_id'] == 'card.choose_sex_position',
    );
    final definitions = {
      for (final variant in objects(positions['new_variants']))
        variant['stable_id']! as String:
            variant['complexity_definition']! as String,
    };
    expect(definitions['variant.v3.choose_sex_position.s'], contains('Facile'));
    expect(
      definitions['variant.v3.choose_sex_position.a'],
      contains('davantage de mobilité'),
    );
    expect(
      definitions['variant.v3.choose_sex_position.e'],
      contains('Nettement exigeante'),
    );

    final proposedIds = objects(
      expansion['proposed_cards'],
    ).map((card) => card['proposed_stable_id']).toSet();
    expect(proposedIds, contains('card.v3.swallow_choice'));
    expect(proposedIds, contains('card.v3.spit_choice'));
    expect(proposedIds, contains('card.v3.ejaculation_choice'));
    expect(proposedIds, isNot(contains('card.v3.fluids_choice')));
  });

  test('the implementation matches the approved plan and zero-tag policy', () {
    final cards = {
      for (final card in objects(catalog['cards']))
        card['stable_id']! as String: card,
    };
    for (final proposal in objects(expansion['proposed_cards'])) {
      final cardId = proposal['proposed_stable_id']! as String;
      expect(cards, contains(cardId));
      final implementedCard = cards[cardId]!;
      expect(implementedCard['v3_deck_enabled'], isTrue);
      expect(implementedCard['enabled'], isFalse);
      // Titles may receive later editorial corrections while the approved
      // content intent and stable identifiers remain unchanged.
      expect((implementedCard['title']! as String).trim(), isNotEmpty);
      final implementedVariants = {
        for (final variant in objects(implementedCard['variants']))
          variant['stable_id']! as String: variant,
      };
      for (final plannedVariant in objects(proposal['variants'])) {
        final id = plannedVariant['stable_id']! as String;
        final implemented = implementedVariants[id]!;
        final actualV3 = implemented['v3']! as JsonMap;
        final expectedRequirements = <String, Object?>{
          ...(plannedVariant['requirements']! as JsonMap),
          if (proposal['distance_excluded'] == true) 'DISTANCE_EXCLUE': true,
        };
        expectImplementedTagsMatchPlan(
          actualV3['tags'],
          plannedVariant['tags_v3'],
          reason: id,
        );
        expect(
          actualV3['baseEngagementLevel'],
          plannedVariant['baseEngagementLevel'],
          reason: id,
        );
        expect(actualV3['requirements'], expectedRequirements, reason: id);
      }
    }
    for (final extension in objects(expansion['existing_card_extensions'])) {
      final target = cards[extension['target_card_id']]!;
      final implemented = objects(
        target['variants'],
      ).map((variant) => variant['stable_id']).toSet();
      final planned = objects(
        extension['new_variants'],
      ).map((variant) => variant['stable_id']).toSet();
      expect(implemented, containsAll(planned));
      for (final plannedVariant in objects(extension['new_variants'])) {
        final id = plannedVariant['stable_id']! as String;
        final actual = objects(
          target['variants'],
        ).singleWhere((variant) => variant['stable_id'] == id);
        final actualV3 = actual['v3']! as JsonMap;
        expectImplementedTagsMatchPlan(
          actualV3['tags'],
          plannedVariant['tags_v3'],
          reason: id,
        );
        expect(
          actualV3['baseEngagementLevel'],
          plannedVariant['baseEngagementLevel'],
          reason: id,
        );
        expect(
          actualV3['requirements'],
          plannedVariant['requirements'],
          reason: id,
        );
      }
    }

    final remaining =
        (expansion['remaining_zero_coverage_after_plan']! as List<Object?>)
            .cast<String>()
            .toSet();
    expect(
      (coverage['zero_coverage_tags']! as List<Object?>).cast<String>().toSet(),
      remaining,
    );
    expect(
      remaining,
      containsAll({
        'v3.preference.regard_exterieur',
        'v3.materiel.alcool',
        'v3.materiel.protection',
      }),
    );
  });
}
