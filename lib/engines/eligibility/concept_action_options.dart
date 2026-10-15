import '../../domain/catalog/concept_catalog.dart';
import '../../domain/catalog/enums.dart';
import '../../domain/game/game_models.dart';
import '../deck/concept_deck_engine.dart';
import 'catalog_engine_adapter.dart';
import 'concept_runtime_catalog.dart';
import 'eligibility_engine.dart';

final class ConceptActionOption {
  ConceptActionOption({
    required this.choice,
    required this.variant,
    required this.title,
    Map<String, Object?> parameters = const {},
  }) : parameters = Map.unmodifiable(parameters);
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
    bool mediaSendRequired = false,
    bool recovery = false,
  }) {
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
        initialClothing: context.clothesByPlayer[actor.playerId] ?? 0,
      ),
      eligibility: eligibility,
      globalChili: recovery ? 4 : context.chiliActive,
      style: PlayerStyle.SOFT,
    );
    bool allowed(EngineVariant variant) {
      final eligible = const EligibilityEngine()
          .evaluate(
            card: EngineCard(id: 'resolved-choice', variants: [variant]),
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
      if (preferences.isEmpty) return false;
      bool directionAllowed(ProfileRole role) => preferences.every(
        (id) =>
            actor.preference(id).status == PreferenceStatus.ACCEPTED &&
            actor.preference(id).valueFor(role) != null,
      );
      if (variant.tags.contains('v3.direction.faire') &&
          variant.tags.contains('v3.direction.recevoir')) {
        return directionAllowed(ProfileRole.FAIRE) ||
            directionAllowed(ProfileRole.RECEVOIR);
      }
      return true;
    }

    for (final candidate in pool.classes.values.expand((items) => items)) {
      final concept = candidate.concept;
      // Profiles currently provide no concrete tagged accessory inventory.
      // No hasSextoy/ID/name fallback may authorize these choices.
      if (concept.kind == ConceptKind.accessory || concept.id == '024') {
        continue;
      }
      final engine = const CatalogEngineAdapter.v3().card(
        catalog.definitions[concept.id]!,
      );
      final choices = <ConceptActionOption>[];
      for (final choice in candidate.choices) {
        final base = engine.variants.singleWhere(
          (v) => v.id == choice.actionId,
        );
        for (final technique
            in concept.id == '004' ? ['lecher', 'sucer'] : <String?>[null]) {
          var variant = _variant(
            base,
            choice,
            preference: technique == null ? null : 'v3.preference.$technique',
          );
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
          if (!allowed(variant)) continue;
          final definition = catalog.definitions[concept.id]!.variants
              .singleWhere((v) => v.stableId == choice.actionId);
          final zone = catalog.concepts.zones
              .where((z) => z.id == choice.zoneId)
              .firstOrNull;
          choices.add(
            ConceptActionOption(
              choice: choice,
              variant: variant,
              title:
                  '${definition.title ?? concept.title}${zone == null ? '' : ' · ${zone.title}'}${technique == null ? '' : ' · $technique'}',
              parameters: {
                'technique': ?technique,
                if (media) 'media_capture_player_id': actor.playerId,
                if (media) 'media_send': mediaSendRequired,
              },
            ),
          );
        }
      }
      if (choices.isNotEmpty) result[concept.id] = List.unmodifiable(choices);
    }
    // Joker borrows a compatible existing intimate practice, never its quota.
    const intimate = {
      '019',
      '020',
      '021',
      '022',
      '023',
      '025',
      '026',
      '027',
      '028',
      '029',
      '030',
      '031',
      '049',
      '050',
      '051',
      '052',
      '065',
    };
    final joker = catalog.definitions['024'];
    if (joker != null && (recovery || context.chiliActive >= 3)) {
      final borrowed = <ConceptActionOption>[];
      for (final entry in result.entries.where(
        (e) => intimate.contains(e.key),
      )) {
        for (final option in entry.value) {
          const choice = ConceptDeckChoice(actionId: '024.action', chili: 3);
          borrowed.add(
            ConceptActionOption(
              choice: choice,
              variant: _variant(option.variant, choice),
              title:
                  '${catalog.definitions[entry.key]!.title} · ${option.title}',
              parameters: {
                ...option.parameters,
                'practice_concept_id': entry.key,
                'practice_action_id': option.choice.actionId,
                'practice_chili': option.choice.chili,
                if (option.choice.zoneId != null)
                  'practice_zone_id': option.choice.zoneId,
              },
            ),
          );
        }
      }
      if (borrowed.isNotEmpty) result['024'] = List.unmodifiable(borrowed);
    }
    return Map.unmodifiable(result);
  }

  EngineVariant _variant(
    EngineVariant base,
    ConceptDeckChoice choice, {
    String? preference,
  }) => EngineVariant(
    id: choice.actionId,
    chiliLevel: choice.chili,
    consentRules: preference == null
        ? base.consentRules
        : [
            ConsentRule(
              elementId: preference,
              role: ProfileRole.FAIRE,
              oneOfGroup: 'direction:$preference',
            ),
            ConsentRule(
              elementId: preference,
              role: ProfileRole.RECEVOIR,
              oneOfGroup: 'direction:$preference',
            ),
          ],
    technicalRules: base.technicalRules,
    technicalAlternatives: base.technicalAlternatives,
    effects: base.effects,
    tags: {
      for (final tag in base.tags)
        if (preference == null || !tag.startsWith('v3.preference.')) tag,
      ?preference,
    },
    invertible: base.invertible,
  );
}
