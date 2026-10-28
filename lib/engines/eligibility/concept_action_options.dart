import '../../domain/catalog/concept_catalog.dart';
import '../../domain/catalog/enums.dart';
import '../../domain/catalog/v4_catalog.dart';
import '../../domain/game/game_models.dart';
import '../../domain/profile/v4_profile.dart';
import '../profile/v4_card_rating_engine.dart';
import '../deck/concept_deck_engine.dart';
import 'catalog_engine_adapter.dart';
import 'concept_runtime_catalog.dart';
import 'eligibility_engine.dart';
import 'directional_clothing.dart';

final class ConceptActionOption {
  ConceptActionOption({
    required this.choice,
    required this.variant,
    required this.title,
    Map<String, Object?> parameters = const {},
    Set<CardOccurrenceDirection>? allowedDirections,
  }) : parameters = Map.unmodifiable(parameters),
       allowedDirections = allowedDirections == null
           ? null
           : Set.unmodifiable(allowedDirections);
  final Set<CardOccurrenceDirection>? allowedDirections;
  bool allowsDirection(CardOccurrenceDirection direction) =>
      allowedDirections == null || allowedDirections!.contains(direction);
  final ConceptDeckChoice choice;
  final EngineVariant variant;
  final String title;
  final Map<String, Object?> parameters;
  String get key =>
      '${choice.actionId}/${choice.zoneId ?? ''}/${parameters['technique'] ?? ''}/${parameters['practice_concept_id'] ?? ''}/${parameters['practice_action_id'] ?? ''}';
}

/// Resolves current choices through existing V4 eligibility. Never spends quota.
final class ConceptActionOptions {
  const ConceptActionOptions();

  Map<String, List<ConceptActionOption>> evaluate({
    required ConceptRuntimeCatalog catalog,
    required EngineSessionContext context,
    required PlayerGameProfile actor,
    required PlayerGameProfile partner,
    required ProfileHierarchy hierarchy,
    V4Profile? profile,
    CardSpecificLearningStore? cardRatings,
    bool mediaSendRequired = false,
    bool recovery = false,
    int? recoveryMinimumChili,
  }) {
    final minimumChili = recoveryMinimumChili ?? context.chiliActive;
    if (recovery) {
      RangeError.checkValueInInterval(
        minimumChili,
        1,
        4,
        'recoveryMinimumChili',
      );
    }
    final result = <String, List<ConceptActionOption>>{};
    final eligibility = ConceptDeckEligibility(
      actionIdsByConcept: {
        for (final c in catalog.concepts.concepts)
          c.id: {...c.stages.map((a) => a.id), ...c.variants.map((a) => a.id)},
      },
      zoneIdsByConcept: {
        for (final c in catalog.concepts.concepts)
          c.id: catalog.concepts.zones.map((z) => z.id).toSet(),
      },
    );
    final pool = const ConceptDeckEngine().prepare(
      catalog: catalog.concepts,
      // Definition-only availability. Runtime stock is checked by the caller.
      stock: ConceptDeckStock.startCycle(
        catalog: catalog.concepts,
        initialClothing:
            3, // Definition-only pool; current clothing is checked below.
      ),
      eligibility: eligibility,
      globalChili: recovery ? 4 : context.chiliActive,
      style: PlayerStyle.SOFT,
    );
    bool allowed(
      String conceptId,
      EngineVariant variant,
      CardOccurrenceDirection direction,
    ) {
      if (profile != null) {
        final tags = catalog.vetoTags(conceptId, actionId: variant.id);
        final rating = catalog.optionalRatingFor(conceptId, variant.id);
        if (rating == null) return false;
        bool rated(String direction) {
          if (profile.excludesStage(conceptId, variant.id, direction)) {
            return false;
          }
          if (profile.allowsPresentation(conceptId, variant.id, direction) &&
              cardRatings?.referenceEstimate(
                    CardRatingKey(
                      profileId: profile.profileId,
                      cardId: conceptId,
                      variantId: variant.id,
                      role: ProfilePreferenceRole.parse(direction),
                    ),
                  ) !=
                  null) {
            return true;
          }
          final result = const V4CardRatingEngine().initializeForDirection(
            profile: profile,
            variant: rating,
            conceptId: conceptId,
            direction: direction,
            vetoTags: tags,
          );
          if (result.kind == V4RatingResultKind.excluded ||
              result.kind == V4RatingResultKind.unavailable) {
            return false;
          }
          return result.kind == V4RatingResultKind.rated ||
              cardRatings?.referenceEstimate(
                    CardRatingKey(
                      profileId: profile.profileId,
                      cardId: conceptId,
                      variantId: variant.id,
                      role: ProfilePreferenceRole.parse(direction),
                    ),
                  ) !=
                  null;
        }

        if (!rated(direction.name)) return false;
      }
      final eligible = const EligibilityEngine()
          .evaluate(
            card: EngineCard(
              id: 'resolved-choice',
              variants: [
                if (profile == null)
                  variant
                else
                  EngineVariant(
                    id: variant.id,
                    enabled: variant.enabled,
                    chiliLevel: variant.chiliLevel,
                    technicalRules: variant.technicalRules,
                    technicalAlternatives: variant.technicalAlternatives,
                    effects: variant.effects,
                    tags: variant.tags,
                    invertible: variant.invertible,
                  ),
              ],
            ),
            context: context,
            actor: actor,
            partner: partner,
            hierarchy: hierarchy,
            requirePersonalValue: true,
            recovery: recovery,
          )
          .eligibleVariants
          .isNotEmpty;
      if (!eligible) return false;
      final preferences = variant.tags.where(
        (t) => t.startsWith('v3.preference.'),
      );
      if (profile != null) return true;
      if (preferences.isEmpty) return false;
      bool directionAllowed(ProfileRole role) => preferences.every(
        (id) =>
            actor.preference(id).status == PreferenceStatus.ACCEPTED &&
            actor.preference(id).valueFor(role) != null,
      );
      if (variant.tags.contains('v3.direction.faire') &&
          variant.tags.contains('v3.direction.recevoir')) {
        return directionAllowed(
          direction == CardOccurrenceDirection.FAIRE
              ? ProfileRole.FAIRE
              : ProfileRole.RECEVOIR,
        );
      }
      return true;
    }

    for (final candidate in pool.classes.values.expand((items) => items)) {
      final concept = candidate.concept;
      final definition = catalog.definitions[concept.id]!;
      final presence =
          context.mode == SessionMode.distance ||
              (context.mode == SessionMode.hybrid &&
                  context.proximity == ProximityState.SEPARATED)
          ? V4SessionPresence.distance
          : V4SessionPresence.presentiel;
      if (definition.v4 != null &&
          !definition.v4!.presence.supports(presence)) {
        continue;
      }
      if (concept.sessionModes.isNotEmpty &&
          !concept.sessionModes.contains(
            presence == V4SessionPresence.distance
                ? SessionMode.distance
                : SessionMode.face_to_face,
          )) {
        continue;
      }
      // Profiles currently provide no concrete tagged accessory inventory.
      // No hasSextoy/ID/name fallback may authorize these choices.
      if (concept.kind == ConceptKind.accessory) {
        continue;
      }
      final engine = const CatalogEngineAdapter.v3().card(
        catalog.definitions[concept.id]!,
      );
      final choices = <ConceptActionOption>[];
      for (final choice in candidate.choices) {
        if (recovery && choice.chili < minimumChili) continue;
        final base = engine.variants.singleWhere(
          (v) => v.id == choice.actionId,
        );
        {
          var variant = _variant(base, choice);
          final media = {'044', '045', '046', '047'}.contains(concept.id);
          if (media) {
            final photo = concept.id == '044' || concept.id == '045';
            variant = EngineVariant(
              id: variant.id,
              chiliLevel: variant.chiliLevel,
              consentRules: [
                ...variant.consentRules.where(
                  (r) => r.elementId != 'v3.preference.envoyer',
                ),
                if (mediaSendRequired)
                  const ConsentRule(
                    elementId: 'v3.preference.envoyer',
                    role: ProfileRole.GENERAL,
                  ),
              ],
              technicalRules: [
                ...variant.technicalRules,
                TechnicalRule(
                  kind: TechnicalRuleKind.MEDIA_CAPABILITY,
                  values: {photo ? 'PHOTO_CAPTURE' : 'RECORDED_VIDEO'},
                ),
                if (mediaSendRequired) ...[
                  const TechnicalRule(
                    kind: TechnicalRuleKind.MEDIA_CAPABILITY,
                    values: {'MEDIA_SEND'},
                  ),
                  const TechnicalRule(
                    kind: TechnicalRuleKind.MEDIA_CAPABILITY,
                    subject: RequirementSubject.PARTNER,
                    values: {'MEDIA_RECEIVE'},
                  ),
                ],
              ],
              technicalAlternatives: variant.technicalAlternatives,
              effects: variant.effects,
              tags: {
                for (final tag in variant.tags)
                  if (tag != 'v3.preference.envoyer') tag,
                if (mediaSendRequired) 'v3.preference.envoyer',
              },
              invertible: variant.invertible,
            );
          }
          final allowedDirections = {
            for (final direction in CardOccurrenceDirection.values)
              if (variant.tags.contains(
                    'v3.direction.${direction.name.toLowerCase()}',
                  ) &&
                  allowed(
                    concept.id,
                    clothingVariantForDirection(definition, variant, direction),
                    direction,
                  ))
                direction,
          };
          if (allowedDirections.isEmpty) continue;
          final actionDefinition = catalog.definitions[concept.id]!.variants
              .singleWhere((v) => v.stableId == choice.actionId);
          final zone = catalog.concepts.zones
              .where((z) => z.id == choice.zoneId)
              .firstOrNull;
          choices.add(
            ConceptActionOption(
              choice: choice,
              allowedDirections: allowedDirections,
              variant: variant,
              title: concept.id == '024'
                  ? concept.actionText
                  : concept.variants.any(
                      (v) => v.id == choice.actionId && v.freeZone,
                    )
                  ? switch (concept.id) {
                      '002' =>
                        'Choisis librement une partie du corps à embrasser.',
                      '004' =>
                        'Choisis librement la partie du corps et la manière d’utiliser ta bouche.',
                      '005' =>
                        'Choisis librement la partie du corps et la manière d’utiliser tes mains.',
                      _ => 'Choisis librement une partie du corps.',
                    }
                  : '${actionDefinition.title ?? concept.title}${zone == null ? '' : ' · ${zone.title}'}',
              parameters: {
                if (media) 'media_capture_player_id': actor.playerId,
                if (media) 'media_send': mediaSendRequired,
              },
            ),
          );
        }
      }
      if (choices.isNotEmpty) result[concept.id] = List.unmodifiable(choices);
    }
    return Map.unmodifiable(result);
  }

  EngineVariant _variant(EngineVariant base, ConceptDeckChoice choice) =>
      EngineVariant(
        id: choice.actionId,
        chiliLevel: choice.chili,
        consentRules: base.consentRules,
        technicalRules: base.technicalRules,
        technicalAlternatives: base.technicalAlternatives,
        effects: base.effects,
        tags: base.tags,
        invertible: base.invertible,
      );
}
