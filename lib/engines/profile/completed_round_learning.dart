import '../../domain/profile/adaptive_profile.dart';
import 'profile_learning_engine.dart';

/// Receipt and aggregate are one immutable value, saved in the existing store.
/// No rule is run until both canonical completion acknowledgements exist.
AdaptiveProfileState recordCompletedUsageRound({
  required AdaptiveProfileState state,
  required String eventId,
  required Set<String> expectedPlayers,
  required Set<String> completedPlayers,
  required HandLearningEvent hand,
  required List<ResolvedLearningCard> accepted,
  List<ResistanceLearningEvent> resistance = const [],
  ProfileLearningEngine engine = const ProfileLearningEngine(),
}) {
  if (state.appliedRoundEvents.contains(eventId) ||
      expectedPlayers.length != 2 ||
      !completedPlayers.containsAll(expectedPlayers)) {
    return state;
  }
  var next = engine.recordHand(state, hand);
  final unique = {for (final card in accepted) card.card.identity: card};
  next = engine.recordRoundOutcome(
    {state.profileId: next},
    RoundLearningOutcome(acceptedCards: unique.values.toList()),
  )[state.profileId]!;
  for (final event in resistance) {
    next = engine.recordResistance(next, event);
  }
  return next.copyWith(
    appliedRoundEvents: {...next.appliedRoundEvents, eventId},
  );
}
