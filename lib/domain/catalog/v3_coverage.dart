import 'catalog.dart';
import 'definitions.dart';
import 'enums.dart';
import 'v3_taxonomy.dart';

const _reportedDirections = <String>[
  'FAIRE',
  'RECEVOIR',
  'SOLO',
  'MUTUEL',
  'SIMULTANE',
];

final class V3CoverageReportBuilder {
  const V3CoverageReportBuilder();

  Map<String, Object?> build(Catalog catalog, V3Taxonomy taxonomy) {
    final excludedCards = taxonomy.roleplayScenarioCardIds.toSet();
    final mappings = {
      for (final mapping in taxonomy.legacyMappings)
        mapping.legacyTagId: mapping.v3TagIds,
    };
    final entries = {
      for (final tag in taxonomy.tags) tag.stableId: _MutableCoverage(tag),
    };
    final unmapped = <String>{};
    var variantCount = 0;

    for (final card in catalog.cards) {
      if (excludedCards.contains(card.stableId)) continue;
      for (final variant in card.variants) {
        variantCount++;
        final legacyIds = _effectiveLegacyTags(card, variant);
        final v3Ids = <String>{};
        for (final legacyId in legacyIds) {
          final targets = mappings[legacyId];
          if (targets == null || targets.isEmpty) {
            unmapped.add(legacyId);
          } else {
            v3Ids.addAll(targets);
          }
        }
        final directions = _directions(card.directionality, v3Ids, entries);
        final distanceCompatible = _distanceCompatible(card, variant);
        for (final id in v3Ids) {
          final entry = entries[id];
          if (entry == null) continue;
          entry.cards.add(card.stableId);
          entry.variants.add(variant.stableId);
          if (distanceCompatible) entry.distanceVariants.add(variant.stableId);
          for (final direction in directions) {
            entry.directionVariants[direction]!.add(variant.stableId);
          }
        }
      }
    }

    final grouped = <String, Object?>{};
    for (final category in V3TagCategory.values) {
      grouped[category.name] = [
        for (final tag in taxonomy.tags.where((t) => t.category == category))
          entries[tag.stableId]!.toJson(),
      ];
    }
    final zero = [
      for (final entry in entries.values)
        if (entry.variants.isEmpty) entry.tag.stableId,
    ]..sort();
    final legacyMapped = taxonomy.legacyMappings
        .where((mapping) => mapping.v3TagIds.isNotEmpty)
        .length;
    final mappingsByStatus = <String, int>{};
    for (final mapping in taxonomy.legacyMappings) {
      mappingsByStatus.update(
        mapping.status,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }

    return {
      'schema_version': 3,
      'source_catalog_version': catalog.catalogVersion,
      'playable_cards_analyzed': catalog.cards.length - excludedCards.length,
      'variants_analyzed': variantCount,
      'excluded_roleplay_scenario_cards': excludedCards.toList()..sort(),
      'legacy_mappings': {
        'total': taxonomy.legacyMappings.length,
        'mapped': legacyMapped,
        'without_v3_target': taxonomy.legacyMappings.length - legacyMapped,
        'by_status': mappingsByStatus,
        'unmapped_tags_used_by_playable_cards': unmapped.toList()..sort(),
      },
      'coverage_by_category': grouped,
      'zero_coverage_tags': zero,
    };
  }

  Set<String> _effectiveLegacyTags(
    CardDefinition card,
    CardVariantDefinition variant,
  ) {
    String normalize(String id) => id.startsWith('tag.') ? id : 'tag.$id';
    final tags = card.baseTags.map(normalize).toSet()
      ..addAll(variant.additionalTags.map(normalize))
      ..removeAll(variant.removedTags.map(normalize));
    return tags;
  }

  Set<String> _directions(
    CardDirectionality? legacy,
    Set<String> v3Ids,
    Map<String, _MutableCoverage> entries,
  ) {
    final result = <String>{};
    switch (legacy) {
      case CardDirectionality.FAIRE:
        result.add('FAIRE');
        break;
      case CardDirectionality.RECEVOIR:
        result.add('RECEVOIR');
        break;
      case CardDirectionality.MUTUAL:
        result.add('MUTUEL');
        break;
      case CardDirectionality.FAIRE_RECEVOIR:
        result.addAll(const ['FAIRE', 'RECEVOIR']);
        break;
      case CardDirectionality.CONTEXTUAL:
      case null:
        break;
    }
    for (final id in v3Ids) {
      final tag = entries[id]?.tag;
      if (tag?.category == V3TagCategory.DIRECTION &&
          _reportedDirections.contains(tag!.key)) {
        result.add(tag.key);
      }
    }
    return result;
  }

  bool _distanceCompatible(CardDefinition card, CardVariantDefinition variant) {
    final requirements = [
      ...card.technicalRequirements,
      ...variant.technicalRequirements,
    ];
    final legacyModeRequirements = requirements.where(
      (requirement) =>
          requirement.type == TechnicalRequirementType.SESSION_MODE_IN,
    );
    if (legacyModeRequirements.isEmpty) return true;
    return legacyModeRequirements.every(
      (requirement) => requirement.sessionModes.contains(SessionMode.distance),
    );
  }
}

final class _MutableCoverage {
  _MutableCoverage(this.tag)
    : directionVariants = {
        for (final direction in _reportedDirections) direction: <String>{},
      };

  final V3TagDefinition tag;
  final Set<String> cards = {};
  final Set<String> variants = {};
  final Set<String> distanceVariants = {};
  final Map<String, Set<String>> directionVariants;

  Map<String, Object?> toJson() => {
    'stable_id': tag.stableId,
    'key': tag.key,
    'scoreable': tag.scoreable,
    'card_count': cards.length,
    'variant_count': variants.length,
    'direction_coverage': {
      for (final direction in _reportedDirections)
        direction: directionVariants[direction]!.length,
    },
    'distance_compatible_variants': distanceVariants.length,
    'cards': cards.toList()..sort(),
  };
}
