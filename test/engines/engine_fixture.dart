import 'package:couple_cards/domain/domain.dart';

PlayerGameProfile gameProfile(
  String id, {
  Map<String, PreferenceValue> preferences = const {},
}) => PlayerGameProfile(playerId: id, preferences: preferences);

PreferenceValue accepted({
  int? general = 10,
  int? faire = 10,
  int? recevoir = 10,
}) => PreferenceValue(
  status: PreferenceStatus.ACCEPTED,
  general: general,
  faire: faire,
  recevoir: recevoir,
);

EngineSessionContext gameContext({
  SessionMode mode = SessionMode.face_to_face,
  ProximityState proximity = ProximityState.TOGETHER,
  int chiliActive = 3,
  int chiliUnlocked = 3,
  Set<String> accessories = const {},
  Map<String, Set<MediaCapability>> media = const {},
  Set<String> removed = const {},
  Set<String> exhausted = const {},
  Map<String, int> clothes = const {},
  Map<String, String> physical = const {},
  Map<String, bool> flags = const {},
  bool temporaryMeetingAllowed = false,
}) => EngineSessionContext(
  mode: mode,
  proximity: proximity,
  chiliActive: chiliActive,
  chiliUnlocked: chiliUnlocked,
  accessories: accessories,
  mediaCapabilitiesByPlayer: media,
  removedVariantIds: removed,
  exhaustedCardIds: exhausted,
  clothesByPlayer: clothes,
  physicalStateByPlayer: physical,
  flags: flags,
  temporaryMeetingAllowed: temporaryMeetingAllowed,
);

EngineCard gameCard({
  String id = 'card.test',
  int chili = 1,
  List<ConsentRule> consent = const [],
  List<TechnicalRule> technical = const [],
  List<TechnicalRuleGroup> alternatives = const [],
  Set<String> tags = const {'tag.test'},
  bool invertible = false,
}) => EngineCard(
  id: id,
  tags: tags,
  variants: [
    EngineVariant(
      id: 'variant.$id',
      chiliLevel: chili,
      consentRules: consent,
      technicalRules: technical,
      technicalAlternatives: alternatives,
      invertible: invertible,
    ),
  ],
);

final emptyHierarchy = ProfileHierarchy(<String, String?>{});
