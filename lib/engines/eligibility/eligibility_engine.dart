import '../../domain/catalog/enums.dart';
import '../../domain/game/game_models.dart';

final class EligibilityEngine {
  const EligibilityEngine();

  CardEligibility evaluate({
    required EngineCard card,
    required EngineSessionContext context,
    required PlayerGameProfile actor,
    required PlayerGameProfile partner,
    required ProfileHierarchy hierarchy,
    bool recovery = false,
    bool requirePersonalValue = false,
  }) {
    final shared = <IneligibilityReason>[
      if (!card.enabled)
        const IneligibilityReason(IneligibilityCode.CARD_DISABLED),
      if (context.exhaustedCardIds.contains(card.id))
        IneligibilityReason(IneligibilityCode.EXHAUSTED, referenceId: card.id),
    ];
    return CardEligibility(
      card: card,
      variants: [
        for (final variant in card.variants)
          VariantEligibility(
            variant: variant,
            reasons: [
              ...shared,
              ..._variantReasons(
                variant: variant,
                context: context,
                actor: actor,
                partner: partner,
                hierarchy: hierarchy,
                recovery: recovery,
                requirePersonalValue: requirePersonalValue,
              ),
            ],
          ),
      ],
    );
  }

  List<IneligibilityReason> _variantReasons({
    required EngineVariant variant,
    required EngineSessionContext context,
    required PlayerGameProfile actor,
    required PlayerGameProfile partner,
    required ProfileHierarchy hierarchy,
    required bool recovery,
    required bool requirePersonalValue,
  }) {
    final reasons = <IneligibilityReason>[];
    if (!variant.enabled) {
      reasons.add(
        const IneligibilityReason(IneligibilityCode.VARIANT_DISABLED),
      );
    }
    if (context.removedVariantIds.contains(variant.id)) {
      reasons.add(
        IneligibilityReason(
          IneligibilityCode.VARIANT_REMOVED,
          referenceId: variant.id,
        ),
      );
    }
    if (!recovery && variant.chiliLevel > context.chiliActive) {
      reasons.add(
        IneligibilityReason(
          IneligibilityCode.CHILI_TOO_HIGH,
          referenceId: variant.id,
        ),
      );
    }
    _evaluateConsent(
      variant.consentRules,
      actor,
      partner,
      hierarchy,
      reasons,
      requirePersonalValue,
    );
    for (final rule in variant.technicalRules) {
      final reason = _technicalReason(
        rule,
        context,
        actor.playerId,
        partner.playerId,
      );
      if (reason != null) reasons.add(reason);
    }
    for (final group in variant.technicalAlternatives) {
      final results = [
        for (final rule in group.rules)
          _technicalReason(rule, context, actor.playerId, partner.playerId),
      ];
      final passed = switch (group.operator) {
        RuleOperator.ALL => results.every((result) => result == null),
        RuleOperator.ANY => results.any((result) => result == null),
      };
      if (!passed) {
        reasons.add(results.whereType<IneligibilityReason>().first);
      }
    }
    return reasons;
  }

  void _evaluateConsent(
    List<ConsentRule> rules,
    PlayerGameProfile actor,
    PlayerGameProfile partner,
    ProfileHierarchy hierarchy,
    List<IneligibilityReason> reasons,
    bool requirePersonalValue,
  ) {
    final oneOf = <String, List<ConsentRule>>{};
    for (final rule in rules) {
      if (rule.oneOfGroup != null) {
        oneOf.putIfAbsent(rule.oneOfGroup!, () => []).add(rule);
      } else if (rule.required) {
        reasons.addAll(
          _consentReasons(
            rule,
            actor,
            partner,
            hierarchy,
            requirePersonalValue,
          ),
        );
      }
    }
    for (final group in oneOf.values) {
      if (!group.any(
        (rule) => _consentReasons(
          rule,
          actor,
          partner,
          hierarchy,
          requirePersonalValue,
        ).isEmpty,
      )) {
        reasons.add(
          IneligibilityReason(
            IneligibilityCode.CONSENT_NOT_ACCEPTED,
            referenceId: group.first.oneOfGroup,
          ),
        );
      }
    }
  }

  List<IneligibilityReason> _consentReasons(
    ConsentRule rule,
    PlayerGameProfile actor,
    PlayerGameProfile partner,
    ProfileHierarchy hierarchy,
    bool requirePersonalValue,
  ) {
    final profiles = switch (rule.subject) {
      RequirementSubject.ACTOR => [actor],
      RequirementSubject.PARTNER => [partner],
      RequirementSubject.BOTH => [actor, partner],
    };
    final reasons = <IneligibilityReason>[];
    for (final profile in profiles) {
      final excludedAncestor = hierarchy
          .ancestorsOf(rule.elementId)
          .firstWhere(
            (ancestor) =>
                profile.preference(ancestor).status ==
                PreferenceStatus.EXCLUDED,
            orElse: () => '',
          );
      if (excludedAncestor.isNotEmpty) {
        reasons.add(
          IneligibilityReason(
            IneligibilityCode.PARENT_EXCLUDED,
            subjectPlayerId: profile.playerId,
            referenceId: excludedAncestor,
          ),
        );
        continue;
      }
      final preference = profile.preference(rule.elementId);
      if (preference.status != PreferenceStatus.ACCEPTED) {
        reasons.add(
          IneligibilityReason(
            IneligibilityCode.CONSENT_NOT_ACCEPTED,
            subjectPlayerId: profile.playerId,
            referenceId: rule.elementId,
          ),
        );
      } else if (requirePersonalValue &&
          preference.valueFor(rule.role) == null) {
        reasons.add(
          IneligibilityReason(
            IneligibilityCode.MISSING_PERSONAL_VALUE,
            subjectPlayerId: profile.playerId,
            referenceId: rule.elementId,
          ),
        );
      }
    }
    return reasons;
  }

  IneligibilityReason? _technicalReason(
    TechnicalRule rule,
    EngineSessionContext context,
    String actorId,
    String partnerId,
  ) {
    if (rule.applicableModes.isNotEmpty &&
        !rule.applicableModes.contains(context.mode)) {
      return null;
    }
    final subjects = switch (rule.subject) {
      RequirementSubject.ACTOR => [actorId],
      RequirementSubject.PARTNER => [partnerId],
      RequirementSubject.BOTH => [actorId, partnerId],
    };
    bool passesFor(String playerId) => switch (rule.kind) {
      TechnicalRuleKind.SESSION_MODE => rule.values.contains(context.mode.name),
      TechnicalRuleKind.PROXIMITY => rule.values.contains(
        context.proximity.name,
      ),
      TechnicalRuleKind.PHYSICAL_STATE => rule.values.contains(
        context.physicalStateByPlayer[playerId],
      ),
      TechnicalRuleKind.CLOTHES_AT_LEAST =>
        (context.clothesByPlayer[playerId] ?? 0) >= (rule.minimum ?? 0),
      TechnicalRuleKind.ACCESSORY => rule.values.any(
        context.accessories.contains,
      ),
      TechnicalRuleKind.MEDIA_CAPABILITY =>
        rule.values
            .map(_mediaCapability)
            .whereType<MediaCapability>()
            .any(
              (capability) =>
                  context.mediaCapabilitiesByPlayer[playerId]?.contains(
                    capability,
                  ) ??
                  false,
            ),
      TechnicalRuleKind.TEMPORARY_MEETING => context.temporaryMeetingAllowed,
      TechnicalRuleKind.SESSION_FLAG => rule.values.every(
        (flag) => context.flags[flag] == (rule.expected ?? true),
      ),
    };
    if (subjects.every(passesFor)) return null;
    return IneligibilityReason(switch (rule.kind) {
      TechnicalRuleKind.SESSION_MODE => IneligibilityCode.SESSION_MODE,
      TechnicalRuleKind.PROXIMITY => IneligibilityCode.PROXIMITY,
      TechnicalRuleKind.PHYSICAL_STATE => IneligibilityCode.PHYSICAL_STATE,
      TechnicalRuleKind.CLOTHES_AT_LEAST => IneligibilityCode.CLOTHES,
      TechnicalRuleKind.ACCESSORY => IneligibilityCode.ACCESSORY,
      TechnicalRuleKind.MEDIA_CAPABILITY => IneligibilityCode.MEDIA_CAPABILITY,
      TechnicalRuleKind.TEMPORARY_MEETING =>
        IneligibilityCode.TEMPORARY_MEETING,
      TechnicalRuleKind.SESSION_FLAG => IneligibilityCode.SESSION_FLAG,
    }, referenceId: rule.values.isEmpty ? null : rule.values.first);
  }

  MediaCapability? _mediaCapability(String id) {
    final normalized = id
        .toUpperCase()
        .replaceAll('CAPABILITY.', '')
        .replaceAll('MEDIA.', '');
    for (final capability in MediaCapability.values) {
      if (capability.name == normalized) return capability;
    }
    return null;
  }
}
