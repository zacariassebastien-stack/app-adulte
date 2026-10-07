import 'dart:math' as math;

enum InitialSwipeChoice { love, like, unsure, excluded }

enum AdaptiveProfileSource {
  initialSwipe,
  initialQuestionnaire,
  autoLearned,
  manualCustomized,
}

extension AdaptiveProfileSourceWire on AdaptiveProfileSource {
  String get wireName => switch (this) {
    AdaptiveProfileSource.initialSwipe => 'INITIAL_SWIPE',
    AdaptiveProfileSource.initialQuestionnaire => 'INITIAL_QUESTIONNAIRE',
    AdaptiveProfileSource.autoLearned => 'AUTO_LEARNED',
    AdaptiveProfileSource.manualCustomized => 'MANUAL_CUSTOMIZED',
  };

  static AdaptiveProfileSource parse(String value) => switch (value) {
    'INITIAL_SWIPE' => AdaptiveProfileSource.initialSwipe,
    'INITIAL_QUESTIONNAIRE' => AdaptiveProfileSource.initialQuestionnaire,
    'AUTO_LEARNED' => AdaptiveProfileSource.autoLearned,
    'MANUAL_CUSTOMIZED' => AdaptiveProfileSource.manualCustomized,
    _ => throw FormatException('Unknown adaptive profile source: $value'),
  };
}

enum ProfileLearningPreference { personalize, trustGame, defer }

enum DetailedPreferenceCategory {
  essential,
  love,
  likeALot,
  like,
  tempted,
  depends,
  occasional,
  atMyLimit,
  unsure,
  excluded,
}

enum LearningRole {
  general,
  faire,
  recevoir,
  mutuel,
  solo,
  observer,
  simultane,
}

enum ProposalDecision { pending, accepted, declined }

extension DetailedPreferenceCategoryRules on DetailedPreferenceCategory {
  static DetailedPreferenceCategory fromPa(
    double? pa, {
    bool excluded = false,
  }) {
    if (excluded) return DetailedPreferenceCategory.excluded;
    if (pa == null || pa >= 19.5) return DetailedPreferenceCategory.unsure;
    if (pa <= 2) return DetailedPreferenceCategory.essential;
    if (pa <= 4) return DetailedPreferenceCategory.love;
    if (pa <= 6) return DetailedPreferenceCategory.likeALot;
    if (pa <= 8) return DetailedPreferenceCategory.like;
    if (pa <= 11) return DetailedPreferenceCategory.tempted;
    if (pa <= 14) return DetailedPreferenceCategory.depends;
    if (pa <= 16) return DetailedPreferenceCategory.occasional;
    return DetailedPreferenceCategory.atMyLimit;
  }

  String get label => switch (this) {
    DetailedPreferenceCategory.essential => 'Incontournable',
    DetailedPreferenceCategory.love => 'J’adore',
    DetailedPreferenceCategory.likeALot => 'J’aime beaucoup',
    DetailedPreferenceCategory.like => 'J’aime',
    DetailedPreferenceCategory.tempted => 'Ça me tente',
    DetailedPreferenceCategory.depends => 'Ça dépend',
    DetailedPreferenceCategory.occasional => 'Occasionnellement',
    DetailedPreferenceCategory.atMyLimit => 'À ma limite',
    DetailedPreferenceCategory.unsure => 'Je ne sais pas',
    DetailedPreferenceCategory.excluded => 'Exclu',
  };
}

final class PreferenceLearningKey {
  const PreferenceLearningKey({
    required this.preferenceId,
    this.role = LearningRole.general,
    this.zoneId,
  });

  final String preferenceId;
  final LearningRole role;
  final String? zoneId;

  String get storageKey =>
      [preferenceId, role.name, if (zoneId != null) zoneId].join('|');

  factory PreferenceLearningKey.fromStorageKey(String value) {
    final parts = value.split('|');
    if (parts.length < 2 || parts.length > 3) {
      throw FormatException('Invalid preference learning key: $value');
    }
    return PreferenceLearningKey(
      preferenceId: parts[0],
      role: LearningRole.values.byName(parts[1]),
      zoneId: parts.length == 3 ? parts[2] : null,
    );
  }

  Map<String, Object?> toJson() => {
    'preference_id': preferenceId,
    'role': role.name,
    if (zoneId != null) 'zone_id': zoneId,
  };
}

final class LearningSample {
  const LearningSample({
    required this.equivalentWeight,
    required this.spiceLevel,
    this.exposure = 0,
    this.attraction = 0,
    this.acceptance = 0,
    this.resistance = 0,
    this.resultOccurrences = 0,
  });

  final double equivalentWeight;
  final int spiceLevel;
  final double exposure;
  final double attraction;
  final double acceptance;
  final double resistance;
  final double resultOccurrences;

  Map<String, Object?> toJson() => {
    'equivalent_weight': equivalentWeight,
    'spice_level': spiceLevel,
    'exposure': exposure,
    'attraction': attraction,
    'acceptance': acceptance,
    'resistance': resistance,
    'result_occurrences': resultOccurrences,
  };

  factory LearningSample.fromJson(Map<String, Object?> json) => LearningSample(
    equivalentWeight: (json['equivalent_weight']! as num).toDouble(),
    spiceLevel: json['spice_level']! as int,
    exposure: (json['exposure']! as num).toDouble(),
    attraction: (json['attraction']! as num).toDouble(),
    acceptance: (json['acceptance']! as num).toDouble(),
    resistance: (json['resistance']! as num).toDouble(),
    resultOccurrences: (json['result_occurrences']! as num).toDouble(),
  );
}

final class ProfileLearningProposal {
  const ProfileLearningProposal({
    required this.key,
    required this.fromCategory,
    required this.toCategory,
    required this.estimatedPa,
    required this.tendency,
    required this.equivalentOccurrences,
    required this.createdAt,
    this.decision = ProposalDecision.pending,
  });

  final PreferenceLearningKey key;
  final DetailedPreferenceCategory fromCategory;
  final DetailedPreferenceCategory toCategory;
  final double estimatedPa;
  final double tendency;
  final double equivalentOccurrences;
  final DateTime createdAt;
  final ProposalDecision decision;

  ProfileLearningProposal copyWith({ProposalDecision? decision}) =>
      ProfileLearningProposal(
        key: key,
        fromCategory: fromCategory,
        toCategory: toCategory,
        estimatedPa: estimatedPa,
        tendency: tendency,
        equivalentOccurrences: equivalentOccurrences,
        createdAt: createdAt,
        decision: decision ?? this.decision,
      );

  Map<String, Object?> toJson() => {
    'key': key.storageKey,
    'from_category': fromCategory.name,
    'to_category': toCategory.name,
    'estimated_pa': estimatedPa,
    'tendency': tendency,
    'equivalent_occurrences': equivalentOccurrences,
    'created_at': createdAt.toUtc().toIso8601String(),
    'decision': decision.name,
  };

  factory ProfileLearningProposal.fromJson(Map<String, Object?> json) =>
      ProfileLearningProposal(
        key: PreferenceLearningKey.fromStorageKey(json['key']! as String),
        fromCategory: DetailedPreferenceCategory.values.byName(
          json['from_category']! as String,
        ),
        toCategory: DetailedPreferenceCategory.values.byName(
          json['to_category']! as String,
        ),
        estimatedPa: (json['estimated_pa']! as num).toDouble(),
        tendency: (json['tendency']! as num).toDouble(),
        equivalentOccurrences: (json['equivalent_occurrences']! as num)
            .toDouble(),
        createdAt: DateTime.parse(json['created_at']! as String).toUtc(),
        decision: ProposalDecision.values.byName(json['decision']! as String),
      );
}

final class PreferenceLearningEntry {
  PreferenceLearningEntry({
    required this.key,
    required this.source,
    required this.currentPa,
    required this.estimatedPa,
    this.excluded = false,
    this.exposureCount = 0,
    this.playedCount = 0,
    this.lockedCount = 0,
    this.ignoredCount = 0,
    this.attractionCount = 0,
    this.acceptanceCount = 0,
    this.resistanceCount = 0,
    this.resultOccurrences = 0,
    this.spiceTotal = 0,
    this.spiceWeight = 0,
    this.totalEquivalentOccurrences = 0,
    this.observationsSinceReference = 0,
    this.lastEvaluationAt = 0,
    this.confirmationOccurrences = 0,
    this.proposalCooldown = 0,
    this.lastTendency = 0,
    this.pendingCategory,
    this.lastProposal,
    List<LearningSample> recent = const [],
  }) : recent = List.unmodifiable(recent.takeLast(20));

  final PreferenceLearningKey key;
  final AdaptiveProfileSource source;
  final double? currentPa;
  final double? estimatedPa;
  final bool excluded;
  final double exposureCount;
  final double playedCount;
  final double lockedCount;
  final double ignoredCount;
  final double attractionCount;
  final double acceptanceCount;
  final double resistanceCount;
  final double resultOccurrences;
  final double spiceTotal;
  final double spiceWeight;
  final double totalEquivalentOccurrences;
  final double observationsSinceReference;
  final double lastEvaluationAt;
  final double confirmationOccurrences;
  final double proposalCooldown;
  final double lastTendency;
  final DetailedPreferenceCategory? pendingCategory;
  final ProfileLearningProposal? lastProposal;
  final List<LearningSample> recent;

  DetailedPreferenceCategory get currentCategory =>
      DetailedPreferenceCategoryRules.fromPa(currentPa, excluded: excluded);
  DetailedPreferenceCategory get estimatedCategory =>
      DetailedPreferenceCategoryRules.fromPa(estimatedPa, excluded: excluded);
  double get averageSpice => spiceWeight == 0 ? 0 : spiceTotal / spiceWeight;
  double get recentEquivalentOccurrences =>
      recent.fold(0, (sum, sample) => sum + sample.equivalentWeight);
  double get attractionRelative => _ratio(
    recent.fold(0, (sum, sample) => sum + sample.attraction),
    recent.fold(0, (sum, sample) => sum + sample.exposure),
  );
  double get acceptanceRelative => _ratio(
    recent.fold(0, (sum, sample) => sum + sample.acceptance),
    recent.fold(0, (sum, sample) => sum + sample.resultOccurrences),
  );
  double get resistanceRelative => _ratio(
    recent.fold(0, (sum, sample) => sum + sample.resistance),
    recent.fold(0, (sum, sample) => sum + sample.resultOccurrences),
  );
  double get tendency =>
      0.5 * attractionRelative + 0.5 * acceptanceRelative - resistanceRelative;

  PreferenceLearningEntry copyWith({
    AdaptiveProfileSource? source,
    double? currentPa,
    bool clearCurrentPa = false,
    double? estimatedPa,
    bool clearEstimatedPa = false,
    bool? excluded,
    double? exposureCount,
    double? playedCount,
    double? lockedCount,
    double? ignoredCount,
    double? attractionCount,
    double? acceptanceCount,
    double? resistanceCount,
    double? resultOccurrences,
    double? spiceTotal,
    double? spiceWeight,
    double? totalEquivalentOccurrences,
    double? observationsSinceReference,
    double? lastEvaluationAt,
    double? confirmationOccurrences,
    double? proposalCooldown,
    double? lastTendency,
    DetailedPreferenceCategory? pendingCategory,
    bool clearPendingCategory = false,
    ProfileLearningProposal? lastProposal,
    bool clearLastProposal = false,
    List<LearningSample>? recent,
  }) => PreferenceLearningEntry(
    key: key,
    source: source ?? this.source,
    currentPa: clearCurrentPa ? null : (currentPa ?? this.currentPa),
    estimatedPa: clearEstimatedPa ? null : (estimatedPa ?? this.estimatedPa),
    excluded: excluded ?? this.excluded,
    exposureCount: exposureCount ?? this.exposureCount,
    playedCount: playedCount ?? this.playedCount,
    lockedCount: lockedCount ?? this.lockedCount,
    ignoredCount: ignoredCount ?? this.ignoredCount,
    attractionCount: attractionCount ?? this.attractionCount,
    acceptanceCount: acceptanceCount ?? this.acceptanceCount,
    resistanceCount: resistanceCount ?? this.resistanceCount,
    resultOccurrences: resultOccurrences ?? this.resultOccurrences,
    spiceTotal: spiceTotal ?? this.spiceTotal,
    spiceWeight: spiceWeight ?? this.spiceWeight,
    totalEquivalentOccurrences:
        totalEquivalentOccurrences ?? this.totalEquivalentOccurrences,
    observationsSinceReference:
        observationsSinceReference ?? this.observationsSinceReference,
    lastEvaluationAt: lastEvaluationAt ?? this.lastEvaluationAt,
    confirmationOccurrences:
        confirmationOccurrences ?? this.confirmationOccurrences,
    proposalCooldown: proposalCooldown ?? this.proposalCooldown,
    lastTendency: lastTendency ?? this.lastTendency,
    pendingCategory: clearPendingCategory
        ? null
        : (pendingCategory ?? this.pendingCategory),
    lastProposal: clearLastProposal
        ? null
        : (lastProposal ?? this.lastProposal),
    recent: recent ?? this.recent,
  );

  Map<String, Object?> toJson() => {
    'key': key.storageKey,
    'source': source.wireName,
    'current_pa': currentPa,
    'estimated_pa': estimatedPa,
    'excluded': excluded,
    'exposure_count': exposureCount,
    'played_count': playedCount,
    'locked_count': lockedCount,
    'ignored_count': ignoredCount,
    'attraction_count': attractionCount,
    'acceptance_count': acceptanceCount,
    'resistance_count': resistanceCount,
    'result_occurrences': resultOccurrences,
    'spice_total': spiceTotal,
    'spice_weight': spiceWeight,
    'total_equivalent_occurrences': totalEquivalentOccurrences,
    'observations_since_reference': observationsSinceReference,
    'last_evaluation_at': lastEvaluationAt,
    'confirmation_occurrences': confirmationOccurrences,
    'proposal_cooldown': proposalCooldown,
    'last_tendency': lastTendency,
    'pending_category': pendingCategory?.name,
    'last_proposal': lastProposal?.toJson(),
    'recent': recent.map((sample) => sample.toJson()).toList(),
  };

  factory PreferenceLearningEntry.fromJson(
    Map<String, Object?> json,
  ) => PreferenceLearningEntry(
    key: PreferenceLearningKey.fromStorageKey(json['key']! as String),
    source: AdaptiveProfileSourceWire.parse(json['source']! as String),
    currentPa: (json['current_pa'] as num?)?.toDouble(),
    estimatedPa: (json['estimated_pa'] as num?)?.toDouble(),
    excluded: json['excluded']! as bool,
    exposureCount: (json['exposure_count']! as num).toDouble(),
    playedCount: (json['played_count']! as num).toDouble(),
    lockedCount: (json['locked_count']! as num).toDouble(),
    ignoredCount: (json['ignored_count']! as num).toDouble(),
    attractionCount: (json['attraction_count']! as num).toDouble(),
    acceptanceCount: (json['acceptance_count']! as num).toDouble(),
    resistanceCount: (json['resistance_count']! as num).toDouble(),
    resultOccurrences: (json['result_occurrences']! as num).toDouble(),
    spiceTotal: (json['spice_total']! as num).toDouble(),
    spiceWeight: (json['spice_weight']! as num).toDouble(),
    totalEquivalentOccurrences: (json['total_equivalent_occurrences']! as num)
        .toDouble(),
    observationsSinceReference: (json['observations_since_reference']! as num)
        .toDouble(),
    lastEvaluationAt: (json['last_evaluation_at']! as num).toDouble(),
    confirmationOccurrences: (json['confirmation_occurrences']! as num)
        .toDouble(),
    proposalCooldown: (json['proposal_cooldown']! as num).toDouble(),
    lastTendency: (json['last_tendency']! as num).toDouble(),
    pendingCategory: json['pending_category'] == null
        ? null
        : DetailedPreferenceCategory.values.byName(
            json['pending_category']! as String,
          ),
    lastProposal: json['last_proposal'] == null
        ? null
        : ProfileLearningProposal.fromJson(
            (json['last_proposal']! as Map).cast<String, Object?>(),
          ),
    recent: (json['recent']! as List<Object?>)
        .map(
          (value) =>
              LearningSample.fromJson((value! as Map).cast<String, Object?>()),
        )
        .toList(growable: false),
  );

  static double _ratio(double numerator, double denominator) =>
      denominator == 0 ? 0 : numerator / denominator;
}

final class AdaptiveProfileState {
  AdaptiveProfileState({
    required this.profileId,
    this.learningPreference = ProfileLearningPreference.defer,
    Map<String, PreferenceLearningEntry> entries = const {},
  }) : entries = Map.unmodifiable(entries);

  static const schemaVersion = 1;
  final String profileId;
  final ProfileLearningPreference learningPreference;
  final Map<String, PreferenceLearningEntry> entries;

  PreferenceLearningEntry? entry(PreferenceLearningKey key) =>
      entries[key.storageKey];

  AdaptiveProfileState copyWith({
    ProfileLearningPreference? learningPreference,
    Map<String, PreferenceLearningEntry>? entries,
  }) => AdaptiveProfileState(
    profileId: profileId,
    learningPreference: learningPreference ?? this.learningPreference,
    entries: entries ?? this.entries,
  );

  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'profile_id': profileId,
    'learning_preference': learningPreference.name,
    'entries': {
      for (final entry in entries.entries) entry.key: entry.value.toJson(),
    },
  };

  factory AdaptiveProfileState.fromJson(Map<String, Object?> json) {
    if (json['schema_version'] != schemaVersion) {
      throw FormatException(
        'Unsupported adaptive profile schema ${json['schema_version']}',
      );
    }
    final rawEntries = (json['entries']! as Map).cast<String, Object?>();
    return AdaptiveProfileState(
      profileId: json['profile_id']! as String,
      learningPreference: ProfileLearningPreference.values.byName(
        json['learning_preference']! as String,
      ),
      entries: {
        for (final entry in rawEntries.entries)
          entry.key: PreferenceLearningEntry.fromJson(
            (entry.value! as Map).cast<String, Object?>(),
          ),
      },
    );
  }
}

extension _TakeLast<T> on Iterable<T> {
  Iterable<T> takeLast(int count) {
    final values = toList(growable: false);
    return values.skip(math.max(0, values.length - count));
  }
}
