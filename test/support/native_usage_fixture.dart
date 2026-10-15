import 'package:couple_cards/sync/protocol/network_usage_projection.dart';

NetworkUsageProjection nativeUsageFixture({
  String conceptId = '019',
  String usageId = 'usage-test',
  String owner = 'alice',
  String direction = 'FAIRE',
  int value = 10,
  int chili = 3,
  String? sourceUsageId,
}) {
  Map<String, Object?> action(String d) => {
    'concept_id': conceptId,
    'catalog_version': 1,
    'locale': 'fr-FR',
    'stage_id': '$conceptId.stage.1',
    'effective_chili': chili,
    'direction': d,
    'actor_player_ids': d == 'MUTUEL'
        ? ['alice', 'bob']
        : [d == 'RECEVOIR' ? (owner == 'alice' ? 'bob' : 'alice') : owner],
    'target_player_ids': d == 'MUTUEL'
        ? ['alice', 'bob']
        : d == 'SOLO'
        ? <String>[]
        : [d == 'RECEVOIR' ? owner : (owner == 'alice' ? 'bob' : 'alice')],
    'parameters': {'committed_at': '2026-10-15T12:00:00.000Z'},
    'accessories': <Object?>[],
    'effects': <Object?>[],
    'tags': ['v3.preference.masturbation'],
    'primary_preference_ids': ['v3.preference.masturbation'],
    'action_text': 'Frozen test action',
  };
  return NetworkUsageProjection.fromJson({
    'usage_schema_version': 1,
    'concept_id': conceptId,
    'usage_id': usageId,
    'owner_player_id': owner,
    'native_direction': direction,
    'effective_direction': direction,
    'snapshot_value': value,
    'resolved_action': action(direction),
    if (direction == 'FAIRE' || direction == 'RECEVOIR')
      'inverted_resolution': {
        'snapshot_value': value,
        'resolved_action': action(direction == 'FAIRE' ? 'RECEVOIR' : 'FAIRE'),
      },
    'source_usage_id': ?sourceUsageId,
  });
}
