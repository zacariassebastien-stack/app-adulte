enum ProfilePreferenceRole {
  general,
  faire,
  recevoir,
  mutuel,
  solo,
  soi,
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

/// Legacy persisted status. It is never consulted for card eligibility.
enum PracticeConsentStatus { unknown, allowed, excluded }

/// Legacy persisted source. It is never consulted for card eligibility.
enum PracticeConsentSource { manualExplicit, sessionExplicit }

const v4AccessoryTags = {
  'ANAL',
  'VAGINAL',
  'BUCCAL',
  'PHALLUS',
  'EXTERNE',
  'VIBRANT',
};

final class V4ProfileAccessory {
  V4ProfileAccessory({
    required this.id,
    required this.name,
    required this.ownerProfileId,
    required Set<String> tags,
    this.active = true,
    Map<ProfilePreferenceRole, double?> preferences = const {},
  }) : tags = Set.unmodifiable(tags),
       preferences = Map.unmodifiable({
         for (final role in const [
           ProfilePreferenceRole.faire,
           ProfilePreferenceRole.recevoir,
           ProfilePreferenceRole.soi,
         ])
           role: preferences.containsKey(role) ? preferences[role] : 18.0,
       }) {
    if (id.isEmpty ||
        name.trim().isEmpty ||
        !v4AccessoryTags.containsAll(tags)) {
      throw ArgumentError('Invalid V4 profile accessory');
    }
  }

  final String id;
  final String name;
  final String ownerProfileId;
  final Set<String> tags;
  final bool active;
  final Map<ProfilePreferenceRole, double?> preferences;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'owner_profile_id': ownerProfileId,
    'tags': tags.toList()..sort(),
    'active': active,
    'preferences': {
      for (final entry in preferences.entries) entry.key.wireName: entry.value,
    },
  };

  factory V4ProfileAccessory.fromJson(Map<String, Object?> json) {
    final rawPreferences = Map<String, Object?>.from(
      (json['preferences'] as Map?) ?? const {},
    );
    return V4ProfileAccessory(
      id: json['id']! as String,
      name: json['name']! as String,
      ownerProfileId: json['owner_profile_id']! as String,
      tags: ((json['tags'] as List?) ?? const []).cast<String>().toSet(),
      active: (json['active'] as bool?) ?? true,
      preferences: {
        for (final entry in rawPreferences.entries)
          ProfilePreferenceRole.parse(entry.key): (entry.value as num?)
              ?.toDouble(),
      },
    );
  }
}

/// Compatibility model for already persisted data.
///
/// New gameplay decisions use [ProfilePreference.excluded] as their only
/// persistent profile veto. This model must never gate card eligibility.
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
    List<V4ProfileAccessory> accessories = const [],
  }) : preferences = Map.unmodifiable(preferences),
       consents = Map.unmodifiable(consents),
       accessories = List.unmodifiable(accessories);

  final String profileId;
  final Map<String, ProfilePreference> preferences;
  final Map<String, PracticeConsent> consents;
  final List<V4ProfileAccessory> accessories;

  Map<ProfilePreferenceRole, double?> accessoryPreferencesForExactTags(
    Set<String> tags,
  ) =>
      accessories
          .where(
            (item) =>
                item.tags.length == tags.length && item.tags.containsAll(tags),
          )
          .map((item) => item.preferences)
          .firstOrNull ??
      const {
        ProfilePreferenceRole.faire: 18,
        ProfilePreferenceRole.recevoir: 18,
        ProfilePreferenceRole.soi: 18,
      };

  ProfilePreference? preference(ProfilePreferenceKey key) =>
      preferences[key.storageKey];

  /// Reads legacy data for migration/export only, never for eligibility.
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
    'accessories': [for (final value in accessories) value.toJson()],
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
      accessories: [
        for (final value in (json['accessories'] as List? ?? const []))
          V4ProfileAccessory.fromJson(Map<String, Object?>.from(value as Map)),
      ],
    );
  }

  V4Profile copyWith({List<V4ProfileAccessory>? accessories}) => V4Profile(
    profileId: profileId,
    preferences: preferences,
    consents: consents,
    accessories: accessories ?? this.accessories,
  );
}
