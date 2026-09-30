import 'dart:convert';

import '../../core/json.dart';

// Wire names deliberately match the canonical taxonomy document.
// ignore_for_file: constant_identifier_names

enum V3TagCategory {
  PREFERENCE,
  ZONE,
  DIRECTION,
  MATERIEL,
  TECHNIQUE,
  CONTEXTE,
  SESSION_PREF,
}

final class V3TagDefinition {
  const V3TagDefinition({
    required this.stableId,
    required this.key,
    required this.category,
    required this.scoreable,
  });

  factory V3TagDefinition.fromJson(JsonMap json) => V3TagDefinition(
    stableId: json['stable_id']! as String,
    key: json['key']! as String,
    category: V3TagCategory.values.byName(json['category']! as String),
    scoreable: json['scoreable']! as bool,
  );

  final String stableId;
  final String key;
  final V3TagCategory category;
  final bool scoreable;
}

final class V3LegacyMapping {
  const V3LegacyMapping({
    required this.legacyTagId,
    required this.legacyProfileId,
    required this.v3TagIds,
    required this.status,
  });

  factory V3LegacyMapping.fromJson(JsonMap json) => V3LegacyMapping(
    legacyTagId: json['legacy_tag_id']! as String,
    legacyProfileId: json['legacy_profile_id'] as String?,
    v3TagIds: List.unmodifiable((json['v3_tag_ids']! as List).cast<String>()),
    status: json['status']! as String,
  );

  final String legacyTagId;
  final String? legacyProfileId;
  final List<String> v3TagIds;
  final String status;
}

final class V3LegacyProfileMapping {
  const V3LegacyProfileMapping({
    required this.legacyProfileId,
    required this.v3TagIds,
    required this.status,
  });

  factory V3LegacyProfileMapping.fromJson(JsonMap json) =>
      V3LegacyProfileMapping(
        legacyProfileId: json['legacy_profile_id']! as String,
        v3TagIds: List.unmodifiable(
          (json['v3_tag_ids']! as List).cast<String>(),
        ),
        status: json['status']! as String,
      );

  final String legacyProfileId;
  final List<String> v3TagIds;
  final String status;
}

/// Additive V3 contract. The active V1/V2 catalogue remains the runtime source
/// until cards and profiles are migrated in the next catalogue step.
final class V3Taxonomy {
  V3Taxonomy({
    required this.schemaVersion,
    required this.tags,
    required this.legacyMappings,
    required this.legacyProfileMappings,
    required this.roleplayScenarioCardIds,
  }) {
    if (schemaVersion != 3) {
      throw const FormatException('V3 taxonomy requires schema_version 3');
    }
    final tagIds = <String>{};
    final keys = <String>{};
    for (final tag in tags) {
      if (!tagIds.add(tag.stableId) || !keys.add(tag.key)) {
        throw FormatException('Duplicate V3 tag: ${tag.stableId}/${tag.key}');
      }
      if (tag.scoreable != (tag.category == V3TagCategory.PREFERENCE)) {
        throw FormatException('Only PREFERENCE tags are scoreable: ${tag.key}');
      }
    }
    final mappingIds = <String>{};
    for (final mapping in legacyMappings) {
      if (!mappingIds.add(mapping.legacyTagId)) {
        throw FormatException(
          'Duplicate legacy mapping: ${mapping.legacyTagId}',
        );
      }
      for (final id in mapping.v3TagIds) {
        if (!tagIds.contains(id)) {
          throw FormatException('Unknown V3 mapping target: $id');
        }
      }
    }
    final profileMappingIds = <String>{};
    for (final mapping in legacyProfileMappings) {
      if (!profileMappingIds.add(mapping.legacyProfileId)) {
        throw FormatException(
          'Duplicate legacy profile mapping: ${mapping.legacyProfileId}',
        );
      }
      for (final id in mapping.v3TagIds) {
        if (!tagIds.contains(id)) {
          throw FormatException('Unknown V3 profile mapping target: $id');
        }
      }
    }
  }

  factory V3Taxonomy.fromJson(JsonMap json) {
    final tags = (json['tags']! as List)
        .cast<JsonMap>()
        .map(V3TagDefinition.fromJson)
        .toList(growable: false);
    final mappings = (json['legacy_mappings']! as List)
        .cast<JsonMap>()
        .map(V3LegacyMapping.fromJson)
        .toList(growable: false);
    final profileMappings = (json['legacy_profile_mappings']! as List)
        .cast<JsonMap>()
        .map(V3LegacyProfileMapping.fromJson)
        .toList(growable: false);
    return V3Taxonomy(
      schemaVersion: json['schema_version']! as int,
      tags: List.unmodifiable(tags),
      legacyMappings: List.unmodifiable(mappings),
      legacyProfileMappings: List.unmodifiable(profileMappings),
      roleplayScenarioCardIds: List.unmodifiable(
        (json['roleplay_scenario_card_ids']! as List).cast<String>(),
      ),
    );
  }

  factory V3Taxonomy.decode(String source) =>
      V3Taxonomy.fromJson(jsonDecode(source) as JsonMap);

  final int schemaVersion;
  final List<V3TagDefinition> tags;
  final List<V3LegacyMapping> legacyMappings;
  final List<V3LegacyProfileMapping> legacyProfileMappings;
  final List<String> roleplayScenarioCardIds;
}
