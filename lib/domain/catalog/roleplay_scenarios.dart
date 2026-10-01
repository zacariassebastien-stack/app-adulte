import 'dart:convert';

import '../../core/json.dart';
import 'catalog.dart';
import 'definitions.dart';
import 'v3_taxonomy.dart';

final class RoleplayScenario {
  RoleplayScenario.read(JsonReader reader)
    : stableId = reader.string('stable_id'),
      title = reader.string('title'),
      description = reader.string('description'),
      enabled = reader.boolean('enabled'),
      roles = reader.strings('roles', optional: true),
      legacyCardId = reader.string('legacy_card_id'),
      legacyProfileId = reader.string('legacy_profile_id'),
      legacyTagId = reader.string('legacy_tag_id') {
    reader.only(const {
      'stable_id',
      'title',
      'description',
      'enabled',
      'roles',
      'legacy_card_id',
      'legacy_profile_id',
      'legacy_tag_id',
    });
    if (!stableId.startsWith('roleplay.')) {
      throw FormatException('Invalid roleplay scenario ID: $stableId');
    }
  }

  final String stableId;
  final String title;
  final String description;
  final bool enabled;
  final List<String> roles;
  final String legacyCardId;
  final String legacyProfileId;
  final String legacyTagId;
}

final class RoleplayScenarioLibrary {
  RoleplayScenarioLibrary({
    required this.schemaVersion,
    required this.libraryVersion,
    required this.locale,
    required List<RoleplayScenario> scenarios,
  }) : scenarios = List.unmodifiable(scenarios) {
    if (schemaVersion != 1 || libraryVersion != 1) {
      throw const FormatException('Unsupported roleplay scenario library');
    }
    _requireUnique(scenarios.map((scenario) => scenario.stableId), 'scenario');
    _requireUnique(
      scenarios.map((scenario) => scenario.legacyCardId),
      'legacy card',
    );
    _requireUnique(
      scenarios.map((scenario) => scenario.legacyProfileId),
      'legacy profile',
    );
    _requireUnique(
      scenarios.map((scenario) => scenario.legacyTagId),
      'legacy tag',
    );
  }

  factory RoleplayScenarioLibrary.fromJson(JsonMap json) {
    final reader = JsonReader(json, 'RoleplayScenarioLibrary');
    reader.only(const {
      'schema_version',
      'library_version',
      'locale',
      'scenarios',
    });
    return RoleplayScenarioLibrary(
      schemaVersion: reader.integer('schema_version', min: 1, max: 1),
      libraryVersion: reader.integer('library_version', min: 1, max: 1),
      locale: reader.string('locale'),
      scenarios: reader.objects(
        'scenarios',
        RoleplayScenario.read,
        'RoleplayScenario',
      ),
    );
  }

  factory RoleplayScenarioLibrary.decode(String source) =>
      RoleplayScenarioLibrary.fromJson(jsonDecode(source) as JsonMap);

  final int schemaVersion;
  final int libraryVersion;
  final String locale;
  final List<RoleplayScenario> scenarios;

  Set<String> get scenarioIds =>
      scenarios.map((scenario) => scenario.stableId).toSet();
  Set<String> get legacyCardIds =>
      scenarios.map((scenario) => scenario.legacyCardId).toSet();

  String? resolveScenarioId(String? id) {
    if (id == null) return null;
    for (final scenario in scenarios) {
      if (scenario.stableId == id ||
          scenario.legacyCardId == id ||
          scenario.legacyProfileId == id ||
          scenario.legacyTagId == id) {
        return scenario.stableId;
      }
    }
    throw FormatException('Unknown roleplay scenario: $id');
  }

  static void _requireUnique(Iterable<String> values, String label) {
    final all = values.toList(growable: false);
    if (all.toSet().length != all.length) {
      throw FormatException('Duplicate $label mapping');
    }
  }
}

/// Validated V3 view over the legacy catalogue. Scenario cards stay available
/// for legacy deserialization but can never enter this playable deck.
final class V3CatalogView {
  V3CatalogView({
    required this.catalog,
    required this.taxonomy,
    required this.roleplayScenarios,
  }) {
    final taxonomyLegacyIds = taxonomy.roleplayScenarioCardIds.toSet();
    if (taxonomyLegacyIds.length != taxonomy.roleplayScenarioCardIds.length ||
        taxonomyLegacyIds
            .difference(roleplayScenarios.legacyCardIds)
            .isNotEmpty ||
        roleplayScenarios.legacyCardIds
            .difference(taxonomyLegacyIds)
            .isNotEmpty) {
      throw const FormatException(
        'Roleplay taxonomy and scenario legacy mappings disagree',
      );
    }
    final cardsById = {for (final card in catalog.cards) card.stableId: card};
    final mappingsByTag = {
      for (final mapping in taxonomy.legacyMappings)
        mapping.legacyTagId: mapping,
    };
    for (final legacyId in roleplayScenarios.legacyCardIds) {
      final card = cardsById[legacyId];
      if (card == null || card.v3DeckEnabled) {
        throw FormatException(
          'Legacy scenario card must exist and be disabled in V3: $legacyId',
        );
      }
    }
    for (final scenario in roleplayScenarios.scenarios) {
      final mapping = mappingsByTag[scenario.legacyTagId];
      if (mapping == null ||
          mapping.legacyProfileId != scenario.legacyProfileId ||
          mapping.status != 'scenario_migrated' ||
          mapping.v3TagIds.isNotEmpty) {
        throw FormatException(
          'Invalid legacy scenario migration: ${scenario.stableId}',
        );
      }
    }
    playableCards = List.unmodifiable(
      catalog.cards.where((card) => card.v3DeckEnabled),
    );
    if (roleplayScenarios.scenarios.length != 10) {
      throw const FormatException(
        'V3 catalogue requires 10 roleplay scenarios',
      );
    }
    for (final card in catalog.cards) {
      final replacementCardId = card.v3ReplacementCardId;
      final replacementVariantId = card.v3ReplacementVariantId;
      if (replacementVariantId != null && replacementCardId == null) {
        throw FormatException(
          'A replacement variant requires a replacement card: ${card.stableId}',
        );
      }
      if (replacementCardId != null) {
        final replacement = cardsById[replacementCardId];
        if (replacement == null || !replacement.v3DeckEnabled) {
          throw FormatException(
            'Invalid V3 replacement card for ${card.stableId}: '
            '$replacementCardId',
          );
        }
        if (replacementVariantId != null &&
            !replacement.variants.any(
              (variant) =>
                  variant.stableId == replacementVariantId &&
                  variant.v3DeckEnabled,
            )) {
          throw FormatException(
            'Invalid V3 replacement variant for ${card.stableId}: '
            '$replacementVariantId',
          );
        }
      }
      if (card.v3DeckEnabled && playableVariants(card).isEmpty) {
        throw FormatException(
          'Playable V3 card has no playable variant: ${card.stableId}',
        );
      }
      for (final variant in card.variants) {
        final variantReplacementCardId = variant.v3ReplacementCardId;
        final variantReplacementId = variant.v3ReplacementVariantId;
        if (variantReplacementCardId == null && variantReplacementId == null) {
          continue;
        }
        final replacement = cardsById[variantReplacementCardId];
        if (replacement == null ||
            !replacement.v3DeckEnabled ||
            variantReplacementId == null ||
            !replacement.variants.any(
              (candidate) =>
                  candidate.stableId == variantReplacementId &&
                  candidate.v3DeckEnabled,
            )) {
          throw FormatException(
            'Invalid V3 replacement for ${variant.stableId}',
          );
        }
      }
    }
  }

  final Catalog catalog;
  final V3Taxonomy taxonomy;
  final RoleplayScenarioLibrary roleplayScenarios;
  late final List<CardDefinition> playableCards;

  Iterable<CardVariantDefinition> playableVariants(CardDefinition card) =>
      card.variants.where((variant) => variant.v3DeckEnabled);
}
