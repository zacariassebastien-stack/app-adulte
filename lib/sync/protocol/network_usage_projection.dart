import '../../core/json.dart';
import '../../domain/round/concept_usage_snapshot.dart';

/// Explicit shared action contract, separate from the private usage checkpoint.
/// Current runtime DTOs are not routed through this contract until Lot 5/6.
final class NetworkUsageProjection extends JsonModel {
  NetworkUsageProjection.fromJson(JsonMap json)
    : super(JsonReader(json, 'NetworkUsageProjection')) {
    reader.only({
      'usage_schema_version',
      'usage_id',
      'concept_id',
      'owner_player_id',
      'native_direction',
      'effective_direction',
      'resolved_action',
      'snapshot_value',
      'inverted_resolution',
      'source_usage_id',
    });
    reader.integer('usage_schema_version', min: 1, max: 1);
    usageId;
    conceptId;
    ownerPlayerId;
    reader.string('native_direction');
    reader.string('effective_direction');
    if (!{
      'GENERAL',
      'FAIRE',
      'RECEVOIR',
      'MUTUEL',
      'SOLO',
      'SIMULTANE',
    }.contains(reader.string('native_direction'))) {
      reader.fail('native_direction', 'Unknown native direction');
    }
    snapshotValue;
    reader.optionalString('source_usage_id');
    for (final key in [
      'snapshot_value',
      'source_usage_id',
      'inverted_resolution',
    ]) {
      if (json.containsKey(key) && json[key] == null) {
        reader.fail(
          key,
          'Optional shared fields must be omitted rather than null',
        );
      }
    }
    _validateAction(
      reader.child(
        json['resolved_action'],
        'resolved_action',
        'SharedUsageAction',
      ),
    );
    if (resolvedAction['concept_id'] != conceptId ||
        resolvedAction['direction'] != reader.string('effective_direction')) {
      reader.fail(
        'resolved_action',
        'Resolved action identity/direction mismatch',
      );
    }
    if (json.containsKey('inverted_resolution')) {
      final inverse = reader.child(
        json['inverted_resolution'],
        'inverted_resolution',
        'SharedInversion',
      );
      inverse.only({'resolved_action', 'snapshot_value'});
      inverse.optionalInteger('snapshot_value', min: 1, max: 20);
      if (inverse.json.containsKey('snapshot_value') &&
          inverse.json['snapshot_value'] == null) {
        inverse.fail('snapshot_value', 'Omit an undisclosed value');
      }
      final action = inverse.child(
        inverse.json['resolved_action'],
        'resolved_action',
        'SharedUsageAction',
      );
      _validateAction(action);
      if (action.json['concept_id'] != conceptId ||
          action.json['stage_id'] != resolvedAction['stage_id'] ||
          action.json['variant_id'] != resolvedAction['variant_id']) {
        reader.fail(
          'inverted_resolution',
          'Inversion cannot select another definition',
        );
      }
    }
  }

  /// Parameter/effect disclosure is explicit. Never forward the private JSON.
  factory NetworkUsageProjection.fromSnapshot(
    ConceptUsageSnapshot usage, {
    required Set<String> sharedParameterKeys,
    required Set<String> sharedEffectIds,
    required bool includePersonalValue,
  }) {
    JsonMap projectAction(ResolvedConceptAction action) {
      final json = action.toJson();
      return {
        for (final key in _actionKeys)
          if (json.containsKey(key) && json[key] != null) key: json[key],
        'parameters': {
          for (final key in sharedParameterKeys)
            if (action.parameters.containsKey(key)) key: action.parameters[key],
        },
        'effects': [
          for (final effect in action.effects)
            if (sharedEffectIds.contains(effect.effectId)) effect.toJson(),
        ],
      };
    }

    int value(ResolvedConceptAction action) => action.personalValues
        .singleWhere((entry) => entry.playerId == usage.ownerPlayerId)
        .value;
    final inverse = usage.invertedAction;
    return NetworkUsageProjection.fromJson({
      'usage_schema_version': 1,
      'usage_id': usage.usageId,
      'concept_id': usage.conceptId,
      'owner_player_id': usage.ownerPlayerId,
      'native_direction': usage.action.direction.name,
      'effective_direction': usage.action.direction.name,
      'resolved_action': projectAction(usage.action),
      if (includePersonalValue) 'snapshot_value': value(usage.action),
      if (inverse != null)
        'inverted_resolution': {
          'resolved_action': projectAction(inverse),
          if (includePersonalValue) 'snapshot_value': value(inverse),
        },
      'source_usage_id': ?usage.sourceUsageId,
    });
  }

  static const _actionKeys = {
    'concept_id',
    'catalog_version',
    'locale',
    'stage_id',
    'variant_id',
    'zone_id',
    'effective_chili',
    'direction',
    'actor_player_ids',
    'target_player_ids',
    'parameters',
    'accessories',
    'tags',
    'primary_preference_ids',
    'effects',
    'action_text',
  };

  static void _validateAction(JsonReader r) {
    r.only(_actionKeys);
    final concept = r.string('concept_id');
    r.integer('catalog_version', min: 1);
    r.string('locale');
    final stage = r.optionalString('stage_id');
    final variant = r.optionalString('variant_id');
    for (final key in ['stage_id', 'variant_id', 'zone_id']) {
      if (r.json.containsKey(key) && r.json[key] == null) {
        r.fail(key, 'Omit an unresolved optional field');
      }
    }
    if ((stage == null) == (variant == null) ||
        !(stage ?? variant!).startsWith('$concept.')) {
      r.fail(
        'stage_id/variant_id',
        'One resolved definition of this concept is required',
      );
    }
    r.optionalString('zone_id');
    r.integer('effective_chili', min: 1, max: 4);
    final direction = r.string('direction');
    if (!{
      'GENERAL',
      'FAIRE',
      'RECEVOIR',
      'MUTUEL',
      'SOLO',
      'SIMULTANE',
    }.contains(direction)) {
      r.fail('direction', 'Unknown direction');
    }
    if (r.strings('actor_player_ids').isEmpty) {
      r.fail('actor_player_ids', 'Missing actor');
    }
    r.strings('target_player_ids');
    r.strings('tags');
    r.strings('primary_preference_ids');
    r.child(r.json['parameters'], 'parameters', 'SharedUsageParameters');
    for (final accessory in r.list('accessories')) {
      final child = r.child(accessory, 'accessories', 'SharedUsageAccessory');
      child.only({'accessory_id', 'label'});
      child.string('accessory_id');
      child.string('label');
    }
    for (final effect in r.list('effects')) {
      final child = r.child(effect, 'effects', 'SharedUsageEffect');
      child.only({'effect_id', 'parameters'});
      child.string('effect_id');
      child.child(
        child.json['parameters'],
        'parameters',
        'SharedUsageEffectParameters',
      );
    }
    r.string('action_text');
  }

  String get usageId => reader.string('usage_id');
  String get conceptId => reader.string('concept_id');
  String get ownerPlayerId => reader.string('owner_player_id');
  int? get snapshotValue =>
      reader.optionalInteger('snapshot_value', min: 1, max: 20);
  JsonMap get resolvedAction => reader
      .child(
        reader.json['resolved_action'],
        'resolved_action',
        'SharedUsageAction',
      )
      .json;

  /// Only selects an already frozen counterpart. It never recalculates values.
  NetworkUsageProjection resolved({required bool inverted}) {
    final json = Map<String, Object?>.from(toJson())
      ..remove('inverted_resolution');
    if (inverted) {
      final inverse = reader.child(
        reader.json['inverted_resolution'],
        'inverted_resolution',
        'SharedInversion',
      );
      final native = reader.string('native_direction');
      if (!{'FAIRE', 'RECEVOIR'}.contains(native) ||
          !inverse.json.containsKey('snapshot_value') ||
          (inverse.json['resolved_action']! as JsonMap)['direction'] !=
              (native == 'FAIRE' ? 'RECEVOIR' : 'FAIRE')) {
        reader.fail('inverted_resolution', 'No applicable frozen inversion');
      }
      json['resolved_action'] = inverse.json['resolved_action'];
      json['effective_direction'] =
          (inverse.json['resolved_action']! as JsonMap)['direction'];
      json.remove('snapshot_value');
      if (inverse.json.containsKey('snapshot_value')) {
        json['snapshot_value'] = inverse.json['snapshot_value'];
      }
    }
    return NetworkUsageProjection.fromJson(json);
  }
}
