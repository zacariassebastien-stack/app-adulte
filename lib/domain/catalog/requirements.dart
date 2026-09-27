import '../../core/json.dart';
import 'enums.dart';

final class ProfileRequirement extends JsonModel {
  ProfileRequirement.fromJson(JsonMap json)
    : this.read(JsonReader(json, 'ProfileRequirement'));
  ProfileRequirement.read(super.reader) {
    reader.only({
      'element_id',
      'role',
      'requirement',
      'one_of_group_id',
      'minimum_status',
      'applies_to_variant_id',
    });
    elementId;
    role;
    requirement;
    oneOfGroupId;
    minimumStatus;
    appliesToVariantId;
    if ((requirement == RequirementKind.ONE_OF) != (oneOfGroupId != null)) {
      reader.fail(
        'one_of_group_id',
        'Required exactly when requirement is ONE_OF',
      );
    }
    if (minimumStatus != PreferenceStatus.ACCEPTED) {
      reader.fail('minimum_status', 'Only ACCEPTED is supported');
    }
  }
  String get elementId => reader.string('element_id');
  ProfileRole get role => reader.enumeration('role', ProfileRole.values);
  RequirementKind get requirement =>
      reader.enumeration('requirement', RequirementKind.values);
  String? get oneOfGroupId => reader.optionalString('one_of_group_id');
  PreferenceStatus get minimumStatus => reader.enumeration(
    'minimum_status',
    PreferenceStatus.values,
    fallback: PreferenceStatus.ACCEPTED,
  );
  String? get appliesToVariantId =>
      reader.optionalString('applies_to_variant_id');
}

/// Declarative data only: no evaluation and no scripts in phase 1.
final class TechnicalRequirement extends JsonModel {
  TechnicalRequirement.fromJson(JsonMap json)
    : this.read(JsonReader(json, 'TechnicalRequirement'));
  TechnicalRequirement.read(super.reader) {
    switch (type) {
      case TechnicalRequirementType.SESSION_MODE_IN:
        reader.only({'type', 'values'});
        final values = reader.strings('values');
        if (values.isEmpty) {
          reader.fail('values', 'At least one session mode required');
        }
        for (var i = 0; i < values.length; i++) {
          if (!SessionMode.values.any((v) => v.name == values[i])) {
            reader.fail(
              'values[$i]',
              'Unknown session mode',
              code: 'unknown_enum',
            );
          }
        }
      case TechnicalRequirementType.CLOTHES_AT_LEAST:
        reader.only({'type', 'target', 'value'});
        reader.enumeration('target', ParticipantRole.values);
        reader.integer('value', min: 0);
      case TechnicalRequirementType.PHYSICAL_STATE_IS:
        reader.only({'type', 'value'});
        reader.string('value');
      case TechnicalRequirementType.ACCESSORY_AVAILABLE:
        reader.only({'type', 'accessory_id'});
        reader.string('accessory_id');
      case TechnicalRequirementType.MEDIA_CAPABILITY_AVAILABLE:
        reader.only({'type', 'capability_id'});
        reader.string('capability_id');
      case TechnicalRequirementType.TEMPORARY_MEETING_ALLOWED:
        reader.only({'type'});
      case TechnicalRequirementType.SESSION_FLAG_IS:
        reader.only({'type', 'flag_id', 'value'});
        reader.string('flag_id');
        reader.boolean('value');
    }
  }
  TechnicalRequirementType get type =>
      reader.enumeration('type', TechnicalRequirementType.values);
  ParticipantRole? get target => reader.json.containsKey('target')
      ? reader.enumeration('target', ParticipantRole.values)
      : null;
  List<SessionMode> get sessionModes => List.unmodifiable(
    reader
        .strings('values', optional: true)
        .map((v) => SessionMode.values.byName(v)),
  );
  int? get minimumClothes => type == TechnicalRequirementType.CLOTHES_AT_LEAST
      ? reader.integer('value')
      : null;
  String? get physicalState =>
      type == TechnicalRequirementType.PHYSICAL_STATE_IS
      ? reader.string('value')
      : null;
  String? get accessoryId => reader.optionalString('accessory_id');
  String? get capabilityId => reader.optionalString('capability_id');
  String? get flagId => reader.optionalString('flag_id');
  bool? get flagValue => type == TechnicalRequirementType.SESSION_FLAG_IS
      ? reader.boolean('value')
      : null;
}

final class StateEffect extends JsonModel {
  StateEffect.fromJson(JsonMap json)
    : this.read(JsonReader(json, 'StateEffect'));
  StateEffect.read(super.reader) {
    switch (type) {
      case StateEffectType.CLOTHES_DELTA:
        reader.only({'type', 'target', 'delta'});
        reader.enumeration('target', ParticipantRole.values);
        reader.integer('delta');
      case StateEffectType.SET_PHYSICAL_STATE_TEMPORARY:
        reader.only({'type', 'value'});
        reader.string('value');
      case StateEffectType.RESTORE_PHYSICAL_STATE_AFTER_ACTION:
        reader.only({'type'});
      case StateEffectType.SET_SESSION_FLAG:
        reader.only({'type', 'flag_id', 'value'});
        reader.string('flag_id');
        reader.boolean('value');
      case StateEffectType.CLEAR_SESSION_FLAG:
        reader.only({'type', 'flag_id'});
        reader.string('flag_id');
    }
  }
  StateEffectType get type =>
      reader.enumeration('type', StateEffectType.values);
  ParticipantRole? get target => reader.json.containsKey('target')
      ? reader.enumeration('target', ParticipantRole.values)
      : null;
  int? get clothesDelta => reader.optionalInteger('delta');
  String? get physicalState =>
      type == StateEffectType.SET_PHYSICAL_STATE_TEMPORARY
      ? reader.string('value')
      : null;
  String? get flagId => reader.optionalString('flag_id');
  bool? get flagValue =>
      type == StateEffectType.SET_SESSION_FLAG ? reader.boolean('value') : null;
}
