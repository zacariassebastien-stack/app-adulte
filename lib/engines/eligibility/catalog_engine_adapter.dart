import '../../domain/catalog/definitions.dart';
import '../../domain/catalog/enums.dart';
import '../../domain/catalog/requirements.dart';
import '../../domain/catalog/v3_rules.dart';
import '../../domain/game/game_models.dart';

final class CatalogEngineAdapter {
  const CatalogEngineAdapter() : useV3 = false;
  const CatalogEngineAdapter.v3() : useV3 = true;
  const CatalogEngineAdapter.v4() : useV3 = true;

  final bool useV3;

  EngineCard card(CardDefinition card) => EngineCard(
    id: card.stableId,
    enabled: useV3 ? card.v3DeckEnabled : card.enabled,
    tags: (useV3 ? card.v3?.tags ?? card.baseTags : card.baseTags).toSet(),
    precision: card.precision,
    frequency: card.frequency,
    repeatability: card.repeatability,
    variants: [
      for (final variant in card.variants)
        EngineVariant(
          id: variant.stableId,
          enabled: useV3 ? variant.v3DeckEnabled : variant.enabled,
          chiliLevel: variant.chiliLevel,
          consentRules: useV3 && (variant.v3 != null || card.v3 != null)
              ? card.stableId.startsWith('card.v4.')
                    // V4 eligibility uses profile exclusions as its only
                    // persistent veto. Legacy PracticeConsent data never gates.
                    ? const []
                    : _v3Consent(variant.v3 ?? card.v3!)
              : [
                  ...card.profileRequirements.map(_consent),
                  ...variant.profileRequirements.map(_consent),
                ],
          technicalRules: [
            ...card.technicalRequirements.map(TechnicalRule.fromCatalog),
            ...variant.technicalRequirements.map(TechnicalRule.fromCatalog),
            if (useV3 && (variant.v3 != null || card.v3 != null))
              ..._v3Technical((variant.v3 ?? card.v3!).requirements),
            ..._validatedRuntimeRules(variant.stableId),
          ],
          effects: variant.stateEffects,
          tags:
              (useV3
                      ? variant.v3?.tags ?? card.v3?.tags ?? const <String>[]
                      : {
                          ...card.baseTags.where(
                            (tag) => !variant.removedTags.contains(tag),
                          ),
                          ...variant.additionalTags,
                        })
                  .toSet(),
          invertible:
              (variant.inversionOverride ?? card.inversionPolicy) !=
              InversionPolicy.NONE,
        ),
    ],
  );

  List<ConsentRule> _v3Consent(V3EditorialData data) {
    final reversible =
        data.tags.contains('v3.direction.faire') &&
        data.tags.contains('v3.direction.recevoir');
    if (reversible) {
      return [
        for (final tag in data.tags)
          if (tag.startsWith('v3.preference.')) ...[
            ConsentRule(
              elementId: tag,
              role: ProfileRole.FAIRE,
              oneOfGroup: 'direction:$tag',
            ),
            ConsentRule(
              elementId: tag,
              role: ProfileRole.RECEVOIR,
              oneOfGroup: 'direction:$tag',
            ),
          ],
      ];
    }
    final role = data.tags.contains('v3.direction.faire')
        ? ProfileRole.FAIRE
        : data.tags.contains('v3.direction.recevoir')
        ? ProfileRole.RECEVOIR
        : ProfileRole.GENERAL;
    return [
      for (final tag in data.tags)
        if (tag.startsWith('v3.preference.'))
          ConsentRule(elementId: tag, role: role),
    ];
  }

  List<TechnicalRule> _v3Technical(V3Requirements requirements) => [
    if (requirements.distanceExcluded)
      const TechnicalRule(
        kind: TechnicalRuleKind.SESSION_MODE,
        values: {'face_to_face', 'hybrid'},
      ),
    if (requirements.requiresVideo)
      const TechnicalRule(
        kind: TechnicalRuleKind.MEDIA_CAPABILITY,
        subject: RequirementSubject.BOTH,
        values: {'RECORDED_VIDEO', 'LIVE_CAMERA'},
      ),
    if (requirements.minimumRemovableClothing > 0)
      TechnicalRule(
        kind: TechnicalRuleKind.CLOTHES_AT_LEAST,
        subject: RequirementSubject.BOTH,
        minimum: requirements.minimumRemovableClothing,
      ),
    ..._flagRules(requirements),
  ];

  List<TechnicalRule> _flagRules(V3Requirements value) {
    final flags = <String, bool>{
      'roleplayEnabled': value.requiresRoleplay,
      'surprisePartyEnabled': value.requiresSurpriseParty,
      'hasSextoy': value.requiresSextoy,
      'hasVibratingToy': value.requiresVibratingToy,
      'hasRemoteControlToy': value.requiresRemoteControlToy,
      'hasConstraintAccessory': value.requiresConstraintAccessory,
      'hasOil': value.requiresOil,
      'hasLubricant': value.requiresLubricant,
      'hasProtection': value.requiresProtection,
      'hasFood': value.requiresFood,
      'hasDrink': value.requiresDrink,
      'hasAlcohol': value.requiresAlcohol,
    };
    return [
      for (final entry in flags.entries)
        if (entry.value)
          TechnicalRule(
            kind: TechnicalRuleKind.SESSION_FLAG,
            values: {entry.key},
            expected: true,
          ),
    ];
  }

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
