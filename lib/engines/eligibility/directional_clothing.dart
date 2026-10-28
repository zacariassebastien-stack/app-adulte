import '../../domain/catalog/definitions.dart';
import '../../domain/game/game_models.dart';

/// Clothing removal targets the partner for FAIRE and the owner for RECEVOIR.
/// Other requirements retain their existing subjects and semantics.
EngineVariant clothingVariantForDirection(
  CardDefinition definition,
  EngineVariant variant,
  CardOccurrenceDirection direction,
) {
  final behavior = definition.v4?.clothingBehavior.name;
  if (behavior != 'removeOne' && behavior != 'removeTwo') return variant;
  return EngineVariant(
    id: variant.id,
    chiliLevel: variant.chiliLevel,
    enabled: variant.enabled,
    consentRules: variant.consentRules,
    technicalRules: [
      for (final rule in variant.technicalRules)
        if (rule.kind == TechnicalRuleKind.CLOTHES_AT_LEAST)
          TechnicalRule(
            kind: rule.kind,
            subject: direction == CardOccurrenceDirection.RECEVOIR
                ? RequirementSubject.ACTOR
                : RequirementSubject.PARTNER,
            minimum: rule.minimum,
            values: rule.values,
            expected: rule.expected,
            applicableModes: rule.applicableModes,
          )
        else
          rule,
    ],
    technicalAlternatives: variant.technicalAlternatives,
    effects: variant.effects,
    tags: variant.tags,
    invertible: variant.invertible,
  );
}
