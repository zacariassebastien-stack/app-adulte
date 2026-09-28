import '../catalog/enums.dart';

final class LocalProfile {
  const LocalProfile({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
}

/// A suggestion or observation. It never changes [PreferenceStatus] by itself.
final class ProfileEvolutionData {
  const ProfileEvolutionData({
    required this.profileId,
    required this.profileElementId,
    required this.createdAt,
    this.generalValue,
    this.faireValue,
    this.recevoirValue,
    this.evidence = const <String, Object?>{},
  });

  final String profileId;
  final String profileElementId;
  final int? generalValue;
  final int? faireValue;
  final int? recevoirValue;
  final Map<String, Object?> evidence;
  final DateTime createdAt;

  void validate() {
    for (final value in [generalValue, faireValue, recevoirValue]) {
      if (value != null && (value < 1 || value > 20)) {
        throw ArgumentError.value(value, 'value', 'must be between 1 and 20');
      }
    }
  }
}

final class StoredUserPreference {
  const StoredUserPreference({
    required this.profileId,
    required this.profileElementId,
    required this.status,
    required this.updatedAt,
    required this.source,
    this.generalValue,
    this.faireValue,
    this.recevoirValue,
  });

  final String profileId;
  final String profileElementId;
  final PreferenceStatus status;
  final int? generalValue;
  final int? faireValue;
  final int? recevoirValue;
  final DateTime updatedAt;
  final PreferenceSource source;
}

final class StoredCardPreferenceOverride {
  const StoredCardPreferenceOverride({
    required this.profileId,
    required this.cardOrVariantId,
    required this.updatedAt,
    this.status,
    this.faireValue,
    this.recevoirValue,
  });

  final String profileId;
  final String cardOrVariantId;
  final PreferenceStatus? status;
  final int? faireValue;
  final int? recevoirValue;
  final DateTime updatedAt;
}
