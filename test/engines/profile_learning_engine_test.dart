import 'package:couple_cards/domain/domain.dart';
import 'package:couple_cards/engines/engines.dart';
import 'package:test/test.dart';

void main() {
  const engine = ProfileLearningEngine();
  const massage = 'v3.preference.masser';
  const caresser = 'v3.preference.caresses';
  const back = 'v3.zone.dos';
  final card = LearningCardDescriptor(
    cardId: 'card.massage',
    variantId: 'variant.massage.back',
    tags: const [massage, back, 'v3.direction.faire', 'v3.technique.douce'],
    spiceLevel: 2,
  );
  final plainCard = LearningCardDescriptor(
    cardId: 'card.caress',
    variantId: 'variant.caress',
    tags: const [caresser, 'v3.direction.faire'],
    spiceLevel: 4,
  );
  const generalMassage = PreferenceLearningKey(preferenceId: massage);

  group('initialization and categories', () {
    test('maps initial swipe to 3, 8, 20 and immutable exclusion', () {
      var state = engine.initialize(
        profileId: 'a',
        choices: const {
          'love': InitialSwipeChoice.love,
          'like': InitialSwipeChoice.like,
          'unknown': InitialSwipeChoice.unsure,
          'excluded': InitialSwipeChoice.excluded,
        },
      );
      expect(
        state
            .entry(const PreferenceLearningKey(preferenceId: 'love'))!
            .currentPa,
        3,
      );
      expect(
        state
            .entry(const PreferenceLearningKey(preferenceId: 'like'))!
            .currentPa,
        8,
      );
      expect(
        state
            .entry(const PreferenceLearningKey(preferenceId: 'unknown'))!
            .currentPa,
        20,
      );
      expect(
        state
            .entry(const PreferenceLearningKey(preferenceId: 'excluded'))!
            .excluded,
        isTrue,
      );

      state = engine.recordHand(
        state,
        HandLearningEvent(
          playerId: 'a',
          availableCards: [
            LearningCardDescriptor(
              cardId: 'excluded-card',
              variantId: 'excluded-variant',
              tags: const ['excluded'],
              spiceLevel: 5,
            ),
          ],
          playedCardIdentities: const {'excluded-card|excluded-variant'},
        ),
      );
      expect(state.entries, hasLength(4));
      expect(
        state
            .entry(const PreferenceLearningKey(preferenceId: 'excluded'))!
            .excluded,
        isTrue,
      );
    });

    test('uses the ten detailed profile categories', () {
      expect(
        DetailedPreferenceCategoryRules.fromPa(1),
        DetailedPreferenceCategory.essential,
      );
      expect(
        DetailedPreferenceCategoryRules.fromPa(3),
        DetailedPreferenceCategory.love,
      );
      expect(
        DetailedPreferenceCategoryRules.fromPa(5),
        DetailedPreferenceCategory.likeALot,
      );
      expect(
        DetailedPreferenceCategoryRules.fromPa(7),
        DetailedPreferenceCategory.like,
      );
      expect(
        DetailedPreferenceCategoryRules.fromPa(10),
        DetailedPreferenceCategory.tempted,
      );
      expect(
        DetailedPreferenceCategoryRules.fromPa(13),
        DetailedPreferenceCategory.depends,
      );
      expect(
        DetailedPreferenceCategoryRules.fromPa(16),
        DetailedPreferenceCategory.occasional,
      );
      expect(
        DetailedPreferenceCategoryRules.fromPa(18),
        DetailedPreferenceCategory.atMyLimit,
      );
      expect(
        DetailedPreferenceCategoryRules.fromPa(20),
        DetailedPreferenceCategory.unsure,
      );
      expect(
        DetailedPreferenceCategoryRules.fromPa(null, excluded: true),
        DetailedPreferenceCategory.excluded,
      );
    });

    test('post-game learning preference can be changed later', () {
      var state = engine.initialize(profileId: 'a', choices: const {});
      for (final preference in ProfileLearningPreference.values) {
        state = engine.setLearningPreference(state, preference);
        expect(state.learningPreference, preference);
      }
    });
  });

  group('signals and tag projection', () {
    test('records exposure, played, locked and ignored without rejection', () {
      final locked = LearningCardDescriptor(
        cardId: 'card.locked',
        variantId: 'variant.locked',
        tags: const [caresser],
        spiceLevel: 2,
      );
      var state = engine.initialize(profileId: 'a', choices: const {});
      state = engine.recordHand(
        state,
        HandLearningEvent(
          playerId: 'a',
          availableCards: [plainCard, locked, card],
          playedCardIdentities: {plainCard.identity},
          lockedCardIdentities: {locked.identity},
        ),
      );
      final caress = state.entry(
        const PreferenceLearningKey(
          preferenceId: caresser,
          role: LearningRole.faire,
        ),
      )!;
      expect(caress.exposureCount, 1);
      expect(caress.playedCount, 1);
      expect(caress.lockedCount, 0);
      expect(caress.attractionRelative, 1);
      final lockedAttraction = state.entry(
        const PreferenceLearningKey(preferenceId: caresser),
      )!;
      expect(lockedAttraction.lockedCount, 1);
      expect(lockedAttraction.attractionRelative, 1);
      final ignored = state.entry(
        const PreferenceLearningKey(
          preferenceId: massage,
          role: LearningRole.faire,
          zoneId: back,
        ),
      )!;
      expect(ignored.ignoredCount, 1);
      expect(ignored.resistanceCount, 0);
    });

    test('weights primary, secondary and two indissociable preferences', () {
      const projector = V3LearningTagProjector();
      final projected = projector.project(
        LearningCardDescriptor(
          cardId: 'c',
          variantId: 'v',
          tags: const [
            massage,
            caresser,
            'v3.context.douceur',
            'v3.direction.recevoir',
          ],
          spiceLevel: 2,
        ),
      );
      expect(projected.map((e) => e.weight), [1, .5]);
      expect(
        projected.map((e) => e.key.role),
        everyElement(LearningRole.recevoir),
      );
      final paired = projector.project(
        LearningCardDescriptor(
          cardId: 'c2',
          variantId: 'v2',
          tags: const [massage, caresser],
          primaryPreferenceIds: const [massage, caresser],
          spiceLevel: 2,
        ),
      );
      expect(paired.map((e) => e.weight), everyElement(.75));
    });

    test(
      'zones are learned mainly as combinations and no cartesian state is generated',
      () {
        const projector = V3LearningTagProjector();
        final projected = projector.project(card);
        final combined = projected.singleWhere((e) => e.key.zoneId == back);
        final generic = projected.singleWhere((e) => e.key.zoneId == null);
        expect(combined.weight, 1);
        expect(generic.weight, .5);
        expect(projected, hasLength(2));
        expect(
          projected.any((e) => e.key.preferenceId.startsWith('v3.direction.')),
          isFalse,
        );
      },
    );
  });

  group('final resolution and roles', () {
    test('learns FAIRE/RECEVOIR from final roles and inversion swaps them', () {
      final states = {
        'a': engine.initialize(profileId: 'a', choices: const {}),
        'b': engine.initialize(profileId: 'b', choices: const {}),
      };
      final result = engine.recordRoundOutcome(
        states,
        RoundLearningOutcome(
          acceptedCards: [
            ResolvedLearningCard(
              card: plainCard,
              participation: ResolvedParticipation.directed,
              performerPlayerId: 'b',
              receiverPlayerId: 'a',
            ),
          ],
        ),
      );
      expect(
        result['b']!
            .entry(
              const PreferenceLearningKey(
                preferenceId: caresser,
                role: LearningRole.faire,
              ),
            )!
            .acceptanceCount,
        1,
      );
      expect(
        result['a']!
            .entry(
              const PreferenceLearningKey(
                preferenceId: caresser,
                role: LearningRole.recevoir,
              ),
            )!
            .acceptanceCount,
        1,
      );
    });

    test('preserves MUTUEL, SOLO and SIMULTANE meanings', () {
      var states = {
        'a': engine.initialize(profileId: 'a', choices: const {}),
        'b': engine.initialize(profileId: 'b', choices: const {}),
      };
      states = engine.recordRoundOutcome(
        states,
        RoundLearningOutcome(
          acceptedCards: [
            ResolvedLearningCard(
              card: plainCard,
              participation: ResolvedParticipation.mutual,
              participantPlayerIds: const ['a', 'b'],
            ),
            ResolvedLearningCard(
              card: card,
              participation: ResolvedParticipation.solo,
              soloPlayerId: 'a',
            ),
            ResolvedLearningCard(
              card: LearningCardDescriptor(
                cardId: 'sim',
                variantId: 'sim',
                tags: const [caresser],
                spiceLevel: 3,
              ),
              participation: ResolvedParticipation.simultaneous,
              participantPlayerIds: const ['a', 'b'],
            ),
          ],
        ),
      );
      expect(
        states['a']!.entry(
          const PreferenceLearningKey(
            preferenceId: caresser,
            role: LearningRole.mutuel,
          ),
        ),
        isNotNull,
      );
      expect(
        states['a']!.entry(
          const PreferenceLearningKey(
            preferenceId: massage,
            role: LearningRole.solo,
            zoneId: back,
          ),
        ),
        isNotNull,
      );
      expect(
        states['b']!.entry(
          const PreferenceLearningKey(
            preferenceId: caresser,
            role: LearningRole.simultane,
          ),
        ),
        isNotNull,
      );
    });

    test(
      'accepted auction compromise counts every unique card once for both players',
      () {
        final states = {
          'a': engine.initialize(profileId: 'a', choices: const {}),
          'b': engine.initialize(profileId: 'b', choices: const {}),
        };
        final resolved = ResolvedLearningCard(
          card: plainCard,
          participation: ResolvedParticipation.mutual,
          participantPlayerIds: const ['a', 'b'],
        );
        final result = engine.recordRoundOutcome(
          states,
          RoundLearningOutcome(
            acceptedCards: [
              resolved,
              resolved,
              ResolvedLearningCard(
                card: card,
                participation: ResolvedParticipation.directed,
                performerPlayerId: 'a',
                receiverPlayerId: 'b',
              ),
            ],
          ),
        );
        expect(
          result['a']!
              .entry(
                const PreferenceLearningKey(
                  preferenceId: caresser,
                  role: LearningRole.mutuel,
                ),
              )!
              .acceptanceCount,
          1,
        );
        expect(
          result['b']!
              .entry(
                const PreferenceLearningKey(
                  preferenceId: caresser,
                  role: LearningRole.mutuel,
                ),
              )!
              .acceptanceCount,
          1,
        );
        expect(
          result['a']!.entry(
            const PreferenceLearningKey(
              preferenceId: massage,
              role: LearningRole.faire,
              zoneId: back,
            ),
          ),
          isNotNull,
        );
        expect(
          result['b']!.entry(
            const PreferenceLearningKey(
              preferenceId: massage,
              role: LearningRole.recevoir,
              zoneId: back,
            ),
          ),
          isNotNull,
        );
      },
    );

    test('STOP produces no learning', () {
      final initial = engine.initialize(profileId: 'a', choices: const {});
      final result = engine.recordRoundOutcome(
        {'a': initial},
        RoundLearningOutcome(
          consentStopped: true,
          acceptedCards: [
            ResolvedLearningCard(
              card: plainCard,
              participation: ResolvedParticipation.solo,
              soloPlayerId: 'a',
            ),
          ],
        ),
      );
      expect(result['a']!.entries, isEmpty);
    });

    test(
      'resistance targets the precise role rather than the generic action',
      () {
        var state = engine.initialize(
          profileId: 'a',
          choices: const {massage: InitialSwipeChoice.like},
        );
        state = engine.recordResistance(
          state,
          ResistanceLearningEvent(
            playerId: 'a',
            card: card,
            resistedRole: LearningRole.recevoir,
            signal: ResistanceSignal.inversionSought,
          ),
        );
        expect(
          state
              .entry(
                const PreferenceLearningKey(
                  preferenceId: massage,
                  role: LearningRole.recevoir,
                  zoneId: back,
                ),
              )!
              .resistanceCount,
          1,
        );
        expect(state.entry(generalMassage)!.resistanceCount, 0);
      },
    );
  });

  group('proposal policy', () {
    AdaptiveProfileState acceptedSignals(
      AdaptiveProfileState state,
      int count, {
      int spice = 4,
    }) {
      final observed = LearningCardDescriptor(
        cardId: 'accepted',
        variantId: 'accepted',
        tags: const [caresser],
        spiceLevel: spice,
      );
      for (var i = 0; i < count; i++) {
        state = engine.recordRoundOutcome(
          {'a': state},
          RoundLearningOutcome(
            acceptedCards: [
              ResolvedLearningCard(
                card: observed,
                participation: ResolvedParticipation.solo,
                soloPlayerId: 'a',
              ),
            ],
          ),
        )['a']!;
      }
      return state;
    }

    const key = PreferenceLearningKey(
      preferenceId: caresser,
      role: LearningRole.solo,
    );

    test(
      'requires 10 occurrences plus 3 confirmations and unknown jumps directly',
      () {
        var state = engine.initialize(
          profileId: 'a',
          choices: const {caresser: InitialSwipeChoice.unsure},
        );
        state = acceptedSignals(state, 9);
        expect(engine.proposalFor(state, key, now: DateTime.utc(2026)), isNull);
        state = acceptedSignals(state, 1);
        expect(state.entry(key)!.estimatedPa, 11);
        expect(
          state.entry(key)!.estimatedCategory,
          DetailedPreferenceCategory.tempted,
        );
        expect(engine.proposalFor(state, key, now: DateTime.utc(2026)), isNull);
        state = acceptedSignals(state, 3);
        expect(
          engine.proposalFor(state, key, now: DateTime.utc(2026)),
          isNotNull,
        );
      },
    );

    test('manual profile waits for 20 new occurrences', () {
      var state = engine.initialize(profileId: 'a', choices: const {});
      state = engine.manuallyCustomize(state, key: key, pa: 20);
      state = acceptedSignals(state, 19);
      expect(state.entry(key)!.pendingCategory, isNull);
      state = acceptedSignals(state, 1);
      expect(state.entry(key)!.pendingCategory, isNotNull);
      state = acceptedSignals(state, 3);
      final proposal = engine.proposalFor(state, key, now: DateTime.utc(2026))!;
      state = engine.acceptProposal(state, proposal);
      expect(state.entry(key)!.source, AdaptiveProfileSource.manualCustomized);
    });

    test('decline preserves evidence and enforces 20-occurrence cooldown', () {
      var state = engine.initialize(
        profileId: 'a',
        choices: const {caresser: InitialSwipeChoice.unsure},
      );
      state = acceptedSignals(state, 13);
      final proposal = engine.proposalFor(state, key, now: DateTime.utc(2026))!;
      final before = state.entry(key)!.totalEquivalentOccurrences;
      state = engine.declineProposal(state, proposal);
      state = acceptedSignals(state, 19);
      expect(state.entry(key)!.totalEquivalentOccurrences, before + 19);
      expect(engine.proposalFor(state, key, now: DateTime.utc(2026)), isNull);
      state = acceptedSignals(state, 1);
      expect(state.entry(key)!.proposalCooldown, 0);
    });

    test(
      'exclusion never moves automatically and only manual lift restores it',
      () {
        var state = engine.initialize(
          profileId: 'a',
          choices: const {caresser: InitialSwipeChoice.excluded},
        );
        state = acceptedSignals(state, 30);
        expect(
          state
              .entry(const PreferenceLearningKey(preferenceId: caresser))!
              .excluded,
          isTrue,
        );
        expect(state.entry(key), isNull);
        state = engine.manuallyCustomize(
          state,
          key: const PreferenceLearningKey(preferenceId: caresser),
          pa: 8,
        );
        expect(
          state
              .entry(const PreferenceLearningKey(preferenceId: caresser))!
              .excluded,
          isFalse,
        );
      },
    );

    test('spice reduces only movement toward lower PA', () {
      expect(engine.suggestedDelta(.8, 1), -.4);
      expect(engine.suggestedDelta(.8, 2), -.6);
      expect(engine.suggestedDelta(.8, 3), -.8);
      expect(engine.suggestedDelta(.8, 4), -1);
      expect(engine.suggestedDelta(-.8, 1), 1);
      expect(engine.suggestedDelta(.2, 5), 0);
    });

    test('tendency follows the documented relative-ratio formula', () {
      final entry = PreferenceLearningEntry(
        key: key,
        source: AdaptiveProfileSource.autoLearned,
        currentPa: 8,
        estimatedPa: 8,
        recent: const [
          LearningSample(
            equivalentWeight: 1,
            spiceLevel: 3,
            exposure: 4,
            attraction: 3,
          ),
          LearningSample(
            equivalentWeight: 1,
            spiceLevel: 3,
            acceptance: 3,
            resistance: 1,
            resultOccurrences: 4,
          ),
        ],
      );
      expect(entry.attractionRelative, .75);
      expect(entry.acceptanceRelative, .75);
      expect(entry.resistanceRelative, .25);
      expect(entry.tendency, .5);
    });
  });

  test('state serialization keeps a sparse incremental profile', () {
    var state = engine.initialize(profileId: 'a', choices: const {});
    state = engine.recordHand(
      state,
      HandLearningEvent(
        playerId: 'a',
        availableCards: [plainCard],
        playedCardIdentities: {plainCard.identity},
      ),
    );
    expect(state.entries, hasLength(1));
    final decoded = AdaptiveProfileState.fromJson(state.toJson());
    expect(decoded.toJson(), state.toJson());
    final serializedEntry =
        (state.toJson()['entries']! as Map<String, Object?>).values.single
            as Map<String, Object?>;
    expect(serializedEntry['source'], 'AUTO_LEARNED');
  });
}
