import 'dart:collection';
import 'dart:convert';

import '../../core/json.dart';
import '../catalog/enums.dart';
import '../game/game_models.dart' show CardOccurrenceDirection;

/// A value resolved for this action, not a reference to the current profile.
final class UsagePersonalValue extends JsonModel {
  UsagePersonalValue.read(super.reader) {
    reader.only({'player_id', 'role', 'value'});
    playerId;
    role;
    value;
  }
  String get playerId => reader.string('player_id');
  ProfileRole get role => reader.enumeration('role', ProfileRole.values);
  int get value => reader.integer('value', min: 1, max: 20);
}

final class UsageAccessory extends JsonModel {
  UsageAccessory.read(super.reader) {
    reader.only({'accessory_id', 'label'});
    accessoryId;
    label;
  }
  String get accessoryId => reader.string('accessory_id');
  String get label => reader.string('label');
}

/// Frozen effect inputs; remaining turns, execution and acceptance stay outside.
final class UsageEffect extends JsonModel {
  UsageEffect.read(super.reader) {
    reader.only({'effect_id', 'parameters'});
    effectId;
    parameters;
  }
  String get effectId => reader.string('effect_id');
  JsonMap get parameters =>
      reader.child(reader.json['parameters'], 'parameters', 'UsageEffect').json;
}

/// Self-contained resolved action. Reconstruction never consults a catalogue,
/// profile, equipment inventory or the current global chili/clothing state.
final class ResolvedConceptAction extends JsonModel {
  ResolvedConceptAction.fromJson(JsonMap json)
    : this.read(JsonReader(json, 'ResolvedConceptAction'));

  ResolvedConceptAction.read(super.reader) {
    reader.only({
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
      'personal_values',
      'effects',
      'action_text',
    });
    conceptId;
    catalogVersion;
    locale;
    stageId;
    variantId;
    zoneId;
    effectiveChili;
    direction;
    actionText;
    parameters;
    if ((stageId == null) == (variantId == null)) {
      reader.fail(
        'stage_id/variant_id',
        'Exactly one action definition is required',
      );
    }
    if (!(stageId ?? variantId!).startsWith('$conceptId.')) {
      reader.fail('stage_id/variant_id', 'Action must belong to its concept');
    }
    _unique(actorPlayerIds, 'actor_player_ids');
    _unique(targetPlayerIds, 'target_player_ids');
    if (actorPlayerIds.isEmpty) {
      reader.fail('actor_player_ids', 'Missing resolved actor');
    }
    _unique(tags, 'tags');
    _unique(primaryPreferenceIds, 'primary_preference_ids');
    if (!tags.toSet().containsAll(primaryPreferenceIds)) {
      reader.fail(
        'primary_preference_ids',
        'Primary preferences must be frozen tags',
      );
    }
    accessories = reader.objects(
      'accessories',
      UsageAccessory.read,
      'UsageAccessory',
    );
    personalValues = reader.objects(
      'personal_values',
      UsagePersonalValue.read,
      'UsagePersonalValue',
    );
    effects = reader.objects('effects', UsageEffect.read, 'UsageEffect');
    _unique(accessories.map((value) => value.accessoryId), 'accessories');
    _unique(personalValues.map((value) => value.playerId), 'personal_values');
    final participants = {...actorPlayerIds, ...targetPlayerIds};
    if (personalValues.isEmpty ||
        personalValues.any((value) => !participants.contains(value.playerId))) {
      reader.fail(
        'personal_values',
        'Values must identify resolved participants',
      );
    }
    // Reject non-JSON numbers/values at creation rather than during persistence.
    jsonEncode(reader.json);
  }

  String get conceptId => reader.string('concept_id');
  int get catalogVersion => reader.integer('catalog_version', min: 1);
  String get locale => reader.string('locale');
  String? get stageId => reader.optionalString('stage_id');
  String? get variantId => reader.optionalString('variant_id');
  String? get zoneId => reader.optionalString('zone_id');
  int get effectiveChili => reader.integer('effective_chili', min: 1, max: 4);
  CardOccurrenceDirection get direction =>
      reader.enumeration('direction', CardOccurrenceDirection.values);
  List<String> get actorPlayerIds => reader.strings('actor_player_ids');
  List<String> get targetPlayerIds => reader.strings('target_player_ids');
  JsonMap get parameters => reader
      .child(reader.json['parameters'], 'parameters', 'ResolvedConceptAction')
      .json;
  List<String> get tags => reader.strings('tags');
  List<String> get primaryPreferenceIds =>
      reader.strings('primary_preference_ids');
  String get actionText => reader.string('action_text');
  late final List<UsageAccessory> accessories;
  late final List<UsagePersonalValue> personalValues;
  late final List<UsageEffect> effects;

  void _unique(Iterable<String> values, String field) {
    final seen = <String>{};
    for (final value in values) {
      if (!seen.add(value)) {
        reader.fail(field, 'Duplicate resolved identity: $value');
      }
    }
  }
}

/// Private local persistence contract. toJson is not a public network DTO.
final class ConceptUsageSnapshot extends JsonModel {
  ConceptUsageSnapshot.create({
    required String sessionId,
    required String ownerPlayerId,
    required int cycle,
    required String intentId,
    required DateTime engagedAt,
    required ResolvedConceptAction action,
    ResolvedConceptAction? invertedAction,
    String? sourceUsageId,
  }) : this.fromJson({
         'schema_version': 1,
         'usage_id': identityFor(sessionId, ownerPlayerId, cycle, intentId),
         'session_id': sessionId,
         'owner_player_id': ownerPlayerId,
         'cycle': cycle,
         'intent_id': intentId,
         'engaged_at': engagedAt.toUtc().toIso8601String(),
         'action': action.toJson(),
         'inverted_action': ?invertedAction?.toJson(),
         'source_usage_id': ?sourceUsageId,
       });

  ConceptUsageSnapshot.fromJson(JsonMap json)
    : super(JsonReader(json, 'ConceptUsageSnapshot')) {
    reader.only({
      'schema_version',
      'usage_id',
      'session_id',
      'owner_player_id',
      'cycle',
      'intent_id',
      'engaged_at',
      'action',
      'inverted_action',
      'source_usage_id',
    });
    reader.integer('schema_version', min: 1, max: 1);
    usageId;
    sessionId;
    ownerPlayerId;
    cycle;
    intentId;
    engagedAt;
    sourceUsageId;
    if (usageId != identityFor(sessionId, ownerPlayerId, cycle, intentId)) {
      reader.fail('usage_id', 'Usage identity does not match its intent scope');
    }
    action = ResolvedConceptAction.read(
      reader.child(reader.json['action'], 'action', 'ResolvedConceptAction'),
    );
    invertedAction = reader.json['inverted_action'] == null
        ? null
        : ResolvedConceptAction.read(
            reader.child(
              reader.json['inverted_action'],
              'inverted_action',
              'ResolvedConceptAction',
            ),
          );
    for (final resolution in [action, ?invertedAction]) {
      if (!resolution.personalValues.any(
        (value) => value.playerId == ownerPlayerId,
      )) {
        reader.fail('action.personal_values', 'Missing owner value');
      }
      if (resolution.conceptId != action.conceptId ||
          resolution.stageId != action.stageId ||
          resolution.variantId != action.variantId) {
        reader.fail(
          'inverted_action',
          'Inversion cannot substitute another action',
        );
      }
    }
  }

  /// An injective encoding of a scoped logical intent, not a card/stage ID.
  /// The caller reuses intentId on retry and uses a new one for each new usage.
  static String identityFor(
    String session,
    String owner,
    int cycle,
    String intent,
  ) {
    for (final id in [session, owner, intent]) {
      if (id.trim().isEmpty) throw ArgumentError('Empty usage scope/intent');
    }
    if (cycle < 1) throw RangeError.range(cycle, 1, null, 'cycle');
    return 'usage:v1:${base64Url.encode(utf8.encode(jsonEncode([session, owner, cycle, intent])))}';
  }

  String get usageId => reader.string('usage_id');
  String get sessionId => reader.string('session_id');
  String get ownerPlayerId => reader.string('owner_player_id');
  int get cycle => reader.integer('cycle', min: 1);
  String get intentId => reader.string('intent_id');
  DateTime get engagedAt => reader.dateTime('engaged_at');
  String? get sourceUsageId => reader.optionalString('source_usage_id');
  String get conceptId => action.conceptId;
  late final ResolvedConceptAction action;
  late final ResolvedConceptAction? invertedAction;

  /// The caller's existing resolution rules choose the projection, not this codec.
  ResolvedConceptAction reconstruct({bool inverted = false}) {
    if (!inverted) return action;
    return invertedAction ??
        (throw StateError('No frozen inverted resolution'));
  }

  String encode() => canonicalUsageJson(toJson());
}

/// Stable local encoding; no digest, signature or network protocol introduced.
String canonicalUsageJson(JsonMap value) {
  Object? ordered(Object? item) {
    if (item is JsonMap) {
      return SplayTreeMap<String, Object?>.from({
        for (final entry in item.entries) entry.key: ordered(entry.value),
      });
    }
    if (item is List<Object?>) return item.map(ordered).toList();
    return item;
  }

  return jsonEncode(ordered(value));
}
