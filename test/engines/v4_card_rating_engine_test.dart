import 'package:couple_cards/domain/domain.dart';
import 'package:couple_cards/engines/profile/v4_card_rating_engine.dart';
import 'package:test/test.dart';

void main() {
  const engine = V4CardRatingEngine();
  final variant = V4VariantRatingDefinition(
    variantId: 'variant',
    stage: null,
    scope: 'test',
    primaryPreferenceTags: const ['principal'],
    secondaryPreferenceTags: const ['secondary'],
    nonPreferenceData: const ['cost', 'zone'],
  );

  test('principal 5 and secondary 12 produce raw 11 and weight 1.5', () {
    final result = engine.initialize(
      profile: _profile(principal: 5, secondary: 12),
      variant: variant,
      effectiveRole: ProfilePreferenceRole.faire,
    );
    expect(result.kind, V4RatingResultKind.rated);
    expect(result.rawScore, 11);
    expect(result.totalWeight, 1.5);
    expect(result.source, 'TAG_PRIOR');
  });

  test('two primary tags at 5 and 12 produce raw 17', () {
    final result = engine.initialize(
      profile: _profile(principal: 5, secondary: 12),
      variant: V4VariantRatingDefinition(
        variantId: 'two-primary',
        stage: null,
        scope: 'test',
        primaryPreferenceTags: const ['principal', 'secondary'],
        secondaryPreferenceTags: const [],
        nonPreferenceData: const ['cost', 'zone'],
      ),
      effectiveRole: ProfilePreferenceRole.faire,
    );
    expect(result.rawScore, 17);
    expect(result.totalWeight, 2);
  });

  test('excluded secondary wins over a missing primary', () {
    final profile = V4Profile(
      profileId: 'p',
      preferences: {
        'secondary|faire': _value('secondary', null, excluded: true),
      },
    );
    final result = engine.initialize(
      profile: profile,
      variant: variant,
      effectiveRole: ProfilePreferenceRole.faire,
    );
    expect(result.kind, V4RatingResultKind.excluded);
    expect(result.reasonId, 'secondary');
  });

  test('excluded primary preference remains an eligibility veto', () {
    final profile = V4Profile(
      profileId: 'p',
      preferences: {
        'principal|faire': _value('principal', null, excluded: true),
        'secondary|faire': _value('secondary', 12),
      },
    );
    final result = engine.initialize(
      profile: profile,
      variant: variant,
      effectiveRole: ProfilePreferenceRole.faire,
    );

    expect(result.kind, V4RatingResultKind.excluded);
    expect(result.reasonId, 'principal');
  });

  test('unknown and technical unavailable stay distinct', () {
    final unknown = engine.initialize(
      profile: V4Profile(profileId: 'p', preferences: const {}),
      variant: variant,
      effectiveRole: ProfilePreferenceRole.faire,
    );
    expect(unknown.kind, V4RatingResultKind.unknown);

    final profile = _profile(principal: 5, secondary: 12);
    final unavailable = engine.initialize(
      profile: profile,
      variant: variant,
      effectiveRole: ProfilePreferenceRole.faire,
      technicalAvailable: false,
    );
    expect(unavailable.kind, V4RatingResultKind.unavailable);
  });

  test('positive PA never creates consent', () {
    final profile = _profile(principal: 5, secondary: 12);
    expect(profile.consents, isEmpty);
  });

  test('missing or legacy UNKNOWN consent never blocks scoring', () {
    final base = _profile(principal: 5, secondary: 12);
    const legacy = PracticeConsent(
      profileId: 'p',
      practiceTagId: 'principal',
      role: ProfilePreferenceRole.faire,
      status: PracticeConsentStatus.unknown,
      source: PracticeConsentSource.manualExplicit,
    );
    final withLegacy = V4Profile(
      profileId: 'p',
      preferences: base.preferences,
      consents: {legacy.storageKey: legacy},
    );

    expect(
      engine
          .initialize(
            profile: base,
            variant: variant,
            effectiveRole: ProfilePreferenceRole.faire,
          )
          .kind,
      V4RatingResultKind.rated,
    );
    expect(
      engine
          .initialize(
            profile: withLegacy,
            variant: variant,
            effectiveRole: ProfilePreferenceRole.faire,
          )
          .kind,
      V4RatingResultKind.rated,
    );
  });

  test('legacy EXCLUDED consent is preserved but is not a profile veto', () {
    final base = _profile(principal: 5, secondary: 12);
    const legacy = PracticeConsent(
      profileId: 'p',
      practiceTagId: 'principal',
      role: ProfilePreferenceRole.faire,
      status: PracticeConsentStatus.excluded,
      source: PracticeConsentSource.manualExplicit,
    );
    final profile = V4Profile(
      profileId: 'p',
      preferences: base.preferences,
      consents: {legacy.storageKey: legacy},
    );

    final result = engine.initialize(
      profile: profile,
      variant: variant,
      effectiveRole: ProfilePreferenceRole.faire,
    );
    expect(result.kind, V4RatingResultKind.rated);
    expect(
      profile.consents.values.single.status,
      PracticeConsentStatus.excluded,
    );
  });

  test(
    'card-specific learning is isolated by card, variant and final role',
    () {
      final store = CardSpecificLearningStore();
      const aFaire = CardRatingKey(
        profileId: 'p',
        cardId: 'a',
        variantId: 'a.1',
        role: ProfilePreferenceRole.faire,
      );
      const aRecevoir = CardRatingKey(
        profileId: 'p',
        cardId: 'a',
        variantId: 'a.1',
        role: ProfilePreferenceRole.recevoir,
      );
      const bFaire = CardRatingKey(
        profileId: 'p',
        cardId: 'b',
        variantId: 'b.1',
        role: ProfilePreferenceRole.faire,
      );
      store.record(
        key: aFaire,
        initialScore: 11,
        signal: V4CardLearningSignal.accepted,
      );
      expect(store.read(aFaire)!.observationCount, 1);
      expect(store.read(aRecevoir), isNull);
      expect(store.read(bFaire), isNull);
    },
  );

  test('card-specific learning round-trips without changing its key', () {
    final store = CardSpecificLearningStore();
    const key = CardRatingKey(
      profileId: 'p',
      cardId: 'card.v4.002',
      variantId: 'variant.v4.002.s1',
      role: ProfilePreferenceRole.recevoir,
    );
    store.record(
      key: key,
      initialScore: 12,
      signal: V4CardLearningSignal.accepted,
    );
    final restored = CardSpecificLearningStore()..restore(store.toJson());

    expect(restored.read(key)?.initialScore, 12);
    expect(restored.read(key)?.observationCount, 1);
    expect(restored.read(key)?.acceptanceCount, 1);
    expect(restored.read(key)?.resistanceCount, 0);
    expect(restored.read(key)?.source, 'TAG_PRIOR');
  });

  test('ignored and STOP never become resistance or acceptance', () {
    final store = CardSpecificLearningStore();
    const key = CardRatingKey(
      profileId: 'p',
      cardId: 'card.v4.002',
      variantId: 'variant.v4.002.s1',
      role: ProfilePreferenceRole.faire,
    );
    store
      ..record(key: key, initialScore: 5, signal: V4CardLearningSignal.ignored)
      ..record(key: key, initialScore: 5, signal: V4CardLearningSignal.stopped);
    final value = store.read(key)!;
    expect(value.ignoredCount, 1);
    expect(value.acceptanceCount, 0);
    expect(value.resistanceCount, 0);
  });

  test('STOP does not create a profile exclusion', () {
    final profile = _profile(principal: 5, secondary: 12);
    final before = profile.toJson();
    final store = CardSpecificLearningStore();
    const key = CardRatingKey(
      profileId: 'p',
      cardId: 'card.v4.002',
      variantId: 'variant.v4.002.s1',
      role: ProfilePreferenceRole.faire,
    );
    store.record(
      key: key,
      initialScore: 5,
      signal: V4CardLearningSignal.stopped,
    );

    expect(profile.toJson(), before);
    expect(profile.preferences.values.any((value) => value.excluded), isFalse);
  });

  test('mutual resolution keeps every player and role contribution', () {
    final soloObserverVariant = V4VariantRatingDefinition(
      variantId: 'variant.v4.021.base',
      stage: null,
      scope: 'mutual solo',
      primaryPreferenceTags: const ['masturbation'],
      secondaryPreferenceTags: const [],
      nonPreferenceData: const ['MUTUEL'],
    );
    final playerA = V4Profile(
      profileId: 'a',
      preferences: {
        'masturbation|solo': _value(
          'masturbation',
          5,
          role: ProfilePreferenceRole.solo,
        ),
        'masturbation|observer': _value(
          'masturbation',
          12,
          role: ProfilePreferenceRole.observer,
        ),
      },
    );
    final playerB = V4Profile(
      profileId: 'b',
      preferences: {
        'masturbation|solo': _value(
          'masturbation',
          20,
          role: ProfilePreferenceRole.solo,
        ),
        'masturbation|observer': ProfilePreference(
          profileId: 'b',
          key: const ProfilePreferenceKey(
            tagId: 'masturbation',
            role: ProfilePreferenceRole.observer,
          ),
          pa: null,
          excluded: true,
          source: ProfilePreferenceSource.initialQuestionnaire,
        ),
      },
    );
    final result = engine.initializeMutual(
      contributions: [
        V4RatingContribution(
          profile: playerA,
          role: ProfilePreferenceRole.solo,
        ),
        V4RatingContribution(
          profile: playerA,
          role: ProfilePreferenceRole.observer,
        ),
        V4RatingContribution(
          profile: playerB,
          role: ProfilePreferenceRole.solo,
        ),
        V4RatingContribution(
          profile: playerB,
          role: ProfilePreferenceRole.observer,
        ),
      ],
      variant: soloObserverVariant,
    );
    expect(result.contributions, hasLength(4));
    expect(result.kind, V4RatingResultKind.excluded);
  });

  test('an own card estimate is not rewritten by a changed tag prior', () {
    final store = CardSpecificLearningStore();
    const key = CardRatingKey(
      profileId: 'p',
      cardId: 'card.v4.002',
      variantId: 'variant.v4.002.s1',
      role: ProfilePreferenceRole.faire,
    );
    store.write(
      const CardRatingStateV4(
        key: key,
        initialScore: 12,
        currentEstimate: 12,
        observationCount: 10,
        acceptanceCount: 8,
        resistanceCount: 0,
        source: 'TAG_PRIOR',
      ).withOwnEstimate(7),
    );
    final changedPrior = engine.initialize(
      profile: _profile(principal: 20, secondary: 20),
      variant: variant,
      effectiveRole: ProfilePreferenceRole.faire,
    );
    expect(changedPrior.rawScore, 30);
    expect(store.read(key)?.currentEstimate, 7);
    expect(store.read(key)?.source, 'CARD_ESTIMATE');
  });
}

V4Profile _profile({required double principal, required double secondary}) =>
    V4Profile(
      profileId: 'p',
      preferences: {
        'principal|faire': _value('principal', principal),
        'secondary|faire': _value('secondary', secondary),
      },
    );

ProfilePreference _value(
  String tag,
  double? pa, {
  bool excluded = false,
  ProfilePreferenceRole role = ProfilePreferenceRole.faire,
}) => ProfilePreference(
  profileId: 'p',
  key: ProfilePreferenceKey(tagId: tag, role: role),
  pa: pa,
  excluded: excluded,
  source: ProfilePreferenceSource.initialQuestionnaire,
);
