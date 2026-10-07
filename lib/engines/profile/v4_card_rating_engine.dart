import '../../domain/catalog/v4_catalog.dart';
import '../../domain/profile/v4_profile.dart';

enum V4RatingResultKind {
  rated,
  excluded,
  unknown,
  unknownConsent,
  unavailable,
}

final class V4RatingResult {
  V4RatingResult._({
    required this.kind,
    this.rawScore,
    this.totalWeight = 0,
    this.reasonId,
    List<String> missingTagIds = const [],
  }) : missingTagIds = List.unmodifiable(missingTagIds);

  factory V4RatingResult.rated(double rawScore, double totalWeight) =>
      V4RatingResult._(
        kind: V4RatingResultKind.rated,
        rawScore: rawScore,
        totalWeight: totalWeight,
      );
  factory V4RatingResult.excluded(String tagId) =>
      V4RatingResult._(kind: V4RatingResultKind.excluded, reasonId: tagId);
  factory V4RatingResult.unknown(List<String> tagIds) =>
      V4RatingResult._(kind: V4RatingResultKind.unknown, missingTagIds: tagIds);
  factory V4RatingResult.unknownConsent(String practiceTagId) =>
      V4RatingResult._(
        kind: V4RatingResultKind.unknownConsent,
        reasonId: practiceTagId,
      );
  factory V4RatingResult.unavailable(String requirementId) => V4RatingResult._(
    kind: V4RatingResultKind.unavailable,
    reasonId: requirementId,
  );

  final V4RatingResultKind kind;
  final double? rawScore;
  final double totalWeight;
  final String? reasonId;
  final List<String> missingTagIds;
  String? get source => kind == V4RatingResultKind.rated ? 'TAG_PRIOR' : null;
}

final class V4RatingContribution {
  const V4RatingContribution({required this.profile, required this.role});

  final V4Profile profile;
  final ProfilePreferenceRole role;
}

final class V4MutualRatingResult {
  V4MutualRatingResult({required List<V4RatingResult> contributions})
    : contributions = List.unmodifiable(contributions);

  final List<V4RatingResult> contributions;

  V4RatingResultKind get kind {
    for (final candidate in const [
      V4RatingResultKind.excluded,
      V4RatingResultKind.unknownConsent,
      V4RatingResultKind.unknown,
      V4RatingResultKind.unavailable,
    ]) {
      if (contributions.any((item) => item.kind == candidate)) return candidate;
    }
    return V4RatingResultKind.rated;
  }

  double? get rawScore => kind == V4RatingResultKind.rated
      ? contributions.fold<double>(0, (sum, item) => sum + item.rawScore!)
      : null;
}

final class V4CardRatingEngine {
  const V4CardRatingEngine();

  V4RatingResult initialize({
    required V4Profile profile,
    required V4VariantRatingDefinition variant,
    required ProfilePreferenceRole effectiveRole,
    bool technicalAvailable = true,
    String technicalRequirementId = 'technical_requirement',
    bool requiresExplicitConsent = false,
    String? practiceTagId,
  }) {
    final tags = [
      ...variant.primaryPreferenceTags,
      ...variant.secondaryPreferenceTags,
    ];
    final resolved = <String, ProfilePreference?>{};

    // All known vetoes are resolved before missing values.
    for (final tag in tags) {
      final value = _resolve(profile, tag, effectiveRole);
      resolved[tag] = value;
      if (value?.excluded ?? false) return V4RatingResult.excluded(tag);
      final consent = profile.consent(practiceTagId: tag, role: effectiveRole);
      if (consent?.status == PracticeConsentStatus.excluded) {
        return V4RatingResult.excluded(tag);
      }
    }

    final missing = [
      for (final entry in resolved.entries)
        if (entry.value == null || entry.value!.pa == null) entry.key,
    ];
    if (missing.isNotEmpty) return V4RatingResult.unknown(missing);
    if (!technicalAvailable) {
      return V4RatingResult.unavailable(technicalRequirementId);
    }
    if (requiresExplicitConsent) {
      final id = practiceTagId ?? variant.primaryPreferenceTags.first;
      final consent = profile.consent(practiceTagId: id, role: effectiveRole);
      if (consent?.status != PracticeConsentStatus.allowed) {
        return V4RatingResult.unknownConsent(id);
      }
    }

    var raw = 0.0;
    for (final tag in variant.primaryPreferenceTags) {
      raw += resolved[tag]!.pa!;
    }
    for (final tag in variant.secondaryPreferenceTags) {
      raw += resolved[tag]!.pa! * 0.5;
    }
    return V4RatingResult.rated(
      raw,
      variant.primaryPreferenceTags.length +
          variant.secondaryPreferenceTags.length * 0.5,
    );
  }

  ProfilePreference? _resolve(
    V4Profile profile,
    String tag,
    ProfilePreferenceRole role,
  ) =>
      profile.preference(ProfilePreferenceKey(tagId: tag, role: role)) ??
      profile.preference(
        ProfilePreferenceKey(tagId: tag, role: ProfilePreferenceRole.general),
      );

  V4MutualRatingResult initializeMutual({
    required List<V4RatingContribution> contributions,
    required V4VariantRatingDefinition variant,
    bool technicalAvailable = true,
    bool requiresExplicitConsent = false,
  }) => V4MutualRatingResult(
    contributions: [
      for (final contribution in contributions)
        initialize(
          profile: contribution.profile,
          variant: variant,
          effectiveRole: contribution.role,
          technicalAvailable: technicalAvailable,
          requiresExplicitConsent: requiresExplicitConsent,
        ),
    ],
  );
}

final class CardRatingKey {
  const CardRatingKey({
    required this.profileId,
    required this.cardId,
    required this.variantId,
    required this.role,
  });
  final String profileId;
  final String cardId;
  final String variantId;
  final ProfilePreferenceRole role;
  String get storageKey => '$profileId|$cardId|$variantId|${role.name}';

  Map<String, Object?> toJson() => {
    'profile_id': profileId,
    'card_id': cardId,
    'variant_id': variantId,
    'role': role.wireName,
  };

  factory CardRatingKey.fromJson(Map<String, Object?> json) => CardRatingKey(
    profileId: json['profile_id']! as String,
    cardId: json['card_id']! as String,
    variantId: json['variant_id']! as String,
    role: ProfilePreferenceRole.parse(json['role']! as String),
  );
}

final class CardRatingStateV4 {
  const CardRatingStateV4({
    required this.key,
    required this.initialScore,
    required this.currentEstimate,
    required this.observationCount,
    this.exposureCount = 0,
    this.playedCount = 0,
    this.lockedCount = 0,
    this.ignoredCount = 0,
    this.resultOccurrenceCount = 0,
    required this.acceptanceCount,
    required this.resistanceCount,
    required this.source,
  });

  final CardRatingKey key;
  final double? initialScore;
  final double? currentEstimate;
  final int observationCount;
  final int exposureCount;
  final int playedCount;
  final int lockedCount;
  final int ignoredCount;
  final int resultOccurrenceCount;
  final int acceptanceCount;
  final int resistanceCount;
  final String source;

  Map<String, Object?> toJson() => {
    'key': key.toJson(),
    'initial_score': initialScore,
    'current_estimate': currentEstimate,
    'observation_count': observationCount,
    'exposure_count': exposureCount,
    'played_count': playedCount,
    'locked_count': lockedCount,
    'ignored_count': ignoredCount,
    'result_occurrence_count': resultOccurrenceCount,
    'acceptance_count': acceptanceCount,
    'resistance_count': resistanceCount,
    'source': source,
  };

  factory CardRatingStateV4.fromJson(Map<String, Object?> json) =>
      CardRatingStateV4(
        key: CardRatingKey.fromJson(
          Map<String, Object?>.from(json['key']! as Map),
        ),
        initialScore: (json['initial_score'] as num?)?.toDouble(),
        currentEstimate: (json['current_estimate'] as num?)?.toDouble(),
        observationCount: json['observation_count']! as int,
        exposureCount: json['exposure_count'] as int? ?? 0,
        playedCount: json['played_count'] as int? ?? 0,
        lockedCount: json['locked_count'] as int? ?? 0,
        ignoredCount: json['ignored_count'] as int? ?? 0,
        resultOccurrenceCount: json['result_occurrence_count'] as int? ?? 0,
        acceptanceCount: json['acceptance_count']! as int,
        resistanceCount: json['resistance_count']! as int,
        source: json['source']! as String,
      );

  CardRatingStateV4 record(V4CardLearningSignal signal) => CardRatingStateV4(
    key: key,
    initialScore: initialScore,
    currentEstimate: currentEstimate,
    observationCount: observationCount + 1,
    exposureCount:
        exposureCount + (signal == V4CardLearningSignal.exposed ? 1 : 0),
    playedCount: playedCount + (signal == V4CardLearningSignal.played ? 1 : 0),
    lockedCount: lockedCount + (signal == V4CardLearningSignal.locked ? 1 : 0),
    ignoredCount:
        ignoredCount + (signal == V4CardLearningSignal.ignored ? 1 : 0),
    resultOccurrenceCount:
        resultOccurrenceCount +
        ((signal == V4CardLearningSignal.accepted ||
                signal == V4CardLearningSignal.resisted)
            ? 1
            : 0),
    acceptanceCount:
        acceptanceCount + (signal == V4CardLearningSignal.accepted ? 1 : 0),
    resistanceCount:
        resistanceCount + (signal == V4CardLearningSignal.resisted ? 1 : 0),
    source: source,
  );

  CardRatingStateV4 withOwnEstimate(double estimate) => CardRatingStateV4(
    key: key,
    initialScore: initialScore,
    currentEstimate: estimate,
    observationCount: observationCount,
    exposureCount: exposureCount,
    playedCount: playedCount,
    lockedCount: lockedCount,
    ignoredCount: ignoredCount,
    resultOccurrenceCount: resultOccurrenceCount,
    acceptanceCount: acceptanceCount,
    resistanceCount: resistanceCount,
    source: 'CARD_ESTIMATE',
  );
}

enum V4CardLearningSignal {
  exposed,
  played,
  locked,
  ignored,
  accepted,
  resisted,
  stopped,
}

final class CardSpecificLearningStore {
  final Map<String, CardRatingStateV4> _values = {};

  CardRatingStateV4? read(CardRatingKey key) => _values[key.storageKey];

  void write(CardRatingStateV4 value) {
    _values[value.key.storageKey] = value;
  }

  List<Map<String, Object?>> toJson() => [
    for (final value in _values.values) value.toJson(),
  ];

  void restore(Iterable<Object?> encoded) {
    _values
      ..clear()
      ..addEntries(
        encoded.map((value) {
          final state = CardRatingStateV4.fromJson(
            Map<String, Object?>.from(value! as Map),
          );
          return MapEntry(state.key.storageKey, state);
        }),
      );
  }

  void record({
    required CardRatingKey key,
    required double initialScore,
    required V4CardLearningSignal signal,
  }) {
    final current =
        _values[key.storageKey] ??
        CardRatingStateV4(
          key: key,
          initialScore: initialScore,
          currentEstimate: initialScore,
          observationCount: 0,
          acceptanceCount: 0,
          resistanceCount: 0,
          source: 'TAG_PRIOR',
        );
    _values[key.storageKey] = current.record(signal);
  }
}
