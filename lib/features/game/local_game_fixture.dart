import '../../domain/domain.dart';
import 'local_game_controller.dart';

LocalGameController createLocalGameFixture({
  int localFaire = 16,
  int localRecevoir = 13,
  int partnerFaire = 11,
  int partnerRecevoir = 9,
  int? localPa,
  int? partnerPa,
  int chiliActive = 2,
  Set<String> removedVariantIds = const {},
}) {
  const elementId = 'fixture.shared-action';
  final localProfile = PlayerGameProfile(
    playerId: 'local-player',
    preferences: {
      elementId: PreferenceValue(
        status: PreferenceStatus.ACCEPTED,
        general: 14,
        faire: localFaire,
        recevoir: localRecevoir,
      ),
    },
  );
  final partnerProfile = PlayerGameProfile(
    playerId: 'local-partner',
    preferences: {
      elementId: PreferenceValue(
        status: PreferenceStatus.ACCEPTED,
        general: 10,
        faire: partnerFaire,
        recevoir: partnerRecevoir,
      ),
    },
  );
  final cards = <LocalGameCard>[];
  final localPreferences = <String, LocalVariantPreference>{};
  final partnerPreferences = <String, LocalVariantPreference>{};
  for (var index = 0; index < 8; index++) {
    final cardId = 'local-card-$index';
    final role = index.isEven ? ProfileRole.FAIRE : ProfileRole.RECEVOIR;
    final variants = [
      for (final level in [1, 2])
        EngineVariant(
          id: '$cardId.variant.$level',
          chiliLevel: level,
          invertible: level == 2,
          consentRules: [
            ConsentRule(
              elementId: elementId,
              role: role,
              subject: RequirementSubject.BOTH,
            ),
          ],
        ),
    ];
    cards.add(
      LocalGameCard(
        view: GameCardView(
          cardId: cardId,
          category: role.name,
          chiliLevels: const [1, 2],
          locked: index == 1,
          titleKey: 'Carte locale ${index + 1}',
          descriptionKey:
              'Fixture locale éligible utilisée pour la boucle de manche.',
          personalValue: role == ProfileRole.FAIRE ? localFaire : localRecevoir,
          instructionKeys: const ['Choisis une variante avant engagement.'],
        ),
        engine: EngineCard(
          id: cardId,
          variants: variants,
          tags: {'fixture', 'card-$index'},
        ),
      ),
    );
    for (final variant in variants) {
      localPreferences[variant.id] = LocalVariantPreference(
        role: role,
        preference: _preference(
          elementId,
          general: 14,
          faire: localFaire,
          recevoir: localRecevoir,
        ),
      );
      partnerPreferences[variant.id] = LocalVariantPreference(
        role: role,
        preference: _preference(
          elementId,
          general: 10,
          faire: partnerFaire,
          recevoir: partnerRecevoir,
        ),
      );
    }
  }
  return LocalGameController(
    cards: cards,
    local: LocalPlayerSetup(
      playerId: 'local-player',
      profile: localProfile,
      initialHandIds: const [
        'local-card-0',
        'local-card-1',
        'local-card-2',
        'local-card-3',
      ],
      initialDiscardIds: const ['local-card-6'],
      initialActionPoints: localPa,
      preferencesByVariant: localPreferences,
    ),
    partner: LocalPlayerSetup(
      playerId: 'local-partner',
      profile: partnerProfile,
      initialHandIds: const [
        'local-card-2',
        'local-card-3',
        'local-card-4',
        'local-card-5',
      ],
      initialDiscardIds: const ['local-card-7'],
      initialActionPoints: partnerPa,
      preferencesByVariant: partnerPreferences,
    ),
    context: EngineSessionContext(
      mode: SessionMode.face_to_face,
      proximity: ProximityState.TOGETHER,
      chiliActive: chiliActive,
      chiliUnlocked: chiliActive,
      removedVariantIds: removedVariantIds,
    ),
    hierarchy: ProfileHierarchy(const {elementId: null}),
    clock: () => DateTime.utc(2026, 9, 29, 12),
  );
}

UserPreference _preference(
  String elementId, {
  required int general,
  required int faire,
  required int recevoir,
}) => UserPreference.fromJson({
  'profile_element_id': elementId,
  'status': PreferenceStatus.ACCEPTED.name,
  'general_value': general,
  'faire_value': faire,
  'recevoir_value': recevoir,
  'updated_at': DateTime.utc(2026, 9, 29).toIso8601String(),
  'source': PreferenceSource.CARD_REVIEW.name,
});
