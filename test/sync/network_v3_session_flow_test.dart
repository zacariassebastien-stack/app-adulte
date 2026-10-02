import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:couple_cards/engines/engines.dart';
import 'package:couple_cards/features/game/network_duel_secret_store.dart';
import 'package:couple_cards/features/game/network_profile_learning.dart';
import 'package:couple_cards/sync/sync.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  NetworkCompromiseCardDto card({
    required String occurrence,
    required String owner,
    String? cardStableId,
    NetworkCompromiseOrigin origin = NetworkCompromiseOrigin.AUCTION,
    NetworkCardDirection direction = NetworkCardDirection.FAIRE,
    int value = 6,
  }) => NetworkCompromiseCardDto(
    occurrenceId: occurrence,
    cardId: cardStableId ?? 'card.$occurrence',
    variantId: 'variant.$occurrence',
    ownerPlayerId: owner,
    nativeDirection: direction,
    effectiveDirection: direction,
    origin: origin,
    snapshotValue: value,
  );

  test(
    'ABA DTO round-trip preserves three-card compromise and occurrences',
    () {
      final initial = card(
        occurrence: 'round-1:initial:alice',
        owner: 'alice',
        origin: NetworkCompromiseOrigin.INITIAL_DUEL,
        direction: NetworkCardDirection.FAIRE,
        value: 12,
      ).copyWith(effectiveDirection: NetworkCardDirection.RECEVOIR);
      final auction1 = card(
        occurrence: 'bob:copy-1',
        owner: 'bob',
        cardStableId: 'card.repeated',
      );
      final auction2 = card(
        occurrence: 'bob:copy-2',
        owner: 'bob',
        cardStableId: 'card.repeated',
      );
      final result = NetworkFinalResolutionDto(
        retainedPlayerId: 'bob',
        initialWinnerPlayerId: 'alice',
        finalWinnerPlayerId: 'bob',
        cardId: initial.cardId,
        variantId: initial.variantId,
        inverted: true,
        compromise: [initial, auction1, auction2],
      );
      final decoded = NetworkFinalResolutionDto.fromJson(result.toJson());
      expect(decoded.compromise, hasLength(3));
      expect(decoded.compromise.map((item) => item.occurrenceId).toSet(), {
        'round-1:initial:alice',
        'bob:copy-1',
        'bob:copy-2',
      });
      expect(decoded.compromise.skip(1).map((item) => item.cardId).toSet(), {
        'card.repeated',
      });
      expect(
        decoded.compromise.first.effectiveDirection,
        NetworkCardDirection.RECEVOIR,
      );
      expect(
        decoded.compromise
            .skip(1)
            .every((item) => item.nativeDirection == item.effectiveDirection),
        isTrue,
      );
    },
  );

  test(
    'bounded ABA applies one final debit and cancels initial gap on B win',
    () {
      const engine = NegotiationEngineV3();
      var state = NegotiationState(
        initialWinnerId: 'a',
        initialLoserId: 'b',
        initialHighValue: 12,
        initialGapCost: 5,
        actionPoints: const {'a': 100, 'b': 100},
      );
      state = engine.propose(
        state,
        NegotiationOffer(
          inversionRequested: true,
          personalPa: 3,
          cardIds: const ['b:1', 'b:2'],
          cardValues: const {'b:1': 6, 'b:2': 7},
        ),
      );
      state = engine.respond(
        state,
        const NegotiationResponse(acceptInversion: true, acceptAuction: true),
      );
      state = engine.adapt(
        state,
        NegotiationOffer(
          inversionRequested: true,
          personalPa: 3,
          cardIds: const ['b:1', 'b:2'],
          cardValues: const {'b:1': 6, 'b:2': 7},
        ),
      );
      state = engine.validate(state, accepted: true);
      expect(state.finalWinnerId, 'b');
      expect(state.actionPoints['a'], 100);
      expect(state.actionPoints['b'], 85);
    },
  );

  test('refused component cannot survive adaptation and refusal keeps A', () {
    const engine = NegotiationEngineV3();
    var state = NegotiationState(
      initialWinnerId: 'a',
      initialLoserId: 'b',
      initialHighValue: 12,
      initialGapCost: 5,
      actionPoints: const {'a': 100, 'b': 100},
    );
    state = engine.propose(
      state,
      NegotiationOffer(inversionRequested: true, personalPa: 4),
    );
    state = engine.respond(
      state,
      const NegotiationResponse(acceptInversion: false, acceptAuction: true),
    );
    expect(
      () => engine.adapt(
        state,
        NegotiationOffer(inversionRequested: true, personalPa: 4),
      ),
      throwsStateError,
    );
    state = engine.adapt(state, NegotiationOffer(personalPa: 4));
    state = engine.validate(state, accepted: false);
    expect(state.finalWinnerId, 'a');
    expect(state.actionPoints, {'a': 95, 'b': 100});
  });

  test(
    'private hybrid decks survive reconstruction without public leakage',
    () {
      const candidate = DeckCandidateV3(
        cardId: 'card.a',
        variantId: 'variant.a',
        spiceLevel: 3,
        distanceExcluded: true,
      );
      final state = NetworkPrivateGameState(
        roundNumber: 2,
        cards: const [],
        history: const {},
        faceToFaceDeck: const [candidate],
        distanceDeck: const [candidate],
        deckCycle: 3,
        infiniteMode: true,
      );
      final decoded = NetworkPrivateGameState.fromJson(state.toJson());
      expect(
        decoded.faceToFaceDeck.single.occurrenceKey,
        candidate.occurrenceKey,
      );
      expect(
        decoded.distanceDeck.single.occurrenceKey,
        candidate.occurrenceKey,
      );
      expect(decoded.deckCycle, 3);
      expect(decoded.infiniteMode, isTrue);
      final encoded = jsonEncode(state.toJson());
      expect(encoded, isNot(contains('preference')));
    },
  );

  test('mirror draw consumes one matching occurrence only', () {
    const a = DeckCandidateV3(
      cardId: 'a',
      variantId: 'v',
      spiceLevel: 2,
      distanceExcluded: false,
    );
    final runtime = SessionDeckRuntime(
      faceToFace: const [a, a],
      distance: const [a, a, a],
      random: Random(1),
    );
    runtime.draw(HybridDeckOrientation.faceToFace);
    expect(runtime.faceToFace, hasLength(1));
    expect(runtime.distance, hasLength(2));
  });

  test('post-game profile choice remains private and changeable', () async {
    final store = MemoryPostGameProfileChoiceStore();
    await store.save('alice', PostGameProfileChoice.trustGame);
    expect(await store.load('alice'), PostGameProfileChoice.trustGame);
    await store.save('alice', PostGameProfileChoice.customize);
    expect(await store.load('alice'), PostGameProfileChoice.customize);
    expect(await store.load('bob'), isNull);
  });

  test(
    'migration defines bounded phases, atomic debit and repeat Recovery',
    () {
      final sql = File(
        'supabase/migrations/202610010002_network_v3_aba.sql',
      ).readAsStringSync();
      for (final phase in [
        'NEGOTIATION_PROPOSAL',
        'NEGOTIATION_RESPONSE',
        'NEGOTIATION_ADAPTATION',
        'NEGOTIATION_VALIDATION',
      ]) {
        expect(sql, contains(phase));
      }
      expect(sql, contains('validate_network_negotiation'));
      expect(sql, contains("phase='RECOVERY'"));
      expect(sql, contains('recovery_history'));
      expect(sql, isNot(contains('profile_preferences')));
      expect(sql, isNot(contains('personal_profile')));
    },
  );

  test('all ABA phases survive public state reconstruction', () {
    for (final phase in [
      NetworkGamePhase.negotiationProposal,
      NetworkGamePhase.negotiationResponse,
      NetworkGamePhase.negotiationAdaptation,
      NetworkGamePhase.negotiationValidation,
    ]) {
      final state = NetworkGameRoundStateDto(
        roundId: 'round',
        sessionId: 'session',
        sessionRound: 'session.round-1',
        roundNumber: 1,
        phase: phase,
        playerId: 'alice',
        commits: const {},
        actionPoints: const {'alice': 100, 'bob': 100},
        readyNextPlayerIds: const {},
        tieDecisions: const {},
        negotiation: NetworkNegotiationDto(
          proposal: NetworkNegotiationOfferDto(
            inversionRequested: true,
            directPa: 2,
            cards: [card(occurrence: 'bob:1', owner: 'bob')],
          ),
          response: const NetworkNegotiationResponseDto(
            acceptInversion: true,
            acceptAuction: true,
          ),
          finalOffer: NetworkNegotiationOfferDto(
            inversionRequested: true,
            directPa: 2,
            cards: [card(occurrence: 'bob:1', owner: 'bob')],
          ),
        ),
      );
      final restored = NetworkGameRoundStateDto.fromJson(state.toJson());
      expect(restored.phase, phase);
      expect(
        restored.negotiation!.finalOffer!.cards.single.occurrenceId,
        'bob:1',
      );
      final encoded = jsonEncode(restored.toJson());
      expect(encoded, isNot(contains('preferences')));
      expect(encoded, isNot(contains('profile_learning')));
    }
  });
}
