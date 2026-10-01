import 'catalog.dart';
import 'definitions.dart';
import 'enums.dart';
import 'roleplay_scenarios.dart';
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

  Map<String, Object?> build(
    Catalog catalog,
    V3Taxonomy taxonomy,
    RoleplayScenarioLibrary roleplayScenarios,
  ) {
    final view = V3CatalogView(
      catalog: catalog,
      taxonomy: taxonomy,
      roleplayScenarios: roleplayScenarios,
    );
    final excludedCards = roleplayScenarios.legacyCardIds;
    final mappings = {
      for (final mapping in taxonomy.legacyMappings)
        mapping.legacyTagId: mapping.v3TagIds,
    };
    final entries = {
      for (final tag in taxonomy.tags) tag.stableId: _MutableCoverage(tag),
    };
    final unmapped = <String>{};
    var variantCount = 0;

    for (final card in view.playableCards) {
      for (final variant in view.playableVariants(card)) {
        variantCount++;
        final explicitV3 = variant.v3 ?? card.v3;
        final v3Ids = <String>{};
        if (explicitV3 != null) {
          v3Ids.addAll(explicitV3.tags);
          final unknown = v3Ids.where((id) => !entries.containsKey(id));
          if (unknown.isNotEmpty) {
            throw StateError(
              '${variant.stableId} references unknown V3 tags: '
              '${unknown.join(', ')}',
            );
          }
        } else {
          final legacyIds = _effectiveLegacyTags(card, variant);
          for (final legacyId in legacyIds) {
            final targets = mappings[legacyId];
            if (targets == null || targets.isEmpty) {
              unmapped.add(legacyId);
            } else {
              v3Ids.addAll(targets);
            }
          }
        }
        final directions = _directions(
          explicitV3 == null ? card.directionality : null,
          v3Ids,
          entries,
        );
        final distanceCompatible =
            explicitV3?.requirements.isDistanceCompatible ??
            _distanceCompatible(card, variant);
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
      'playable_cards_analyzed': view.playableCards.length,
      'variants_analyzed': variantCount,
      'excluded_roleplay_scenario_cards': excludedCards.toList()..sort(),
      'roleplay_scenarios': {
        'count': roleplayScenarios.scenarios.length,
        'enabled': roleplayScenarios.scenarios
            .where((scenario) => scenario.enabled)
            .length,
        'ids': roleplayScenarios.scenarioIds.toList()..sort(),
      },
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

final class V3ConsolidationReportBuilder {
  const V3ConsolidationReportBuilder();

  static const preferenceLessBefore = <String>[
    'variant.manual_intimate.base',
    'variant.oral_give.base',
    'variant.oral_receive.base',
    'variant.sixty_nine.base',
    'variant.anal_play.base',
    'variant.anal_oral.base',
    'variant.facesitting.base',
    'variant.chest_play.base',
    'variant.nipple_stimulation.base',
    'variant.feet_play.base',
    'variant.guess_touch.base',
    'variant.sensory_play.base',
    'variant.sensory_play.eyes',
    'variant.look_at_me.base',
    'variant.private_exhibition.base',
    'variant.private_exhibition.nude',
    'variant.pose.base',
    'variant.private_video_call.base',
    'variant.nude_video_call.base',
  ];

  static const createdVariants = <String>[
    'variant.oral_give.suck',
    'variant.oral_receive.suck',
    'variant.sixty_nine.suck',
    'variant.anal_manual.internal',
    'variant.chest_play.massage',
    'variant.nipple_stimulation.pinch',
    'variant.simultaneous_self_masturbation.base',
  ];

  Map<String, Object?> build(
    Catalog catalog,
    V3Taxonomy taxonomy,
    RoleplayScenarioLibrary roleplayScenarios,
  ) {
    final view = V3CatalogView(
      catalog: catalog,
      taxonomy: taxonomy,
      roleplayScenarios: roleplayScenarios,
    );
    final preferences = taxonomy.tags
        .where(
          (tag) => tag.category == V3TagCategory.PREFERENCE && tag.scoreable,
        )
        .map((tag) => tag.stableId)
        .toSet();
    final preferenceLessAfter = <String>[];
    final remainingAmbiguities = <Map<String, Object?>>[];
    var variantCount = 0;
    for (final card in view.playableCards) {
      for (final variant in view.playableVariants(card)) {
        variantCount++;
        final editorial = variant.v3 ?? card.v3;
        if (editorial == null || !editorial.tags.any(preferences.contains)) {
          preferenceLessAfter.add(variant.stableId);
        }
        if (editorial != null && editorial.ambiguities.isNotEmpty) {
          remainingAmbiguities.add({
            'card_id': card.stableId,
            'variant_id': variant.stableId,
            'ambiguities': editorial.ambiguities,
          });
        }
      }
    }

    final scenarioIds = roleplayScenarios.legacyCardIds;
    final removed =
        catalog.cards
            .where(
              (card) =>
                  !card.v3DeckEnabled && !scenarioIds.contains(card.stableId),
            )
            .map((card) => card.stableId)
            .toList()
          ..sort();
    final replacements = <Map<String, Object?>>[];
    for (final card in catalog.cards) {
      if (card.v3ReplacementCardId != null ||
          card.v3ReplacementSessionField != null) {
        replacements.add({
          'source_id': card.stableId,
          if (card.v3ReplacementCardId != null)
            'replacement_card_id': card.v3ReplacementCardId,
          if (card.v3ReplacementVariantId != null)
            'replacement_variant_id': card.v3ReplacementVariantId,
          if (card.v3ReplacementSessionField != null)
            'replacement_session_field': card.v3ReplacementSessionField,
        });
      }
      for (final variant in card.variants) {
        if (variant.v3ReplacementCardId != null) {
          replacements.add({
            'source_id': variant.stableId,
            'replacement_card_id': variant.v3ReplacementCardId,
            'replacement_variant_id': variant.v3ReplacementVariantId,
          });
        }
      }
    }
    replacements.sort(
      (left, right) => (left['source_id']! as String).compareTo(
        right['source_id']! as String,
      ),
    );
    preferenceLessAfter.sort();

    final coverage = const V3CoverageReportBuilder().build(
      catalog,
      taxonomy,
      roleplayScenarios,
    );
    return {
      'schema_version': 1,
      'removed_from_v3_deck': removed,
      'replacement_mappings': replacements,
      'new_v3_cards': [
        for (final card in view.playableCards.where(
          (card) => (card.order ?? 0) > 100,
        ))
          card.stableId,
      ],
      'created_variants': createdVariants,
      'preference_less_before': preferenceLessBefore,
      'preference_less_after': preferenceLessAfter,
      'remaining_ambiguities': remainingAmbiguities,
      'counts_before': const {'playable_cards': 90, 'playable_variants': 119},
      'counts_after': {
        'playable_cards': view.playableCards.length,
        'playable_variants': variantCount,
      },
      'zero_coverage_count_before': 52,
      'coverage': coverage,
    };
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
