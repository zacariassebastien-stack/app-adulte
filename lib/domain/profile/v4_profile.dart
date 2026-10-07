enum ProfilePreferenceRole {
  general,
  faire,
  recevoir,
  mutuel,
  solo,
  observer,
  simultane;

  String get wireName => name.toUpperCase();

  static ProfilePreferenceRole parse(String value) => values.firstWhere(
    (item) => item.wireName == value,
    orElse: () => throw FormatException('Unknown profile role: $value'),
  );
}

enum ProfilePreferenceSource {
  initialQuestionnaire,
  autoLearned,
  manualCustomized,
}

final class ProfilePreferenceKey {
  const ProfilePreferenceKey({
    required this.tagId,
    required this.role,
    this.zoneId,
  });

  final String tagId;
  final ProfilePreferenceRole role;
  final String? zoneId;

  String get storageKey =>
      [tagId, role.name, if (zoneId != null) zoneId].join('|');
}

final class ProfilePreference {
  const ProfilePreference({
    required this.profileId,
    required this.key,
    required this.pa,
    required this.excluded,
    required this.source,
  }) : assert(!excluded || pa == null),
       assert(pa == null || (pa >= 1 && pa <= 20));

  final String profileId;
  final ProfilePreferenceKey key;
  final double? pa;
  final bool excluded;
  final ProfilePreferenceSource source;

  Map<String, Object?> toJson() => {
    'profile_id': profileId,
    'tag_id': key.tagId,
    'role': key.role.wireName,
    'zone_id': key.zoneId,
    'pa': pa,
    'excluded': excluded,
    'source': source.name,
  };

  factory ProfilePreference.fromJson(Map<String, Object?> json) =>
      ProfilePreference(
        profileId: json['profile_id']! as String,
        key: ProfilePreferenceKey(
          tagId: json['tag_id']! as String,
          role: ProfilePreferenceRole.parse(json['role']! as String),
          zoneId: json['zone_id'] as String?,
        ),
        pa: (json['pa'] as num?)?.toDouble(),
        excluded: json['excluded']! as bool,
        source: ProfilePreferenceSource.values.byName(
          json['source']! as String,
        ),
      );
}

enum PracticeConsentStatus { unknown, allowed, excluded }

enum PracticeConsentSource { manualExplicit, sessionExplicit }

final class PracticeConsent {
  const PracticeConsent({
    required this.profileId,
    required this.practiceTagId,
    required this.role,
    required this.status,
    required this.source,
    this.zoneId,
  });

  final String profileId;
  final String practiceTagId;
  final ProfilePreferenceRole role;
  final String? zoneId;
  final PracticeConsentStatus status;
  final PracticeConsentSource source;

  String get storageKey => [practiceTagId, role.name, ?zoneId].join('|');

  Map<String, Object?> toJson() => {
    'profile_id': profileId,
    'practice_tag_id': practiceTagId,
    'role': role.wireName,
    'zone_id': zoneId,
    'status': status.name,
    'source': source.name,
  };

  factory PracticeConsent.fromJson(Map<String, Object?> json) =>
      PracticeConsent(
        profileId: json['profile_id']! as String,
        practiceTagId: json['practice_tag_id']! as String,
        role: ProfilePreferenceRole.parse(json['role']! as String),
        zoneId: json['zone_id'] as String?,
        status: PracticeConsentStatus.values.byName(json['status']! as String),
        source: PracticeConsentSource.values.byName(json['source']! as String),
      );
}

final class V4Profile {
  V4Profile({
    required this.profileId,
    required Map<String, ProfilePreference> preferences,
    Map<String, PracticeConsent> consents = const {},
  }) : preferences = Map.unmodifiable(preferences),
       consents = Map.unmodifiable(consents);

  final String profileId;
  final Map<String, ProfilePreference> preferences;
  final Map<String, PracticeConsent> consents;

  ProfilePreference? preference(ProfilePreferenceKey key) =>
      preferences[key.storageKey];

  PracticeConsent? consent({
    required String practiceTagId,
    required ProfilePreferenceRole role,
    String? zoneId,
  }) => consents[[practiceTagId, role.name, ?zoneId].join('|')];

  Map<String, Object?> toJson() => {
    'schema_version': 1,
    'profile_id': profileId,
    'preferences': [for (final value in preferences.values) value.toJson()],
    'consents': [for (final value in consents.values) value.toJson()],
  };

  factory V4Profile.fromJson(Map<String, Object?> json) {
    final preferences = [
      for (final value in json['preferences']! as List)
        ProfilePreference.fromJson(Map<String, Object?>.from(value as Map)),
    ];
    final consents = [
      for (final value in (json['consents'] as List? ?? const []))
        PracticeConsent.fromJson(Map<String, Object?>.from(value as Map)),
    ];
    return V4Profile(
      profileId: json['profile_id']! as String,
      preferences: {
        for (final value in preferences) value.key.storageKey: value,
      },
      consents: {for (final value in consents) value.storageKey: value},
    );
  }
}
