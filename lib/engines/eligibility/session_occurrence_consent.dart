import '../../domain/game/game_models.dart';
import '../../domain/profile/v4_profile.dart';
import '../profile/v4_card_rating_engine.dart';
import '../runtime/v4_runtime_engine.dart';
import 'concept_runtime_catalog.dart';

/// One participant's veto-only contribution. It never exports their profile.
/// PA, missing estimates and learning are deliberately not consent decisions.
final class SessionOccurrenceConsent {
  const SessionOccurrenceConsent();

  bool allows({
    required ConceptRuntimeCatalog catalog,
    required V4Profile profile,
    required String subjectId,
    required String ownerId,
    required List<String> playerIds,
    required String conceptId,
    required String actionId,
    required CardOccurrenceDirection direction,
  }) {
    final targets = const V4ActionTargetResolver().resolve(
      ownerPlayerId: ownerId,
      playerIds: playerIds,
      direction: direction,
    );
    final actor = direction == CardOccurrenceDirection.RECEVOIR
        ? playerIds.singleWhere((id) => id != ownerId)
        : ownerId;
    final both =
        direction == CardOccurrenceDirection.MUTUEL ||
        direction == CardOccurrenceDirection.SIMULTANE;
    if (!both && actor != subjectId && !targets.contains(subjectId)) {
      return true;
    }
    final localDirection = both
        ? direction.name
        : direction == CardOccurrenceDirection.FAIRE ||
              direction == CardOccurrenceDirection.RECEVOIR
        ? (actor == subjectId ? 'FAIRE' : 'RECEVOIR')
        : direction.name;
    final roles = V4CardRatingEngine.rolesForDirection(
      conceptId,
      localDirection,
    );
    final preciseVeto = profile.stageVetoes.any(
      (v) =>
          v.conceptId == conceptId &&
          v.actionId == actionId &&
          (v.role == ProfilePreferenceRole.general ||
              v.role.wireName == localDirection ||
              roles.contains(v.role)),
    );
    if (preciseVeto) return false;
    if (profile.allowsPresentation(conceptId, actionId, localDirection)) {
      return true;
    }
    if (profile.excludesStage(conceptId, actionId, localDirection) ||
        roles.any(
          (r) => profile.excludesStage(conceptId, actionId, r.wireName),
        )) {
      return false;
    }
    final concept = catalog.concepts.concepts.singleWhere(
      (c) => c.id == conceptId,
    );
    final zone = concept.variants
        .where((v) => v.id == actionId)
        .firstOrNull
        ?.zoneId;
    // Concrete anatomical vetoes apply only to the actual fixed zone, not LIBRE
    // or another anatomical variant of the same concept.
    final tags = catalog.vetoTags(conceptId, actionId: actionId);
    if (conceptId == '039' && localDirection == 'RECEVOIR') {
      tags.remove('etre_regarde');
      tags.add('regarder');
    }
    final scoped = V4Profile(
      sex: profile.sex,
      profileId: profile.profileId,
      preferences: {
        for (final entry in profile.preferences.entries)
          if (entry.value.key.zoneId == null || entry.value.key.zoneId == zone)
            entry.key: entry.value,
      },
    );
    final rating = catalog.optionalRatingFor(conceptId, actionId);
    if (rating != null &&
        const V4CardRatingEngine()
                .initializeForDirection(
                  profile: scoped,
                  variant: rating,
                  conceptId: conceptId,
                  direction: localDirection,
                  vetoTags: tags,
                )
                .kind ==
            V4RatingResultKind.excluded) {
      return false;
    }
    return !profile.preferences.values.any(
      (p) =>
          p.excluded &&
          tags.contains(p.key.tagId) &&
          (p.key.zoneId == null || p.key.zoneId == zone) &&
          (p.key.role == ProfilePreferenceRole.general ||
              roles.contains(p.key.role)),
    );
  }
}
