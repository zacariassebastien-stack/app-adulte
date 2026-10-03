import '../catalog/enums.dart';
import '../catalog/requirements.dart';
import '../session/session_state.dart';

// Stable wire values used by the pure engines.
// ignore_for_file: constant_identifier_names
enum ProximityState { TOGETHER, SEPARATED }

enum PlayerStyle { SOFT, EPICE, INTENABLE }

/// Direction persisted on a concrete card occurrence. The native value is
/// immutable; the effective value may only change through an official
/// inversion of the initial duel card.
enum CardOccurrenceDirection {
  GENERAL,
  FAIRE,
  RECEVOIR,
  MUTUEL,
  SOLO,
  SIMULTANE,
}

enum MediaCapability {
  PHOTO_CAPTURE,
  RECORDED_VIDEO,
  LIVE_CAMERA,
  MEDIA_SEND,
  MEDIA_RECEIVE,
}

enum RequirementSubject { ACTOR, PARTNER, BOTH }

enum TechnicalRuleKind {
  SESSION_MODE,
  PROXIMITY,
  PHYSICAL_STATE,
  CLOTHES_AT_LEAST,
  ACCESSORY,
  MEDIA_CAPABILITY,
  TEMPORARY_MEETING,
  SESSION_FLAG,
}

enum RuleOperator { ALL, ANY }

enum IneligibilityCode {
  CARD_DISABLED,
  VARIANT_DISABLED,
  CONSENT_NOT_ACCEPTED,
  PARENT_EXCLUDED,
  CHILI_TOO_HIGH,
  SESSION_MODE,
  PROXIMITY,
  PHYSICAL_STATE,
  CLOTHES,
  ACCESSORY,
  MEDIA_CAPABILITY,
  TEMPORARY_MEETING,
  SESSION_FLAG,
  VARIANT_REMOVED,
  EXHAUSTED,
  MISSING_PERSONAL_VALUE,
}

final class PreferenceValue {
  const PreferenceValue({
    required this.status,
    this.general,
    this.faire,
    this.recevoir,
  });
  final PreferenceStatus status;
  final int? general;
  final int? faire;
  final int? recevoir;

  int? valueFor(ProfileRole role) => switch (role) {
    ProfileRole.GENERAL => general,
    ProfileRole.FAIRE => faire,
    ProfileRole.RECEVOIR => recevoir,
  };
}

final class PlayerGameProfile {
  PlayerGameProfile({
    required this.playerId,
    Map<String, PreferenceValue>? preferences,
  }) : preferences = Map.unmodifiable(preferences ?? const {});
  final String playerId;
  final Map<String, PreferenceValue> preferences;
  PreferenceValue preference(String elementId) =>
      preferences[elementId] ??
      const PreferenceValue(status: PreferenceStatus.UNSET);
}

final class ProfileHierarchy {
  ProfileHierarchy(Map<String, String?> parentByElement)
    : parentByElement = Map.unmodifiable(parentByElement);
  final Map<String, String?> parentByElement;

  Iterable<String> ancestorsOf(String elementId) sync* {
    final visited = <String>{};
    var current = parentByElement[elementId];
    while (current != null && visited.add(current)) {
      yield current;
      current = parentByElement[current];
    }
  }
}

final class ConsentRule {
  const ConsentRule({
    required this.elementId,
    required this.role,
    this.subject = RequirementSubject.ACTOR,
    this.required = true,
    this.oneOfGroup,
  });
  final String elementId;
  final ProfileRole role;
  final RequirementSubject subject;
  final bool required;
  final String? oneOfGroup;
}

final class TechnicalRule {
  const TechnicalRule({
    required this.kind,
    this.subject = RequirementSubject.ACTOR,
    this.values = const {},
    this.minimum,
    this.expected,
    this.applicableModes = const {},
  });
  final TechnicalRuleKind kind;
  final RequirementSubject subject;
  final Set<String> values;
  final int? minimum;
  final bool? expected;
  final Set<SessionMode> applicableModes;

  factory TechnicalRule.fromCatalog(TechnicalRequirement requirement) {
    return switch (requirement.type) {
      TechnicalRequirementType.SESSION_MODE_IN => TechnicalRule(
        kind: TechnicalRuleKind.SESSION_MODE,
        values: requirement.sessionModes.map((mode) => mode.name).toSet(),
      ),
      TechnicalRequirementType.PHYSICAL_STATE_IS => TechnicalRule(
        kind: TechnicalRuleKind.PHYSICAL_STATE,
        values: {requirement.physicalState!},
      ),
      TechnicalRequirementType.CLOTHES_AT_LEAST => TechnicalRule(
        kind: TechnicalRuleKind.CLOTHES_AT_LEAST,
        subject: _subject(requirement.target),
        minimum: requirement.minimumClothes,
      ),
      TechnicalRequirementType.ACCESSORY_AVAILABLE => TechnicalRule(
        kind: TechnicalRuleKind.ACCESSORY,
        values: {requirement.accessoryId!},
      ),
      TechnicalRequirementType.MEDIA_CAPABILITY_AVAILABLE => TechnicalRule(
        kind: TechnicalRuleKind.MEDIA_CAPABILITY,
        values: {requirement.capabilityId!},
      ),
      TechnicalRequirementType.TEMPORARY_MEETING_ALLOWED => const TechnicalRule(
        kind: TechnicalRuleKind.TEMPORARY_MEETING,
      ),
      TechnicalRequirementType.SESSION_FLAG_IS => TechnicalRule(
        kind: TechnicalRuleKind.SESSION_FLAG,
        values: {requirement.flagId!},
        expected: requirement.flagValue,
      ),
    };
  }

  static RequirementSubject _subject(ParticipantRole? role) => switch (role) {
    ParticipantRole.PARTNER => RequirementSubject.PARTNER,
    ParticipantRole.MUTUAL => RequirementSubject.BOTH,
    _ => RequirementSubject.ACTOR,
  };
}

final class TechnicalRuleGroup {
  const TechnicalRuleGroup({required this.operator, required this.rules});
  final RuleOperator operator;
  final List<TechnicalRule> rules;
}

final class EngineVariant {
  const EngineVariant({
    required this.id,
    required this.chiliLevel,
    this.enabled = true,
    this.consentRules = const [],
    this.technicalRules = const [],
    this.technicalAlternatives = const [],
    this.effects = const [],
    this.tags = const {},
    this.invertible = false,
  });
  final String id;
  final int chiliLevel;
  final bool enabled;
  final List<ConsentRule> consentRules;
  final List<TechnicalRule> technicalRules;
  final List<TechnicalRuleGroup> technicalAlternatives;
  final List<StateEffect> effects;
  final Set<String> tags;
  final bool invertible;
}

final class EngineCard {
  const EngineCard({
    required this.id,
    required this.variants,
    this.enabled = true,
    this.tags = const {},
    this.precision = Precision.OPEN,
    this.frequency = EditorialFrequency.COMMON,
    this.repeatability = Repeatability.REPEATABLE,
  });
  final String id;
  final bool enabled;
  final List<EngineVariant> variants;
  final Set<String> tags;
  final Precision precision;
  final EditorialFrequency frequency;
  final Repeatability repeatability;
}

final class EngineSessionContext {
  EngineSessionContext({
    required this.mode,
    required this.proximity,
    required this.chiliActive,
    required this.chiliUnlocked,
    Map<String, String>? physicalStateByPlayer,
    Map<String, int>? clothesByPlayer,
    Set<String>? accessories,
    Map<String, Set<MediaCapability>>? mediaCapabilitiesByPlayer,
    Map<String, bool>? flags,
    Set<String>? removedVariantIds,
    Set<String>? exhaustedCardIds,
    this.temporaryMeetingAllowed = false,
  }) : physicalStateByPlayer = Map.unmodifiable(
         physicalStateByPlayer ?? const {},
       ),
       clothesByPlayer = Map.unmodifiable(clothesByPlayer ?? const {}),
       accessories = Set.unmodifiable(accessories ?? const {}),
       mediaCapabilitiesByPlayer = Map.unmodifiable({
         for (final entry in (mediaCapabilitiesByPlayer ?? const {}).entries)
           entry.key: Set.unmodifiable(entry.value),
       }),
       flags = Map.unmodifiable(flags ?? const {}),
       removedVariantIds = Set.unmodifiable(removedVariantIds ?? const {}),
       exhaustedCardIds = Set.unmodifiable(exhaustedCardIds ?? const {});
  final SessionMode mode;
  final ProximityState proximity;
  final int chiliActive;
  final int chiliUnlocked;
  final Map<String, String> physicalStateByPlayer;
  final Map<String, int> clothesByPlayer;
  final Set<String> accessories;
  final Map<String, Set<MediaCapability>> mediaCapabilitiesByPlayer;
  final Map<String, bool> flags;
  final Set<String> removedVariantIds;
  final Set<String> exhaustedCardIds;
  final bool temporaryMeetingAllowed;

  EngineSessionContext copyWith({
    SessionMode? mode,
    ProximityState? proximity,
    int? chiliActive,
    int? chiliUnlocked,
    Map<String, String>? physicalStateByPlayer,
    Map<String, int>? clothesByPlayer,
    Set<String>? accessories,
    Map<String, Set<MediaCapability>>? mediaCapabilitiesByPlayer,
    Map<String, bool>? flags,
    Set<String>? removedVariantIds,
    Set<String>? exhaustedCardIds,
    bool? temporaryMeetingAllowed,
  }) => EngineSessionContext(
    mode: mode ?? this.mode,
    proximity: proximity ?? this.proximity,
    chiliActive: chiliActive ?? this.chiliActive,
    chiliUnlocked: chiliUnlocked ?? this.chiliUnlocked,
    physicalStateByPlayer: physicalStateByPlayer ?? this.physicalStateByPlayer,
    clothesByPlayer: clothesByPlayer ?? this.clothesByPlayer,
    accessories: accessories ?? this.accessories,
    mediaCapabilitiesByPlayer:
        mediaCapabilitiesByPlayer ?? this.mediaCapabilitiesByPlayer,
    flags: flags ?? this.flags,
    removedVariantIds: removedVariantIds ?? this.removedVariantIds,
    exhaustedCardIds: exhaustedCardIds ?? this.exhaustedCardIds,
    temporaryMeetingAllowed:
        temporaryMeetingAllowed ?? this.temporaryMeetingAllowed,
  );
}

final class IneligibilityReason {
  const IneligibilityReason(
    this.code, {
    this.subjectPlayerId,
    this.referenceId,
  });
  final IneligibilityCode code;
  final String? subjectPlayerId;
  final String? referenceId;
}

final class VariantEligibility {
  const VariantEligibility({required this.variant, required this.reasons});
  final EngineVariant variant;
  final List<IneligibilityReason> reasons;
  bool get eligible => reasons.isEmpty;
}

final class CardEligibility {
  const CardEligibility({required this.card, required this.variants});
  final EngineCard card;
  final List<VariantEligibility> variants;
  bool get eligible => variants.any((variant) => variant.eligible);
  List<EngineVariant> get eligibleVariants => variants
      .where((variant) => variant.eligible)
      .map((variant) => variant.variant)
      .toList(growable: false);
}

final class PlayerRoundState {
  const PlayerRoundState({
    required this.playerId,
    required this.actionPoints,
    required this.style,
    this.lockedCardId,
  });
  final String playerId;
  final int actionPoints;
  final PlayerStyle style;
  final String? lockedCardId;
  PlayerRoundState copyWith({
    int? actionPoints,
    PlayerStyle? style,
    String? lockedCardId,
    bool clearLock = false,
  }) => PlayerRoundState(
    playerId: playerId,
    actionPoints: actionPoints ?? this.actionPoints,
    style: style ?? this.style,
    lockedCardId: clearLock ? null : lockedCardId ?? this.lockedCardId,
  );
}

final class CardRuntimeState {
  const CardRuntimeState({
    required this.cardId,
    required this.zone,
    String? occurrenceId,
    this.variantId,
    this.locked = false,
    this.nativeDirection = CardOccurrenceDirection.GENERAL,
    CardOccurrenceDirection? effectiveDirection,
  }) : occurrenceId = occurrenceId ?? cardId,
       effectiveDirection = effectiveDirection ?? nativeDirection;
  final String cardId;
  final String occurrenceId;
  final String? variantId;
  final CardZone zone;
  final bool locked;
  final CardOccurrenceDirection nativeDirection;
  final CardOccurrenceDirection effectiveDirection;
  CardRuntimeState copyWith({
    CardZone? zone,
    bool? locked,
    CardOccurrenceDirection? effectiveDirection,
  }) => CardRuntimeState(
    cardId: cardId,
    occurrenceId: occurrenceId,
    variantId: variantId,
    zone: zone ?? this.zone,
    locked: locked ?? this.locked,
    nativeDirection: nativeDirection,
    effectiveDirection: effectiveDirection ?? this.effectiveDirection,
  );
}
