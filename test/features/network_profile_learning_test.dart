import 'package:couple_cards/domain/profile/adaptive_profile.dart';
import 'package:couple_cards/engines/profile/profile_learning_engine.dart';
import 'package:couple_cards/features/game/network_profile_learning.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  LearningCardDescriptor card(String id, List<String> tags) =>
      LearningCardDescriptor(
        cardId: id,
        variantId: '$id.v',
        tags: tags,
        spiceLevel: 3,
      );

  test(
    'real network hand signals persist only in local sparse state',
    () async {
      final store = MemoryNetworkProfileLearningStore();
      final coordinator = NetworkProfileLearningCoordinator(
        playerId: 'alice',
        store: store,
      );
      final massage = card('massage', [
        'v3.preference.masser',
        'v3.zone.dos',
        'v3.direction.faire',
        'v3.technique.distance_exclue',
      ]);
      await coordinator.recordHand(
        cards: [massage],
        played: {massage.identity},
        locked: {massage.identity},
      );
      final state = store.values['alice']!;
      expect(state.entries, isNotEmpty);
      expect(
        state.entries.values.every(
          (entry) => entry.key.preferenceId.startsWith('v3.preference.'),
        ),
        isTrue,
      );
      expect(state.entries.values.first.exposureCount, greaterThan(0));
      expect(state.entries.values.first.playedCount, greaterThan(0));
      expect(state.entries.values.first.lockedCount, greaterThan(0));
      expect(state.toJson().toString(), isNot(contains('bob')));
    },
  );

  test(
    'accepted directed result projects final FAIRE and RECEVOIR roles',
    () async {
      final store = MemoryNetworkProfileLearningStore();
      await store.save(AdaptiveProfileState(profileId: 'alice'));
      final coordinator = NetworkProfileLearningCoordinator(
        playerId: 'alice',
        store: store,
      );
      final massage = card('massage', [
        'v3.preference.masser',
        'v3.direction.faire',
      ]);
      await coordinator.recordAccepted([
        ResolvedLearningCard(
          card: massage,
          participation: ResolvedParticipation.directed,
          performerPlayerId: 'alice',
          receiverPlayerId: 'bob',
        ),
      ]);
      final roles = store.values['alice']!.entries.values
          .map((entry) => entry.key.role)
          .toSet();
      expect(roles, contains(LearningRole.faire));
      expect(roles, isNot(contains(LearningRole.recevoir)));
    },
  );

  test('consent STOP records no accepted learning', () {
    const engine = ProfileLearningEngine();
    final initial = AdaptiveProfileState(profileId: 'alice');
    final updated = engine.recordRoundOutcome(
      {'alice': initial},
      RoundLearningOutcome(
        acceptedCards: [
          ResolvedLearningCard(
            card: card('x', ['v3.preference.masser']),
            participation: ResolvedParticipation.solo,
            soloPlayerId: 'alice',
          ),
        ],
        consentStopped: true,
      ),
    );
    expect(updated['alice']!.entries, isEmpty);
  });

  test(
    'manual customization changes only the selected sparse preference',
    () async {
      final store = MemoryNetworkProfileLearningStore();
      final initial = AdaptiveProfileState(profileId: 'alice');
      const engine = ProfileLearningEngine();
      final first = engine.manuallyCustomize(
        initial,
        key: const PreferenceLearningKey(preferenceId: 'v3.preference.a'),
        pa: 8,
      );
      final withSecond = engine.manuallyCustomize(
        first,
        key: const PreferenceLearningKey(preferenceId: 'v3.preference.b'),
        pa: 12,
      );
      await store.save(withSecond);
      final coordinator = NetworkProfileLearningCoordinator(
        playerId: 'alice',
        store: store,
      );
      const edited = PreferenceLearningKey(preferenceId: 'v3.preference.a');
      await coordinator.manuallyCustomize(key: edited, pa: 3);
      final result = store.values['alice']!;
      expect(result.entry(edited)!.currentPa, 3);
      expect(
        result.entry(edited)!.source,
        AdaptiveProfileSource.manualCustomized,
      );
      expect(
        result
            .entry(
              const PreferenceLearningKey(preferenceId: 'v3.preference.b'),
            )!
            .currentPa,
        12,
      );
    },
  );

  test('duplicate content learns one played occurrence only', () async {
    final store = MemoryNetworkProfileLearningStore();
    final coordinator = NetworkProfileLearningCoordinator(
      playerId: 'alice',
      store: store,
    );
    LearningCardDescriptor copy(String occurrence) => LearningCardDescriptor(
      cardId: 'massage',
      variantId: 'massage.v',
      occurrenceId: occurrence,
      tags: const ['v3.preference.masser', 'v3.direction.faire'],
      spiceLevel: 2,
    );
    await coordinator.recordHand(
      cards: [copy('massage#17'), copy('massage#42')],
      played: const {'massage#17'},
    );
    final entry = store.values['alice']!.entries.values.first;
    expect(entry.exposureCount, 2);
    expect(entry.playedCount, 1);
    expect(entry.ignoredCount, 1);
  });
}
