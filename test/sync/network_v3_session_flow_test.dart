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

  test('accepted complete proposal resolves once with every proposed card', () {
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
    state = engine.decide(state, accepted: true);
    expect(state.finalWinnerId, 'b');
    expect(state.finalOffer!.cardIds, ['b:1', 'b:2']);
    expect(state.actionPoints['a'], 100);
    expect(state.actionPoints['b'], 85);
  });

  test('refusing the complete proposal keeps the initial result', () {
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
    state = engine.decide(state, accepted: false);
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
            accepted: true,
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

  test('accepted inverted compromise keeps loser card and added cards', () {
    final sql = File(
      'supabase/migrations/202610100001_simplify_network_negotiation.sql',
    ).readAsStringSync();
    expect(sql, contains("v_round.phase<>'NEGOTIATION_RESPONSE'"));
    expect(sql, contains("'NEGOTIATION_RESPONSE',p_response"));
    expect(sql, contains("phase='FINAL_RESOLVED'"));
    expect(sql, contains('v_choice_owner := v_final;'));
    expect(
      sql,
      isNot(
        contains(
          'v_choice_owner := case when v_inverted then v_winner else v_final end;',
        ),
      ),
    );
    expect(sql, contains("when 'FAIRE' then case when v_inverted"));
    expect(sql, contains("when 'RECEVOIR' then case when v_inverted"));
    expect(sql, contains("if v_accepted then"));
    expect(sql, contains("v_cards := v_cards ||"));
    expect(sql, contains("'NEGOTIATION_RESPONSE',"));
    expect(sql, isNot(contains("phase='NEGOTIATION_ADAPTATION'")));
    expect(sql, isNot(contains("phase='NEGOTIATION_VALIDATION'")));
  });

  test(
    'corruption batch DTO preserves exact occurrences and execution state',
    () {
      final dto = NetworkCorruptionDto(
        offeredBy: 'bob',
        objective: CorruptionObjective.OWN_INITIAL_ACTION,
        accepted: true,
        actions: const [
          ActionPromise(
            cardId: 'card.v4.001',
            occurrenceId: 'bob:discard:1',
            variantId: 'variant.v4.001.base',
            effectiveSpice: 2,
            source: CardZone.DISCARD,
            status: ActionExecutionStatus.COMPLETED,
          ),
          ActionPromise(
            cardId: 'card.v4.002',
            occurrenceId: 'bob:discard:2',
            variantId: 'variant.v4.002.base',
            effectiveSpice: 3,
            source: CardZone.DISCARD,
            status: ActionExecutionStatus.SKIPPED,
          ),
        ],
      );
      final restored = NetworkCorruptionDto.fromJson(dto.toJson());
      expect(restored.actions.map((item) => item.identity), [
        'bob:discard:1',
        'bob:discard:2',
      ]);
      expect(restored.actions.map((item) => item.effectiveSpice), [2, 3]);
      expect(restored.actions.map((item) => item.status), [
        ActionExecutionStatus.COMPLETED,
        ActionExecutionStatus.SKIPPED,
      ]);
    },
  );

  test('corruption migration replaces actions without recalculating PA', () {
    final sql = File(
      'supabase/migrations/202610100002_network_corruption_replacement.sql',
    ).readAsStringSync();
    expect(sql, contains("'final_winner_player_id'"));
    expect(sql, contains("'{compromise}',v_compromise"));
    expect(sql, contains("'{accepted_compromise}'"));
    expect(sql, contains("phase='FINAL_RESOLVED'"));
    expect(sql, contains("phase='CORRUPTION_EXECUTION'"));
    expect(sql, contains("'origin','CORRUPTION'"));
    expect(sql, contains("action->>'status'='COMPLETED'"));
    expect(sql, contains('previous.recovery_history'));
    expect(sql, contains("p_objective<>'OWN_INITIAL_ACTION'"));
    expect(sql, contains("previous.final_resolution->'compromise'"));
    expect(sql, isNot(contains('set action_points=')));
    expect(
      sql,
      isNot(contains('update public.network_game_states set action_points')),
    );
    expect(
      RegExp(
        r"\(card->>'effective_spice'\)::integer>v_unlocked_spice",
      ).allMatches(sql),
      hasLength(2),
    );
    expect(sql, contains('select v4_unlocked_spice into v_unlocked_spice'));
  });

  test('canonical network spice is shared and published monotonically', () {
    final sql = File(
      'supabase/migrations/202610100002_network_corruption_replacement.sql',
    ).readAsStringSync();
    expect(sql, contains('v4_unlocked_spice integer not null default 1'));
    expect(sql, contains("'v4_unlocked_spice',g.v4_unlocked_spice"));
    expect(sql, contains('publish_network_v4_unlocked_spice'));
    expect(sql, contains("v_round.phase<>'WAITING_NEXT'"));
    expect(sql, contains("role='PLAYER_1'"));
    expect(sql, contains('p_unlocked_spice<>v_current+1'));
    expect(sql, contains('p_unlocked_spice not between 1 and 4'));
    expect(sql, contains("'PUBLISH_V4_SPICE'"));
    expect(sql, contains('submit_network_negotiation_proposal'));
    expect(sql, contains("p_offer->'cards'"));
    expect(sql, contains('v_compromise:=public.v4_corruption_compromise'));
    expect(
      sql,
      contains("(card->>'effective_spice')::integer>v_unlocked_spice"),
    );
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

  test('session-round binding protects SECURITY DEFINER cycle RPCs', () {
    final sql = File(
      'supabase/migrations/202610050001_network_session_round_binding.sql',
    ).readAsStringSync();
    for (final functionName in [
      'set_network_hybrid_orientation',
      'continue_network_deck_cycle',
    ]) {
      expect(sql, contains('function public.$functionName('));
    }
    expect(sql, contains('security definer set search_path=public'));
    expect(sql, contains('auth.uid()'));
    expect(
      RegExp(
        r'where id=p_round_id and session_id=p_session_id for update;',
      ).allMatches(sql),
      hasLength(2),
    );
    expect(sql, contains("raise exception 'ROUND_NOT_FOUND'"));
    expect(sql, isNot(contains('profile_preferences')));
    expect(sql, isNot(contains('personal_profile')));
  });

  group('unified post-duel choice', () {
    final migration = File(
      'supabase/migrations/202610100003_unified_post_duel_choice.sql',
    ).readAsStringSync();
    final paSettlementMigration = File(
      'supabase/migrations/202610100004_fix_duel_pa_settlement.sql',
    ).readAsStringSync();
    final corruptionCompletionMigration = File(
      'supabase/migrations/202610100005_normalize_corruption_action_completion.sql',
    ).readAsStringSync();
    final controller = File(
      'lib/features/game/network_game_controller.dart',
    ).readAsStringSync();
    final screen = File(
      'lib/features/game/network_duel_screen.dart',
    ).readAsStringSync();

    test('offers the three final-loser routes', () {
      expect(screen, contains("Key('choose-negotiation')"));
      expect(screen, contains("Key('choose-corruption')"));
      expect(screen, contains("Key('accept-final-result')"));
      expect(screen, contains('onPressed: controller.skipCorruption'));
      expect(controller, contains('isFinalLoser'));
      expect(controller, contains('isFinalWinner'));
    });

    test('rejects an empty compromise on client and server', () {
      expect(
        controller,
        contains('Une proposition de compromis ne peut pas être vide'),
      );
      expect(
        migration,
        contains("raise exception 'ROUND_NEGOTIATION_INVALID'"),
      );
      expect(migration, contains("and jsonb_array_length(p_offer->'cards')=0"));
    });

    test('accepted or refused compromise never reopens corruption', () {
      expect(migration, contains("phase='FINAL_RESOLVED',updated_at=now()"));
      final route = migration.substring(
        migration.indexOf(
          'create or replace function public.route_network_post_duel',
        ),
      );
      expect(route, isNot(contains("'NEGOTIATION_RESPONSE'")));
      expect(route, contains("'COUNTER_DECISION'"));
      expect(route, contains("'CORRUPTION_DECISION'"));
    });

    test('uses final actors after a modified resolution', () {
      expect(
        migration,
        contains("v_round.final_resolution->>'final_winner_player_id'"),
      );
      expect(migration, contains("v_round.negotiation->>'offered_by'"));
      expect(
        migration,
        contains('where session_id=p_session_id and user_id<>v_winner'),
      );
      expect(controller, contains('finalResolution?.finalWinnerPlayerId'));
    });

    test('corruption uses the normal action completion flow', () {
      expect(screen, contains('_PostDuelChoice.corruption'));
      expect(screen, contains('controller.proposeCorruption'));
      expect(
        corruptionCompletionMigration,
        contains(
          'create or replace function public.respond_network_corruption',
        ),
      );
      expect(
        corruptionCompletionMigration,
        contains("phase='FINAL_RESOLVED',updated_at=now()"),
      );
      expect(
        corruptionCompletionMigration,
        contains("old.phase='FINAL_RESOLVED'"),
      );
      expect(
        corruptionCompletionMigration,
        contains("new.phase='WAITING_NEXT'"),
      );
      expect(
        corruptionCompletionMigration,
        contains("action||jsonb_build_object('status','COMPLETED')"),
      );
      expect(
        corruptionCompletionMigration,
        contains("where phase='CORRUPTION_EXECUTION'"),
      );
      expect(screen, isNot(contains('complete-network-corruption')));
      expect(screen, isNot(contains('Confirmer l’exécution')));
      expect(screen, isNot(contains("Key('start-next-network-round')")));
      expect(controller, contains('_startNextRoundAutomatically'));
    });

    test('direct duel acceptance settles its PA cost exactly once', () {
      expect(
        paSettlementMigration,
        contains("old.phase='COUNTER_DECISION' and new.phase='FINAL_RESOLVED'"),
      );
      expect(paSettlementMigration, contains('and old.counter_bid is null'));
      expect(
        paSettlementMigration,
        contains("old.initial_resolution->>'gap_cost'"),
      );
      expect(
        paSettlementMigration,
        contains("where session_id=new.session_id for update"),
      );
      expect(
        RegExp(
          r'update public\.network_game_states set',
        ).allMatches(paSettlementMigration),
        hasLength(1),
      );
    });
  });
}
