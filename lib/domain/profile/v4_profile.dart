// Wire names used by the profile and setup contracts.
// ignore: constant_identifier_names
enum PlayerAnatomy { PENIS, VULVE }

enum ProfileSex {
  // ignore: constant_identifier_names
  HOMME,
  // ignore: constant_identifier_names
  FEMME;

  PlayerAnatomy get anatomy => switch (this) {
    HOMME => PlayerAnatomy.PENIS,
    FEMME => PlayerAnatomy.VULVE,
  };
  String get label => this == HOMME ? 'Homme' : 'Femme';
  static ProfileSex parse(Object? value) => values.firstWhere(
    (sex) => sex.name == value,
    orElse: () => throw const FormatException('Invalid profile sex'),
  );
}

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
    this.initialResponse,
  }) : assert(!excluded || pa == null),
       assert(pa == null || (pa >= 1 && pa <= 20));

  final String profileId;
  final ProfilePreferenceKey key;
  final double? pa;
  final bool excluded;
  final ProfilePreferenceSource source;
  final String? initialResponse;

  Map<String, Object?> toJson() => {
    'profile_id': profileId,
    'tag_id': key.tagId,
    'role': key.role.wireName,
    'zone_id': key.zoneId,
    'pa': pa,
    'excluded': excluded,
    'source': source.name,
    if (initialResponse != null) 'initial_response': initialResponse,
  };

  factory ProfilePreference.fromJson(Map<String, Object?> json) =>
      ProfilePreference(
        profileId: json['profile_id']! as String,
        key: ProfilePreferenceKey(
          tagId: json['tag_id']! as String,
          role: ProfilePreferenceRole.parse(json['role']! as String),
          zoneId: json['zone_id'] as String?,
        ),
        pa:
            json['source'] == 'initialQuestionnaire' &&
                json['initial_response'] == 'unsure' &&
                json['pa'] == 20
            ? 18
            : (json['pa'] as num?)?.toDouble(),
        initialResponse: json['initial_response'] as String?,
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

final class StageVeto {
  const StageVeto({
    required this.conceptId,
    required this.actionId,
    required this.role,
  });
  final String conceptId;
  final String actionId;
  final ProfilePreferenceRole role;
  String get storageKey => '$conceptId|$actionId|${role.name}';
  Map<String, Object?> toJson() => {
    'concept_id': conceptId,
    'action_id': actionId,
    'role': role.wireName,
  };
  factory StageVeto.fromJson(Map<String, Object?> json) => StageVeto(
    conceptId: json['concept_id']! as String,
    actionId: json['action_id']! as String,
    role: ProfilePreferenceRole.parse(json['role']! as String),
  );
}

final class V4Profile {
  V4Profile({
    required this.profileId,
    required this.sex,
    this.gameNickname,
    required Map<String, ProfilePreference> preferences,
    Map<String, PracticeConsent> consents = const {},
    List<V4ProfileAccessory> accessories = const [],
    List<StageVeto> stageVetoes = const [],
    List<StageVeto> presentationAllowances = const [],
  }) : preferences = Map.unmodifiable(_initializeMutual(preferences)),
       consents = Map.unmodifiable(consents),
       accessories = List.unmodifiable(accessories),
       stageVetoes = List.unmodifiable(stageVetoes),
       presentationAllowances = List.unmodifiable(presentationAllowances);

  // One-time questionnaire prior. Once present, MUTUEL never follows SOLO or
  // OBSERVER again, including when a persisted profile is reconstructed.
  static Map<String, ProfilePreference> _initializeMutual(
    Map<String, ProfilePreference> values,
  ) {
    const key = ProfilePreferenceKey(
      tagId: 'masturbation',
      role: ProfilePreferenceRole.mutuel,
    );
    if (values.containsKey(key.storageKey)) return values;
    final solo = values['masturbation|solo'];
    final observer = values['masturbation|observer'];
    if (solo == null ||
        observer == null ||
        solo.source != ProfilePreferenceSource.initialQuestionnaire ||
        observer.source != ProfilePreferenceSource.initialQuestionnaire) {
      return values;
    }
    final excluded = solo.excluded || observer.excluded;
    if (!excluded && (solo.pa == null || observer.pa == null)) return values;
    return {
      ...values,
      key.storageKey: ProfilePreference(
        profileId: solo.profileId,
        key: key,
        pa: excluded ? null : (solo.pa! + observer.pa!) / 2,
        excluded: excluded,
        source: ProfilePreferenceSource.initialQuestionnaire,
        initialResponse: 'mutual_bootstrap',
      ),
    };
  }

  final String profileId;
  final ProfileSex sex;
  PlayerAnatomy get anatomy => sex.anatomy;
  final String? gameNickname;
  final Map<String, ProfilePreference> preferences;
  final Map<String, PracticeConsent> consents;
  final List<V4ProfileAccessory> accessories;
  final List<StageVeto> stageVetoes;
  final List<StageVeto> presentationAllowances;
  bool allowsPresentation(String concept, String action, String direction) =>
      presentationAllowances.any(
        (a) =>
            a.conceptId == concept &&
            a.actionId == action &&
            a.role.wireName == direction,
      );
  bool excludesStage(String conceptId, String actionId, String direction) =>
      stageVetoes.any(
        (v) =>
            v.conceptId == conceptId &&
            (v.actionId == actionId ||
                (v.actionId == '*' &&
                    !allowsPresentation(conceptId, actionId, direction))) &&
            (v.role == ProfilePreferenceRole.general ||
                v.role.wireName == direction),
      );

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
    'sex': sex.name,
    if (gameNickname != null) 'game_nickname': gameNickname,
    'preferences': [for (final value in preferences.values) value.toJson()],
    'consents': [for (final value in consents.values) value.toJson()],
    'accessories': [for (final value in accessories) value.toJson()],
    'stage_vetoes': [for (final value in stageVetoes) value.toJson()],
    'presentation_allowances': [
      for (final value in presentationAllowances) value.toJson(),
    ],
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
      sex: ProfileSex.parse(json['sex']),
      gameNickname: json['game_nickname'] as String?,
      preferences: {
        for (final value in preferences) value.key.storageKey: value,
      },
      consents: {for (final value in consents) value.storageKey: value},
      accessories: [
        for (final value in (json['accessories'] as List? ?? const []))
          V4ProfileAccessory.fromJson(Map<String, Object?>.from(value as Map)),
      ],
      stageVetoes: [
        for (final value in json['stage_vetoes'] as List? ?? const [])
          StageVeto.fromJson(Map<String, Object?>.from(value as Map)),
      ],
      presentationAllowances: [
        for (final value
            in json['presentation_allowances'] as List? ?? const [])
          StageVeto.fromJson(Map<String, Object?>.from(value as Map)),
      ],
    );
  }

  V4Profile copyWith({
    ProfileSex? sex,
    String? gameNickname,
    List<V4ProfileAccessory>? accessories,
    List<StageVeto>? stageVetoes,
    List<StageVeto>? presentationAllowances,
  }) => V4Profile(
    profileId: profileId,
    sex: sex ?? this.sex,
    gameNickname: gameNickname ?? this.gameNickname,
    preferences: preferences,
    consents: consents,
    accessories: accessories ?? this.accessories,
    stageVetoes: stageVetoes ?? this.stageVetoes,
    presentationAllowances:
        presentationAllowances ?? this.presentationAllowances,
  );
}

/// Identity metadata, independent of questionnaire and preference scoring.
abstract final class GameNickname {
  static String? error(String? value) {
    final length = (value ?? '').trim().runes.length;
    return length < 2 || length > 20
        ? 'Choisis un pseudo de 2 à 20 caractères.'
        : null;
  }

  static String normalize(String value) {
    if (error(value) != null) throw ArgumentError('Invalid game nickname');
    return value.trim();
  }
}
