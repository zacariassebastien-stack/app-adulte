import '../../core/json.dart';
import '../../engines/usage/concept_usage_checkpoint.dart';
import '../local/media_guard.dart';

/// Temporary opt-in bridge to existing PersistedRoundState.state / state_json.
/// No existing producer uses it yet. Retire when the canonical game checkpoint
/// owns usage state directly; it never interprets a legacy occurrence.
final class ConceptUsageCheckpointCodec {
  const ConceptUsageCheckpointCodec();
  static const key = 'concept_usage_v1';

  JsonMap attach({
    required JsonMap roundState,
    required ConceptUsageCheckpoint checkpoint,
  }) {
    final payload = checkpoint.toJson();
    assertNoPersistedMedia(payload);
    return freezeJson({...roundState, key: payload})! as JsonMap;
  }

  ConceptUsageCheckpoint? read(JsonMap roundState) {
    if (!roundState.containsKey(key)) return null;
    final reader = JsonReader(roundState, 'ConceptUsageCheckpointCodec');
    final json = reader
        .child(roundState[key], key, 'ConceptUsageCheckpoint')
        .json;
    assertNoPersistedMedia(json);
    return ConceptUsageCheckpoint.fromJson(json);
  }
}
