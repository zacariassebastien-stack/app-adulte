import '../../domain/game/analytics_models.dart';
import '../../domain/game/events.dart';

/// Pure descriptive aggregation. No names, diagnosis, desirability weights or
/// partner comparisons. Unknown/legacy evidence cannot create a denominator.
final class AnalyticsEngine {
  const AnalyticsEngine({this.minimumSamples = 3});
  final int minimumSamples;
  PlayerBehaviorMetrics compute(String playerId, Iterable<GameEvent> events) {
    if (minimumSamples < 1) {
      throw ArgumentError('minimumSamples must be positive');
    }
    final groups = <BehaviorAxis, Map<String, List<PrivateAnalyticsContext>>>{};
    for (final event in events) {
      for (final c in event.analyticsFor(playerId)) {
        groups
            .putIfAbsent(c.axis, () => {})
            .putIfAbsent(c.opportunityId, () => [])
            .add(c);
      }
    }
    final result = <BehaviorAxis, AxisMetrics>{};
    for (final axis in BehaviorAxis.values) {
      var opportunities = 0,
          attempts = 0,
          accepted = 0,
          completed = 0,
          excluded = 0;
      var total = 0, available = 0, valueSum = 0, valueCount = 0, repeats = 0;
      final chosen = <String, int>{}, eligible = <String>{}, tags = <String>{};
      final decisions = (groups[axis] ?? {}).entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      for (final decision in decisions) {
        final observations = decision.value;
        if (observations.any((c) => c.stage == ObservationStage.EXCLUDED)) {
          excluded++;
          continue;
        }
        if (!observations.any((c) => c.stage == ObservationStage.OPPORTUNITY)) {
          continue;
        }
        final options = observations.expand((c) => c.availableCardIds).toSet();
        if ((axis == BehaviorAxis.VARIETE ||
                axis == BehaviorAxis.SPECIALISATION) &&
            options.length < 2) {
          excluded++;
          continue;
        }
        opportunities++;
        final stages = observations.map((c) => c.stage).toSet();
        if (stages.contains(ObservationStage.ATTEMPT)) attempts++;
        if (stages.contains(ObservationStage.ACCEPTED)) accepted++;
        if (stages.contains(ObservationStage.COMPLETED)) completed++;
        int uniqueNumber(Iterable<int?> values) {
          final nonnull = values.whereType<int>().toSet();
          if (nonnull.length > 1) {
            throw StateError(
              'Conflicting analytics evidence for ${decision.key}',
            );
          }
          return nonnull.firstOrNull ?? 0;
        }

        total += uniqueNumber(observations.map((c) => c.amount));
        available += uniqueNumber(observations.map((c) => c.availableAmount));
        final snapshots = observations
            .where((c) => c.snapshot != null)
            .map((c) => c.snapshot!)
            .toList();
        if (snapshots.isNotEmpty) {
          final snapshot = snapshots.first;
          if (snapshots.any(
            (s) =>
                s.playerId != snapshot.playerId ||
                s.cardId != snapshot.cardId ||
                s.variantId != snapshot.variantId ||
                s.personalValue != snapshot.personalValue ||
                s.roleAtCommit != snapshot.roleAtCommit ||
                !s.committedAt.isAtSameMomentAs(snapshot.committedAt),
          )) {
            throw StateError('Changed commit snapshot');
          }
          valueSum += snapshot.personalValue;
          valueCount++;
        }
        eligible.addAll(options);
        final selections = observations
            .map((c) => c.chosenCardId)
            .whereType<String>()
            .toSet();
        if (selections.length > 1) {
          throw StateError('Conflicting selected card');
        }
        if (selections.isNotEmpty) {
          final id = selections.single;
          if (options.isNotEmpty && !options.contains(id)) {
            throw StateError('Choice outside recorded opportunity');
          }
          if (chosen.containsKey(id) && options.length > 1) repeats++;
          chosen.update(id, (n) => n + 1, ifAbsent: () => 1);
        }
        tags.addAll(observations.expand((c) => c.chosenTags));
      }
      final counts = chosen.values.toList()..sort();
      final samplesEnough = opportunities >= minimumSamples;
      result[axis] = AxisMetrics(
        opportunities: opportunities,
        attempts: attempts,
        accepted: accepted,
        completed: completed,
        excluded: excluded,
        status: samplesEnough
            ? AnalyticsDataStatus.AVAILABLE
            : AnalyticsDataStatus.INSUFFICIENT_DATA,
        meanPersonalValue: valueCount == 0 ? null : valueSum / valueCount,
        totalAmount: total,
        availableAmount: available,
        uniqueChoices: chosen.length,
        eligibleChoices: eligible.length,
        voluntaryRepeats: repeats,
        uniqueTags: tags.length,
        topChoiceShare: counts.isEmpty
            ? null
            : counts.last / counts.fold(0, (a, b) => a + b),
      );
    }
    return PlayerBehaviorMetrics(playerId, result);
  }
}
