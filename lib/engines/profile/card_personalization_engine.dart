import 'dart:math' as math;

import '../../domain/profile/adaptive_profile.dart';
import 'v4_card_rating_engine.dart';

/// Tuning changes must not alter consent, role identity or official PA.
final class PersonalizationConfig {
  const PersonalizationConfig({
    this.nonChoice = .05,
    this.lock = .075,
    this.choice = .10,
    this.acceptance = .075,
    this.resistance = .10,
    this.repeatDecay = .5,
    this.drawAmplitude = .20,
    this.minimumDrawWeight = .5,
    this.minimumEvidence = 3,
    this.refusalCooldown = 20,
  });
  final double nonChoice, lock, choice, acceptance, resistance;
  final double repeatDecay, drawAmplitude, minimumDrawWeight;
  final int minimumEvidence, refusalCooldown;
}

enum PersonalizationSignal { nonChoice, locked, chosen, accepted, resisted }

/// The existing card store holds the official reference and a separate private
/// continuous estimate. No automatic event ever writes currentEstimate.
final class CardPersonalizationEngine {
  const CardPersonalizationEngine({
    this.config = const PersonalizationConfig(),
  });
  final PersonalizationConfig config;

  CardRatingStateV4 seed(
    CardSpecificLearningStore store,
    CardRatingKey key,
    double prior,
    Map<String, double> tags,
  ) {
    final old = store.read(key);
    final state =
        old ??
        CardRatingStateV4(
          key: key,
          initialScore: prior,
          currentEstimate: prior,
          observationCount: 0,
          acceptanceCount: 0,
          resistanceCount: 0,
          source: 'TAG_PRIOR',
        );
    final next = CardRatingStateV4.fromJson({
      ...state.toJson(),
      if (state.currentEstimate == null) 'current_estimate': prior,
      if (state.initialScore == null) 'initial_score': prior,
      'personalization': {
        ...state.personalization,
        'internal':
            state.personalization['internal'] ?? state.currentEstimate ?? prior,
        'tags': tags,
      },
    });
    store.write(next);
    return next;
  }

  bool observe({
    required CardSpecificLearningStore store,
    required CardRatingKey key,
    required double prior,
    required Map<String, double> tags,
    required String eventId,
    required PersonalizationSignal signal,
    required bool enabled,
    String? exposureEpisode,
  }) {
    if (!enabled) return false;
    final old = seed(store, key, prior, tags);
    final data = Map<String, Object?>.from(old.personalization);
    final receipts = ((data['events'] as List?) ?? const [])
        .cast<String>()
        .toSet();
    if (!receipts.add(eventId)) return false;
    final repeats = Map<String, Object?>.from(
      (data['repeats'] as Map?) ?? const {},
    );
    final count = exposureEpisode == null
        ? 0
        : (repeats[exposureEpisode] as int? ?? 0);
    final magnitude = switch (signal) {
      PersonalizationSignal.nonChoice =>
        config.nonChoice * math.pow(config.repeatDecay, count),
      PersonalizationSignal.locked => -config.lock,
      PersonalizationSignal.chosen => -config.choice,
      PersonalizationSignal.accepted => -config.acceptance,
      PersonalizationSignal.resisted => config.resistance,
    };
    if (exposureEpisode != null) repeats[exposureEpisode] = count + 1;
    final estimate =
        ((data['internal'] as num?)?.toDouble() ??
        old.currentEstimate ??
        prior);
    final nextEstimate = (estimate + magnitude).clamp(1.0, 20.0);
    final category = DetailedPreferenceCategoryRules.fromPa(
      nextEstimate.toDouble(),
    );
    final official = DetailedPreferenceCategoryRules.fromPa(
      old.currentEstimate,
    );
    final observations = old.observationCount + 1;
    final declined = observations < (data['declined_until'] as int? ?? 0)
        ? data['declined'] as String?
        : null;
    final pending =
        observations >= config.minimumEvidence &&
            category != official &&
            category.name != declined
        ? category.name
        : null;
    store.write(
      CardRatingStateV4.fromJson({
        ...old.toJson(),
        'observation_count': observations,
        'personalization': {
          ...data,
          'internal': nextEstimate,
          'events': receipts.toList(),
          'repeats': repeats,
          'pending': pending,
        },
      }),
    );
    return true;
  }

  bool decide(
    CardSpecificLearningStore store,
    CardRatingKey key, {
    required bool accept,
    String? expectedCategory,
  }) {
    final old = store.read(key);
    final pending = old?.personalization['pending'] as String?;
    if (old == null || pending == null) return false;
    if (expectedCategory != null && pending != expectedCategory) return false;
    final category = DetailedPreferenceCategory.values.byName(pending);
    final value = category.personalPa;
    if (value == null) return false;
    store.write(
      CardRatingStateV4.fromJson({
        ...old.toJson(),
        if (accept) 'current_estimate': value,
        'personalization': {
          ...old.personalization,
          'pending': null,
          'declined': accept ? null : pending,
          'declined_until': accept
              ? null
              : old.observationCount + config.refusalCooldown,
          if (accept) 'internal': value,
        },
      }),
    );
    return true;
  }

  /// Only unexposed presentations borrow hypotheses. Exact estimates remain
  /// autonomous; in manual mode their behavioral state is never changed.
  double drawWeight(
    CardSpecificLearningStore store,
    CardRatingKey key,
    double prior,
    Map<String, double> tags,
  ) {
    final exact = store.read(key);
    double value = exact?.personalization['internal'] is num
        ? (exact!.personalization['internal']! as num).toDouble()
        : exact?.currentEstimate ?? prior;
    if (exact == null) {
      var sum = 0.0;
      var weight = 0.0;
      for (final other in store.values) {
        if (other.personalization['excluded'] == true ||
            other.source == 'EXCLUSION_MARKER') {
          continue;
        }
        if (other.key.profileId != key.profileId ||
            other.key.role != key.role) {
          continue;
        }
        final metadata = (other.personalization['tags'] as Map?) ?? const {};
        final shared = tags.entries.fold<double>(
          0,
          (s, t) =>
              s +
              (metadata[t.key] is num
                  ? t.value * (metadata[t.key] as num).toDouble()
                  : 0),
        );
        if (shared == 0) continue;
        final estimate =
            (other.personalization['internal'] as num?)?.toDouble() ??
            other.currentEstimate;
        if (estimate == null) continue;
        sum += estimate * shared;
        weight += shared;
      }
      if (weight > 0) value = sum / weight;
    }
    return math.max(
      config.minimumDrawWeight,
      1 + config.drawAmplitude * (10.5 - value) / 9.5,
    );
  }
}
