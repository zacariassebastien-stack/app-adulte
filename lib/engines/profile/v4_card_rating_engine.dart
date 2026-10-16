import '../../domain/catalog/v4_catalog.dart';
import '../../domain/profile/v4_profile.dart';
import '../runtime/v4_runtime_engine.dart';

enum V4RatingResultKind { rated, excluded, unknown, unavailable }

final class V4RatingResult {
  V4RatingResult._({
    required this.kind,
    this.rawScore,
    this.totalWeight = 0,
    this.reasonId,
    List<String> missingTagIds = const [],
    List<double> componentValues = const [],
  }) : missingTagIds = List.unmodifiable(missingTagIds),
       componentValues = List.unmodifiable(componentValues);

  factory V4RatingResult.rated(
    double rawScore,
    double totalWeight, {
    required List<double> componentValues,
  }) => V4RatingResult._(
    kind: V4RatingResultKind.rated,
    rawScore: rawScore,
    totalWeight: totalWeight,
    componentValues: componentValues,
  );
  factory V4RatingResult.excluded(String tagId) =>
      V4RatingResult._(kind: V4RatingResultKind.excluded, reasonId: tagId);
  factory V4RatingResult.unknown(List<String> tagIds) =>
      V4RatingResult._(kind: V4RatingResultKind.unknown, missingTagIds: tagIds);
  factory V4RatingResult.unavailable(String requirementId) => V4RatingResult._(
    kind: V4RatingResultKind.unavailable,
    reasonId: requirementId,
  );

  final V4RatingResultKind kind;
  final double? rawScore;
  final double totalWeight;
  final String? reasonId;
  final List<String> missingTagIds;
  final List<double> componentValues;
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
    String? conceptId,
    Set<String>? vetoTags,
    bool technicalAvailable = true,
    String technicalRequirementId = 'technical_requirement',
  }) {
    final tags = [
      ...variant.primaryPreferenceTags,
      ...variant.secondaryPreferenceTags,
    ];
    final allTags = {...tags, ...variant.nonPreferenceData, ...?vetoTags};
    for (final preference in profile.preferences.values) {
      if (preference.excluded && allTags.contains(preference.key.tagId)) {
        return V4RatingResult.excluded(preference.key.tagId);
      }
    }
    final resolved = <String, ProfilePreference?>{};

    // All known vetoes are resolved before missing values.
    for (final tag in tags) {
      final priorTag = conceptId == '022' && tag == 'penetrer'
          ? 'penetration_vaginale'
          : tag;
      final priorRole =
          conceptId == '013' &&
              tag == 'tenue' &&
              effectiveRole == ProfilePreferenceRole.soi
          ? ProfilePreferenceRole.faire
          : effectiveRole;
      final value =
          _resolve(profile, tag, effectiveRole) ??
          _resolve(profile, priorTag, priorRole);
      resolved[tag] = value;
      if (value?.excluded ?? false) return V4RatingResult.excluded(tag);
    }

    final missing = [
      for (final entry in resolved.entries)
        if (entry.value == null || entry.value!.pa == null) entry.key,
    ];
    if (missing.isNotEmpty) return V4RatingResult.unknown(missing);
    if (!technicalAvailable) {
      return V4RatingResult.unavailable(technicalRequirementId);
    }
    final values = [for (final tag in tags) resolved[tag]!.pa!];
    final weights = [
      for (final tag in tags)
        variant.primaryPreferenceTags.contains(tag) ? 1.0 : .5,
    ];
    final weight = weights.fold<double>(0, (s, w) => s + w);
    final raw = const V4PaCalculator()
        .combine(values, weights: weights)
        .toDouble();
    return V4RatingResult.rated(raw, weight, componentValues: values);
  }

  /// Explicit V4 participation rules; no general equivalence between roles.
  V4RatingResult initializeForDirection({
    required V4Profile profile,
    required V4VariantRatingDefinition variant,
    required String conceptId,
    required String direction,
    Set<String>? vetoTags,
  }) {
    final roles = switch (conceptId) {
      '013' => const [ProfilePreferenceRole.soi],
      '021' => const [
        ProfilePreferenceRole.solo,
        ProfilePreferenceRole.observer,
      ],
      '053' => const [ProfilePreferenceRole.recevoir],
      '045' || '047' => const [ProfilePreferenceRole.mutuel],
      _ => switch (direction) {
        'FAIRE' => const [ProfilePreferenceRole.faire],
        'RECEVOIR' => const [ProfilePreferenceRole.recevoir],
        'MUTUEL' || 'SIMULTANE' =>
          const {'003', '020', '026'}.contains(conceptId)
              ? const [
                  ProfilePreferenceRole.faire,
                  ProfilePreferenceRole.recevoir,
                ]
              : const [ProfilePreferenceRole.mutuel],
        // Q05 explicitly uses FAIRE for the person whose clothing changes.
        'SOLO' =>
          const {'008', '009', '010'}.contains(conceptId)
              ? const [ProfilePreferenceRole.faire]
              : const [ProfilePreferenceRole.solo],
        _ => const [ProfilePreferenceRole.general],
      },
    };
    final results = [
      for (final role in roles)
        initialize(
          profile: profile,
          variant: variant,
          effectiveRole: role,
          conceptId: conceptId,
          vetoTags: vetoTags,
        ),
    ];
    for (final kind in [
      V4RatingResultKind.excluded,
      V4RatingResultKind.unknown,
      V4RatingResultKind.unavailable,
    ]) {
      for (final result in results) {
        if (result.kind == kind) return result;
      }
    }
    final values = [for (final r in results) ...r.componentValues];
    final weights = [
      for (final _ in results) ...[
        for (final _ in variant.primaryPreferenceTags) 1.0,
        for (final _ in variant.secondaryPreferenceTags) .5,
      ],
    ];
    final total = weights.fold<double>(0, (s, w) => s + w);
    return V4RatingResult.rated(
      const V4PaCalculator().combine(values, weights: weights).toDouble(),
      total,
      componentValues: values,
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
  }) => V4MutualRatingResult(
    contributions: [
      for (final contribution in contributions)
        initialize(
          profile: contribution.profile,
          variant: variant,
          effectiveRole: contribution.role,
          technicalAvailable: technicalAvailable,
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
