import 'dart:math' as math;

import '../../domain/profile/adaptive_profile.dart';

enum ResolvedParticipation { directed, mutual, solo, simultaneous }

enum ResistanceSignal {
  resultModification,
  inversionSought,
  finalDefense,
  consistentAvoidance,
}

final class LearningCardDescriptor {
  LearningCardDescriptor({
    required this.cardId,
    required this.variantId,
    required List<String> tags,
    required this.spiceLevel,
    List<String> primaryPreferenceIds = const [],
    this.occurrenceId,
  }) : assert(spiceLevel >= 1 && spiceLevel <= 5),
       tags = List.unmodifiable(tags),
       primaryPreferenceIds = List.unmodifiable(primaryPreferenceIds);

  final String cardId;
  final String variantId;
  final List<String> tags;
  final int spiceLevel;
  final List<String> primaryPreferenceIds;
  final String? occurrenceId;

  String get identity => occurrenceId ?? '$cardId|$variantId';
}

final class HandLearningEvent {
  HandLearningEvent({
    required this.playerId,
    required List<LearningCardDescriptor> availableCards,
    Set<String> playedCardIdentities = const {},
    Set<String> lockedCardIdentities = const {},
  }) : availableCards = List.unmodifiable(availableCards),
       playedCardIdentities = Set.unmodifiable(playedCardIdentities),
       lockedCardIdentities = Set.unmodifiable(lockedCardIdentities);

  final String playerId;
  final List<LearningCardDescriptor> availableCards;
  final Set<String> playedCardIdentities;
  final Set<String> lockedCardIdentities;
}

final class ResolvedLearningCard {
  ResolvedLearningCard({
    required this.card,
    required this.participation,
    this.performerPlayerId,
    this.receiverPlayerId,
    this.soloPlayerId,
    List<String> participantPlayerIds = const [],
  }) : participantPlayerIds = List.unmodifiable(participantPlayerIds) {
    switch (participation) {
      case ResolvedParticipation.directed:
        if (performerPlayerId == null || receiverPlayerId == null) {
          throw ArgumentError('Directed learning requires both final roles');
        }
      case ResolvedParticipation.solo:
        if (soloPlayerId == null) {
          throw ArgumentError('Solo learning requires its final player');
        }
      case ResolvedParticipation.mutual || ResolvedParticipation.simultaneous:
        if (participantPlayerIds.isEmpty) {
          throw ArgumentError('Shared learning requires participants');
        }
    }
  }

  final LearningCardDescriptor card;
  final ResolvedParticipation participation;
  final String? performerPlayerId;
  final String? receiverPlayerId;
  final String? soloPlayerId;
  final List<String> participantPlayerIds;
}

final class RoundLearningOutcome {
  RoundLearningOutcome({
    required List<ResolvedLearningCard> acceptedCards,
    this.accepted = true,
    this.consentStopped = false,
  }) : acceptedCards = List.unmodifiable(acceptedCards);

  /// Contains only the winning card and cards retained in the final compromise.
  final List<ResolvedLearningCard> acceptedCards;
  final bool accepted;
  final bool consentStopped;
}

final class ResistanceLearningEvent {
  const ResistanceLearningEvent({
    required this.playerId,
    required this.card,
    required this.resistedRole,
    required this.signal,
  });

  final String playerId;
  final LearningCardDescriptor card;
  final LearningRole resistedRole;
  final ResistanceSignal signal;
}

final class WeightedPreferenceEvidence {
  const WeightedPreferenceEvidence({required this.key, required this.weight});
  final PreferenceLearningKey key;
  final double weight;
}

final class V3LearningTagProjector {
  const V3LearningTagProjector();

  List<WeightedPreferenceEvidence> project(
    LearningCardDescriptor card, {
    LearningRole? finalRole,
  }) {
    final preferences = card.tags
        .where((tag) => tag.startsWith('v3.preference.'))
        .toList(growable: false);
    if (preferences.isEmpty) return const [];
    final zones = card.tags
        .where((tag) => tag.startsWith('v3.zone.'))
        .toList(growable: false);
    final role = finalRole ?? _roleFromTags(card.tags);
    final explicitPrimaries = card.primaryPreferenceIds
        .where(preferences.contains)
        .toList(growable: false);
    final primaries = explicitPrimaries.isEmpty
        ? [preferences.first]
        : explicitPrimaries;
    final twoIndissociable = primaries.length == 2;
    final evidence = <WeightedPreferenceEvidence>[];

    for (final preference in preferences) {
      final isPrimary = primaries.contains(preference);
      final weight = isPrimary ? (twoIndissociable ? 0.75 : 1.0) : 0.5;
      if (zones.isEmpty) {
        evidence.add(
          WeightedPreferenceEvidence(
            key: PreferenceLearningKey(preferenceId: preference, role: role),
            weight: weight,
          ),
        );
        continue;
      }
      for (final zone in zones) {
        evidence.add(
          WeightedPreferenceEvidence(
            key: PreferenceLearningKey(
              preferenceId: preference,
              role: role,
              zoneId: zone,
            ),
            weight: weight,
          ),
        );
      }
      evidence.add(
        WeightedPreferenceEvidence(
          key: PreferenceLearningKey(preferenceId: preference, role: role),
          weight: weight * 0.5,
        ),
      );
    }
    return List.unmodifiable(evidence);
  }

  LearningRole _roleFromTags(List<String> tags) {
    if (tags.contains('v3.direction.simultane')) {
      return LearningRole.simultane;
    }
    if (tags.contains('v3.direction.mutuel')) return LearningRole.mutuel;
    if (tags.contains('v3.direction.solo')) return LearningRole.solo;
    if (tags.contains('v3.direction.faire')) return LearningRole.faire;
    if (tags.contains('v3.direction.recevoir')) return LearningRole.recevoir;
    return LearningRole.general;
  }
}

final class ProfileLearningEngine {
  const ProfileLearningEngine({
    this.tagProjector = const V3LearningTagProjector(),
    this.minimumOccurrences = 10,
    this.confirmationOccurrences = 3,
    this.manualMinimumOccurrences = 20,
    this.refusalCooldown = 20,
    this.evaluationInterval = 10,
  });

  final V3LearningTagProjector tagProjector;
  final double minimumOccurrences;
  final double confirmationOccurrences;
  final double manualMinimumOccurrences;
  final double refusalCooldown;
  final double evaluationInterval;

  AdaptiveProfileState initialize({
    required String profileId,
    required Map<String, InitialSwipeChoice> choices,
  }) {
    final entries = <String, PreferenceLearningEntry>{};
    for (final choice in choices.entries) {
      final key = PreferenceLearningKey(preferenceId: choice.key);
      final excluded = choice.value == InitialSwipeChoice.excluded;
      final pa = switch (choice.value) {
        InitialSwipeChoice.love => 5.0,
        InitialSwipeChoice.like => 12.0,
        InitialSwipeChoice.unsure => 20.0,
        InitialSwipeChoice.excluded => null,
      };
      entries[key.storageKey] = PreferenceLearningEntry(
        key: key,
        source: AdaptiveProfileSource.initialSwipe,
        currentPa: pa,
        estimatedPa: pa,
        excluded: excluded,
      );
    }
    return AdaptiveProfileState(profileId: profileId, entries: entries);
  }

  AdaptiveProfileState setLearningPreference(
    AdaptiveProfileState state,
    ProfileLearningPreference preference,
  ) => state.copyWith(learningPreference: preference);

  AdaptiveProfileState recordHand(
    AdaptiveProfileState state,
    HandLearningEvent event,
  ) {
    if (event.playerId != state.profileId) return state;
    var result = state;
    for (final card in event.availableCards) {
      final played = event.playedCardIdentities.contains(card.identity);
      final locked = event.lockedCardIdentities.contains(card.identity);
      final ignored = !played && !locked;
      result = _recordCard(
        result,
        card,
        signal: _Signal(
          exposure: true,
          played: played,
          locked: locked,
          ignored: ignored,
          attraction: played || locked,
        ),
      );
    }
    return result;
  }

  Map<String, AdaptiveProfileState> recordRoundOutcome(
    Map<String, AdaptiveProfileState> states,
    RoundLearningOutcome outcome,
  ) {
    if (!outcome.accepted || outcome.consentStopped) {
      return Map.unmodifiable(states);
    }
    final updated = Map<String, AdaptiveProfileState>.from(states);
    final seen = <String>{};
    for (final resolved in outcome.acceptedCards) {
      if (!seen.add(resolved.card.identity)) continue;
      switch (resolved.participation) {
        case ResolvedParticipation.directed:
          _recordForPlayer(
            updated,
            resolved.performerPlayerId!,
            resolved.card,
            LearningRole.faire,
          );
          _recordForPlayer(
            updated,
            resolved.receiverPlayerId!,
            resolved.card,
            LearningRole.recevoir,
          );
        case ResolvedParticipation.mutual:
          for (final playerId in resolved.participantPlayerIds.toSet()) {
            _recordForPlayer(
              updated,
              playerId,
              resolved.card,
              LearningRole.mutuel,
            );
          }
        case ResolvedParticipation.solo:
          _recordForPlayer(
            updated,
            resolved.soloPlayerId!,
            resolved.card,
            LearningRole.solo,
          );
        case ResolvedParticipation.simultaneous:
          for (final playerId in resolved.participantPlayerIds.toSet()) {
            _recordForPlayer(
              updated,
              playerId,
              resolved.card,
              LearningRole.simultane,
            );
          }
      }
    }
    return Map.unmodifiable(updated);
  }

  AdaptiveProfileState recordResistance(
    AdaptiveProfileState state,
    ResistanceLearningEvent event,
  ) {
    if (event.playerId != state.profileId) return state;
    return _recordCard(
      state,
      event.card,
      finalRole: event.resistedRole,
      signal: const _Signal(resistance: true, result: true),
    );
  }

  AdaptiveProfileState manuallyCustomize(
    AdaptiveProfileState state, {
    required PreferenceLearningKey key,
    double? pa,
    bool excluded = false,
  }) {
    if (!excluded && (pa == null || pa < 1 || pa > 20)) {
      throw ArgumentError.value(pa, 'pa', 'must be 1..20 or excluded');
    }
    final entries = Map<String, PreferenceLearningEntry>.from(state.entries);
    final existing = _entryFor(state, key);
    entries[key.storageKey] = (existing ?? _freshEntry(key)).copyWith(
      source: AdaptiveProfileSource.manualCustomized,
      currentPa: pa,
      clearCurrentPa: excluded,
      estimatedPa: pa,
      clearEstimatedPa: excluded,
      excluded: excluded,
      observationsSinceReference: 0,
      lastEvaluationAt: existing?.totalEquivalentOccurrences ?? 0,
      confirmationOccurrences: 0,
      proposalCooldown: 0,
      clearPendingCategory: true,
      clearLastProposal: true,
    );
    return state.copyWith(entries: entries);
  }

  ProfileLearningProposal? proposalFor(
    AdaptiveProfileState state,
    PreferenceLearningKey key, {
    required DateTime now,
  }) {
    final entry = state.entry(key);
    if (entry == null || entry.excluded || entry.pendingCategory == null) {
      return null;
    }
    final required = entry.source == AdaptiveProfileSource.manualCustomized
        ? manualMinimumOccurrences
        : minimumOccurrences;
    if (entry.observationsSinceReference < required ||
        entry.recentEquivalentOccurrences < minimumOccurrences ||
        entry.confirmationOccurrences < confirmationOccurrences ||
        entry.proposalCooldown > 0 ||
        entry.pendingCategory == entry.currentCategory) {
      return null;
    }
    return ProfileLearningProposal(
      key: key,
      fromCategory: entry.currentCategory,
      toCategory: entry.pendingCategory!,
      estimatedPa: entry.estimatedPa!,
      tendency: entry.lastTendency,
      equivalentOccurrences: entry.observationsSinceReference,
      createdAt: now.toUtc(),
    );
  }

  AdaptiveProfileState declineProposal(
    AdaptiveProfileState state,
    ProfileLearningProposal proposal,
  ) => _replaceEntry(
    state,
    proposal.key,
    (entry) => entry.copyWith(
      lastProposal: proposal.copyWith(decision: ProposalDecision.declined),
      proposalCooldown: refusalCooldown,
      confirmationOccurrences: 0,
    ),
  );

  AdaptiveProfileState acceptProposal(
    AdaptiveProfileState state,
    ProfileLearningProposal proposal,
  ) => _replaceEntry(
    state,
    proposal.key,
    (entry) => entry.copyWith(
      source: entry.source == AdaptiveProfileSource.manualCustomized
          ? AdaptiveProfileSource.manualCustomized
          : AdaptiveProfileSource.autoLearned,
      currentPa: proposal.estimatedPa,
      estimatedPa: proposal.estimatedPa,
      observationsSinceReference: 0,
      lastEvaluationAt: entry.totalEquivalentOccurrences,
      confirmationOccurrences: 0,
      proposalCooldown: 0,
      clearPendingCategory: true,
      lastProposal: proposal.copyWith(decision: ProposalDecision.accepted),
    ),
  );

  double suggestedDelta(double tendency, double averageSpice) {
    final positiveAmplitude = tendency >= 0.70
        ? 1.0
        : tendency >= 0.40
        ? 0.5
        : 0.0;
    if (positiveAmplitude > 0) {
      return -positiveAmplitude * _spiceMultiplier(averageSpice);
    }
    if (tendency <= -0.70) return 1.0;
    if (tendency <= -0.40) return 0.5;
    return 0;
  }

  void _recordForPlayer(
    Map<String, AdaptiveProfileState> states,
    String playerId,
    LearningCardDescriptor card,
    LearningRole role,
  ) {
    final state = states[playerId];
    if (state == null) return;
    states[playerId] = _recordCard(
      state,
      card,
      finalRole: role,
      signal: const _Signal(acceptance: true, result: true),
    );
  }

  AdaptiveProfileState _recordCard(
    AdaptiveProfileState state,
    LearningCardDescriptor card, {
    required _Signal signal,
    LearningRole? finalRole,
  }) {
    var result = state;
    for (final evidence in tagProjector.project(card, finalRole: finalRole)) {
      result = _applyEvidence(result, card, evidence, signal);
    }
    return result;
  }

  AdaptiveProfileState _applyEvidence(
    AdaptiveProfileState state,
    LearningCardDescriptor card,
    WeightedPreferenceEvidence evidence,
    _Signal signal,
  ) {
    final inherited = _entryFor(state, evidence.key);
    if (inherited?.excluded ?? false) return state;
    var entry = inherited ?? _freshEntry(evidence.key);
    final weight = evidence.weight;
    final sample = LearningSample(
      equivalentWeight: weight,
      spiceLevel: card.spiceLevel,
      exposure: signal.exposure ? weight : 0,
      attraction: signal.attraction ? weight : 0,
      acceptance: signal.acceptance ? weight : 0,
      resistance: signal.resistance ? weight : 0,
      resultOccurrences: signal.result ? weight : 0,
    );
    final recent = [...entry.recent, sample];
    final hadPending = entry.pendingCategory != null;
    entry = entry.copyWith(
      exposureCount: entry.exposureCount + (signal.exposure ? weight : 0),
      playedCount: entry.playedCount + (signal.played ? weight : 0),
      lockedCount: entry.lockedCount + (signal.locked ? weight : 0),
      ignoredCount: entry.ignoredCount + (signal.ignored ? weight : 0),
      attractionCount: entry.attractionCount + (signal.attraction ? weight : 0),
      acceptanceCount: entry.acceptanceCount + (signal.acceptance ? weight : 0),
      resistanceCount: entry.resistanceCount + (signal.resistance ? weight : 0),
      resultOccurrences: entry.resultOccurrences + (signal.result ? weight : 0),
      spiceTotal: entry.spiceTotal + card.spiceLevel * weight,
      spiceWeight: entry.spiceWeight + weight,
      totalEquivalentOccurrences: entry.totalEquivalentOccurrences + weight,
      observationsSinceReference: entry.observationsSinceReference + weight,
      proposalCooldown: math.max(0.0, entry.proposalCooldown - weight),
      confirmationOccurrences: hadPending
          ? entry.confirmationOccurrences + weight
          : entry.confirmationOccurrences,
      recent: recent,
    );
    entry = _evaluateIfDue(entry);
    final entries = Map<String, PreferenceLearningEntry>.from(state.entries)
      ..[evidence.key.storageKey] = entry;
    return state.copyWith(entries: entries);
  }

  PreferenceLearningEntry _evaluateIfDue(PreferenceLearningEntry entry) {
    final required = entry.source == AdaptiveProfileSource.manualCustomized
        ? manualMinimumOccurrences
        : minimumOccurrences;
    if (entry.observationsSinceReference < required ||
        entry.recentEquivalentOccurrences < minimumOccurrences ||
        entry.totalEquivalentOccurrences - entry.lastEvaluationAt <
            evaluationInterval) {
      return entry;
    }
    final tendency = entry.tendency;
    final currentEstimate = entry.estimatedPa ?? 20;
    final estimate =
        entry.currentCategory == DetailedPreferenceCategory.unsure &&
            tendency >= 0.40
        ? _directEstimateFromUnknown(tendency, entry.averageSpice)
        : (currentEstimate + suggestedDelta(tendency, entry.averageSpice))
              .clamp(1.0, 20.0)
              .toDouble();
    final nextCategory = DetailedPreferenceCategoryRules.fromPa(estimate);
    final crossed = nextCategory != entry.currentCategory;
    final samePending = crossed && nextCategory == entry.pendingCategory;
    return entry.copyWith(
      estimatedPa: estimate,
      lastEvaluationAt: entry.totalEquivalentOccurrences,
      lastTendency: tendency,
      pendingCategory: crossed ? nextCategory : null,
      clearPendingCategory: !crossed,
      confirmationOccurrences: crossed
          ? (samePending ? entry.confirmationOccurrences : 0)
          : 0,
    );
  }

  PreferenceLearningEntry? _entryFor(
    AdaptiveProfileState state,
    PreferenceLearningKey key,
  ) {
    final exact = state.entry(key);
    if (exact != null) return exact;
    final base = state.entry(
      PreferenceLearningKey(preferenceId: key.preferenceId),
    );
    if (base == null) return null;
    return PreferenceLearningEntry(
      key: key,
      source: base.source,
      currentPa: base.currentPa,
      estimatedPa: base.currentPa,
      excluded: base.excluded,
    );
  }

  PreferenceLearningEntry _freshEntry(PreferenceLearningKey key) =>
      PreferenceLearningEntry(
        key: key,
        source: AdaptiveProfileSource.autoLearned,
        currentPa: 20,
        estimatedPa: 20,
      );

  AdaptiveProfileState _replaceEntry(
    AdaptiveProfileState state,
    PreferenceLearningKey key,
    PreferenceLearningEntry Function(PreferenceLearningEntry) update,
  ) {
    final entry = state.entry(key);
    if (entry == null) return state;
    final entries = Map<String, PreferenceLearningEntry>.from(state.entries)
      ..[key.storageKey] = update(entry);
    return state.copyWith(entries: entries);
  }

  double _directEstimateFromUnknown(double tendency, double averageSpice) {
    if (tendency >= 0.70) {
      if (averageSpice >= 4) return 7;
      if (averageSpice >= 3) return 9;
      if (averageSpice >= 2) return 11;
      return 14;
    }
    if (averageSpice >= 4) return 11;
    return 14;
  }

  double _spiceMultiplier(double averageSpice) {
    if (averageSpice < 2) return 0.4;
    if (averageSpice < 3) return 0.6;
    if (averageSpice < 4) return 0.8;
    return 1.0;
  }
}

final class _Signal {
  const _Signal({
    this.exposure = false,
    this.played = false,
    this.locked = false,
    this.ignored = false,
    this.attraction = false,
    this.acceptance = false,
    this.resistance = false,
    this.result = false,
  });

  final bool exposure;
  final bool played;
  final bool locked;
  final bool ignored;
  final bool attraction;
  final bool acceptance;
  final bool resistance;
  final bool result;
}
