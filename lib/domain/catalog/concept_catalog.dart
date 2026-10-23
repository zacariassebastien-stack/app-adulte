import '../../core/json.dart';
import 'enums.dart';
import '../profile/v4_profile.dart' show PlayerAnatomy;
import '../game/game_models.dart' show CardOccurrenceDirection;

enum ConceptKind { action, evolution, zones, accessory }

// These values are serialized exactly as written in the editorial contract.
// ignore: constant_identifier_names
enum ConceptCapacityRule { initial_clothing_single, initial_clothing_double }

/// Editorial definitions only. No draw, quota runtime or session migration.
final class ConceptCatalog extends JsonModel {
  ConceptCatalog.fromJson(JsonMap json)
    : super(JsonReader(json, 'ConceptCatalog')) {
    reader.only({
      'schema_version',
      'catalog_version',
      'locale',
      'source',
      'zones',
      'concepts',
    });
    reader.integer('schema_version', min: 1, max: 1);
    reader.integer('catalog_version', min: 1);
    reader.string('locale');
    reader.string('source');
    zones = reader.objects('zones', ConceptBodyZone.read, 'ConceptBodyZone');
    concepts = reader.objects('concepts', CardConcept.read, 'CardConcept');
    _unique(zones.map((zone) => zone.id), 'zones');
    _unique(concepts.map((concept) => concept.id), 'concepts');
    _unique([
      for (final concept in concepts) ...[
        ...concept.stages.map((stage) => stage.id),
        ...concept.variants.map((variant) => variant.id),
      ],
    ], 'actions');
    final zoneIds = zones.map((zone) => zone.id).toSet();
    for (final concept in concepts) {
      for (final actionId in [
        ...concept.stages.map((stage) => stage.id),
        ...concept.variants.map((variant) => variant.id),
      ]) {
        if (!actionId.startsWith('${concept.id}.')) {
          reader.fail('concepts', 'Action identity belongs to another concept');
        }
      }
      for (final variant in concept.variants) {
        if (variant.zoneId != null && !zoneIds.contains(variant.zoneId)) {
          reader.fail('concepts', 'Unknown zone on ${variant.id}');
        }
      }
    }
  }

  late final List<ConceptBodyZone> zones;
  late final List<CardConcept> concepts;

  void _unique(Iterable<String> ids, String property) {
    final seen = <String>{};
    for (final id in ids) {
      if (!seen.add(id)) reader.fail(property, 'Duplicate identity: $id');
    }
  }
}

final class ConceptBodyZone extends JsonModel {
  ConceptBodyZone.read(super.reader) {
    reader.only({
      'id',
      'title',
      'modifier',
      'object_form',
      'possessive_form',
      'composed',
    });
    id;
    title;
    modifier;
    objectForm;
    possessiveForm;
    composed;
  }

  String get id => reader.string('id');
  String get title => reader.string('title');
  int get modifier => reader.integer('modifier', min: 0, max: 2);
  String get objectForm => reader.string('object_form');
  String get possessiveForm => reader.string('possessive_form');
  bool get composed => reader.boolean('composed', fallback: false);

  /// Applies only to generic zone actions, never to intrinsic intimate practices.
  int effectiveChili(int intrinsicChili) {
    RangeError.checkValueInInterval(intrinsicChili, 1, 4, 'intrinsicChili');
    return (intrinsicChili + modifier).clamp(1, 4);
  }
}

final class ConceptStage extends JsonModel {
  ConceptStage.read(super.reader) {
    anatomyRequirements;
    reader.only({
      'anatomy_requirements',
      'id',
      'title',
      'chili',
      'action_text',
      'details_text',
      'action_templates',
    });
    id;
    title;
    chili;
    actionText;
    detailsText;
    actionTemplates;
  }

  AnatomyRequirements? get anatomyRequirements =>
      AnatomyRequirements.read(reader.json['anatomy_requirements']);

  String get id => reader.string('id');
  String get title => reader.string('title');
  int get chili => reader.integer('chili', min: 1, max: 4);
  String? get actionText => reader.optionalString('action_text');
  String? get detailsText => reader.optionalString('details_text');
  Map<String, String> get actionTemplates => _directionTemplates(reader);
}

final class ConceptActionVariant extends JsonModel {
  ConceptActionVariant.read(super.reader) {
    anatomyRequirements;
    reader.only({
      'anatomy_requirements',
      'id',
      'title',
      'chili',
      'zone_id',
      'free_zone',
      'action_text',
      'details_text',
      'action_templates',
    });
    id;
    title;
    chili;
    zoneId;
    freeZone;
    actionText;
    detailsText;
    actionTemplates;
    final forms = [chili != null, zoneId != null, freeZone];
    if (forms.where((present) => present).length != 1) {
      reader.fail(
        'chili/zone_id/free_zone',
        'Expected exactly one action form',
      );
    }
  }

  AnatomyRequirements? get anatomyRequirements =>
      AnatomyRequirements.read(reader.json['anatomy_requirements']);

  String get id => reader.string('id');
  String get title => reader.string('title');
  int? get chili => reader.optionalInteger('chili', min: 1, max: 4);
  String? get zoneId => reader.optionalString('zone_id');
  bool get freeZone => reader.boolean('free_zone', fallback: false);
  String? get actionText => reader.optionalString('action_text');
  String? get detailsText => reader.optionalString('details_text');
  Map<String, String> get actionTemplates => _directionTemplates(reader);
}

final class CardConcept extends JsonModel {
  CardConcept.read(super.reader) {
    anatomyRequirements;
    reader.only({
      'anatomy_requirements',
      'id',
      'title',
      'kind',
      'action_text',
      'details_text',
      'action_templates',
      'free_action_templates',
      'composed_details_text',
      'stages',
      'variants',
      'intrinsic_chili',
      'selection_axes',
      'capacity_rule',
      'persistent_effect',
      'session_modes',
    });
    id;
    title;
    kind;
    actionText;
    detailsText;
    actionTemplates;
    freeActionTemplates;
    composedDetailsText;
    intrinsicChili;
    capacityRule;
    persistentEffect;
    sessionModes;
    stages = reader.objects(
      'stages',
      ConceptStage.read,
      'ConceptStage',
      optional: true,
    );
    variants = reader.objects(
      'variants',
      ConceptActionVariant.read,
      'ConceptActionVariant',
      optional: true,
    );
    final axes = reader.strings('selection_axes', optional: true);
    if (kind == ConceptKind.evolution) {
      if (stages.length < 2 || stages.length > 3 || variants.isNotEmpty) {
        reader.fail('stages', 'An evolution has 2 or 3 stages and no variants');
      }
    } else if (stages.isNotEmpty || variants.isEmpty) {
      reader.fail('variants', 'A non-evolution has variants and no stages');
    }
    if (kind == ConceptKind.action && variants.length != 1) {
      reader.fail('variants', 'A simple action has exactly one variant');
    }
    if (kind == ConceptKind.zones) {
      if (intrinsicChili == null ||
          variants.any((variant) => variant.chili != null) ||
          variants.where((variant) => variant.freeZone).length != 1) {
        reader.fail(
          'variants',
          'Zones need an intrinsic chili and one free choice',
        );
      }
      final fixedZones = variants.map((variant) => variant.zoneId).nonNulls;
      if (fixedZones.toSet().length != fixedZones.length) {
        reader.fail('variants', 'Duplicate fixed zone');
      }
    } else if (intrinsicChili != null ||
        variants.any((variant) => variant.chili == null)) {
      reader.fail(
        'intrinsic_chili',
        'Only generic zone actions add zone modifiers',
      );
    }
    if (freeActionTemplates.isNotEmpty && kind != ConceptKind.zones) {
      reader.fail(
        'free_action_templates',
        'Only generic zone actions have a free action template',
      );
    }
    if (composedDetailsText != null && kind != ConceptKind.zones) {
      reader.fail(
        'composed_details_text',
        'Only generic zone actions have composed body parts',
      );
    }
    if (kind == ConceptKind.accessory) {
      if (axes.length != 2 ||
          axes.toSet().length != 2 ||
          !axes.contains('zone') ||
          !axes.contains('accessory')) {
        reader.fail('selection_axes', 'Expected zone and accessory selection');
      }
    } else if (axes.isNotEmpty) {
      reader.fail('selection_axes', 'Only accessory variants use these axes');
    }
    if (capacityRule != null && kind != ConceptKind.action) {
      reader.fail('capacity_rule', 'Clothing capacity is not an evolution');
    }
  }

  AnatomyRequirements? get anatomyRequirements =>
      AnatomyRequirements.read(reader.json['anatomy_requirements']);

  String get id => reader.string('id');
  String get title => reader.string('title');
  ConceptKind get kind => reader.enumeration('kind', ConceptKind.values);
  String get actionText => reader.string('action_text');
  String? get detailsText => reader.optionalString('details_text');
  Map<String, String> get actionTemplates => _directionTemplates(reader);
  Map<String, String> get freeActionTemplates =>
      _directionTemplates(reader, key: 'free_action_templates');
  String? get composedDetailsText =>
      reader.optionalString('composed_details_text');
  int? get intrinsicChili =>
      reader.optionalInteger('intrinsic_chili', min: 1, max: 4);
  ConceptCapacityRule? get capacityRule =>
      reader.json.containsKey('capacity_rule')
      ? reader.enumeration('capacity_rule', ConceptCapacityRule.values)
      : null;
  bool get persistentEffect =>
      reader.boolean('persistent_effect', fallback: false);

  /// Absence means unspecified here, never implicitly all session modes.
  List<SessionMode> get sessionModes => List.unmodifiable([
    for (final value in reader.strings('session_modes', optional: true))
      SessionMode.values.firstWhere(
        (mode) => mode.name == value,
        orElse: () =>
            reader.fail('session_modes', 'Unknown session mode: $value'),
      ),
  ]);

  late final List<ConceptStage> stages;
  late final List<ConceptActionVariant> variants;
}

Map<String, String> _directionTemplates(
  JsonReader reader, {
  String key = 'action_templates',
}) {
  final raw = reader.readerObject(key);
  if (raw == null) return const {};
  const directions = {'FAIRE', 'RECEVOIR', 'MUTUEL', 'SIMULTANE', 'SOLO'};
  final result = <String, String>{};
  for (final entry in raw.entries) {
    if (!directions.contains(entry.key)) {
      reader.fail(key, 'Unknown editorial direction: ${entry.key}');
    }
    if (entry.value is! String || (entry.value! as String).trim().isEmpty) {
      reader.fail('$key.${entry.key}', 'Expected non-empty string');
    }
    result[entry.key] = entry.value! as String;
  }
  return Map.unmodifiable(result);
}

/// Declarative requirements, relative to the occurrence owner, by effective direction.
final class AnatomyRequirements {
  AnatomyRequirements._(this.byDirection);
  final Map<CardOccurrenceDirection, Map<String, PlayerAnatomy>> byDirection;
  static AnatomyRequirements? read(Object? value) {
    if (value == null) return null;
    if (value is! Map) {
      throw const FormatException('Invalid anatomy requirements');
    }
    final result = <CardOccurrenceDirection, Map<String, PlayerAnatomy>>{};
    for (final entry in value.entries) {
      final direction = CardOccurrenceDirection.values
          .where((d) => d.name == entry.key)
          .firstOrNull;
      if (direction == null || entry.value is! Map) {
        throw const FormatException('Invalid anatomy direction');
      }
      final requirements = <String, PlayerAnatomy>{};
      for (final requirement in (entry.value as Map).entries) {
        final anatomy = PlayerAnatomy.values
            .where((a) => a.name == requirement.value)
            .firstOrNull;
        if (!{'OWNER', 'PARTNER'}.contains(requirement.key) ||
            anatomy == null) {
          throw const FormatException('Invalid anatomy subject or value');
        }
        requirements[requirement.key as String] = anatomy;
      }
      result[direction] = Map.unmodifiable(requirements);
    }
    return AnatomyRequirements._(Map.unmodifiable(result));
  }
}
