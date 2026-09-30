import 'dart:convert';
import 'dart:io';

import 'package:couple_cards/data/catalog_loader/catalog_loader.dart';
import 'package:couple_cards/domain/domain.dart';
import 'package:test/test.dart';

const source = 'assets/catalog/source';

void main() {
  late V3Taxonomy taxonomy;
  late Catalog catalog;

  setUpAll(() async {
    taxonomy = V3Taxonomy.decode(
      File('$source/catalog_v3_taxonomy.json').readAsStringSync(),
    );
    catalog = await const CatalogLoader().load(
      (path) => File(path).readAsString(),
    );
  });

  test('V3 taxonomy is atomic, complete and migration-safe', () {
    expect(taxonomy.schemaVersion, 3);
    expect(
      taxonomy.tags.map((tag) => tag.category).toSet(),
      V3TagCategory.values.toSet(),
    );
    expect(taxonomy.tags.map((tag) => tag.key), isNot(contains('PAPOUILLE')));
    expect(
      taxonomy.tags.map((tag) => tag.key),
      isNot(contains('DISTANCE_COMPATIBLE')),
    );
    expect(
      taxonomy.tags.where((tag) => tag.scoreable),
      everyElement(
        predicate<V3TagDefinition>(
          (tag) => tag.category == V3TagCategory.PREFERENCE,
        ),
      ),
    );

    final legacyTagIds = catalog.tags.map((tag) => tag.stableId).toSet();
    final legacyProfileIds = catalog.profileElements
        .map((profile) => profile.stableId)
        .toSet();
    expect(
      taxonomy.legacyMappings.map((mapping) => mapping.legacyTagId).toSet(),
      legacyTagIds,
    );
    for (final mapping in taxonomy.legacyMappings) {
      if (mapping.legacyProfileId != null) {
        expect(legacyProfileIds, contains(mapping.legacyProfileId));
      }
    }
  });

  test('engagement clothing modifier only applies to levels 1 to 3', () {
    expect(
      v3EffectiveEngagementLevel(baseEngagementLevel: 2, clothingModifier: 1),
      3,
    );
    expect(
      v3EffectiveEngagementLevel(baseEngagementLevel: 3, clothingModifier: -2),
      1,
    );
    expect(
      v3EffectiveEngagementLevel(baseEngagementLevel: 4, clothingModifier: -3),
      4,
    );
    expect(
      v3EffectiveEngagementLevel(baseEngagementLevel: 5, clothingModifier: 1),
      5,
    );
  });

  test('distance is compatible by default and only excluded explicitly', () {
    expect(const V3Requirements().isDistanceCompatible, isTrue);
    expect(
      const V3Requirements(distanceExcluded: true).isDistanceCompatible,
      isFalse,
    );
  });

  test('clothing, roleplay and all V3 requirements have typed support', () {
    const fixed = V3ClothingDelta.fixed(-1);
    const asked = V3ClothingDelta.askPlayer();
    expect(fixed.kind, V3ClothingDeltaKind.fixed);
    expect(fixed.value, -1);
    expect(asked.kind, V3ClothingDeltaKind.askPlayer);
    expect(asked.value, isNull);

    const session = V3SessionData(
      removableClothingInitial: 4,
      removableClothingRemaining: 2,
      roleplayEnabled: true,
      roleplayScenario: 'card.rp_strangers',
    );
    expect(session.removableClothingRemaining, 2);
    expect(session.roleplayScenario, 'card.rp_strangers');

    const requirements = V3Requirements(
      requiresVideo: true,
      requiresRoleplay: true,
      requiresSurpriseParty: true,
      requiresSextoy: true,
      requiresVibratingToy: true,
      requiresRemoteControlToy: true,
      requiresConstraintAccessory: true,
      requiresOil: true,
      requiresLubricant: true,
      requiresProtection: true,
      requiresFood: true,
      requiresDrink: true,
      requiresAlcohol: true,
      minimumRemovableClothing: 2,
    );
    expect(requirements.requiresRemoteControlToy, isTrue);
    expect(requirements.minimumRemovableClothing, 2);
    expect(
      V3Requirements.fromJson(requirements.toJson()).toJson(),
      requirements.toJson(),
    );
    expect(V3SessionData.fromJson(session.toJson()).toJson(), session.toJson());
    expect(V3ClothingDelta.fromJson(asked.toJson()).kind, asked.kind);

    final mechanics = V3CardMechanics(
      baseEngagementLevel: 4,
      clothingDelta: fixed,
      requirements: requirements,
    );
    expect(mechanics.engagementLevelFor(-1), 4);
  });

  test('cards 91 to 100 are marked as future roleplay scenarios', () {
    final expected = catalog.cards
        .where((card) => card.order != null && card.order! >= 91)
        .map((card) => card.stableId)
        .toSet();
    expect(taxonomy.roleplayScenarioCardIds.toSet(), expected);
  });

  test('inverse coverage report is deterministic and current', () {
    final report = const V3CoverageReportBuilder().build(catalog, taxonomy);
    expect(report['playable_cards_analyzed'], 90);
    expect(report['coverage_by_category'], isA<Map<String, Object?>>());
    expect(
      (report['coverage_by_category']! as Map<String, Object?>).keys,
      V3TagCategory.values.map((value) => value.name),
    );
    expect(report['zero_coverage_tags'], isA<List<String>>());
    expect(
      jsonDecode(File('docs/catalog_v3_coverage.json').readAsStringSync()),
      report,
    );
  });
}
