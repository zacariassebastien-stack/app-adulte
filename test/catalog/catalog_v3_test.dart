import 'dart:convert';
import 'dart:io';

import 'package:couple_cards/data/catalog_loader/catalog_loader.dart';
import 'package:couple_cards/domain/domain.dart';
import 'package:test/test.dart';

const source = 'assets/catalog/source';

void main() {
  late V3Taxonomy taxonomy;
  late Catalog catalog;
  late RoleplayScenarioLibrary roleplayScenarios;

  setUpAll(() async {
    taxonomy = V3Taxonomy.decode(
      File('$source/catalog_v3_taxonomy.json').readAsStringSync(),
    );
    roleplayScenarios = RoleplayScenarioLibrary.decode(
      File('$source/roleplay_scenarios.v1.fr.json').readAsStringSync(),
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
    expect(
      taxonomy.legacyProfileMappings.single.legacyProfileId,
      'profile.roleplay',
    );
    expect(taxonomy.legacyProfileMappings.single.v3TagIds, [
      'v3.preference.jeu_role',
    ]);
  });

  test('sensitive legacy semantics keep actor and receiver distinct', () {
    List<String> targets(String legacyId) => taxonomy.legacyMappings
        .singleWhere((mapping) => mapping.legacyTagId == legacyId)
        .v3TagIds;

    expect(targets('tag.observation.be_watched'), [
      'v3.direction.etre_regarde',
    ]);
    expect(targets('tag.observation.watch'), ['v3.preference.regarder']);
    expect(targets('tag.intimate.masturbation.partner'), [
      'v3.preference.masturbation',
      'v3.direction.faire',
    ]);
    expect(targets('tag.intimate.masturbation.mutual'), [
      'v3.preference.masturbation',
      'v3.direction.mutuel',
    ]);
    expect(
      targets('tag.intimate.masturbation.mutual'),
      isNot(contains('v3.direction.simultane')),
    );
    expect(targets('tag.power.order.give'), [
      'v3.preference.ordres',
      'v3.direction.faire',
    ]);
    expect(targets('tag.power.order.receive'), [
      'v3.preference.ordres',
      'v3.direction.recevoir',
    ]);
    expect(targets('tag.power.decision.give'), [
      'v3.preference.controle',
      'v3.direction.faire',
    ]);
    expect(targets('tag.power.decision.receive'), [
      'v3.preference.controle',
      'v3.direction.recevoir',
    ]);
    expect(targets('tag.power.domination.receive'), [
      'v3.preference.controle',
      'v3.direction.recevoir',
    ]);
    expect(targets('tag.media.photo.send'), [
      'v3.preference.photo',
      'v3.preference.envoyer',
    ]);
    expect(targets('tag.media.video.send'), [
      'v3.preference.video',
      'v3.preference.envoyer',
    ]);
    expect(targets('tag.clothing.partner_remove'), ['v3.preference.enlever']);
  });

  test('roleplay and exposed-place preference semantics are preserved', () {
    final roleplay = taxonomy.tags.singleWhere((tag) => tag.key == 'JEU_ROLE');
    expect(roleplay.category, V3TagCategory.PREFERENCE);
    expect(roleplay.scoreable, isTrue);
    final exposedPlace = taxonomy.tags.singleWhere(
      (tag) => tag.key == 'LIEU_EXPOSE',
    );
    expect(exposedPlace.category, V3TagCategory.PREFERENCE);
    expect(exposedPlace.scoreable, isTrue);

    final scenarioMappings = taxonomy.legacyMappings.where(
      (mapping) => mapping.legacyTagId.startsWith('tag.roleplay.'),
    );
    expect(scenarioMappings, hasLength(10));
    expect(
      scenarioMappings,
      everyElement(
        predicate<V3LegacyMapping>(
          (mapping) =>
              mapping.status == 'scenario_migrated' && mapping.v3TagIds.isEmpty,
        ),
      ),
    );
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

    final session = V3SessionData(
      removableClothingInitial: 4,
      removableClothingRemaining: 2,
      roleplayEnabled: true,
      roleplayScenarios: roleplayScenarios,
      roleplayScenario: 'card.rp_strangers',
    );
    expect(session.removableClothingRemaining, 2);
    expect(session.roleplayScenarioId, 'roleplay.strangers');

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
    expect(
      V3SessionData.fromJson(
        session.toJson(),
        roleplayScenarios: roleplayScenarios,
      ).toJson(),
      session.toJson(),
    );
    expect(V3ClothingDelta.fromJson(asked.toJson()).kind, asked.kind);

    final mechanics = V3CardMechanics(
      baseEngagementLevel: 4,
      clothingDelta: fixed,
      requirements: requirements,
    );
    expect(mechanics.engagementLevelFor(-1), 4);
  });

  test('V3 deck has 90 cards and ten dedicated roleplay scenarios', () {
    final view = V3CatalogView(
      catalog: catalog,
      taxonomy: taxonomy,
      roleplayScenarios: roleplayScenarios,
    );
    expect(view.playableCards, hasLength(90));
    expect(view.playableCards.every((card) => card.order! <= 90), isTrue);
    expect(roleplayScenarios.scenarios, hasLength(10));
    expect(
      catalog.cards.where((card) => card.order! >= 91),
      everyElement(predicate<CardDefinition>((card) => !card.v3DeckEnabled)),
    );
    expect(
      roleplayScenarios.scenarios
          .map((scenario) => scenario.legacyCardId)
          .toSet(),
      taxonomy.roleplayScenarioCardIds.toSet(),
    );
    expect(
      roleplayScenarios.scenarios,
      everyElement(
        predicate<RoleplayScenario>(
          (scenario) =>
              scenario.enabled && scenario.stableId.startsWith('roleplay.'),
        ),
      ),
    );
    final scenarioSource =
        jsonDecode(
              File('$source/roleplay_scenarios.v1.fr.json').readAsStringSync(),
            )
            as JsonMap;
    expect(
      (scenarioSource['scenarios']! as List).cast<JsonMap>(),
      everyElement(
        predicate<JsonMap>(
          (scenario) =>
              !scenario.containsKey('scoreable') &&
              !scenario.containsKey('tags') &&
              !scenario.containsKey('profile_elements'),
        ),
      ),
    );
    expect(
      taxonomy.tags.where((tag) => tag.key == 'JEU_ROLE').single.scoreable,
      isTrue,
    );
    expect(
      taxonomy.tags.where(
        (tag) => tag.stableId.startsWith('v3.preference.roleplay.'),
      ),
      isEmpty,
    );
  });

  test('roleplay session selection is validated and changes no card rules', () {
    final card = catalog.cards.singleWhere((card) => card.order == 31);
    final tags = List<String>.of(card.v3!.tags);
    final engagement = card.v3!.baseEngagementLevel;
    final requirements = card.v3!.requirements.toJson();

    final withoutScenario = V3SessionData(
      removableClothingInitial: 3,
      removableClothingRemaining: 3,
      roleplayEnabled: true,
      roleplayScenarios: roleplayScenarios,
    );
    expect(withoutScenario.roleplayScenarioId, isNull);
    final disabled = V3SessionData(
      removableClothingInitial: 3,
      removableClothingRemaining: 3,
      roleplayEnabled: false,
      roleplayScenarios: roleplayScenarios,
    );
    expect(disabled.roleplayScenarioId, isNull);
    expect(
      () => V3SessionData(
        removableClothingInitial: 3,
        removableClothingRemaining: 3,
        roleplayEnabled: false,
        roleplayScenarios: roleplayScenarios,
        roleplayScenarioId: 'roleplay.strangers',
      ),
      throwsFormatException,
    );
    expect(
      () => V3SessionData(
        removableClothingInitial: 3,
        removableClothingRemaining: 3,
        roleplayEnabled: true,
        roleplayScenarios: roleplayScenarios,
        roleplayScenarioId: 'roleplay.unknown',
      ),
      throwsFormatException,
    );
    final active = V3SessionData(
      removableClothingInitial: 3,
      removableClothingRemaining: 3,
      roleplayEnabled: true,
      roleplayScenarios: roleplayScenarios,
      roleplayScenarioId: 'roleplay.strangers',
    );
    expect(active.roleplayScenarioId, 'roleplay.strangers');
    expect(card.v3!.tags, tags);
    expect(card.v3!.baseEngagementLevel, engagement);
    expect(card.v3!.requirements.toJson(), requirements);
  });

  test('inverse coverage report is deterministic and current', () {
    final report = const V3CoverageReportBuilder().build(
      catalog,
      taxonomy,
      roleplayScenarios,
    );
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

  test('only cards 1 to 90 have explicit V3 editorial data after batch 2C', () {
    for (final card in catalog.cards) {
      if (card.order! <= 90) {
        expect(card.v3, isNotNull, reason: card.stableId);
        expect(
          card.variants,
          everyElement(
            predicate<CardVariantDefinition>((variant) => variant.v3 != null),
          ),
          reason: card.stableId,
        );
      } else {
        expect(card.v3, isNull, reason: card.stableId);
        expect(
          card.variants.every((variant) => variant.v3 == null),
          isTrue,
          reason: card.stableId,
        );
      }
    }
  });

  test('migrated cards only reference canonical V3 tags', () {
    final tags = {for (final tag in taxonomy.tags) tag.stableId: tag};
    for (final card in catalog.cards.where((card) => card.order! <= 90)) {
      for (final data in [
        card.v3!,
        ...card.variants.map((variant) => variant.v3!),
      ]) {
        expect(data.tags, everyElement(startsWith('v3.')));
        expect(data.tags, everyElement(isIn(tags.keys)));
        if (data.tags.isEmpty) {
          expect(data.ambiguities, isNotEmpty, reason: card.stableId);
        }
      }
    }
  });

  test('critical engagement and direction decisions are explicit', () {
    CardDefinition card(int order) =>
        catalog.cards.singleWhere((card) => card.order == order);
    expect(card(7).v3!.baseEngagementLevel, 4);
    expect(card(10).v3!.baseEngagementLevel, 4);
    expect(card(7).v3!.clothingDelta, isNull);
    expect(card(10).v3!.clothingDelta, isNull);
    expect(card(21).v3!.tags, isNot(contains('v3.preference.position_s')));
    expect(card(29).v3!.tags, contains('v3.direction.mutuel'));
    expect(card(29).v3!.tags, contains('v3.direction.simultane'));
    for (final order in [28, 29]) {
      expect(card(order).v3!.tags, isNot(contains('v3.zone.buccal')));
      expect(card(order).v3!.tags, isNot(contains('v3.preference.lecher')));
      expect(card(order).v3!.tags, isNot(contains('v3.preference.sucer')));
    }
    expect(card(28).v3!.ambiguities, [
      'Les futures variantes devront préciser LECHER ou SUCER si l’action orale est explicitée.',
    ]);
    expect(card(29).v3!.ambiguities, [
      'Les futures variantes devront préciser les actions orales réellement simulées.',
    ]);
    expect(card(30).v3!.tags, isNot(contains('v3.preference.position_a')));
    expect(card(30).v3!.tags, isNot(contains('v3.zone.fesses')));
    expect(card(30).v3!.tags, isNot(contains('v3.zone.tete')));
  });

  test('cards 11 to 19 encode coherent clothing effects', () {
    CardDefinition card(int order) =>
        catalog.cards.singleWhere((card) => card.order == order);
    Object? delta(CardDefinition card) => card.v3!.clothingDelta?.toJson();

    expect(delta(card(11)), 'ASK_PLAYER');
    expect(
      card(11).variants.map((variant) => variant.v3!.clothingDelta?.toJson()),
      ['ASK_PLAYER', -1, -2],
    );
    expect(delta(card(12)), -1);
    expect(card(12).v3!.requirements.minimumRemovableClothing, 1);
    expect(delta(card(13)), -2);
    expect(card(13).v3!.requirements.minimumRemovableClothing, 2);
    expect(delta(card(14)), 'ASK_PLAYER');
    expect(delta(card(15)), 'ASK_PLAYER');
    expect(delta(card(16)), isNull);
    expect(delta(card(17)), 'ASK_PLAYER');
    expect(
      card(18).variants.map((variant) => variant.v3!.clothingDelta?.toJson()),
      everyElement('ASK_PLAYER'),
    );
    expect(delta(card(19)), 'ASK_PLAYER');
    expect(card(19).v3!.mergeCandidateWith, 'card.striptease');
  });

  test('batch audit report covers every migrated card and variant', () {
    final report =
        jsonDecode(File('docs/catalog_v3_cards_1_30.json').readAsStringSync())
            as JsonMap;
    final cards = (report['cards']! as List).cast<JsonMap>();
    expect(cards, hasLength(30));
    expect(cards.first['order'], 1);
    expect(cards.last['order'], 30);
    expect(cards.expand((card) => card['variants']! as List), hasLength(41));

    final secondReport =
        jsonDecode(File('docs/catalog_v3_cards_31_60.json').readAsStringSync())
            as JsonMap;
    final secondCards = (secondReport['cards']! as List).cast<JsonMap>();
    expect(secondCards, hasLength(30));
    expect(secondCards.first['order'], 31);
    expect(secondCards.last['order'], 60);
    expect(
      secondCards.expand((card) => card['variants']! as List),
      hasLength(37),
    );

    final thirdReport =
        jsonDecode(File('docs/catalog_v3_cards_61_90.json').readAsStringSync())
            as JsonMap;
    final thirdCards = (thirdReport['cards']! as List).cast<JsonMap>();
    expect(thirdCards, hasLength(30));
    expect(thirdCards.first['order'], 61);
    expect(thirdCards.last['order'], 90);
    expect(
      thirdCards.expand((card) => card['variants']! as List),
      hasLength(41),
    );
  });

  test('cards 31 to 60 preserve the reviewed semantic distinctions', () {
    CardDefinition card(int order) =>
        catalog.cards.singleWhere((card) => card.order == order);
    Set<String> tags(int order) => card(order).v3!.tags.toSet();

    final masturbation = card(31);
    final solo = masturbation.variants.singleWhere(
      (variant) => variant.stableId == 'variant.masturbation.self',
    );
    final visible = masturbation.variants.singleWhere(
      (variant) => variant.stableId == 'variant.masturbation.visible',
    );
    expect(
      solo.v3!.tags,
      containsAll(['v3.preference.masturbation', 'v3.direction.solo']),
    );
    expect(solo.v3!.requirements.isDistanceCompatible, isTrue);
    expect(
      visible.v3!.tags,
      containsAll(['v3.direction.solo', 'v3.direction.etre_regarde']),
    );
    expect(visible.v3!.requirements.isDistanceCompatible, isTrue);
    expect(card(32).v3!.requirements.isDistanceCompatible, isTrue);

    expect(tags(33), {'v3.preference.masturbation', 'v3.direction.faire'});
    expect(card(33).v3!.requirements.distanceExcluded, isTrue);
    expect(tags(34), contains('v3.direction.mutuel'));
    expect(tags(34), isNot(contains('v3.direction.simultane')));
    expect(card(34).v3!.splitCandidate, isTrue);
    expect(card(34).v3!.requirements.distanceExcluded, isTrue);

    for (final order in [36, 37, 38, 45]) {
      expect(tags(order), isNot(contains('v3.zone.buccal')));
    }
    expect(card(36).v3!.baseEngagementLevel, 4);
    expect(card(37).v3!.baseEngagementLevel, 4);
    expect(
      tags(38),
      containsAll(['v3.direction.mutuel', 'v3.direction.simultane']),
    );
    expect(
      tags(39),
      containsAll(['v3.preference.penetrer', 'v3.zone.vaginal']),
    );
    expect(tags(42), containsAll(['v3.preference.caresser', 'v3.zone.anal']));
    final manualAnal = card(41).variants.singleWhere(
      (variant) => variant.stableId == 'variant.anal_play.manual',
    );
    expect(
      manualAnal.v3!.tags,
      containsAll([
        'v3.preference.penetrer',
        'v3.preference.doigts',
        'v3.zone.anal',
      ]),
    );
    expect(manualAnal.v3!.baseEngagementLevel, 5);
    expect(tags(44), containsAll(['v3.preference.penetrer', 'v3.zone.anal']));
    expect(
      tags(47),
      containsAll([
        'v3.preference.frotter',
        'v3.zone.parties_intimes',
        'v3.direction.mutuel',
      ]),
    );
    expect(tags(49), contains('v3.zone.tetons'));
    expect(tags(49), isNot(contains('v3.zone.poitrine')));
    expect(
      tags(51),
      containsAll(['v3.preference.controle', 'v3.direction.recevoir']),
    );
    expect(tags(53), {'v3.preference.ordres', 'v3.direction.recevoir'});
    expect(tags(54), {'v3.preference.ordres', 'v3.direction.faire'});
    expect(tags(55), {'v3.preference.controle', 'v3.direction.faire'});
    expect(tags(56), {'v3.preference.controle', 'v3.direction.recevoir'});
    expect(card(59).v3!.requirements.requiresConstraintAccessory, isTrue);
    expect(tags(60), {'v3.preference.attacher', 'v3.direction.recevoir'});
    expect(card(60).v3!.requirements.requiresConstraintAccessory, isTrue);
  });

  test('cards 61 to 90 preserve session, gaze and media semantics', () {
    CardDefinition card(int order) =>
        catalog.cards.singleWhere((card) => card.order == order);
    Set<String> tags(int order) => card(order).v3!.tags.toSet();

    expect(tags(61), contains('v3.preference.yeux_bandes'));
    expect(tags(62), isNot(contains('v3.preference.yeux_bandes')));
    expect(tags(62), isNot(contains('v3.preference.yeux_fermes')));
    expect(tags(62), contains('v3.preference.ordres'));
    expect(tags(66), containsAll(['v3.preference.frapper', 'v3.zone.fesses']));
    expect(tags(69), {'v3.preference.immobiliser', 'v3.direction.recevoir'});
    expect(tags(71), contains('v3.direction.etre_regarde'));
    expect(tags(71), isNot(contains('v3.preference.regarder')));
    expect(tags(72), contains('v3.preference.regarder'));
    expect(tags(72), isNot(contains('v3.direction.etre_regarde')));
    expect(tags(73), isNot(contains('v3.preference.regard_exterieur')));
    expect(tags(73), isNot(contains('v3.preference.lieu_expose')));
    expect(tags(75), {'v3.preference.danser', 'v3.direction.etre_regarde'});
    expect(tags(76), isNot(contains('v3.preference.danser')));
    for (final order in [77, 78]) {
      expect(tags(order), isNot(contains('v3.preference.position_s')));
      expect(tags(order), isNot(contains('v3.preference.position_a')));
      expect(tags(order), isNot(contains('v3.preference.position_e')));
    }
    for (final order in [79, 80]) {
      expect(
        tags(order),
        containsAll([
          'v3.preference.proximite_physique',
          'v3.direction.mutuel',
        ]),
      );
      expect(card(order).v3!.requirements.distanceExcluded, isTrue);
    }
    expect(tags(81), isNot(contains('v3.preference.sexting')));
    expect(tags(83), contains('v3.preference.photo'));
    expect(
      tags(84),
      containsAll(['v3.preference.photo', 'v3.preference.sous_vetements']),
    );
    expect(tags(87), contains('v3.preference.video'));
    expect(tags(85), isNot(contains('v3.preference.contenu_adulte')));
    for (final order in [88, 89]) {
      expect(tags(order), isEmpty);
      expect(tags(order), isNot(contains('v3.preference.visio')));
      expect(card(order).v3!.deckRemovalCandidate, isTrue);
      expect(card(order).v3!.sessionDataCandidate, isTrue);
    }
    expect(tags(90), {'v3.preference.ordres', 'v3.direction.recevoir'});
    expect(card(65).v3!.rationalizationCandidates, [
      'card.blindfold',
      'card.close_eyes',
      'card.temperature_play',
    ]);
  });
}
