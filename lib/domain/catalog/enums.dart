// Wire names are deliberately identical to the versioned data contract.
// ignore_for_file: constant_identifier_names
enum Precision { OPEN, GUIDED, PRECISE }

enum EditorialFrequency { COMMON, OCCASIONAL, RARE }

enum Repeatability { REPEATABLE, SESSION_ONCE }

enum InversionPolicy { NONE, SWAP_ACTOR_TARGET, SPECIFIC }

enum ParticipantRole { ACTOR, PARTNER, MUTUAL }

enum CardDirectionality { FAIRE, RECEVOIR, MUTUAL, FAIRE_RECEVOIR, CONTEXTUAL }

enum ProfileKind {
  PRACTICE,
  BODY_AREA,
  DYNAMIC,
  MEDIA,
  ROLEPLAY,
  CONTEXT,
  PREFERENCE,
}

enum ProfileDirectionality { GENERAL_ONLY, FAIRE_RECEVOIR }

enum ProfileRole { GENERAL, FAIRE, RECEVOIR }

enum RequirementKind { REQUIRED, OPTIONAL, ONE_OF }

enum PreferenceStatus { UNSET, DISCOVER, ACCEPTED, EXCLUDED }

enum PreferenceSource {
  ONBOARDING,
  SEARCH,
  CARD_REVIEW,
  POST_SESSION,
  EVOLUTION_SUGGESTION,
}

enum ParameterType { INTEGER, ENUM, BOOLEAN, DURATION_HINT }

enum SelectionBy { ACTOR, PARTNER, BOTH }

enum ParameterVisibility { PUBLIC, PRIVATE_UNTIL_REVEAL }

enum SessionMode { face_to_face, distance, hybrid }

enum TechnicalRequirementType {
  SESSION_MODE_IN,
  PHYSICAL_STATE_IS,
  CLOTHES_AT_LEAST,
  ACCESSORY_AVAILABLE,
  MEDIA_CAPABILITY_AVAILABLE,
  TEMPORARY_MEETING_ALLOWED,
  SESSION_FLAG_IS,
}

enum StateEffectType {
  CLOTHES_DELTA,
  SET_PHYSICAL_STATE_TEMPORARY,
  RESTORE_PHYSICAL_STATE_AFTER_ACTION,
  SET_SESSION_FLAG,
  CLEAR_SESSION_FLAG,
}
