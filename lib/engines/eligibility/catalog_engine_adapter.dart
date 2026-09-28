import '../../domain/catalog/definitions.dart';
import '../../domain/catalog/enums.dart';
import '../../domain/catalog/requirements.dart';
import '../../domain/game/game_models.dart';

final class CatalogEngineAdapter {
  const CatalogEngineAdapter();

  EngineCard card(CardDefinition card) => EngineCard(
    id: card.stableId,
    enabled: card.enabled,
    tags: card.baseTags.toSet(),
    precision: card.precision,
    frequency: card.frequency,
    repeatability: card.repeatability,
    variants: [
      for (final variant in card.variants)
        EngineVariant(
          id: variant.stableId,
          enabled: variant.enabled,
          chiliLevel: variant.chiliLevel,
          consentRules: [
            ...card.profileRequirements.map(_consent),
            ...variant.profileRequirements.map(_consent),
          ],
          technicalRules: [
            ...card.technicalRequirements.map(TechnicalRule.fromCatalog),
            ...variant.technicalRequirements.map(TechnicalRule.fromCatalog),
            ..._validatedRuntimeRules(variant.stableId),
          ],
          effects: variant.stateEffects,
          tags: {
            ...card.baseTags.where((tag) => !variant.removedTags.contains(tag)),
            ...variant.additionalTags,
          },
          invertible:
              (variant.inversionOverride ?? card.inversionPolicy) !=
              InversionPolicy.NONE,
        ),
    ],
  );

  ConsentRule _consent(ProfileRequirement requirement) => ConsentRule(
    elementId: requirement.elementId,
    role: requirement.role,
    subject: switch (requirement.role) {
      ProfileRole.FAIRE => RequirementSubject.ACTOR,
      ProfileRole.RECEVOIR => RequirementSubject.PARTNER,
      ProfileRole.GENERAL => RequirementSubject.BOTH,
    },
    required: requirement.requirement != RequirementKind.OPTIONAL,
    oneOfGroup: requirement.oneOfGroupId,
  );

  List<TechnicalRule> _validatedRuntimeRules(String variantId) {
    if (variantId == 'variant.dominate_me.restraint') {
      return const [
        TechnicalRule(kind: TechnicalRuleKind.PROXIMITY, values: {'TOGETHER'}),
      ];
    }
    if (_startsWithAny(variantId, const [
      'variant.suggestive_photo.',
      'variant.underwear_photo.',
      'variant.nude_photo.',
      'variant.choose_my_photo.',
    ])) {
      return const [
        TechnicalRule(
          kind: TechnicalRuleKind.MEDIA_CAPABILITY,
          subject: RequirementSubject.ACTOR,
          values: {'PHOTO_CAPTURE'},
        ),
        TechnicalRule(
          kind: TechnicalRuleKind.MEDIA_CAPABILITY,
          subject: RequirementSubject.ACTOR,
          values: {'MEDIA_SEND'},
        ),
        TechnicalRule(
          kind: TechnicalRuleKind.MEDIA_CAPABILITY,
          subject: RequirementSubject.PARTNER,
          values: {'MEDIA_RECEIVE'},
        ),
      ];
    }
    if (variantId.startsWith('variant.intimate_video.')) {
      return const [
        TechnicalRule(
          kind: TechnicalRuleKind.MEDIA_CAPABILITY,
          subject: RequirementSubject.ACTOR,
          values: {'RECORDED_VIDEO'},
        ),
        TechnicalRule(
          kind: TechnicalRuleKind.MEDIA_CAPABILITY,
          subject: RequirementSubject.ACTOR,
          values: {'MEDIA_SEND'},
        ),
        TechnicalRule(
          kind: TechnicalRuleKind.MEDIA_CAPABILITY,
          subject: RequirementSubject.PARTNER,
          values: {'MEDIA_RECEIVE'},
        ),
      ];
    }
    if (_startsWithAny(variantId, const [
      'variant.private_video_call.',
      'variant.nude_video_call.',
    ])) {
      return const [
        TechnicalRule(
          kind: TechnicalRuleKind.MEDIA_CAPABILITY,
          subject: RequirementSubject.BOTH,
          values: {'LIVE_CAMERA'},
        ),
      ];
    }
    return const [];
  }

  bool _startsWithAny(String value, List<String> prefixes) =>
      prefixes.any(value.startsWith);
}
