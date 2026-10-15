import '../../core/json.dart';
import 'enums.dart';

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
    reader.only({'id', 'title', 'modifier'});
    id;
    title;
    modifier;
  }

  String get id => reader.string('id');
  String get title => reader.string('title');
  int get modifier => reader.integer('modifier', min: 0, max: 2);

  /// Applies only to generic zone actions, never to intrinsic intimate practices.
  int effectiveChili(int intrinsicChili) {
    RangeError.checkValueInInterval(intrinsicChili, 1, 4, 'intrinsicChili');
    return (intrinsicChili + modifier).clamp(1, 4);
  }
}

final class ConceptStage extends JsonModel {
  ConceptStage.read(super.reader) {
    reader.only({'id', 'title', 'chili'});
    id;
    title;
    chili;
  }

  String get id => reader.string('id');
  String get title => reader.string('title');
  int get chili => reader.integer('chili', min: 1, max: 4);
}

final class ConceptActionVariant extends JsonModel {
  ConceptActionVariant.read(super.reader) {
    reader.only({'id', 'title', 'chili', 'zone_id', 'free_zone'});
    id;
    title;
    chili;
    zoneId;
    freeZone;
    final forms = [chili != null, zoneId != null, freeZone];
    if (forms.where((present) => present).length != 1) {
      reader.fail(
        'chili/zone_id/free_zone',
        'Expected exactly one action form',
      );
    }
  }

  String get id => reader.string('id');
  String get title => reader.string('title');
  int? get chili => reader.optionalInteger('chili', min: 1, max: 4);
  String? get zoneId => reader.optionalString('zone_id');
  bool get freeZone => reader.boolean('free_zone', fallback: false);
}

final class CardConcept extends JsonModel {
  CardConcept.read(super.reader) {
    reader.only({
      'id',
      'title',
      'kind',
      'action_text',
      'details_text',
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

  String get id => reader.string('id');
  String get title => reader.string('title');
  ConceptKind get kind => reader.enumeration('kind', ConceptKind.values);
  String get actionText => reader.string('action_text');
  String? get detailsText => reader.optionalString('details_text');
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
