import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:couple_cards/engines/engines.dart';
import 'package:couple_cards/domain/domain.dart';
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
        publicDiscards: const [
          NetworkPlayedCardRecord(
            cardId: 'card.public',
            variantId: 'variant.public',
            occurrenceId: 'public#2',
            roundNumber: 2,
          ),
        ],
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
      expect(decoded.publicDiscards.single.occurrenceId, 'public#2');
      final encoded = jsonEncode(state.toJson());
      expect(encoded, isNot(contains('preference')));
      expect(encoded, isNot(contains('owner_player_id')));
    },
  );

  test('mirror draw consumes one matching occurrence only', () {
    const a1 = DeckCandidateV3(
      cardId: 'a',
      variantId: 'v',
      spiceLevel: 2,
      distanceExcluded: false,
      occurrenceId: 'a::v::1',
    );
    const a2 = DeckCandidateV3(
      cardId: 'a',
      variantId: 'v',
      spiceLevel: 2,
      distanceExcluded: false,
      occurrenceId: 'a::v::2',
    );
    final runtime = SessionDeckRuntime(
      faceToFace: const [a1, a2],
      distance: const [a1, a2],
      random: Random(1),
    );
    final drawn = runtime.draw(HybridDeckOrientation.faceToFace)!;
    expect(runtime.faceToFace, hasLength(1));
    expect(runtime.distance, hasLength(1));
    expect(runtime.distance.single.occurrenceId, isNot(drawn.occurrenceId));
    expect(runtime.distance.single.cardId, drawn.cardId);
  });

  test('playing one duplicate occurrence leaves the other copy intact', () {
    const engine = LifecycleEngine();
    final cards = const [
      CardRuntimeState(
        cardId: 'card.same',
        occurrenceId: 'same#17',
        zone: CardZone.HAND,
      ),
      CardRuntimeState(
        cardId: 'card.same',
        occurrenceId: 'same#42',
        zone: CardZone.HAND,
      ),
    ];
    final locked = engine.lock(cards, 'same#42');
    final engaged = engine.engage(locked, 'same#17');
    expect(
      engaged.singleWhere((card) => card.occurrenceId == 'same#17').zone,
      CardZone.ENGAGED,
    );
    final untouched = engaged.singleWhere(
      (card) => card.occurrenceId == 'same#42',
    );
    expect(untouched.zone, CardZone.HAND);
    expect(untouched.locked, isTrue);
  });

  test(
    'private reconstruction preserves occurrence lock cycle and shortages',
    () {
      final state = NetworkPrivateGameState(
        roundNumber: 4,
        cards: const [
          CardRuntimeState(
            cardId: 'card.same',
            occurrenceId: 'same#42',
            zone: CardZone.HAND,
            locked: true,
          ),
        ],
        history: const {},
        deckCycle: 3,
        infiniteMode: true,
        deckStyle: PlayerStyle.INTENABLE,
        recentCardIds: const ['card.recent'],
        deckShortages: [
          DeckShortage(
            requestedSpice: 4,
            requestedCount: 8,
            availableCount: 3,
            missingCount: 5,
            replacementsBySpice: const {5: 5},
          ),
        ],
      );
      final restored = NetworkPrivateGameState.fromJson(state.toJson());
      expect(restored.cards.single.occurrenceId, 'same#42');
      expect(restored.cards.single.locked, isTrue);
      expect(restored.deckStyle, PlayerStyle.INTENABLE);
      expect(restored.infiniteMode, isTrue);
      expect(restored.deckCycle, 3);
      expect(restored.deckShortages.single.missingCount, 5);
      expect(restored.recentCardIds, ['card.recent']);
    },
  );

  test('legacy duplicate decks receive distinct occurrence ids', () {
    final restored = NetworkPrivateGameState.fromJson({
      'round_number': 1,
      'cards': <Object?>[],
      'history': <String, Object?>{},
      'next_round_prepared': false,
      'face_to_face_deck': [
        for (var index = 0; index < 2; index++)
          {
            'card_id': 'same',
            'variant_id': 'v',
            'spice_level': 2,
            'distance_excluded': false,
          },
      ],
      'distance_deck': <Object?>[],
    });
    expect(
      restored.faceToFaceDeck.map((card) => card.occurrenceId).toSet(),
      hasLength(2),
    );
  });

  test('cycle progression keeps intensity in infinite mode', () {
    const soft = DeckCycleState(style: PlayerStyle.SOFT);
    final epice = soft.next(DeckExhaustionChoice.continueSpicier);
    final intense = epice.next(DeckExhaustionChoice.continueSpicier);
    final stillIntense = intense.next(DeckExhaustionChoice.continueIntenable);
    final infinite = stillIntense.next(DeckExhaustionChoice.infinite);
    expect(epice.style, PlayerStyle.EPICE);
    expect(intense.style, PlayerStyle.INTENABLE);
    expect(stillIntense.style, PlayerStyle.INTENABLE);
    expect(infinite.style, PlayerStyle.INTENABLE);
    expect(infinite.infinite, isTrue);
  });

  test('deck builder tracks neutral shortages and style fallback order', () {
    const candidates = [
      DeckCandidateV3(
        cardId: 'low',
        variantId: 'v',
        spiceLevel: 1,
        distanceExcluded: false,
      ),
      DeckCandidateV3(
        cardId: 'high',
        variantId: 'v',
        spiceLevel: 4,
        distanceExcluded: false,
      ),
    ];
    const builder = SessionDeckBuilderV3();
    final soft = builder.build(
      eligible: candidates,
      targetBySpice: const {2: 3},
      style: PlayerStyle.SOFT,
    );
    final epice = builder.build(
      eligible: candidates,
      targetBySpice: const {2: 3},
      style: PlayerStyle.EPICE,
    );
    expect(soft.cards.first.spiceLevel, 1);
    expect(epice.cards.first.spiceLevel, 4);
    expect(soft.shortages.single.requestedSpice, 2);
    expect(soft.shortages.single.requestedCount, 3);
    expect(soft.shortages.single.availableCount, 0);
    expect(soft.shortages.single.missingCount, 3);
    expect(soft.shortages.single.replacementsBySpice, containsPair(1, 1));
  });

  test('anti-repeat draw avoids recent content while alternatives exist', () {
    const recent = DeckCandidateV3(
      cardId: 'recent',
      variantId: 'v',
      spiceLevel: 2,
      distanceExcluded: false,
      occurrenceId: 'recent#1',
    );
    const fresh = DeckCandidateV3(
      cardId: 'fresh',
      variantId: 'v',
      spiceLevel: 2,
      distanceExcluded: false,
      occurrenceId: 'fresh#1',
    );
    final runtime = SessionDeckRuntime(
      faceToFace: const [recent, fresh],
      distance: const [recent, fresh],
      random: Random(0),
    );
    expect(
      runtime
          .draw(
            HybridDeckOrientation.faceToFace,
            avoidCardIds: const {'recent'},
          )!
          .cardId,
      'fresh',
    );
  });

  test('hybrid draw falls back when only the other virtual deck remains', () {
    const remaining = DeckCandidateV3(
      cardId: 'remaining',
      variantId: 'v',
      spiceLevel: 3,
      distanceExcluded: true,
      occurrenceId: 'remaining#1',
    );
    final runtime = SessionDeckRuntime(
      faceToFace: const [],
      distance: const [remaining],
      random: Random(0),
    );
    expect(
      runtime.draw(HybridDeckOrientation.faceToFace)?.occurrenceId,
      'remaining#1',
    );
    expect(runtime.faceToFace, isEmpty);
    expect(runtime.distance, isEmpty);
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
        deckStyle: PlayerStyle.INTENABLE,
        deckCycle: 4,
        infiniteMode: true,
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
      expect(restored.deckStyle, PlayerStyle.INTENABLE);
      expect(restored.deckCycle, 4);
      expect(restored.infiniteMode, isTrue);
      expect(
        restored.negotiation!.finalOffer!.cards.single.occurrenceId,
        'bob:1',
      );
      final encoded = jsonEncode(restored.toJson());
      expect(encoded, isNot(contains('preferences')));
      expect(encoded, isNot(contains('profile_learning')));
    }
  });

  test(
    'final migration persists style and occurrence-aware public actions',
    () {
      final sql = File(
        'supabase/migrations/202610020001_network_v3_occurrences_cycles.sql',
      ).readAsStringSync();
      expect(sql, contains("deck_style text not null default 'SOFT'"));
      expect(sql, contains("'deck_style',g.deck_style"));
      expect(sql, contains("choice_payload#>>'{parameters,occurrence_id}'"));
      expect(sql, contains("action->>'occurrence_id'"));
      expect(sql, isNot(contains('profile_learning')));
    },
  );
}
