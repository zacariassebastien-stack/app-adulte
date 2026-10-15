import 'dart:convert';

import 'package:couple_cards/core/errors/catalog_error.dart';
import 'package:couple_cards/core/json.dart';
import 'package:couple_cards/domain/round/concept_usage_snapshot.dart';
import 'package:couple_cards/sync/protocol/network_usage_projection.dart';

void _check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void _throws<T extends Object>(void Function() action) {
  try {
    action();
  } catch (error) {
    if (error is T) return;
    rethrow;
  }
  throw StateError('Expected $T');
}

JsonMap _decode(String value) =>
    (jsonDecode(value) as Map).cast<String, Object?>();

ConceptUsageSnapshot _usage({String intent = 'first'}) {
  final action = <String, Object?>{
    'concept_id': '045',
    'catalog_version': 1,
    'locale': 'fr-FR',
    'stage_id': '045.stage.1',
    'zone_id': 'arms_hands',
    'effective_chili': 1,
    'direction': 'FAIRE',
    'actor_player_ids': ['alice'],
    'target_player_ids': ['bob'],
    'parameters': {
      'chosen': 'resolved',
      'private_calculation': {'score': 17},
    },
    'accessories': [
      {'accessory_id': 'actual-device', 'label': 'Chosen device'},
    ],
    'tags': ['v3.preference.photo', 'v3.zone.bras'],
    'primary_preference_ids': ['v3.preference.photo'],
    'personal_values': [
      {'player_id': 'alice', 'role': 'FAIRE', 'value': 7},
      {'player_id': 'bob', 'role': 'RECEVOIR', 'value': 19},
    ],
    'effects': [
      {
        'effect_id': 'shared-effect',
        'parameters': {'duration_actions': 3},
      },
      {
        'effect_id': 'private-effect',
        'parameters': {'private_input': 17},
      },
    ],
    'action_text': 'Frozen resolved instruction',
  };
  final inverse = _decode(jsonEncode(action));
  inverse['direction'] = 'RECEVOIR';
  inverse['actor_player_ids'] = ['bob'];
  inverse['target_player_ids'] = ['alice'];
  inverse['personal_values'] = [
    {'player_id': 'alice', 'role': 'RECEVOIR', 'value': 12},
  ];
  return ConceptUsageSnapshot.create(
    sessionId: 's',
    ownerPlayerId: 'alice',
    cycle: 1,
    intentId: intent,
    engagedAt: DateTime.utc(2026, 10, 15),
    action: ResolvedConceptAction.fromJson(action),
    invertedAction: ResolvedConceptAction.fromJson(inverse),
  );
}

NetworkUsageProjection _projection({
  bool values = true,
  String intent = 'first',
}) => NetworkUsageProjection.fromSnapshot(
  _usage(intent: intent),
  sharedParameterKeys: {'chosen'},
  sharedEffectIds: {'shared-effect'},
  includePersonalValue: values,
);

Map<String, void Function()> networkUsageChecks() => {
  'projection omits optional nulls to match native PostgreSQL presence checks':
      () {
        final actionJson = Map<String, Object?>.from(_usage().action.toJson());
        actionJson['variant_id'] = null;
        actionJson['zone_id'] = null;
        final usage = ConceptUsageSnapshot.create(
          sessionId: 's',
          ownerPlayerId: 'alice',
          cycle: 1,
          intentId: 'null-optionals',
          engagedAt: DateTime.utc(2026, 10, 15),
          action: ResolvedConceptAction.fromJson(actionJson),
        );
        final projection = NetworkUsageProjection.fromSnapshot(
          usage,
          sharedParameterKeys: {},
          sharedEffectIds: {},
          includePersonalValue: true,
        );
        _check(
          !projection.resolvedAction.containsKey('variant_id') &&
              !projection.resolvedAction.containsKey('zone_id'),
          'Optional null leaked to SQL',
        );
        final invalid = _decode(canonicalUsageJson(projection.toJson()));
        invalid['snapshot_value'] = null;
        _throws<CatalogException>(
          () => NetworkUsageProjection.fromJson(invalid),
        );
      },
  'usage_id and concept_id are canonical without legacy card/occurrence aliases':
      () {
        final p = _projection();
        _check(
          p.usageId == _usage().usageId && p.conceptId == '045',
          'Canonical identity',
        );
        _check(
          !p.toJson().containsKey('card_id') &&
              !p.toJson().containsKey('occurrence_id'),
          'Legacy server alias',
        );
      },
  'same concept and same stage retain distinct usage references': () {
    final a = _projection(intent: 'a');
    final b = _projection(intent: 'b');
    _check(
      a.conceptId == b.conceptId &&
          a.usageId != b.usageId &&
          a.resolvedAction['stage_id'] == b.resolvedAction['stage_id'],
      'Usages collapsed',
    );
  },
  'public projection round trip keeps exact resolved choices and identity': () {
    final a = _projection();
    final b = NetworkUsageProjection.fromJson(
      _decode(canonicalUsageJson(a.toJson())),
    );
    _check(
      canonicalUsageJson(a.toJson()) == canonicalUsageJson(b.toJson()),
      'Round trip',
    );
    _check(
      b.resolvedAction['zone_id'] == 'arms_hands' &&
          b.resolvedAction['effective_chili'] == 1 &&
          b.resolvedAction['action_text'] == 'Frozen resolved instruction',
      'Frozen action lost',
    );
  },
  'private values and calculation inputs are not copied wholesale': () {
    final p = _projection();
    final encoded = canonicalUsageJson(p.toJson());
    _check(
      p.snapshotValue == 7 &&
          !encoded.contains('personal_values') &&
          !encoded.contains('private_calculation') &&
          !encoded.contains('private-effect') &&
          !encoded.contains('private_input'),
      'Private snapshot leaked',
    );
    _check(
      !p.toJson().containsKey('intent_id') && !p.toJson().containsKey('stock'),
      'Private checkpoint leaked',
    );
  },
  'Recovery and corruption projections can omit all personal values': () {
    final p = _projection(values: false);
    _check(
      p.snapshotValue == null &&
          !(p.toJson()['inverted_resolution'] as JsonMap).containsKey(
            'snapshot_value',
          ),
      'Secondary proposal disclosed personal values',
    );
    _check(
      p.resolvedAction['action_text'] == 'Frozen resolved instruction',
      'Public action absent',
    );
  },
  'semantic tags and primary editorial preferences survive for deterministic learning':
      () {
        final action = _projection().resolvedAction;
        _check(
          (action['tags'] as List).contains('v3.zone.bras') &&
              (action['primary_preference_ids'] as List).single ==
                  'v3.preference.photo',
          'Learning would need current catalogue',
        );
      },
  'parameter and effect disclosure is explicit and concrete accessories survive':
      () {
        final action = _projection().resolvedAction;
        _check(
          (action['parameters'] as JsonMap).keys.single == 'chosen',
          'Parameters not projected',
        );
        _check(
          ((action['effects'] as List).single as JsonMap)['effect_id'] ==
              'shared-effect',
          'Effects not projected',
        );
        _check(
          ((action['accessories'] as List).single as JsonMap)['accessory_id'] ==
              'actual-device',
          'Concrete accessory lost',
        );
      },
  'resolved compromise selects frozen inversion without catalogue/profile lookup':
      () {
        final p = _projection();
        final before = canonicalUsageJson(p.toJson());
        final inverted = p.resolved(inverted: true);
        _check(
          inverted.usageId == p.usageId &&
              inverted.snapshotValue == 12 &&
              inverted.resolvedAction['direction'] == 'RECEVOIR' &&
              (inverted.resolvedAction['actor_player_ids'] as List).single ==
                  'bob',
          'Inversion reconstruction',
        );
        _check(
          canonicalUsageJson(p.toJson()) == before &&
              !inverted.toJson().containsKey('inverted_resolution'),
          'Original mutated or alternate retained',
        );
        _check(p.resolved(inverted: false).snapshotValue == 7, 'Native value');
      },
  'shared data is deeply immutable after deserialization': () {
    final source = _decode(canonicalUsageJson(_projection().toJson()));
    final p = NetworkUsageProjection.fromJson(source);
    (source['resolved_action'] as JsonMap)['action_text'] = 'changed';
    _check(
      p.resolvedAction['action_text'] == 'Frozen resolved instruction',
      'Mutable source alias',
    );
    _throws<UnsupportedError>(() => p.toJson().clear());
    _throws<UnsupportedError>(
      () => (p.resolvedAction['parameters'] as JsonMap).clear(),
    );
  },
  'parser rejects private complete snapshot masquerading as shared projection':
      () {
        _throws<CatalogException>(
          () => NetworkUsageProjection.fromJson(_usage().toJson()),
        );
        final json = _decode(canonicalUsageJson(_projection().toJson()));
        (json['resolved_action'] as JsonMap)['personal_values'] = [];
        _throws<CatalogException>(() => NetworkUsageProjection.fromJson(json));
      },
  'parser rejects inconsistent action identity and inverted stage': () {
    final bad = _decode(canonicalUsageJson(_projection().toJson()));
    bad['concept_id'] = 'other';
    _throws<CatalogException>(() => NetworkUsageProjection.fromJson(bad));
    final inverse = _decode(canonicalUsageJson(_projection().toJson()));
    ((inverse['inverted_resolution'] as JsonMap)['resolved_action']
            as JsonMap)['stage_id'] =
        '045.stage.2';
    _throws<CatalogException>(() => NetworkUsageProjection.fromJson(inverse));
  },
  'codec never resolves an inversion from unavailable values or mutable direction':
      () {
        _throws<CatalogException>(
          () => _projection(values: false).resolved(inverted: true),
        );
        final bad = _decode(canonicalUsageJson(_projection().toJson()));
        bad['native_direction'] = 'MUTUEL';
        _throws<CatalogException>(
          () => NetworkUsageProjection.fromJson(bad).resolved(inverted: true),
        );
      },
};
