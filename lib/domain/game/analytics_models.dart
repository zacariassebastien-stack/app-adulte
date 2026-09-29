import '../../core/json.dart';
import '../round/combat_value_snapshot.dart';

// Versioned wire identifiers; no psychological labels or final scores.
// ignore_for_file: constant_identifier_names
enum DataVisibility { PUBLIC, PLAYER_PRIVATE, SESSION_PRIVATE_INTERNAL }

enum BehaviorAxis {
  AUDACE,
  PRUDENCE,
  DEPENSE_PA,
  ECONOMIE_PA,
  NEGOCIATION,
  TENTATION,
  PROMESSE,
  REALISATION,
  INVERSION,
  INITIATIVE,
  RECEPTIVITE,
  VARIETE,
  SPECIALISATION,
  ESCALADE,
  MODERATION,
  RECOVERY_RISK,
  PROLONGATION,
  RENONCEMENT_STRATEGIQUE,
  CHANGEMENT_STYLE,
}

enum ObservationStage { OPPORTUNITY, ATTEMPT, ACCEPTED, COMPLETED, EXCLUDED }

enum NonPerformanceReason {
  NONE,
  STRATEGIC,
  CONSENT_STOP,
  PRACTICE_REFUSAL,
  CONSENT_WITHDRAWN,
  PROFILE_EXCLUSION,
  TECHNICAL,
  CONTEXTUAL,
  UNKNOWN,
}

enum ActionSource {
  NORMAL_DUEL,
  AUCTION_RESULT,
  CORRUPTION,
  RECOVERY,
  RECOVERY_CONDITION,
}

enum AnalyticsDataStatus { AVAILABLE, INSUFFICIENT_DATA }

/// Local owner-only analytical evidence. An opportunity ID identifies one
/// decision, not an event or an entire session. No consent database is copied.
final class PrivateAnalyticsContext {
  PrivateAnalyticsContext({
    required this.playerId,
    required this.opportunityId,
    required this.axis,
    required this.stage,
    this.reason = NonPerformanceReason.NONE,
    this.snapshot,
    this.amount,
    this.availableAmount,
    Iterable<String> availableCardIds = const [],
    Iterable<String> availableTagIds = const [],
    this.chosenCardId,
    Iterable<String> chosenTags = const [],
  }) : availableCardIds = List.unmodifiable(availableCardIds.toSet()),
       availableTagIds = List.unmodifiable(availableTagIds.toSet()),
       chosenTags = List.unmodifiable(chosenTags.toSet()) {
    if (playerId.isEmpty || opportunityId.isEmpty) {
      throw ArgumentError('Owner and opportunity are required');
    }
    if (snapshot != null && snapshot!.playerId != playerId) {
      throw ArgumentError('Snapshot belongs to another player');
    }
    if ((amount ?? 0) < 0 || (availableAmount ?? 0) < 0) {
      throw ArgumentError('Negative analytics amount');
    }
    if (stage == ObservationStage.EXCLUDED &&
        reason == NonPerformanceReason.NONE) {
      throw ArgumentError('Exclusion requires a reason');
    }
    if (stage != ObservationStage.EXCLUDED &&
        reason != NonPerformanceReason.NONE &&
        reason != NonPerformanceReason.STRATEGIC) {
      throw ArgumentError('Protected reason must exclude the opportunity');
    }
  }
  final String playerId, opportunityId;
  final BehaviorAxis axis;
  final ObservationStage stage;
  final NonPerformanceReason reason;
  final CombatValueSnapshot? snapshot;
  final int? amount, availableAmount;
  final List<String> availableCardIds, availableTagIds, chosenTags;
  final String? chosenCardId;
  Map<String, Object?> toJson() => {
    'player_id': playerId,
    'opportunity_id': opportunityId,
    'axis': axis.name,
    'stage': stage.name,
    'reason': reason.name,
    if (snapshot != null) 'snapshot': snapshot!.toJson(),
    if (amount != null) 'amount': amount,
    if (availableAmount != null) 'available_amount': availableAmount,
    'available_card_ids': availableCardIds,
    'available_tag_ids': availableTagIds,
    if (chosenCardId != null) 'chosen_card_id': chosenCardId,
    'chosen_tags': chosenTags,
  };
  factory PrivateAnalyticsContext.fromJson(Map<String, Object?> json) {
    final r = JsonReader(json, 'PrivateAnalyticsContext');
    r.only({
      'player_id',
      'opportunity_id',
      'axis',
      'stage',
      'reason',
      'snapshot',
      'amount',
      'available_amount',
      'available_card_ids',
      'available_tag_ids',
      'chosen_card_id',
      'chosen_tags',
    });
    return PrivateAnalyticsContext(
      playerId: r.string('player_id'),
      opportunityId: r.string('opportunity_id'),
      axis: r.enumeration('axis', BehaviorAxis.values),
      stage: r.enumeration('stage', ObservationStage.values),
      reason: r.enumeration('reason', NonPerformanceReason.values),
      snapshot: json['snapshot'] == null
          ? null
          : CombatValueSnapshot.fromJson(
              r.child(json['snapshot'], 'snapshot', 'CombatValueSnapshot').json,
            ),
      amount: r.optionalInteger('amount', min: 0),
      availableAmount: r.optionalInteger('available_amount', min: 0),
      availableCardIds: r.strings('available_card_ids'),
      availableTagIds: r.strings('available_tag_ids'),
      chosenCardId: r.optionalString('chosen_card_id'),
      chosenTags: r.strings('chosen_tags'),
    );
  }
}

final class AxisMetrics {
  const AxisMetrics({
    required this.opportunities,
    required this.attempts,
    required this.accepted,
    required this.completed,
    required this.excluded,
    required this.status,
    this.meanPersonalValue,
    this.totalAmount = 0,
    this.availableAmount = 0,
    this.uniqueChoices = 0,
    this.eligibleChoices = 0,
    this.voluntaryRepeats = 0,
    this.topChoiceShare,
    this.uniqueTags = 0,
  });
  final int opportunities,
      attempts,
      accepted,
      completed,
      excluded,
      totalAmount,
      availableAmount,
      uniqueChoices,
      eligibleChoices,
      voluntaryRepeats,
      uniqueTags;
  final AnalyticsDataStatus status;
  final double? meanPersonalValue, topChoiceShare;
  double? get ratio =>
      status == AnalyticsDataStatus.AVAILABLE && opportunities > 0
      ? attempts / opportunities
      : null;
  Map<String, Object?> toJson() => {
    'opportunities': opportunities,
    'attempts': attempts,
    'accepted': accepted,
    'completed': completed,
    'excluded_neutral': excluded,
    'sample_size': opportunities,
    'status': status.name,
    'ratio': ratio,
    'acceptance_ratio':
        status == AnalyticsDataStatus.AVAILABLE && opportunities > 0
        ? accepted / opportunities
        : null,
    'completion_ratio':
        status == AnalyticsDataStatus.AVAILABLE && opportunities > 0
        ? completed / opportunities
        : null,
    'mean_personal_value': meanPersonalValue,
    'total_amount': totalAmount,
    'available_amount': availableAmount,
    'amount_ratio': availableAmount == 0 ? null : totalAmount / availableAmount,
    'unique_choices': uniqueChoices,
    'eligible_choices': eligibleChoices,
    'eligible_coverage': eligibleChoices == 0
        ? null
        : uniqueChoices / eligibleChoices,
    'voluntary_repeats': voluntaryRepeats,
    'top_choice_share': topChoiceShare,
    'unique_tags': uniqueTags,
  };
}

/// Never include this object in PublicState or partner projections.
final class PlayerBehaviorMetrics {
  PlayerBehaviorMetrics(this.playerId, Map<BehaviorAxis, AxisMetrics> axes)
    : axes = Map.unmodifiable(axes);
  final String playerId;
  final Map<BehaviorAxis, AxisMetrics> axes;
  Map<String, Object?> toJson() => {
    'player_id': playerId,
    'visibility': DataVisibility.PLAYER_PRIVATE.name,
    'axes': {for (final e in axes.entries) e.key.name: e.value.toJson()},
  };
}
