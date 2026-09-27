import '../../core/json.dart';
import '../catalog/enums.dart';

/// Private player data. Never embed this model in a public session projection.
final class UserPreference extends JsonModel {
  UserPreference.fromJson(JsonMap json)
    : super(
        JsonReader(
          json,
          'UserPreference',
          ownerId: json['profile_element_id'] is String
              ? json['profile_element_id']! as String
              : '<missing>',
        ),
      ) {
    profileElementId;
    status;
    generalValue;
    faireValue;
    recevoirValue;
    updatedAt;
    source;
  }
  String get profileElementId => reader.string('profile_element_id');
  PreferenceStatus get status =>
      reader.enumeration('status', PreferenceStatus.values);
  int? get generalValue =>
      reader.optionalInteger('general_value', min: 1, max: 20);
  int? get faireValue => reader.optionalInteger('faire_value', min: 1, max: 20);
  int? get recevoirValue =>
      reader.optionalInteger('recevoir_value', min: 1, max: 20);
  DateTime get updatedAt => reader.dateTime('updated_at');
  PreferenceSource get source =>
      reader.enumeration('source', PreferenceSource.values);
}

final class CardPreferenceOverride extends JsonModel {
  CardPreferenceOverride.fromJson(JsonMap json)
    : super(
        JsonReader(
          json,
          'CardPreferenceOverride',
          ownerId: json['card_or_variant_id'] is String
              ? json['card_or_variant_id']! as String
              : '<missing>',
        ),
      ) {
    cardOrVariantId;
    status;
    faireValue;
    recevoirValue;
    updatedAt;
  }
  String get cardOrVariantId => reader.string('card_or_variant_id');
  PreferenceStatus? get status => reader.json['status'] == null
      ? null
      : reader.enumeration('status', PreferenceStatus.values);
  int? get faireValue => reader.optionalInteger('faire_value', min: 1, max: 20);
  int? get recevoirValue =>
      reader.optionalInteger('recevoir_value', min: 1, max: 20);
  DateTime get updatedAt => reader.dateTime('updated_at');
}
