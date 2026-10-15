import '../../engines/profile/profile_learning_engine.dart';
import '../protocol/network_usage_projection.dart';

LearningCardDescriptor usageLearningDescriptor(NetworkUsageProjection usage) {
  final action = usage.resolvedAction;
  return LearningCardDescriptor(
    cardId: usage.conceptId,
    variantId: (action['stage_id'] ?? action['variant_id'])! as String,
    usageId: usage.usageId,
    tags: (action['tags']! as List).cast<String>(),
    spiceLevel: action['effective_chili']! as int,
    primaryPreferenceIds: (action['primary_preference_ids']! as List)
        .cast<String>(),
  );
}

ResolvedLearningCard usageLearningOutcome(NetworkUsageProjection usage) {
  final action = usage.resolvedAction;
  final actors = (action['actor_player_ids']! as List).cast<String>();
  final targets = (action['target_player_ids']! as List).cast<String>();
  final card = usageLearningDescriptor(usage);
  return switch (action['direction']) {
    'MUTUEL' || 'SIMULTANE' => ResolvedLearningCard(
      card: card,
      participation: action['direction'] == 'MUTUEL'
          ? ResolvedParticipation.mutual
          : ResolvedParticipation.simultaneous,
      participantPlayerIds: {...actors, ...targets}.toList(),
    ),
    'SOLO' => ResolvedLearningCard(
      card: card,
      participation: ResolvedParticipation.solo,
      soloPlayerId: actors.single,
    ),
    _ => ResolvedLearningCard(
      card: card,
      participation: ResolvedParticipation.directed,
      performerPlayerId: actors.single,
      receiverPlayerId: targets.single,
    ),
  };
}
