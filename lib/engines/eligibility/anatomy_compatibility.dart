import '../../domain/catalog/concept_catalog.dart';
import '../../domain/game/game_models.dart';
import '../../domain/profile/v4_profile.dart';

/// Structural eligibility only: never a preference or a consent veto.
abstract final class AnatomyCompatibility {
  static bool allows({
    required CardConcept concept,
    required String actionId,
    required CardOccurrenceDirection direction,
    required String ownerId,
    required Map<String, PlayerAnatomy> anatomies,
  }) {
    final stage = concept.stages.where((a) => a.id == actionId).firstOrNull;
    final variant = concept.variants.where((a) => a.id == actionId).firstOrNull;
    if (stage == null && variant == null) return false;
    if (anatomies.length != 2 || !anatomies.containsKey(ownerId)) return false;
    final partnerId = anatomies.keys.singleWhere((id) => id != ownerId);
    final requirements =
        (stage?.anatomyRequirements ??
                variant?.anatomyRequirements ??
                concept.anatomyRequirements)
            ?.byDirection[direction] ??
        const {};
    return requirements.entries.every(
      (entry) =>
          anatomies[entry.key == 'OWNER' ? ownerId : partnerId] == entry.value,
    );
  }
}
