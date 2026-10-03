import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:couple_cards/data/catalog_loader/catalog_loader.dart';
import 'package:couple_cards/domain/domain.dart';
import 'package:couple_cards/engines/engines.dart';
import 'package:couple_cards/features/game/network_duel_secret_store.dart';
import 'package:couple_cards/features/game/network_game_controller.dart';
import 'package:couple_cards/features/game/network_profile_learning.dart';
import 'package:couple_cards/features/lobby/lobby_models.dart';
import 'package:couple_cards/sync/sync.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Catalog catalog;
  late LobbySession session;

  setUpAll(() async {
    catalog = await const CatalogLoader().load(
      (path) => File(path).readAsString(),
    );
    session = LobbySession(
      id: 'session-multi',
      joinCode: 'ABC234',
      status: LobbyStatus.ready,
      expiresAt: DateTime.utc(2026, 10, 1),
      players: const [
        LobbyPlayer(userId: 'alice', role: LobbyPlayerRole.player1),
        LobbyPlayer(userId: 'bob', role: LobbyPlayerRole.player2),
      ],
    );
  });

  test('network DTO round-trips without private hand, lock or profile', () {
    final state = _Backend().state('alice');
    final encoded = jsonEncode(state.toJson());
    expect(
      NetworkGameRoundStateDto.fromJson(state.toJson()).toJson(),
      state.toJson(),
    );
    for (final secret in [
      'hand',
      'locked',
      'personal_value',
      'nonce',
      'preferences',
      'profile',
    ]) {
      expect(encoded, isNot(contains(secret)));
    }
    expect(state.actionPoints, {'alice': 100, 'bob': 100});
  });

  test('private state round-trips hand, lock, history and active secret', () {
    final reveal = ChoiceRevealDto(
      sessionRound: 'session-multi.round-1',
      playerId: 'alice',
      choice: ChoicePayload(
        cardId: 'card.hug',
        variantId: 'variant.hug.base',
        parameters: const {'role': 'GENERAL'},
      ),
      nonce: 'private-nonce',
    );
    final state = NetworkPrivateGameState(
      roundNumber: 1,
      cards: const [
        CardRuntimeState(cardId: 'card.hug', zone: CardZone.HAND, locked: true),
      ],
      history: const {'card.hug': CardHistoryState.seenUnplayed},
      activeReveal: reveal,
    );
    final decoded = NetworkPrivateGameState.fromJson(state.toJson());
    expect(decoded.cards.single.locked, isTrue);
    expect(decoded.history['card.hug'], CardHistoryState.seenUnplayed);
    expect(decoded.activeReveal!.nonce, 'private-nonce');
    expect(
      jsonEncode(_Backend().state('bob').toJson()),
      isNot(contains('private-nonce')),
    );
  });

  test(
    'commit stays secret, bad reveals fail, two commits unlock reveal',
    () async {
      final backend = _Backend();
      final alice = backend.repository('alice');
      final bob = backend.repository('bob');
      final opened = await alice.openCurrentRound(
        command: _command('open-a', 'alice', 'OPEN'),
      );
      final a = _choice('alice', 14);
      final b = _choice('bob', 9);
      const contract = CommitRevealContract();
      await alice.submitCommit(
        command: _command('commit-a', 'alice', 'COMMIT', opened.roundId),
        commitment: contract.commit(
          sessionRound: opened.sessionRound,
          playerId: 'alice',
          choice: a,
          nonce: 'nonce-a',
        ),
      );
      expect(backend.phase, NetworkGamePhase.commit);
      expect(
        jsonEncode(backend.state('bob').toJson()),
        isNot(contains(a.cardId)),
      );
      await expectLater(
        alice.submitReveal(
          command: _command('early', 'alice', 'REVEAL', opened.roundId),
          reveal: ChoiceRevealDto(
            sessionRound: opened.sessionRound,
            playerId: 'alice',
            choice: a,
            nonce: 'nonce-a',
          ),
        ),
        throwsA(isA<NetworkRoundException>()),
      );
      await bob.submitCommit(
        command: _command('commit-b', 'bob', 'COMMIT', opened.roundId),
        commitment: contract.commit(
          sessionRound: opened.sessionRound,
          playerId: 'bob',
          choice: b,
          nonce: 'nonce-b',
        ),
      );
      expect(backend.phase, NetworkGamePhase.reveal);
      await expectLater(
        alice.submitReveal(
          command: _command('bad', 'alice', 'REVEAL', opened.roundId),
          reveal: ChoiceRevealDto(
            sessionRound: opened.sessionRound,
            playerId: 'alice',
            choice: a,
            nonce: 'wrong',
          ),
        ),
        throwsA(isA<NetworkRoundException>()),
      );
      expect(backend.round.reveals, isEmpty);
    },
  );

  test(
    'controllers keep four private cards and engage without exposing hand',
    () async {
      final setup = await _setup(session, catalog);
      expect(setup.alice.hand, hasLength(4));
      expect(setup.bob.hand, hasLength(4));
      final locked = setup.alice.hand.first.identity;
      setup.alice.toggleLock(locked);
      expect(setup.alice.lockedCardId, locked);
      final selected = setup.alice.hand.last;
      setup.alice.selectCard(selected.identity);
      await setup.alice.confirmSelection();
      expect(
        setup.alice.runtime
            .singleWhere((card) => card.occurrenceId == selected.identity)
            .zone,
        CardZone.ENGAGED,
      );
      expect(setup.alice.lockedCardId, locked);
      expect(
        jsonEncode(setup.backend.state('bob').toJson()),
        isNot(contains(locked)),
      );
      setup.dispose();
    },
  );

  test('private directional consent constrains occurrence direction', () async {
    PlayerGameProfile profile({required bool allowRecevoir}) {
      final preferenceIds = catalog.cards
          .expand((card) => card.variants)
          .expand((variant) => variant.v3?.tags ?? const <String>[])
          .where((tag) => tag.startsWith('v3.preference.'))
          .toSet();
      return PlayerGameProfile(
        playerId: 'alice',
        preferences: {
          for (final id in preferenceIds)
            id: PreferenceValue(
              status: PreferenceStatus.ACCEPTED,
              general: 10,
              recevoir: allowRecevoir ? 8 : null,
            ),
        },
      );
    }

    final receivingBackend = _Backend();
    final receiving = NetworkGameController(
      session: session,
      playerId: 'alice',
      repository: receivingBackend.repository('alice'),
      privateStore: MemoryNetworkDuelSecretStore(),
      learningStore: MemoryNetworkProfileLearningStore(),
      catalog: catalog,
      privateProfile: profile(allowRecevoir: true),
    );
    addTearDown(receiving.dispose);
    await receiving.start();
    expect(
      receiving.runtime.map((card) => card.nativeDirection),
      isNot(contains(CardOccurrenceDirection.FAIRE)),
    );
    expect(
      receiving.runtime.map((card) => card.nativeDirection),
      contains(CardOccurrenceDirection.RECEVOIR),
    );
    expect(
      receiving.hand
          .where(
            (card) => card.nativeDirection == CardOccurrenceDirection.RECEVOIR,
          )
          .map((card) => card.oppositePersonalValue),
      everyElement(isNull),
    );

    final excludedBackend = _Backend();
    final excluded = NetworkGameController(
      session: session,
      playerId: 'alice',
      repository: excludedBackend.repository('alice'),
      privateStore: MemoryNetworkDuelSecretStore(),
      learningStore: MemoryNetworkProfileLearningStore(),
      catalog: catalog,
      privateProfile: profile(allowRecevoir: false),
    );
    addTearDown(excluded.dispose);
    await excluded.start();
    expect(
      excluded.runtime.map((card) => card.nativeDirection),
      isNot(
        contains(
          anyOf(
            CardOccurrenceDirection.FAIRE,
            CardOccurrenceDirection.RECEVOIR,
          ),
        ),
      ),
    );
  });

  test(
    'committed choice can be cancelled exactly once before reveal',
    () async {
      final setup = await _setup(session, catalog);
      addTearDown(setup.dispose);
      final card = setup.alice.hand.first;
      setup.alice.toggleLock(card.identity);
      setup.alice.selectCard(card.identity);
      await setup.alice.confirmSelection();
      await _settle();

      expect(setup.alice.canCancelSelection, isTrue);
      expect(setup.backend.round.commits, contains('alice'));
      expect(await setup.alice.cancelSelection(), isTrue);
      await _settle();

      expect(setup.backend.round.commits, isNot(contains('alice')));
      expect(
        setup.alice.hand.where((item) => item.identity == card.identity),
        hasLength(1),
      );
      expect(setup.alice.lockedCardId, isNull);
      expect(setup.alice.viewState, NetworkGameViewState.choosing);

      setup.alice.selectCard(card.identity);
      await setup.alice.confirmSelection();
      expect(setup.backend.round.commits, contains('alice'));
    },
  );

  test(
    'cancellation is idempotent and loses the race against reveal',
    () async {
      final backend = _Backend();
      final alice = backend.repository('alice');
      final bob = backend.repository('bob');
      final round = await alice.openCurrentRound(
        command: _command('open-cancel', 'alice', 'OPEN'),
      );
      final choiceA = _choice('alice', 12);
      final choiceB = _choice('bob', 11);
      const contract = CommitRevealContract();
      await alice.submitCommit(
        command: _command('commit-cancel-a', 'alice', 'COMMIT', round.roundId),
        commitment: contract.commit(
          sessionRound: round.sessionRound,
          playerId: 'alice',
          choice: choiceA,
          nonce: 'a',
        ),
      );
      final cancel = _command(
        'cancel-same',
        'alice',
        'CANCEL_COMMIT',
        round.roundId,
      );
      final cancellable = alice as NetworkCommitCancellationRepository;
      await cancellable.cancelCommit(command: cancel);
      await cancellable.cancelCommit(command: cancel);
      expect(backend.round.commits, isEmpty);
      await expectLater(
        alice.submitReveal(
          command: _command('old-reveal', 'alice', 'REVEAL', round.roundId),
          reveal: ChoiceRevealDto(
            sessionRound: round.sessionRound,
            playerId: 'alice',
            choice: choiceA,
            nonce: 'a',
          ),
        ),
        throwsA(isA<NetworkRoundException>()),
      );

      await alice.submitCommit(
        command: _command(
          'commit-cancel-a-v2',
          'alice',
          'COMMIT',
          round.roundId,
        ),
        commitment: contract.commit(
          sessionRound: round.sessionRound,
          playerId: 'alice',
          choice: choiceA,
          nonce: 'a2',
        ),
      );
      await bob.submitCommit(
        command: _command('commit-cancel-b', 'bob', 'COMMIT', round.roundId),
        commitment: contract.commit(
          sessionRound: round.sessionRound,
          playerId: 'bob',
          choice: choiceB,
          nonce: 'b',
        ),
      );
      expect(backend.phase, NetworkGamePhase.reveal);
      await expectLater(
        cancellable.cancelCommit(
          command: _command(
            'cancel-too-late',
            'alice',
            'CANCEL_COMMIT',
            round.roundId,
          ),
        ),
        throwsA(isA<NetworkRoundException>()),
      );
    },
  );

  test('closing a session is idempotent and visible to both players', () async {
    final setup = await _setup(session, catalog);
    addTearDown(setup.dispose);
    await setup.alice.closeSession();
    await _settle();
    expect(setup.alice.viewState, NetworkGameViewState.sessionEnded);
    expect(setup.bob.viewState, NetworkGameViewState.sessionEnded);
    await setup.alice.closeSession();
    expect(setup.backend.phase, NetworkGamePhase.sessionClosed);
  });

  test(
    'reconnect after cancellation restores only the valid hand state',
    () async {
      final backend = _Backend();
      final store = MemoryNetworkDuelSecretStore();
      final learning = MemoryNetworkProfileLearningStore();
      var controller = NetworkGameController(
        session: session,
        playerId: 'alice',
        repository: backend.repository('alice'),
        privateStore: store,
        learningStore: learning,
        catalog: catalog,
        nonceFactory: () => 'fixed-nonce',
      );
      await controller.start();
      final card = controller.hand.first;
      controller.selectCard(card.identity);
      await controller.confirmSelection();
      final oldNonce = (await store.loadGame(
        sessionId: session.id,
        playerId: 'alice',
      ))!.activeReveal!.nonce;
      expect(await controller.cancelSelection(), isTrue);
      controller.dispose();

      controller = NetworkGameController(
        session: session,
        playerId: 'alice',
        repository: backend.repository('alice'),
        privateStore: store,
        learningStore: learning,
        catalog: catalog,
        nonceFactory: () => 'fixed-nonce',
      );
      addTearDown(controller.dispose);
      await controller.start();
      expect(controller.viewState, NetworkGameViewState.choosing);
      expect(
        controller.hand.where((item) => item.identity == card.identity),
        hasLength(1),
      );
      expect((await learning.load('alice'))?.entries ?? const {}, isEmpty);
      expect(backend.points, {'alice': 100, 'bob': 100});

      controller.selectCard(card.identity);
      await controller.confirmSelection();
      final newNonce = (await store.loadGame(
        sessionId: session.id,
        playerId: 'alice',
      ))!.activeReveal!.nonce;
      expect(newNonce, isNot(oldNonce));
    },
  );

  test('rounds 1 to 3 retain session, PA, hand history and lock', () async {
    final setup = await _setup(session, catalog);
    final locked = setup.alice.hand.first.identity;
    setup.alice.toggleLock(locked);
    final initialHand = setup.alice.hand.map((card) => card.id).toSet();
    for (final expected in [1, 2]) {
      await _playUnequal(setup, avoidAliceCard: locked);
      final initial = setup.alice.initialResolution!;
      final loser = initial.loserPlayerId == 'alice' ? setup.alice : setup.bob;
      await loser.acceptInitialResult();
      await _settle();
      final beforeReady = Map<String, int>.from(setup.alice.actionPoints);
      await setup.alice.readyForNextRound();
      await setup.alice.readyForNextRound();
      expect(setup.alice.roundNumber, expected);
      expect(setup.alice.viewState, NetworkGameViewState.waitingNext);
      expect(setup.bob.viewState, NetworkGameViewState.finalResult);
      await setup.bob.readyForNextRound();
      await _settle();
      expect(setup.alice.roundNumber, expected + 1);
      expect(setup.bob.roundNumber, expected + 1);
      expect(setup.alice.actionPoints, setup.bob.actionPoints);
      expect(setup.alice.actionPoints, beforeReady);
      expect(setup.alice.hand, hasLength(const BalanceConfig().handSize));
      expect(setup.alice.lockedCardId, locked);
    }
    expect(setup.backend.roundCreations, 3);
    expect(
      setup.alice.hand.map((card) => card.id).toSet().intersection(initialHand),
      isNotEmpty,
    );
    expect(setup.backend.initialApplications, 2);
    expect(
      setup.alice.actionPoints.values,
      everyElement(greaterThanOrEqualTo(0)),
    );
    setup.dispose();
  });

  test(
    'playing a locked card removes lock and records discard history',
    () async {
      final setup = await _setup(session, catalog);
      final target = setup.alice.hand.first;
      setup.alice.toggleLock(target.identity);
      await _playUnequal(setup, forceAliceCard: target.identity);
      final loser = setup.alice.initialResolution!.loserPlayerId == 'alice'
          ? setup.alice
          : setup.bob;
      await loser.acceptInitialResult();
      await setup.alice.readyForNextRound();
      expect(setup.alice.lockedCardId, isNot(target.identity));
      expect(
        setup.alice.history[target.id],
        CardHistoryState.playedOrDiscarded,
      );
      setup.dispose();
    },
  );

  test('counter bid spends once, survives loss and adds no gap cost', () async {
    final setup = await _setup(session, catalog);
    await _playUnequal(setup);
    final initial = setup.alice.initialResolution!;
    final loser = initial.loserPlayerId == 'alice' ? setup.alice : setup.bob;
    final winner = initial.winnerPlayerId == 'alice' ? setup.alice : setup.bob;
    final afterGap = Map<String, int>.from(loser.actionPoints);
    await loser.submitCounterBid(2, AuctionTarget.OWN_INITIAL_ACTION);
    await _settle();
    expect(loser.actionPoints[loser.playerId], afterGap[loser.playerId]! - 2);
    expect(setup.backend.counterApplications, 1);
    await setup.backend
        .repository(loser.playerId)
        .submitCounterDecision(
          command: _command(
            'game:session-multi:round-1:${loser.playerId}:counter_decision',
            loser.playerId,
            'COUNTER_DECISION',
            setup.backend.round.id,
          ),
          decision: CounterDecision.bid,
          amount: 2,
          target: AuctionTarget.OWN_INITIAL_ACTION,
        );
    expect(setup.backend.counterApplications, 1);
    await winner.submitFinalDefense(3);
    await _settle();
    expect(loser.actionPoints[loser.playerId], afterGap[loser.playerId]! - 2);
    expect(
      winner.actionPoints[winner.playerId],
      afterGap[winner.playerId]! - 3,
    );
    expect(setup.backend.defenseApplications, 1);
    await setup.backend
        .repository(winner.playerId)
        .submitFinalDefense(
          command: _command(
            'game:session-multi:round-1:${winner.playerId}:final_defense',
            winner.playerId,
            'FINAL_DEFENSE',
            setup.backend.round.id,
          ),
          decision: FinalDefenseDecision.defend,
          amount: 3,
        );
    expect(setup.backend.defenseApplications, 1);
    expect(winner.finalResolution!.retainedPlayerId, winner.playerId);
    setup.backend.notifyTwice();
    await _settle();
    expect(setup.backend.initialApplications, 1);
    expect(setup.backend.counterApplications, 1);
    expect(setup.backend.defenseApplications, 1);
    setup.dispose();
  });

  test('equal, insufficient, excessive and third bids are rejected', () async {
    final setup = await _setup(session, catalog);
    await _playUnequal(setup);
    final initial = setup.alice.initialResolution!;
    final loser = initial.loserPlayerId == 'alice' ? setup.alice : setup.bob;
    final winner = initial.winnerPlayerId == 'alice' ? setup.alice : setup.bob;
    await expectLater(
      loser.submitCounterBid(0, AuctionTarget.OWN_INITIAL_ACTION),
      throwsArgumentError,
    );
    await expectLater(
      loser.submitCounterBid(1000, AuctionTarget.OWN_INITIAL_ACTION),
      throwsStateError,
    );
    await loser.submitCounterBid(2, AuctionTarget.OWN_INITIAL_ACTION);
    await _settle();
    await expectLater(winner.submitFinalDefense(2), throwsArgumentError);
    await winner.submitFinalDefense(3);
    await _settle();
    final before = Map<String, int>.from(winner.actionPoints);
    await winner.submitFinalDefense(4);
    await loser.submitCounterBid(4, AuctionTarget.OWN_INITIAL_ACTION);
    expect(winner.actionPoints, before);
    setup.dispose();
  });

  test(
    'winner can renounce and inversion preserves initial snapshot semantics',
    () async {
      final setup = await _setup(session, catalog);
      await _playUnequal(setup, requireInvertibleWinner: true);
      final initial = setup.alice.initialResolution!;
      final loser = initial.loserPlayerId == 'alice' ? setup.alice : setup.bob;
      final winner = initial.winnerPlayerId == 'alice'
          ? setup.alice
          : setup.bob;
      expect(initial.inversionAllowed, isTrue);
      final winnerReveal = setup.backend.round.reveals[winner.playerId]!;
      final originalValue = winnerReveal.choice.parameters['personal_value'];
      await loser.submitCounterBid(2, AuctionTarget.INVERT_WINNING_ACTION);
      await winner.yieldFinalDefense();
      await _settle();
      expect(winner.finalResolution!.inverted, isTrue);
      expect(winner.finalResolution!.cardId, winnerReveal.choice.cardId);
      expect(
        setup
            .backend
            .round
            .reveals[winner.playerId]!
            .choice
            .parameters['personal_value'],
        originalValue,
      );
      setup.dispose();
    },
  );

  test('inversion is refused when catalog winner is not invertible', () async {
    final setup = await _setup(session, catalog);
    final hasNonInvertibleWinningPair = [
      for (final alice in setup.alice.hand)
        for (final bob in setup.bob.hand)
          if (alice.personalValue != bob.personalValue)
            (alice.personalValue > bob.personalValue ? alice : bob),
    ].any((winner) => !winner.variant.invertible);
    if (!hasNonInvertibleWinningPair) {
      expect(
        catalog.cards
            .map((card) => const CatalogEngineAdapter.v3().card(card))
            .expand((card) => card.variants)
            .any((variant) => variant.invertible == false),
        isTrue,
      );
      setup.dispose();
      return;
    }
    await _playUnequal(setup, requireNonInvertibleWinner: true);
    final initial = setup.alice.initialResolution!;
    final loser = initial.loserPlayerId == 'alice' ? setup.alice : setup.bob;
    expect(initial.inversionAllowed, isFalse);
    await expectLater(
      loser.submitCounterBid(2, AuctionTarget.INVERT_WINNING_ACTION),
      throwsStateError,
    );
    setup.dispose();
  });

  test(
    'tie spends no PA and supports either concession or mutual abandon',
    () async {
      final backend = _Backend();
      await _primeTie(backend);
      final before = Map<String, int>.from(backend.points);
      await backend
          .repository('alice')
          .submitTieDecision(
            command: _command(
              'tie-concede',
              'alice',
              'TIE_DECISION',
              backend.round.id,
            ),
            decision: TieDecision.concede,
          );
      expect(backend.points, before);
      expect(backend.round.finalResolution!.retainedPlayerId, 'bob');

      final abandoned = _Backend();
      await _primeTie(abandoned);
      await abandoned
          .repository('alice')
          .submitTieDecision(
            command: _command(
              'abandon-a',
              'alice',
              'TIE_DECISION',
              abandoned.round.id,
            ),
            decision: TieDecision.abandon,
          );
      expect(abandoned.phase, NetworkGamePhase.tieDecision);
      await abandoned
          .repository('bob')
          .submitTieDecision(
            command: _command(
              'abandon-b',
              'bob',
              'TIE_DECISION',
              abandoned.round.id,
            ),
            decision: TieDecision.abandon,
          );
      expect(abandoned.round.finalResolution!.mutualAbandon, isTrue);
      expect(abandoned.points, before);
    },
  );

  test(
    'reconnect resumes commit, auction, final result and waiting-next',
    () async {
      final backend = _Backend();
      final aliceStore = MemoryNetworkDuelSecretStore();
      final bobStore = MemoryNetworkDuelSecretStore();
      var alice = _controller(backend, session, catalog, 'alice', aliceStore);
      final bob = _controller(backend, session, catalog, 'bob', bobStore);
      await Future.wait([alice.start(), bob.start()]);
      alice.selectCard(alice.hand.first.identity);
      final aliceValue = alice.selectedCard!.personalValue;
      await alice.confirmSelection();
      final savedPoints = Map<String, int>.from(alice.actionPoints);
      final savedHandIds = alice.hand.map((card) => card.id).toList();
      final savedZones = {
        for (final card in alice.runtime) card.cardId: card.zone,
      };
      alice.dispose();
      alice = _controller(backend, session, catalog, 'alice', aliceStore);
      await alice.start();
      expect(alice.viewState, NetworkGameViewState.waitingForPartner);
      expect(alice.actionPoints, savedPoints);
      expect(alice.hand.map((card) => card.id), savedHandIds);
      expect({
        for (final card in alice.runtime) card.cardId: card.zone,
      }, savedZones);
      await _chooseUnequalPartner(bob, aliceValue);
      await _settle();
      expect(alice.initialResolution, isNotNull);
      alice.dispose();
      alice = _controller(backend, session, catalog, 'alice', aliceStore);
      await alice.start();
      expect(
        alice.viewState,
        anyOf(
          NetworkGameViewState.counterDecision,
          NetworkGameViewState.finalDefenseDecision,
        ),
      );
      final loser = alice.initialResolution!.loserPlayerId == 'alice'
          ? alice
          : bob;
      await loser.acceptInitialResult();
      await _settle();
      alice.dispose();
      alice = _controller(backend, session, catalog, 'alice', aliceStore);
      await alice.start();
      expect(alice.viewState, NetworkGameViewState.finalResult);
      await alice.readyForNextRound();
      alice.dispose();
      alice = _controller(backend, session, catalog, 'alice', aliceStore);
      await alice.start();
      expect(alice.viewState, NetworkGameViewState.waitingNext);
      expect(backend.initialApplications, 1);
      await bob.readyForNextRound();
      await _settle();
      alice.dispose();
      alice = _controller(backend, session, catalog, 'alice', aliceStore);
      await alice.start();
      expect(alice.roundNumber, 2);
      expect(alice.viewState, NetworkGameViewState.choosing);
      expect(alice.hand, hasLength(const BalanceConfig().handSize));
      alice.dispose();
      bob.dispose();
    },
  );

  test(
    'corruption refusal is public, idempotent and leaves discard untouched',
    () async {
      final setup = await _setup(session, catalog);
      await _reachSecondResolved(setup);
      setup.backend.round.phase = NetworkGamePhase.corruptionDecision;
      setup.backend.notify();
      await _settle();
      final actor = setup.alice.isCorruptionActor ? setup.alice : setup.bob;
      final partner = identical(actor, setup.alice) ? setup.bob : setup.alice;
      final card = actor.corruptionCards.single;
      final before = actor.runtime.singleWhere(
        (item) => item.occurrenceId == card.identity,
      );
      expect(before.zone, CardZone.DISCARD);

      await actor.proposeCorruption(
        card.identity,
        CorruptionObjective.OWN_INITIAL_ACTION,
      );
      await _settle();
      expect(partner.viewState, NetworkGameViewState.corruptionResponse);
      expect(partner.corruption!.actions.map((item) => item.cardId), [card.id]);

      final reconnect = _controller(
        setup.backend,
        session,
        catalog,
        actor.playerId,
        actor.privateStore,
      );
      await reconnect.start();
      expect(reconnect.viewState, NetworkGameViewState.corruptionResponse);
      reconnect.dispose();

      await partner.respondToCorruption(accepted: false);
      await partner.respondToCorruption(accepted: false);
      await _settle();
      expect(setup.backend.phase, NetworkGamePhase.recovery);
      expect(
        actor.runtime
            .singleWhere((item) => item.occurrenceId == card.identity)
            .zone,
        CardZone.DISCARD,
      );
      setup.dispose();
    },
  );

  test(
    'accepted corruption exhausts only the completed proposed discard once',
    () async {
      final setup = await _setup(session, catalog);
      await _reachSecondResolved(setup);
      setup.backend.round.phase = NetworkGamePhase.corruptionDecision;
      setup.backend.notify();
      await _settle();
      final actor = setup.alice.isCorruptionActor ? setup.alice : setup.bob;
      final partner = identical(actor, setup.alice) ? setup.bob : setup.alice;
      final offered = actor.corruptionCards.single;
      final unrelated = actor.runtime
          .where((item) => item.zone == CardZone.HAND)
          .first;

      await actor.proposeCorruption(
        offered.identity,
        CorruptionObjective.OWN_INITIAL_ACTION,
      );
      await _settle();
      await partner.respondToCorruption(accepted: true);
      await _settle();
      expect(actor.viewState, NetworkGameViewState.corruptionExecution);
      await actor.completeCorruption(completed: true);
      await actor.completeCorruption(completed: true);
      await _settle();

      expect(
        actor.runtime
            .singleWhere((item) => item.occurrenceId == offered.identity)
            .zone,
        CardZone.EXHAUSTED,
      );
      expect(
        actor.runtime
            .singleWhere((item) => item.occurrenceId == unrelated.occurrenceId)
            .zone,
        CardZone.HAND,
      );
      expect(setup.backend.phase, NetworkGamePhase.recovery);
      setup.dispose();
    },
  );

  test(
    'recovery honors threshold, applies gain once and resumes next round',
    () async {
      final setup = await _setup(session, catalog);
      await _playUnequal(setup);
      final loser = setup.alice.isInitialLoser ? setup.alice : setup.bob;
      await loser.acceptInitialResult();
      await _settle();
      setup.backend.points['alice'] = 10;
      setup.backend.points['bob'] = 11;
      setup.backend.round.phase = NetworkGamePhase.recovery;
      setup.backend.notify();
      await _settle();

      final playedCardId = setup.alice.runtime
          .singleWhere((item) => item.zone == CardZone.DISCARD)
          .cardId;
      expect(
        setup.alice.history[playedCardId],
        CardHistoryState.playedOrDiscarded,
      );
      expect(setup.alice.recoveryAvailable, isTrue);
      expect(setup.bob.recoveryAvailable, isFalse);
      final option = setup.alice.recoveryCards.first;
      final before = setup.backend.points['alice']!;
      await setup.alice.recoverWith(option.identity);
      await setup.alice.recoverWith(option.identity);
      await _settle();
      expect(setup.backend.round.recoveries['alice']!.gain, 0);
      expect(setup.backend.round.recoveries['alice']!.completed, isFalse);
      expect(setup.bob.viewState, NetworkGameViewState.recoveryResponse);
      await setup.bob.respondToRecovery(RecoveryResponse.ACCEPT);
      await _settle();
      expect(setup.alice.viewState, NetworkGameViewState.recoveryExecution);
      final resolvedOption = setup.alice.recoveryCards.singleWhere(
        (card) => card.identity == option.identity,
      );
      expect(resolvedOption.role, option.role);
      expect(resolvedOption.personalValue, option.personalValue);
      await setup.alice.completeRecovery(completed: true);
      await setup.alice.completeRecovery(completed: true);
      await _settle();
      expect(
        setup.backend.round.recoveries['alice']!.gain,
        (option.personalValue * 1.5).ceil(),
      );
      expect(
        setup.backend.points['alice'],
        before + (option.personalValue * 1.5).ceil(),
      );
      expect(setup.backend.round.recoveryDone, contains('alice'));

      setup.alice.dispose();
      final alice = _controller(
        setup.backend,
        session,
        catalog,
        'alice',
        setup.alice.privateStore,
      );
      await alice.start();
      expect(alice.round!.recoveryDonePlayerIds, contains('alice'));
      await setup.bob.skipRecovery();
      await _settle();
      expect(setup.backend.phase, NetworkGamePhase.finalResolved);
      await setup.backend
          .repository('alice')
          .readyNextRound(
            command: _command(
              'recovery-ready-alice',
              'alice',
              'READY_NEXT',
              setup.backend.round.id,
            ),
          );
      await setup.backend
          .repository('bob')
          .readyNextRound(
            command: _command(
              'recovery-ready-bob',
              'bob',
              'READY_NEXT',
              setup.backend.round.id,
            ),
          );
      await _settle();
      expect(setup.backend.currentRound, 2);
      alice.dispose();
      setup.bob.dispose();
    },
  );

  test(
    'corruption/recovery projection contains no unrelated private state',
    () {
      final state = NetworkGameRoundStateDto(
        roundId: 'round',
        sessionId: 'session',
        sessionRound: 'session.round-2',
        roundNumber: 2,
        phase: NetworkGamePhase.recovery,
        playerId: 'alice',
        commits: const {},
        actionPoints: const {'alice': 12, 'bob': 40},
        readyNextPlayerIds: const {},
        tieDecisions: const {},
        corruption: NetworkCorruptionDto(
          offeredBy: 'alice',
          objective: CorruptionObjective.OWN_INITIAL_ACTION,
          actions: const [
            ActionPromise(cardId: 'shown-card', source: CardZone.DISCARD),
          ],
        ),
        recoveryByPlayer: const {
          'alice': NetworkRecoveryDto(
            playerId: 'alice',
            cardId: 'recovery-card',
            variantId: 'variant',
            source: RecoverySource.CATALOG,
            completed: true,
            gain: 8,
          ),
        },
        recoveryDonePlayerIds: const {'alice'},
      );
      final encoded = jsonEncode(state.toJson());
      expect(encoded, contains('shown-card'));
      expect(encoded, isNot(contains('private_hand')));
      expect(encoded, isNot(contains('locked')));
      expect(encoded, isNot(contains('profile')));
      expect(encoded, isNot(contains('preference')));
      expect(encoded, isNot(contains('draw_history')));
      expect(encoded, isNot(contains('nonce')));
    },
  );

  test(
    'migration defines RLS, phases, idempotent commands and no private state',
    () {
      final sql = File(
        'supabase/migrations/202609300001_network_multiround_auction.sql',
      ).readAsStringSync();
      expect(sql, contains('enable row level security'));
      expect(sql, contains("'COUNTER_DECISION'"));
      expect(sql, contains("'FINAL_DEFENSE_DECISION'"));
      expect(sql, contains("'WAITING_NEXT'"));
      expect(sql, contains('pg_advisory_xact_lock'));
      expect(sql, contains('ROUND_INSUFFICIENT_PA'));
      expect(sql, contains('ROUND_INVERSION_FORBIDDEN'));
      expect(sql, contains('command_payload'));
      expect(sql, contains("case when r.phase = 'READY'"));
      expect(
        sql,
        contains(
          'revoke execute on function public.create_network_round(uuid, integer, uuid, text) from authenticated',
        ),
      );
      expect(sql, isNot(contains('service_role')));
      expect(sql, isNot(contains('private_hand')));
      final next = File(
        'supabase/migrations/202609300002_network_corruption_recovery.sql',
      ).readAsStringSync();
      expect(next, contains("'CORRUPTION_RESPONSE'"));
      expect(next, contains("'CORRUPTION_EXECUTION'"));
      expect(next, contains("'RECOVERY'"));
      expect(next, contains('pg_advisory_xact_lock'));
      expect(next, contains('auth.uid()'));
      expect(next, contains('ROUND_RECOVERY_NOT_ELIGIBLE'));
      expect(next, isNot(contains('service_role')));
      final privacy = File(
        'supabase/migrations/202609300003_recovery_proposal_privacy.sql',
      ).readAsStringSync();
      expect(privacy, contains('ROUND_RECOVERY_PROPOSAL_PRIVATE'));
      expect(privacy, contains("old.phase = 'RECOVERY'"));
      expect(privacy, contains("new.phase = 'RECOVERY_RESPONSE'"));
      expect(privacy, contains("v_proposal->>'gain'"));
      expect(privacy, isNot(contains('service_role')));
      expect(next, isNot(contains('private_hand')));
      final cancellation = File(
        'supabase/migrations/202610020002_safe_commit_cancel_and_session_close.sql',
      ).readAsStringSync();
      expect(cancellation, contains('cancel_network_round_commit'));
      expect(cancellation, contains("if v_round.phase<>'COMMIT'"));
      expect(
        cancellation,
        contains('delete from public.network_round_commits'),
      );
      expect(cancellation, contains('pg_advisory_xact_lock'));
      expect(cancellation, contains('close_network_game_session'));
      expect(cancellation, contains("set status='closed'"));
      expect(cancellation, contains("phase='SESSION_CLOSED'"));
      expect(cancellation, isNot(contains('private_hand')));
    },
  );
}

final class _Setup {
  _Setup(this.backend, this.alice, this.bob);
  final _Backend backend;
  final NetworkGameController alice;
  final NetworkGameController bob;
  void dispose() {
    alice.dispose();
    bob.dispose();
  }
}

Future<_Setup> _setup(LobbySession session, Catalog catalog) async {
  final backend = _Backend();
  final alice = _controller(
    backend,
    session,
    catalog,
    'alice',
    MemoryNetworkDuelSecretStore(),
  );
  final bob = _controller(
    backend,
    session,
    catalog,
    'bob',
    MemoryNetworkDuelSecretStore(),
  );
  await Future.wait([alice.start(), bob.start()]);
  return _Setup(backend, alice, bob);
}

NetworkGameController _controller(
  _Backend backend,
  LobbySession session,
  Catalog catalog,
  String playerId,
  NetworkDuelSecretStore store,
) => NetworkGameController(
  session: session,
  playerId: playerId,
  repository: backend.repository(playerId),
  privateStore: store,
  learningStore: MemoryNetworkProfileLearningStore(),
  catalog: catalog,
  nonceFactory: () => 'nonce-$playerId-${backend.currentRound}',
  clock: () => DateTime.utc(2026, 9, 30, 12, backend.currentRound),
);

Future<void> _playUnequal(
  _Setup setup, {
  String? avoidAliceCard,
  String? forceAliceCard,
  bool requireInvertibleWinner = false,
  bool requireNonInvertibleWinner = false,
}) async {
  final pairs = [
    for (final a in setup.alice.hand)
      for (final b in setup.bob.hand) (a, b),
  ];
  final pair = pairs.firstWhere((pair) {
    final aWins = pair.$1.personalValue > pair.$2.personalValue;
    final winner = aWins ? pair.$1 : pair.$2;
    return pair.$1.personalValue != pair.$2.personalValue &&
        (avoidAliceCard == null || pair.$1.identity != avoidAliceCard) &&
        (forceAliceCard == null || pair.$1.identity == forceAliceCard) &&
        (!requireInvertibleWinner || winner.variant.invertible) &&
        (!requireNonInvertibleWinner || !winner.variant.invertible);
  });
  setup.alice.selectCard(pair.$1.identity);
  setup.bob.selectCard(pair.$2.identity);
  await setup.alice.confirmSelection();
  await setup.bob.confirmSelection();
  await _settle();
  expect(setup.alice.initialResolution, isNotNull);
}

Future<void> _chooseUnequalPartner(
  NetworkGameController bob,
  int opponentValue,
) async {
  final partner = bob.hand.firstWhere(
    (card) => card.personalValue != opponentValue,
  );
  bob.selectCard(partner.identity);
  await bob.confirmSelection();
}

Future<void> _reachSecondResolved(_Setup setup) async {
  await _playUnequal(setup);
  final firstLoser = setup.alice.isInitialLoser ? setup.alice : setup.bob;
  await firstLoser.acceptInitialResult();
  await _settle();
  await setup.alice.readyForNextRound();
  await setup.bob.readyForNextRound();
  await _settle();
  await _playUnequal(setup);
  final secondLoser = setup.alice.isInitialLoser ? setup.alice : setup.bob;
  await secondLoser.acceptInitialResult();
  await _settle();
}

Future<void> _primeTie(_Backend backend) async {
  final alice = backend.repository('alice');
  final opened = await alice.openCurrentRound(
    command: _command('open', 'alice', 'OPEN'),
  );
  const contract = CommitRevealContract();
  for (final player in ['alice', 'bob']) {
    final choice = _choice(player, 10);
    await backend
        .repository(player)
        .submitCommit(
          command: _command('commit-$player', player, 'COMMIT', opened.roundId),
          commitment: contract.commit(
            sessionRound: opened.sessionRound,
            playerId: player,
            choice: choice,
            nonce: 'nonce-$player',
          ),
        );
  }
  for (final player in ['alice', 'bob']) {
    await backend
        .repository(player)
        .submitReveal(
          command: _command('reveal-$player', player, 'REVEAL', opened.roundId),
          reveal: ChoiceRevealDto(
            sessionRound: opened.sessionRound,
            playerId: player,
            choice: _choice(player, 10),
            nonce: 'nonce-$player',
          ),
        );
  }
  await alice.submitInitialResolution(
    command: _command('resolve', 'alice', 'INITIAL_RESOLVE', opened.roundId),
    resolution: NetworkInitialResolutionDto(
      tied: true,
      gap: 0,
      gapCost: 0,
      actionPoints: backend.points,
    ),
  );
}

ChoicePayload _choice(String player, int value) => ChoicePayload(
  cardId: 'card.$player',
  variantId: 'variant.$player',
  parameters: {
    'role': 'FAIRE',
    'personal_value': value,
    'committed_at': '2026-09-30T12:00:00.000Z',
  },
);

NetworkCommandDto _command(
  String id,
  String player,
  String type, [
  String? roundId,
]) => NetworkCommandDto(
  commandId: id,
  sessionId: 'session-multi',
  playerId: player,
  type: type,
  payload: {'round_id': ?roundId},
);

Future<void> _settle() async {
  for (var index = 0; index < 20; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}

final class _RoundRecord {
  _RoundRecord(this.number) : id = 'round-$number';
  final int number;
  final String id;
  NetworkGamePhase phase = NetworkGamePhase.commit;
  final commits = <String, ChoiceCommitmentDto>{};
  final reveals = <String, ChoiceRevealDto>{};
  NetworkInitialResolutionDto? initial;
  NetworkAuctionBidDto? counter;
  NetworkAuctionBidDto? defense;
  NetworkFinalResolutionDto? finalResolution;
  NetworkCorruptionDto? corruption;
  final recoveries = <String, NetworkRecoveryDto>{};
  final recoveryDone = <String>{};
  final ready = <String>{};
  final ties = <String, TieDecision>{};
}

final class _Backend {
  final rounds = <int, _RoundRecord>{1: _RoundRecord(1)};
  final points = <String, int>{'alice': 100, 'bob': 100};
  final commands = <String>{};
  final changes = StreamController<void>.broadcast();
  int currentRound = 1;
  int roundCreations = 1;
  int initialApplications = 0;
  int counterApplications = 0;
  int defenseApplications = 0;

  _RoundRecord get round => rounds[currentRound]!;
  NetworkGamePhase get phase => round.phase;
  NetworkGameRepository repository(String player) => _Repository(this, player);

  NetworkGameRoundStateDto state(String player) => NetworkGameRoundStateDto(
    roundId: round.id,
    sessionId: 'session-multi',
    sessionRound: 'session-multi.round-${round.number}',
    roundNumber: round.number,
    phase: round.phase,
    playerId: player,
    commits: {
      for (final entry in round.commits.entries) entry.key: entry.value.digest,
    },
    actionPoints: points,
    readyNextPlayerIds: round.ready,
    tieDecisions: round.ties,
    ownReveal: round.reveals[player],
    opponentReveal: _revealsPublic
        ? round.reveals.entries
              .where((entry) => entry.key != player)
              .map((entry) => entry.value)
              .firstOrNull
        : null,
    initialResolution: round.initial,
    counterBid: round.counter,
    finalDefense: round.defense,
    finalResolution: round.finalResolution,
    corruption: round.corruption,
    recoveryByPlayer: round.recoveries,
    recoveryDonePlayerIds: round.recoveryDone,
  );

  bool get _revealsPublic => round.phase == NetworkGamePhase.ready;

  void notify() => changes.add(null);
  void notifyTwice() {
    notify();
    notify();
  }
}

final class _Repository
    implements
        NetworkGameRepository,
        NetworkCommitCancellationRepository,
        NetworkSessionClosureRepository {
  _Repository(this.backend, this.player);
  final _Backend backend;
  final String player;

  bool _accept(NetworkCommandDto command) =>
      backend.commands.add(command.commandId);
  void _notify() => backend.notify();

  @override
  Future<NetworkGameRoundStateDto> openCurrentRound({
    required NetworkCommandDto command,
  }) async {
    _accept(command);
    return backend.state(player);
  }

  @override
  Future<NetworkGameRoundStateDto> getCurrentRound({
    required String sessionId,
  }) async => backend.state(player);

  @override
  Future<NetworkGameRoundStateDto> submitCommit({
    required NetworkCommandDto command,
    required ChoiceCommitmentDto commitment,
  }) async {
    if (!_accept(command)) return backend.state(player);
    if (backend.phase != NetworkGamePhase.commit) {
      throw const NetworkRoundException('ROUND_COMMIT_CLOSED');
    }
    backend.round.commits[player] = commitment;
    if (backend.round.commits.length == 2) {
      backend.round.phase = NetworkGamePhase.reveal;
    }
    _notify();
    return backend.state(player);
  }

  @override
  Future<NetworkGameRoundStateDto> submitReveal({
    required NetworkCommandDto command,
    required ChoiceRevealDto reveal,
  }) async {
    if (backend.phase != NetworkGamePhase.reveal) {
      throw const NetworkRoundException('ROUND_REVEAL_CLOSED');
    }
    if (!const CommitRevealContract().verify(
      backend.round.commits[player]!,
      reveal,
    )) {
      throw const NetworkRoundException('ROUND_REVEAL_MISMATCH');
    }
    if (!_accept(command)) return backend.state(player);
    backend.round.reveals[player] = reveal;
    if (backend.round.reveals.length == 2) {
      backend.round.phase = NetworkGamePhase.ready;
    }
    _notify();
    return backend.state(player);
  }

  @override
  Future<NetworkGameRoundStateDto> cancelCommit({
    required NetworkCommandDto command,
  }) async {
    if (!backend.commands.add(command.commandId)) return backend.state(player);
    if (backend.phase != NetworkGamePhase.commit) {
      throw const NetworkRoundException('ROUND_CANCEL_CLOSED');
    }
    if (backend.round.commits.remove(player) == null) {
      throw const NetworkRoundException('ROUND_COMMIT_MISSING');
    }
    _notify();
    return backend.state(player);
  }

  @override
  Future<NetworkGameRoundStateDto> closeSession({
    required NetworkCommandDto command,
  }) async {
    if (!backend.commands.add(command.commandId)) return backend.state(player);
    backend.round.phase = NetworkGamePhase.sessionClosed;
    _notify();
    return backend.state(player);
  }

  @override
  Future<NetworkGameRoundStateDto> submitInitialResolution({
    required NetworkCommandDto command,
    required NetworkInitialResolutionDto resolution,
  }) async {
    if (backend.round.initial != null) {
      if (backend.round.initial!.toJson().toString() !=
          resolution.toJson().toString()) {
        throw const NetworkRoundException('ROUND_RESOLUTION_MISMATCH');
      }
      _accept(command);
      return backend.state(player);
    }
    if (!_accept(command)) return backend.state(player);
    if (backend.phase != NetworkGamePhase.ready) {
      throw const NetworkRoundException('ROUND_INVALID_PHASE');
    }
    backend.round.initial = resolution;
    backend.points
      ..clear()
      ..addAll(resolution.actionPoints);
    backend.round.phase = resolution.tied
        ? NetworkGamePhase.tieDecision
        : NetworkGamePhase.counterDecision;
    backend.initialApplications++;
    _notify();
    return backend.state(player);
  }

  @override
  Future<NetworkGameRoundStateDto> submitCounterDecision({
    required NetworkCommandDto command,
    required CounterDecision decision,
    int? amount,
    AuctionTarget? target,
  }) async {
    if (!_accept(command)) return backend.state(player);
    final initial = backend.round.initial!;
    if (backend.phase != NetworkGamePhase.counterDecision ||
        initial.loserPlayerId != player) {
      throw const NetworkRoundException('ROUND_INVALID_PHASE');
    }
    if (decision == CounterDecision.accept) {
      backend.round.finalResolution = _finalChoice(
        initial.winnerPlayerId!,
        initial.winnerPlayerId!,
      );
      backend.round.phase = NetworkGamePhase.finalResolved;
    } else {
      if (amount == null || amount <= 0 || amount > backend.points[player]!) {
        throw const NetworkRoundException('ROUND_INVALID_BID');
      }
      if (target == AuctionTarget.INVERT_WINNING_ACTION &&
          !initial.inversionAllowed) {
        throw const NetworkRoundException('ROUND_INVERSION_FORBIDDEN');
      }
      backend.points[player] = backend.points[player]! - amount;
      backend.round.counter = NetworkAuctionBidDto(
        playerId: player,
        amount: amount,
        target: target!,
      );
      backend.round.phase = NetworkGamePhase.finalDefenseDecision;
      backend.counterApplications++;
    }
    _notify();
    return backend.state(player);
  }

  @override
  Future<NetworkGameRoundStateDto> submitFinalDefense({
    required NetworkCommandDto command,
    required FinalDefenseDecision decision,
    int? amount,
  }) async {
    if (!_accept(command)) return backend.state(player);
    final initial = backend.round.initial!;
    final counter = backend.round.counter!;
    if (backend.phase != NetworkGamePhase.finalDefenseDecision ||
        initial.winnerPlayerId != player) {
      throw const NetworkRoundException('ROUND_INVALID_PHASE');
    }
    if (decision == FinalDefenseDecision.defend) {
      if (amount == null ||
          amount <= counter.amount ||
          amount > backend.points[player]!) {
        throw const NetworkRoundException('ROUND_INVALID_BID');
      }
      backend.points[player] = backend.points[player]! - amount;
      backend.round.defense = NetworkAuctionBidDto(
        playerId: player,
        amount: amount,
        target: counter.target,
      );
      backend.round.finalResolution = _finalChoice(player, player);
      backend.defenseApplications++;
    } else if (counter.target == AuctionTarget.OWN_INITIAL_ACTION) {
      backend.round.finalResolution = _finalChoice(
        initial.loserPlayerId!,
        initial.loserPlayerId!,
      );
    } else {
      backend.round.finalResolution = _finalChoice(
        initial.winnerPlayerId!,
        initial.loserPlayerId!,
        inverted: true,
      );
    }
    backend.round.phase = NetworkGamePhase.finalResolved;
    _notify();
    return backend.state(player);
  }

  NetworkFinalResolutionDto _finalChoice(
    String choicePlayer,
    String retained, {
    bool inverted = false,
  }) {
    final choice = backend.round.reveals[choicePlayer]!.choice;
    return NetworkFinalResolutionDto(
      retainedPlayerId: retained,
      cardId: choice.cardId,
      variantId: choice.variantId,
      inverted: inverted,
    );
  }

  @override
  Future<NetworkGameRoundStateDto> submitTieDecision({
    required NetworkCommandDto command,
    required TieDecision decision,
  }) async {
    if (!_accept(command)) return backend.state(player);
    if (backend.phase != NetworkGamePhase.tieDecision) {
      throw const NetworkRoundException('ROUND_INVALID_PHASE');
    }
    backend.round.ties[player] = decision;
    if (decision == TieDecision.concede) {
      final other = player == 'alice' ? 'bob' : 'alice';
      backend.round.finalResolution = _finalChoice(other, other);
      backend.round.phase = NetworkGamePhase.finalResolved;
    } else if (backend.round.ties.length == 2 &&
        backend.round.ties.values.every(
          (value) => value == TieDecision.abandon,
        )) {
      backend.round.finalResolution = const NetworkFinalResolutionDto(
        mutualAbandon: true,
      );
      backend.round.phase = NetworkGamePhase.finalResolved;
    }
    _notify();
    return backend.state(player);
  }

  @override
  Future<NetworkGameRoundStateDto> submitCorruptionOffer({
    required NetworkCommandDto command,
    required CorruptionObjective objective,
    required List<ActionPromise> actions,
  }) async {
    if (!_accept(command)) return backend.state(player);
    if (backend.phase != NetworkGamePhase.corruptionDecision ||
        actions.isEmpty) {
      throw const NetworkRoundException('ROUND_INVALID_PHASE');
    }
    backend.round.corruption = NetworkCorruptionDto(
      offeredBy: player,
      objective: objective,
      actions: actions,
    );
    backend.round.phase = NetworkGamePhase.corruptionResponse;
    _notify();
    return backend.state(player);
  }

  @override
  Future<NetworkGameRoundStateDto> respondCorruption({
    required NetworkCommandDto command,
    required bool accepted,
  }) async {
    if (!_accept(command)) return backend.state(player);
    final offer = backend.round.corruption!;
    backend.round.corruption = NetworkCorruptionDto(
      offeredBy: offer.offeredBy,
      objective: offer.objective,
      actions: offer.actions,
      accepted: accepted,
    );
    backend.round.phase = accepted
        ? NetworkGamePhase.corruptionExecution
        : NetworkGamePhase.recovery;
    _notify();
    return backend.state(player);
  }

  @override
  Future<NetworkGameRoundStateDto> resolveCorruption({
    required NetworkCommandDto command,
    required List<ActionPromise> actions,
  }) async {
    if (!_accept(command)) return backend.state(player);
    final offer = backend.round.corruption!;
    backend.round.corruption = NetworkCorruptionDto(
      offeredBy: offer.offeredBy,
      objective: offer.objective,
      actions: actions,
      accepted: true,
    );
    backend.round.phase = NetworkGamePhase.recovery;
    _notify();
    return backend.state(player);
  }

  @override
  Future<NetworkGameRoundStateDto> skipCorruption({
    required NetworkCommandDto command,
  }) async {
    if (!_accept(command)) return backend.state(player);
    backend.round.phase = NetworkGamePhase.recovery;
    _notify();
    return backend.state(player);
  }

  @override
  Future<NetworkGameRoundStateDto> submitRecovery({
    required NetworkCommandDto command,
    required NetworkRecoveryDto recovery,
  }) async {
    if (!_accept(command)) return backend.state(player);
    if (backend.phase != NetworkGamePhase.recovery ||
        backend.round.recoveryDone.contains(player) ||
        backend.points[player]! > 20) {
      throw const NetworkRoundException('ROUND_RECOVERY_NOT_ELIGIBLE');
    }
    backend.round.recoveries[player] = recovery;
    backend.round.phase = NetworkGamePhase.recoveryResponse;
    _notify();
    return backend.state(player);
  }

  @override
  Future<NetworkGameRoundStateDto> respondRecovery({
    required NetworkCommandDto command,
    required RecoveryResponse response,
  }) async {
    if (!_accept(command)) return backend.state(player);
    final entry = backend.round.recoveries.entries.singleWhere(
      (item) => !backend.round.recoveryDone.contains(item.key),
    );
    final proposal = entry.value;
    backend.round.recoveries[entry.key] = NetworkRecoveryDto(
      playerId: proposal.playerId,
      cardId: proposal.cardId,
      variantId: proposal.variantId,
      source: proposal.source,
      completed: false,
      gain: proposal.gain,
      response: response,
      occurrenceId: proposal.occurrenceId,
    );
    if (response == RecoveryResponse.REFUSE) {
      backend.round.recoveryDone.add(entry.key);
      backend.round.phase = backend.round.recoveryDone.length == 2
          ? NetworkGamePhase.finalResolved
          : NetworkGamePhase.recovery;
    } else {
      backend.round.phase = NetworkGamePhase.recoveryExecution;
    }
    _notify();
    return backend.state(player);
  }

  @override
  Future<NetworkGameRoundStateDto> resolveRecovery({
    required NetworkCommandDto command,
    required NetworkRecoveryDto recovery,
  }) async {
    if (!_accept(command)) return backend.state(player);
    backend.round.recoveries[recovery.playerId] = recovery;
    backend.round.recoveryDone.add(recovery.playerId);
    backend.points[recovery.playerId] =
        backend.points[recovery.playerId]! + recovery.gain;
    backend.round.phase = backend.round.recoveryDone.length == 2
        ? NetworkGamePhase.finalResolved
        : NetworkGamePhase.recovery;
    _notify();
    return backend.state(player);
  }

  @override
  Future<NetworkGameRoundStateDto> skipRecovery({
    required NetworkCommandDto command,
  }) async {
    if (!_accept(command)) return backend.state(player);
    backend.round.recoveryDone.add(player);
    if (backend.round.recoveryDone.length == 2) {
      backend.round.phase = NetworkGamePhase.finalResolved;
    }
    _notify();
    return backend.state(player);
  }

  @override
  Future<NetworkGameRoundStateDto> readyNextRound({
    required NetworkCommandDto command,
  }) async {
    if (!_accept(command)) return backend.state(player);
    if (backend.phase != NetworkGamePhase.finalResolved &&
        backend.phase != NetworkGamePhase.waitingNext) {
      throw const NetworkRoundException('ROUND_INVALID_PHASE');
    }
    backend.round.ready.add(player);
    if (backend.round.ready.length == 1) {
      backend.round.phase = NetworkGamePhase.waitingNext;
    } else {
      backend.round.phase = NetworkGamePhase.closed;
      backend.currentRound++;
      backend.rounds.putIfAbsent(backend.currentRound, () {
        backend.roundCreations++;
        return _RoundRecord(backend.currentRound);
      });
    }
    _notify();
    return backend.state(player);
  }

  @override
  Stream<NetworkGameRoundStateDto> watchRound({
    required String sessionId,
    required String roundId,
  }) async* {
    yield backend.state(player);
    await for (final _ in backend.changes.stream) {
      yield backend.state(player);
    }
  }
}
