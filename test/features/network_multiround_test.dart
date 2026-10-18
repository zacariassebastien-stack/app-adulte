import 'package:flutter/services.dart';
import 'package:couple_cards/sync/projection/usage_learning_projection.dart';
import 'package:couple_cards/features/lobby/two_phone_lobby_screen.dart';
import 'package:couple_cards/features/lobby/lobby_repository.dart';
import '../support/native_action_fixtures.dart';
import '../support/native_usage_fixture.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:couple_cards/data/catalog_loader/catalog_loader.dart';
import 'package:couple_cards/domain/domain.dart';
import 'package:couple_cards/engines/engines.dart';
import 'package:couple_cards/features/game/network_duel_secret_store.dart';
import 'package:couple_cards/features/game/network_game_controller.dart';
import 'package:couple_cards/features/game/network_duel_screen.dart';
import 'package:couple_cards/features/game/network_profile_learning.dart';
import 'package:couple_cards/features/lobby/lobby_models.dart';
import 'package:couple_cards/features/lobby/active_session_store.dart';
import 'package:couple_cards/features/lobby/game_history.dart';
import 'package:couple_cards/sync/sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Catalog catalog;
  late V4ScoringCatalog scoringCatalog;
  late LobbySession session;

  setUpAll(() async {
    catalog = await const CatalogLoader().load(
      (path) => File(path).readAsString(),
      includeConcepts: true,
    );
    scoringCatalog = V4ScoringCatalog.decode(
      File('assets/catalog/source/catalog_v4_scoring.json').readAsStringSync(),
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

  for (final last in ['alice', 'bob']) {
    test(
      'next round clears old reveal when $last misses the boundary',
      () async {
        final setup = await _setup(session, catalog);
        addTearDown(setup.dispose);
        await _playUnequal(setup);
        await (setup.alice.isInitialLoser ? setup.alice : setup.bob)
            .skipCorruption();
        await _settle();
        final first = last == 'alice' ? setup.bob : setup.alice;
        final second = last == 'alice' ? setup.alice : setup.bob;
        setup.backend.missedBoundaryPlayer = last;
        setup.backend.delayedCompletionPlayer = last;
        setup.backend.completionResponse = Completer<void>();
        await first.completeAction();
        await _settle();
        final completion = second.completeAction();
        await _settle();
        expect(setup.backend.currentRound, 2);
        expect(second.roundNumber, 2);
        expect(
          second.selectedCard,
          isNull,
          reason: 'new round must not retain the previous committed choice',
        );
        setup.backend.completionResponse!.complete();
        await completion;
        await _settle();
        expect(setup.backend.roundCreations, 2);
        expect(setup.backend.round.commits, isEmpty);
        await Future.wait([
          setup.alice.retryCurrentAction(),
          setup.bob.retryCurrentAction(),
        ]);
        await _playUnequal(setup);
        for (final entry in setup.backend.round.reveals.entries) {
          expect(entry.value.sessionRound, 'session-multi.round-2');
          expect(
            const CommitRevealContract().verify(
              setup.backend.round.commits[entry.key]!,
              entry.value,
            ),
            isTrue,
          );
        }
        expect(setup.alice.errorMessage, isNull);
        expect(setup.bob.errorMessage, isNull);
      },
    );
  }

  test(
    'free zone engagement stores base spice without anatomical evidence',
    () async {
      final store = MemoryNetworkDuelSecretStore();
      final setup = await _setup(
        session,
        _catalogWithCards(catalog, {'card.v4.002'}),
        aliceSecrets: store,
      );
      addTearDown(setup.dispose);
      final free = setup.alice
          .choicesFor('002')
          .where((o) => o.choice.actionId == '002.zone.free')
          .toList();
      expect(free, hasLength(1));
      expect(free.single.choice.zoneId, isNull);
      expect(free.single.choice.chili, 1);
      setup.alice.selectCard('002');
      setup.alice.chooseAction(free.single);
      await setup.alice.confirmSelection();
      final saved = (await store.loadGame(
        sessionId: session.id,
        playerId: 'alice',
      ))!;
      final usage = saved.activeReveal!.choice.usage!;
      expect(usage.resolvedAction.containsKey('zone_id'), isFalse);
      expect(usage.resolvedAction['effective_chili'], 1);
      expect(
        usage.resolvedAction['action_text'],
        'Choisis librement une zone à embrasser.',
      );
      expect(
        (usage.resolvedAction['tags'] as List).where(
          (tag) => (tag as String).startsWith('v3.zone.'),
        ),
        isEmpty,
      );
      final evidence = const V3LearningTagProjector().project(
        usageLearningDescriptor(usage),
      );
      expect(evidence, isNotEmpty);
      expect(evidence.every((e) => e.key.zoneId == null), isTrue);
      await setup.alice.retryCurrentAction();
      expect(
        (await store.loadGame(
          sessionId: session.id,
          playerId: 'alice',
        ))!.activeReveal!.nonce,
        saved.activeReveal!.nonce,
      );
      expect(setup.alice.usageCheckpoint.usagesByIntent, hasLength(1));
    },
  );

  for (final player in ['alice', 'bob']) {
    for (final stage in [
      'preparation',
      'playing',
      'cycle',
      'restored-playing',
    ]) {
      testWidgets(
        'leaving $stage as $player returns to menu despite pending lobby cancellation',
        (tester) async {
          rootBundle.clear();
          tester.binding.defaultBinaryMessenger.setMockMessageHandler(
            'flutter/assets',
            (data) async {
              final file = File(utf8.decode(data!.buffer.asUint8List()));
              return file.existsSync()
                  ? ByteData.sublistView(file.readAsBytesSync())
                  : null;
            },
          );
          addTearDown(
            () => tester.binding.defaultBinaryMessenger.setMockMessageHandler(
              'flutter/assets',
              null,
            ),
          );

          SharedPreferences.setMockInitialValues(<String, Object>{});
          final backend = _Backend();
          if (stage == 'cycle') {
            backend.cycleExhausted = true;
            backend.round.phase = NetworkGamePhase.waitingNext;
          }
          final store = _MemoryActiveSessionStore();
          if (stage == 'restored-playing') store.value = session.id;
          final cancellation = Completer<void>();
          addTearDown(() {
            if (!cancellation.isCompleted) cancellation.complete();
          });
          final lobby = _MenuLobbyRepository(
            session,
            _PreparedRepository(backend, player, stage != 'preparation'),
            playerId: player,
            cancellation: cancellation,
          );
          await tester.pumpWidget(
            MaterialApp(
              home: TwoPhoneLobbyScreen(
                repository: lobby,
                activeSessionStore: store,
                historyStore: MemoryGameHistoryStore(),
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (stage != 'restored-playing') {
            await tester.tap(find.byKey(const Key('create-lobby')));
            await tester.pumpAndSettle();
            await tester.tap(find.byKey(const Key('launch-network-duel')));
          }
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 300)),
          );
          for (var i = 0; i < 30; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)),
            );
            await tester.pump(const Duration(milliseconds: 50));
          }
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await tester.pumpAndSettle();
          if (stage == 'preparation') {
            await tester.pageBack();
          } else {
            if (stage == 'restored-playing') {
              expect(store.value, session.id);
              expect(find.byKey(const Key('game-status')), findsOneWidget);
            }
            await tester.tap(
              find.byKey(const Key('open-private-profile-settings')),
            );
            await tester.pumpAndSettle();
            await tester.ensureVisible(
              find.byKey(const Key('quit-network-game')),
            );
            await tester.tap(find.byKey(const Key('quit-network-game')));
            await tester.pumpAndSettle();
            await tester.tap(find.byKey(const Key('confirm-quit-game')));
          }
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('create-lobby')), findsOneWidget);
          expect(find.byKey(const Key('show-join-lobby')), findsOneWidget);
          expect(find.byKey(const Key('lobby-ready')), findsNothing);
          expect(store.value, isNull);
          if (stage != 'preparation') {
            expect(backend.phase, NetworkGamePhase.sessionClosed);
            expect(backend.closeApplications, 1);
          }
          expect(tester.takeException(), isNull);
          // The transport has not acknowledged cancellation, but quit must
          // already be durable and must not auto-resume after reconstruction.
          expect(cancellation.isCompleted, isFalse);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpWidget(
            MaterialApp(
              home: TwoPhoneLobbyScreen(
                repository: lobby,
                activeSessionStore: store,
                historyStore: MemoryGameHistoryStore(),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('create-lobby')), findsOneWidget);
          expect(find.byKey(const Key('launch-network-duel')), findsNothing);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
  for (final id in ['alice', 'bob']) {
    testWidgets('RECEVOIR order gives the correct instruction to $id', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final backend = _Backend();
      final usage = nativeUsageFixture(
        owner: 'alice',
        conceptId: '032',
        direction: 'RECEVOIR',
      );
      _setProjectedAction(
        backend,
        cards: [NetworkResolvedActionCardDto.fromUsage(usage)],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: NetworkDuelScreen(
            session: session,
            playerId: id,
            repository: backend.repository(id),
            catalog: catalog,
            secretStore: MemoryNetworkDuelSecretStore(),
          ),
        ),
      );
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(
        find.text(
          id == 'alice'
              ? "Ton partenaire choisit l’ordre que tu devras suivre."
              : "Choisis l’ordre que ton partenaire devra suivre.",
        ),
        findsOneWidget,
      );
      expect(find.textContaining('cible :'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  test(
    'reconnect after a missed round boundary preserves quota and clears old secret',
    () async {
      final store = MemoryNetworkDuelSecretStore();
      final setup = await _setup(session, catalog, bobSecrets: store);
      await _playUnequal(setup);
      await (setup.alice.isInitialLoser ? setup.alice : setup.bob)
          .skipCorruption();
      await _settle();
      final before = (await store.loadGame(
        sessionId: session.id,
        playerId: 'bob',
      ))!;
      setup.bob.dispose();
      await setup.alice.completeAction();
      await setup.backend
          .repository('bob')
          .readyNextRound(
            command: _command(
              'offline-complete',
              'bob',
              'ACTION_COMPLETE',
              'round-1',
            ),
          );
      await _settle();
      expect(setup.backend.currentRound, 2);
      final bob = _controller(setup.backend, session, catalog, 'bob', store);
      addTearDown(() {
        setup.alice.dispose();
        bob.dispose();
      });
      await bob.start();
      await _settle();
      expect(bob.roundNumber, 2);
      expect(bob.selectedCard, isNull);
      expect(
        bob.usageCheckpoint.stock.remaining,
        before.conceptCheckpoint!.stock.remaining,
      );
      expect(
        bob.usageCheckpoint.usagesByIntent.length,
        before.conceptCheckpoint!.usagesByIntent.length,
      );
      final saved = (await store.loadGame(
        sessionId: session.id,
        playerId: 'bob',
      ))!;
      expect(saved.activeReveal, isNull);
      await _playUnequal(_Setup(setup.backend, setup.alice, bob));
      expect(bob.errorMessage, isNull);
      expect(
        setup.backend.round.reveals['bob']!.sessionRound,
        'session-multi.round-2',
      );
    },
  );

  for (final id in ['alice', 'bob']) {
    testWidgets('post duel keeps both public cards visible for $id', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final backend = await tester.runAsync(() async {
        final setup = await _setup(session, catalog);
        setup.backend.routeToUnifiedPostDuelChoice = true;
        await _playUnequal(setup);
        setup.dispose();
        return setup.backend;
      });
      final winner = backend!.round.initial!.winnerPlayerId == id;
      await tester.pumpWidget(
        MaterialApp(
          home: NetworkDuelScreen(
            session: session,
            playerId: id,
            repository: backend.repository(id),
            catalog: catalog,
            secretStore: MemoryNetworkDuelSecretStore(),
          ),
        ),
      );
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(
        find.text(
          winner
              ? 'Tu as gagné le duel.\nEn attente de la réponse de ton partenaire…'
              : 'Tu as perdu le duel.\nChoisis la suite.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('initial-duel-card-alice')), findsOneWidget);
      expect(find.byKey(const Key('initial-duel-card-bob')), findsOneWidget);
      final bounds = tester.getRect(
        find.byKey(const Key('initial-duel-cards')),
      );
      expect(
        bounds.top,
        greaterThan(
          tester.view.physicalSize.height / tester.view.devicePixelRatio * .6,
        ),
      );
      expect(
        find.byKey(const Key('choose-negotiation')),
        winner ? findsNothing : findsOneWidget,
      );
      if (!winner) {
        await tester.tap(find.byKey(const Key('choose-negotiation')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('initial-duel-card-alice')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('initial-duel-card-bob')), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  test('watchRound cancellation detaches without another backend event', () async {
    final backend = _Backend();
    final repository = backend.repository('alice');
    final snapshots = <NetworkGameRoundStateDto>[];
    final initial = Completer<void>();
    final subscription = repository
        .watchRound(sessionId: session.id, roundId: backend.round.id)
        .listen((snapshot) {
          snapshots.add(snapshot);
          if (!initial.isCompleted) initial.complete();
        });
    await initial.future;
    await _settle();
    expect(backend.changes.hasListener, isTrue);

    // No backend event is emitted to release cancellation of the old round.
    await subscription.cancel();
    expect(backend.changes.hasListener, isFalse);
    expect(snapshots, hasLength(1));

    final replacementInitial = Completer<void>();
    final replacementSnapshots = <NetworkGameRoundStateDto>[];
    final replacement = repository
        .watchRound(sessionId: session.id, roundId: backend.round.id)
        .listen((snapshot) {
          replacementSnapshots.add(snapshot);
          if (!replacementInitial.isCompleted) replacementInitial.complete();
        });
    await replacementInitial.future;
    backend.notify();
    await _settle();
    expect(snapshots, hasLength(1));
    expect(replacementSnapshots, hasLength(2));
    await replacement.cancel();
    expect(backend.changes.hasListener, isFalse);
    await backend.changes.close();
  });

  test(
    'shared canonical cycle resets the non-exhausted peer and retries once',
    () async {
      // 006 has min(2, initial clothing) uses: Alice has two, Bob only one.
      // Playing it once therefore exhausts Bob without exhausting Alice.
      final focusedCatalog = _catalogWithCards(catalog, {'card.v4.006'});
      const clothing = {'alice': 2, 'bob': 1};
      final backend = _Backend();
      backend.clothingCounts
        ..clear()
        ..addAll(clothing);
      NetworkGameController controller(String playerId, int value) =>
          NetworkGameController(
            session: session,
            playerId: playerId,
            repository: backend.repository(playerId),
            privateStore: MemoryNetworkDuelSecretStore(),
            learningStore: MemoryNetworkProfileLearningStore(),
            catalog: focusedCatalog,
            initialClothingCounts: clothing,
            privateProfile: PlayerGameProfile(
              playerId: playerId,
              preferences: {
                for (final tag in ['enlever', 'tenue'])
                  'v3.preference.$tag': PreferenceValue(
                    status: PreferenceStatus.ACCEPTED,
                    general: value,
                    faire: value,
                    recevoir: value,
                  ),
              },
            ),
          );
      final setup = _Setup(
        backend,
        controller('alice', 8),
        controller('bob', 12),
      );
      addTearDown(setup.dispose);
      await Future.wait([setup.alice.start(), setup.bob.start()]);
      expect(setup.alice.usageCheckpoint.stock.remainingFor('006'), 2);
      expect(setup.bob.usageCheckpoint.stock.remainingFor('006'), 1);
      expect(setup.backend.deckCycle, 1);

      await _playUnequal(setup);
      final loser = setup.alice.isInitialLoser ? setup.alice : setup.bob;
      await loser.skipCorruption();
      await _settle();
      final oldUsages = {
        for (final player in [setup.alice, setup.bob])
          player.playerId: player.usageCheckpoint.usagesByIntent.values
              .map((usage) => usage.usageId)
              .toSet(),
      };
      expect(setup.bob.usageCheckpoint.availableFor('006'), 0);
      expect(
        setup.bob.usageCheckpoint.stock.remaining.values.every((n) => n == 0),
        isTrue,
      );
      expect(setup.alice.usageCheckpoint.availableFor('006'), 1);
      expect(setup.alice.choicesFor('006'), isNotEmpty);
      expect(setup.backend.phase, NetworkGamePhase.finalResolved);
      expect(setup.backend.round.ready, isEmpty);
      expect(setup.backend.cycleExhausted, isFalse);

      // Exhaustion is reported by the first Terminé, not by bypassing the guard.
      await setup.bob.completeAction();
      await _settle();
      expect(setup.backend.round.ready, {'bob'});
      expect(setup.backend.phase, NetworkGamePhase.finalResolved);
      expect(setup.backend.cycleExhausted, isTrue);
      expect(setup.alice.usageCheckpoint.availableFor('006'), 1);
      await setup.alice.completeAction();
      await _settle();
      expect(setup.backend.round.ready, {'alice', 'bob'});
      expect(setup.backend.phase, NetworkGamePhase.waitingNext);
      expect(setup.alice.viewState, NetworkGameViewState.waitingNext);
      expect(setup.bob.viewState, NetworkGameViewState.waitingNext);
      expect(setup.alice.deckExhausted, isTrue);
      expect(setup.bob.deckExhausted, isTrue);
      expect(setup.alice.usageCheckpoint.availableFor('006'), 1);

      final repository =
          setup.backend.repository('bob') as NetworkSessionFlowRepository;
      final command = NetworkCommandDto(
        sessionId: session.id,
        type: 'CONTINUE_CYCLE',
        payload: {'round_id': setup.backend.round.id},
        playerId: 'bob',
        commandId: 'cycle-bob',
      );
      await repository.continueDeckCycle(
        expectedCycle: 1,
        command: command,
        choice: DeckExhaustionChoice.keepStyle,
      );
      await _settle();
      expect(setup.backend.deckCycle, 2);
      expect(setup.backend.cycleExhausted, isFalse);
      for (final player in [setup.alice, setup.bob]) {
        expect(player.usageCheckpoint.cycle, 2);
        expect(player.usageCheckpoint.usagesByIntent, isEmpty);
        expect(player.usageCheckpoint.reservationsByIntent, isEmpty);
        for (final entry in player.usageCheckpoint.stock.capacity.entries) {
          expect(
            player.usageCheckpoint.stock.remainingFor(entry.key),
            entry.value,
          );
        }
        expect(player.hand, isNotEmpty);
        expect(player.hand.map((c) => c.id).toSet().length, player.hand.length);
        final saved = (await player.privateStore.loadGame(
          sessionId: session.id,
          playerId: player.playerId,
        ))!;
        expect(saved.deckCycle, 2);
        expect(saved.conceptCheckpoint!.cycle, 2);
        expect(
          saved.conceptCheckpoint!.encode(),
          player.usageCheckpoint.encode(),
        );
        expect(
          saved.priorCheckpoints
              .expand((c) => c.usagesByIntent.values)
              .map((u) => u.usageId)
              .toSet(),
          containsAll(oldUsages[player.playerId]!),
        );
      }
      expect(setup.alice.usageCheckpoint.stock.remainingFor('006'), 2);
      expect(setup.bob.usageCheckpoint.stock.remainingFor('006'), 1);
      final checkpoints = {
        for (final player in [setup.alice, setup.bob])
          player.playerId: player.usageCheckpoint.encode(),
      };
      final style = setup.backend.deckStyle;
      await repository.continueDeckCycle(
        expectedCycle: 1,
        command: command,
        choice: DeckExhaustionChoice.keepStyle,
      );
      await _settle();
      expect(setup.backend.deckCycle, 2);
      for (final player in [setup.alice, setup.bob]) {
        expect(player.usageCheckpoint.encode(), checkpoints[player.playerId]);
      }
      await (setup.backend.repository('alice') as NetworkSessionFlowRepository)
          .continueDeckCycle(
            expectedCycle: 1,
            command: NetworkCommandDto(
              sessionId: session.id,
              type: 'CONTINUE_CYCLE',
              payload: {'round_id': setup.backend.round.id},
              playerId: 'alice',
              commandId: 'cycle-concurrent',
            ),
            choice: DeckExhaustionChoice.infinite,
          );
      await _settle();
      expect(setup.backend.deckCycle, 2);
      expect(setup.backend.deckStyle, style);
      expect(setup.backend.infiniteMode, isFalse);
      for (final player in [setup.alice, setup.bob]) {
        expect(player.usageCheckpoint.encode(), checkpoints[player.playerId]);
      }
    },
  );

  test(
    'concept reservation can be cancelled before engagement without quota loss',
    () async {
      final setup = await _setup(session, catalog);
      addTearDown(setup.dispose);
      final card = setup.alice.hand.first;
      final before = setup.alice.usageCheckpoint.stock.remainingFor(card.id);
      setup.alice.selectCard(card.identity);
      await setup.alice.reserveSelection();
      expect(setup.alice.usageCheckpoint.availableFor(card.id), before - 1);
      expect(setup.alice.usageCheckpoint.stock.remainingFor(card.id), before);
      await setup.alice.cancelPendingSelection();
      expect(setup.alice.usageCheckpoint.availableFor(card.id), before);
      expect(setup.alice.usageCheckpoint.usagesByIntent, isEmpty);
      expect(setup.backend.round.commits, isEmpty);
    },
  );

  test(
    'native usage and quota survive retry and controller reconstruction',
    () async {
      final backend = _Backend();
      final store = MemoryNetworkDuelSecretStore();
      var controller = _controller(backend, session, catalog, 'alice', store);
      await controller.start();
      final card = controller.hand.first;
      controller.selectCard(card.identity);
      await controller.reserveSelection();
      controller.chooseAction(controller.choicesFor(card.id).first);
      await controller.confirmSelection();
      final saved = (await store.loadGame(
        sessionId: session.id,
        playerId: 'alice',
      ))!;
      final encoded = saved.conceptCheckpoint!.encode();
      final usage = saved.activeReveal!.choice.usageId;
      expect(usage, startsWith('usage:v1:'));
      expect(
        saved.activeReveal!.choice.toJson(),
        isNot(contains('occurrence_id')),
      );
      await controller.retryCurrentAction();
      expect(controller.usageCheckpoint.encode(), encoded);
      controller.dispose();
      controller = _controller(backend, session, catalog, 'alice', store);
      addTearDown(controller.dispose);
      await controller.start();
      expect(controller.usageCheckpoint.encode(), encoded);
      expect(controller.selectedCard!.identity, usage);
      expect(
        controller.selectedCard!.chiliLevel,
        saved.activeReveal!.choice.usage!.resolvedAction['effective_chili'],
      );
    },
  );

  test(
    'held 045 preserves identity and quota across eligibility changes and canonical spice progression',
    () async {
      final focusedCatalog = _catalogWithCards(catalog, {
        'card.v4.001',
        'card.v4.006',
        'card.v4.045',
      });
      final backend = _Backend();
      backend.clothingCounts.updateAll((player, count) => 2);
      final observedCeilings = <int>[backend.v4UnlockedSpice];
      final observation = backend.changes.stream.listen((_) {
        if (observedCeilings.last != backend.v4UnlockedSpice) {
          observedCeilings.add(backend.v4UnlockedSpice);
        }
      });
      addTearDown(observation.cancel);
      EngineSessionContext context(int clothes) => EngineSessionContext(
        mode: SessionMode.face_to_face,
        proximity: ProximityState.TOGETHER,
        // Context changes retain the existing canonical ceiling; never unlock it.
        chiliActive: 1,
        chiliUnlocked: 1,
        clothesByPlayer: {'alice': clothes, 'bob': clothes},
        mediaCapabilitiesByPlayer: {
          for (final id in ['alice', 'bob']) id: MediaCapability.values.toSet(),
        },
      );
      NetworkGameController controller(String id, int value) =>
          NetworkGameController(
            session: session,
            playerId: id,
            repository: backend.repository(id),
            privateStore: MemoryNetworkDuelSecretStore(),
            learningStore: MemoryNetworkProfileLearningStore(),
            catalog: focusedCatalog,
            initialContext: context(2),
            privateProfile: PlayerGameProfile(
              playerId: id,
              preferences: {
                for (final tag in [
                  'calin',
                  'proximite_physique',
                  'enlever',
                  'tenue',
                  'photo_mutuelle',
                ])
                  'v3.preference.$tag': PreferenceValue(
                    status: PreferenceStatus.ACCEPTED,
                    general: value,
                    faire: value,
                    recevoir: value,
                  ),
              },
            ),
          );
      final setup = _Setup(
        backend,
        controller('alice', 8),
        controller('bob', 12),
      );
      addTearDown(setup.dispose);
      await Future.wait([setup.alice.start(), setup.bob.start()]);
      await _settle();
      CardRuntimeState held045(NetworkGameController player) => player.runtime
          .singleWhere((c) => c.cardId == '045' && c.zone == CardZone.HAND);
      final originalHeld = {
        for (final player in [setup.alice, setup.bob])
          player.playerId: held045(player),
      };
      final originalCheckpoints = {
        for (final player in [setup.alice, setup.bob])
          player.playerId: player.usageCheckpoint.encode(),
      };
      for (final player in [setup.alice, setup.bob]) {
        expect(player.heldConcepts.map((c) => c.id), contains('045'));
        expect(player.activeSpice, 1);
        expect(player.round!.v4UnlockedSpice, 1);
        expect(player.choicesFor('045').map((o) => o.choice.chili), [1]);
        expect(player.choicesFor('006'), isNotEmpty);
      }

      // Eligibility only: clothing actions become unavailable, 045 stays held.
      await setup.alice.applyResolvedContext(context(0));
      expect(setup.alice.choicesFor('006'), isEmpty);
      expect(setup.alice.choicesFor('045').map((o) => o.choice.chili), [1]);
      expect(held045(setup.alice), same(originalHeld['alice']));
      for (final player in [setup.alice, setup.bob]) {
        expect(
          player.usageCheckpoint.encode(),
          originalCheckpoints[player.playerId],
        );
        expect(player.activeSpice, 1);
      }
      expect(backend.v4UnlockedSpice, 1);

      // Complete another action normally, keeping 045 untouched in both hands.
      final completedRoundId = backend.round.id;
      await _playUnequal(setup, forceAliceCard: '001', avoidBobCard: '045');
      final loser = setup.alice.isInitialLoser ? setup.alice : setup.bob;
      await loser.skipCorruption();
      await _settle();
      expect(backend.phase, NetworkGamePhase.finalResolved);
      await setup.alice.completeAction();
      await _settle();
      expect(backend.round.ready, {'alice'});
      await setup.bob.completeAction();
      await _settle();
      final completedRound = backend.rounds.values.singleWhere(
        (r) => r.id == completedRoundId,
      );
      expect(completedRound.ready, {'alice', 'bob'});
      expect(completedRound.phase, NetworkGamePhase.closed);
      expect(backend.closedRoundIds, contains(completedRoundId));
      expect(backend.currentRound, 2);
      // Only settled PA advances spice; held cards and their quotas stay put.
      expect(backend.v4UnlockedSpice, 1);
      final checkpointsBeforePublication = {
        for (final player in [setup.alice, setup.bob])
          player.playerId: player.usageCheckpoint.encode(),
      };
      for (final (spent, next) in [(40, 2), (100, 3), (150, 4)]) {
        backend.points['alice'] = spent <= 100 ? 100 - spent : 0;
        backend.points['bob'] = spent <= 100 ? 100 : 200 - spent;
        backend.refreshPaSpice();
        backend.notify();
        await _settle();
        for (final player in [setup.alice, setup.bob]) {
          expect(player.activeSpice, next);
          expect(player.round!.v4UnlockedSpice, next);
          expect(held045(player), same(originalHeld[player.playerId]));
          expect(
            player.usageCheckpoint.encode(),
            checkpointsBeforePublication[player.playerId],
          );
        }
      }
      expect(observedCeilings, [1, 2, 3, 4]);
      for (final player in [setup.alice, setup.bob]) {
        expect(player.activeSpice, 4);
        expect(player.round!.v4UnlockedSpice, 4);
        expect(player.choicesFor('045').map((o) => o.choice.chili), [1, 2, 4]);
        expect(held045(player), same(originalHeld[player.playerId]));
        expect(player.usageCheckpoint.stock.capacity['045'], 3);
        expect(player.usageCheckpoint.availableFor('045'), 3);
        expect(
          player.usageCheckpoint.usagesByIntent.values.where(
            (u) => u.conceptId == '045',
          ),
          isEmpty,
        );
        expect(
          player.usageCheckpoint.encode(),
          checkpointsBeforePublication[player.playerId],
        );
        final saved = (await player.privateStore.loadGame(
          sessionId: session.id,
          playerId: player.playerId,
        ))!;
        expect(
          saved.conceptCheckpoint!.encode(),
          player.usageCheckpoint.encode(),
        );
      }
    },
  );

  test(
    'retry after an unrecorded commit reuses the persisted usage nonce and quota',
    () async {
      final backend = _Backend();
      final store = MemoryNetworkDuelSecretStore();
      final controller = _controller(backend, session, catalog, 'alice', store);
      addTearDown(controller.dispose);
      await controller.start();
      controller.selectCard(controller.hand.first.identity);
      backend.failNextCommit = true;
      await controller.confirmSelection();
      expect(controller.viewState, NetworkGameViewState.error);
      final saved = (await store.loadGame(
        sessionId: session.id,
        playerId: 'alice',
      ))!;
      expect(backend.round.commits, isEmpty);
      await controller.retryCurrentAction();
      final retried = (await store.loadGame(
        sessionId: session.id,
        playerId: 'alice',
      ))!;
      expect(retried.activeReveal!.nonce, saved.activeReveal!.nonce);
      expect(
        retried.activeReveal!.choice.usageId,
        saved.activeReveal!.choice.usageId,
      );
      expect(
        retried.conceptCheckpoint!.encode(),
        saved.conceptCheckpoint!.encode(),
      );
      expect(backend.round.commits, contains('alice'));
    },
  );

  test(
    'reconnection resumes a persisted cancellation without refunding quota',
    () async {
      final backend = _Backend();
      final store = MemoryNetworkDuelSecretStore();
      var controller = _controller(backend, session, catalog, 'alice', store);
      await controller.start();
      final card = controller.hand.first;
      controller.selectCard(card.identity);
      await controller.confirmSelection();
      final checkpoint = controller.usageCheckpoint.encode();
      backend.failNextCancellation = true;
      expect(await controller.cancelSelection(), isFalse);
      final saved = (await store.loadGame(
        sessionId: session.id,
        playerId: 'alice',
      ))!;
      expect(saved.cancelCommitRequested, isTrue);
      expect(backend.round.commits, contains('alice'));
      controller.dispose();
      controller = _controller(backend, session, catalog, 'alice', store);
      addTearDown(controller.dispose);
      await controller.start();
      await _settle();
      expect(backend.round.commits, isNot(contains('alice')));
      expect(controller.usageCheckpoint.encode(), checkpoint);
      final resumed = (await store.loadGame(
        sessionId: session.id,
        playerId: 'alice',
      ))!;
      expect(resumed.cancelCommitRequested, isFalse);
      expect(resumed.activeReveal, isNull);
    },
  );

  test(
    'learning waits for both done acknowledgements and applies once',
    () async {
      final setup = await _setup(session, catalog);
      addTearDown(setup.dispose);
      await _playUnequal(setup);
      final loser = setup.alice.isInitialLoser ? setup.alice : setup.bob;
      await loser.skipCorruption();
      await _settle();
      await setup.alice.completeAction();
      expect((await setup.alice.learning.state()).entries, isEmpty);
      final waiting = (await setup.alice.privateStore.loadGame(
        sessionId: session.id,
        playerId: 'alice',
      ))!;
      expect(waiting.pendingLearning, isNotNull);
      await setup.bob.completeAction();
      await _settle();
      final learned = (await setup.alice.learning.state()).toJson();
      expect(
        (await setup.alice.learning.state()).appliedRoundEvents,
        hasLength(1),
      );
      await setup.alice.retryCurrentAction();
      await _settle();
      expect((await setup.alice.learning.state()).toJson(), learned);
    },
  );

  test(
    'reconnect replays the reserved Recovery command then engages once on acceptance',
    () async {
      final setup = await _setup(session, catalog);
      await _playUnequal(setup);
      final loser = setup.alice.isInitialLoser ? setup.alice : setup.bob;
      await loser.skipCorruption();
      await _settle();
      setup.backend.points['alice'] = 10;
      setup.backend.round.phase = NetworkGamePhase.recovery;
      setup.backend.notify();
      await _settle();
      final card = setup.alice.recoveryCards.first;
      final before = setup.alice.usageCheckpoint.stock.remainingFor(card.id);
      setup.backend.failNextRecovery = true;
      await setup.alice.recoverWith(card.identity);
      final saved = (await setup.alice.privateStore.loadGame(
        sessionId: session.id,
        playerId: 'alice',
      ))!;
      expect(saved.pendingSecondaryCommand, isNotNull);
      expect(
        jsonEncode(saved.pendingSecondaryCommand),
        isNot(contains('snapshot_value')),
      );
      final planned = saved.reservedChoices.values.single.usageId;
      expect(saved.conceptCheckpoint!.stock.remainingFor(card.id), before);
      setup.alice.dispose();
      final alice = _controller(
        setup.backend,
        session,
        catalog,
        'alice',
        setup.alice.privateStore,
      );
      addTearDown(alice.dispose);
      addTearDown(setup.bob.dispose);
      await alice.start();
      await _settle();
      expect(alice.pendingRecovery!.usageId, planned);
      expect(alice.usageCheckpoint.stock.remainingFor(card.id), before);
      await setup.bob.respondToRecovery(RecoveryResponse.ACCEPT);
      await _settle();
      expect(alice.usageCheckpoint.stock.remainingFor(card.id), before - 1);
      expect(
        alice.usageCheckpoint.usagesByIntent.values.where(
          (u) => u.usageId == planned,
        ),
        hasLength(1),
      );
      await alice.retryCurrentAction();
      await _settle();
      expect(alice.usageCheckpoint.stock.remainingFor(card.id), before - 1);
    },
  );

  test('network DTO round-trips without private hand, lock or profile', () {
    final backend = _Backend()
      ..cycleExhausted = true
      ..v4UnlockedSpice = 3;
    final state = backend.state('alice');
    final encoded = jsonEncode(state.toJson());
    expect(
      NetworkGameRoundStateDto.fromJson(state.toJson()).toJson(),
      state.toJson(),
    );
    final decoded = jsonDecode(encoded);
    const privateKeys = {
      'hand',
      'locked',
      'personal_value',
      'nonce',
      'preferences',
      'profile',
    };
    void expectNoPrivateKeys(Object? value) {
      if (value is Map<String, dynamic>) {
        expect(value.keys.toSet().intersection(privateKeys), isEmpty);
        for (final nested in value.values) {
          expectNoPrivateKeys(nested);
        }
      } else if (value is List<dynamic>) {
        for (final nested in value) {
          expectNoPrivateKeys(nested);
        }
      }
    }
    expectNoPrivateKeys(decoded);
    expect(state.actionPoints, {'alice': 100, 'bob': 100});
    expect(state.cycleExhausted, isTrue);
    expect(state.v4UnlockedSpice, 3);
  });

  test(
    'canonical spice is shared and overrides absent or divergent local cache',
    () async {
      final backend = _Backend()..v4UnlockedSpice = 3;
      final aliceStore = MemoryNetworkDuelSecretStore();
      await aliceStore.saveGame(
        sessionId: session.id,
        playerId: 'alice',
        state: privateGameFixture(
          roundNumber: 1,
          cards: const [],
          activeChili: 4,
        ),
      );
      final alice = _controller(backend, session, catalog, 'alice', aliceStore);
      final bob = _controller(
        backend,
        session,
        catalog,
        'bob',
        MemoryNetworkDuelSecretStore(),
      );

      await Future.wait([alice.start(), bob.start()]);

      // Canonical shared ceiling replaces a divergent cached ceiling.
      expect(alice.activeSpice, 3);
      expect(bob.activeSpice, 3);
      expect(alice.round!.v4UnlockedSpice, 3);
      expect(bob.round!.v4UnlockedSpice, 3);
      alice.dispose();
      bob.dispose();
    },
  );

  test(
    'legacy pool publication cannot unlock spice without PA spending',
    () async {
      final backend = _Backend();
      final repository =
          backend.repository('alice') as NetworkSessionFlowRepository;
      final command = _command(
        'old-spice',
        'alice',
        'PUBLISH_V4_SPICE',
        'round-1',
      );
      for (var attempt = 0; attempt < 2; attempt++) {
        final state = await repository.publishUnlockedSpice(
          command: command,
          unlockedSpice: 4,
        );
        expect(state.v4UnlockedSpice, 1);
        expect(backend.totalPaSpent, 0);
      }
    },
  );



  for(final style in PlayerStyle.values){
    test('first hand receives canonical initial ${style.name} style',()async{
      final backend=_Backend()..deckStyle=style;
      final player=_controller(backend,session,catalog,'alice',MemoryNetworkDuelSecretStore());addTearDown(player.dispose);
      await player.start();
      expect(player.deckStyle,style);expect(player.hand,isNotEmpty);expect(player.activeSpice,1);
      final saved=await player.privateStore.loadGame(sessionId:session.id,playerId:'alice');
      expect(saved!.deckStyle,style);
    });
  }
  test('cycle increase waits for peer; refusal, retry and 80 PA thresholds are canonical',()async{
    final backend=_Backend()..cycleExhausted=true;
    backend.points..['alice']=60..['bob']=60;
    backend.round.phase=NetworkGamePhase.waitingNext;
    final alice=backend.repository('alice') as NetworkSessionFlowRepository;
    final bob=backend.repository('bob') as NetworkSessionFlowRepository;
    Future<NetworkGameRoundStateDto> vote(NetworkSessionFlowRepository repo,String player,String id,DeckExhaustionChoice choice,int revision)=>repo.continueDeckCycle(command:_command(id,player,'CONTINUE_CYCLE',backend.round.id),choice:choice,expectedCycle:1,expectedStyleRevision:revision);
    await vote(alice,'alice','proposal',DeckExhaustionChoice.continueSpicier,0);
    expect(backend.deckStyle,PlayerStyle.SOFT);expect(backend.deckCycle,1);
    expect(backend.state('alice').v4UnlockedSpice,2);
    await vote(bob,'bob','refusal',DeckExhaustionChoice.refuseStyle,1);
    expect(backend.deckStyle,PlayerStyle.SOFT);expect(backend.deckCycle,1);
    await vote(alice,'alice','proposal-2',DeckExhaustionChoice.continueSpicier,2);
    final accepted=await vote(bob,'bob','agreement',DeckExhaustionChoice.continueSpicier,3);
    expect(accepted.deckStyle,PlayerStyle.EPICE);expect(accepted.v4UnlockedSpice,3);
    expect(backend.deckCycle,2);expect(backend.totalPaSpent,80);
    await vote(bob,'bob','agreement',DeckExhaustionChoice.continueSpicier,3);
    expect(backend.deckCycle,2);
  });
  test('duel directly offers post-duel choice and compromise keeps its winner',()async{
    final setup=await _setup(session,catalog);addTearDown(setup.dispose);
    await _playUnequal(setup);
    final winner=setup.alice.isInitialWinner?setup.alice:setup.bob;
    final loser=winner==setup.alice?setup.bob:setup.alice;
    expect(loser.viewState,NetworkGameViewState.corruptionDecision);
    expect(loser.isCorruptionActor,isTrue);
    final originalWinner=winner.playerId;
    await loser.proposeNegotiation(inversion:false,directPa:6);
    await _settle();await winner.respondNegotiation(accepted:true);await _settle();
    expect(loser.finalWinnerId,originalWinner);expect(winner.finalWinnerId,originalWinner);
    expect(setup.backend.counterApplications,0);expect(setup.backend.defenseApplications,0);
  });

  test('auction accepts only eligible discard occurrences', () async {
    final focusedCatalog = _catalogWithCards(catalog, {
      'card.v4.001', 'card.v4.002', 'card.v4.003',
      'card.v4.010', 'card.v4.037',
    });
    final store = MemoryNetworkDuelSecretStore();
    var checkpoint = ConceptUsageCheckpoint.startCycle(
      sessionId: session.id,
      ownerPlayerId: 'alice',
      cycle: 1,
      catalog: focusedCatalog.concepts!,
      initialClothing: 6,
    );
    final history = <NetworkPlayedCardRecord>[];
    NetworkUsageProjection engageHistory(
      String conceptId,
      String actionId,
      CardOccurrenceDirection direction,
      int spice, {
      String? zoneId,
    }) {
      final binding = (focusedCatalog.conceptRules!['bindings']! as List)
          .singleWhere((b) => b['concept_id'] == conceptId) as Map;
      final rule = (binding['actions'] as List)
          .singleWhere((a) => a['action_id'] == actionId) as Map;
      final tags = ((rule['editorial'] as Map)['tags'] as List).cast<String>();
      final rating = rule['rating'] as Map;
      final concept = focusedCatalog.concepts!.concepts
          .singleWhere((c) => c.id == conceptId);
      final action = ResolvedConceptAction.fromJson({
        'concept_id': conceptId,
        'catalog_version': focusedCatalog.concepts!.reader.json['catalog_version'],
        'locale': 'fr-FR',
        if (concept.stages.isNotEmpty) 'stage_id': actionId
        else 'variant_id': actionId,
        if (zoneId != null) 'zone_id': zoneId,
        'effective_chili': spice,
        'direction': direction.name,
        'actor_player_ids': direction == CardOccurrenceDirection.MUTUEL
            ? ['alice', 'bob'] : ['alice'],
        'target_player_ids': direction == CardOccurrenceDirection.MUTUEL
            ? ['alice', 'bob'] : ['bob'],
        'parameters': {'committed_at': '2026-09-29T12:00:00.000Z'},
        'accessories': <Object?>[],
        'effects': <Object?>[],
        'tags': tags,
        'primary_preference_ids': [
          for (final tag in rating['primary_preference_tags'] as List)
            'v3.preference.$tag',
        ],
        'personal_values': [{
          'player_id': 'alice',
          'role': direction == CardOccurrenceDirection.FAIRE ? 'FAIRE' : 'GENERAL',
          'value': 8,
        }],
        'action_text': concept.actionText,
      });
      final intentId = 'historical:$conceptId';
      checkpoint = checkpoint.reserve(conceptId: conceptId, intentId: intentId)
          .engage(conceptId: conceptId, intentId: intentId,
            resolveAction: () => action,
            clock: () => DateTime.utc(2026, 9, 29, 12));
      final usage = NetworkUsageProjection.fromSnapshot(
        checkpoint.usageForIntent(intentId)!,
        sharedParameterKeys: action.parameters.keys.toSet(),
        sharedEffectIds: const {},
        includePersonalValue: true,
      );
      history.add(NetworkPlayedCardRecord(usage: usage, roundNumber: 0));
      return usage;
    }
    final kiss = engageHistory('003', '003.stage.1', CardOccurrenceDirection.MUTUEL, 1);
    final striptease = engageHistory('010', '010.stage.1', CardOccurrenceDirection.FAIRE, 1);
    final exhausted = engageHistory('002', '002.zone.face_hair', CardOccurrenceDirection.FAIRE, 1,
      zoneId: 'face_hair');
    final tooSpicy = engageHistory('037', '037.stage.1', CardOccurrenceDirection.FAIRE, 2);
    expect(history.map((r) => r.usageId).toSet(), hasLength(4));
    expect(checkpoint.availableFor('003'), 2);
    expect(checkpoint.availableFor('010'), 2);
    expect(checkpoint.availableFor('002'), 0);
    expect(checkpoint.availableFor('037'), 2);
    await store.saveGame(
      sessionId: session.id,
      playerId: 'alice',
      state: NetworkPrivateGameState(
        roundNumber: 1,
        cards: [CardRuntimeState(cardId: '001', zone: CardZone.HAND)],
        conceptCheckpoint: checkpoint,
        publicDiscards: history,
        initialClothing: 6,
        clothesByPlayer: const {'alice': 6, 'bob': 6},
      ),
    );
    final backend = _Backend();
    NetworkGameController player(String id, int value) => NetworkGameController(
      session: session,
      playerId: id,
      repository: backend.repository(id),
      privateStore: id == 'alice' ? store : MemoryNetworkDuelSecretStore(),
      learningStore: MemoryNetworkProfileLearningStore(),
      catalog: focusedCatalog,
      privateProfile: PlayerGameProfile(playerId: id, preferences: {
        for (final tag in ['calin', 'proximite_physique', 'embrasser',
          'danser', 'enlever', 'tenue', 'etre_regarde', 'striptease', 'frapper'])
          'v3.preference.$tag': PreferenceValue(status: PreferenceStatus.ACCEPTED,
            general: value, faire: value, recevoir: value),
      }),
    );
    final setup = _Setup(backend, player('alice', 8), player('bob', 12));
    addTearDown(setup.dispose);
    await Future.wait([setup.alice.start(), setup.bob.start()]);
    await _settle();
    await _playUnequal(setup, forceAliceCard: '001');
    expect(setup.alice.isInitialLoser, isTrue);
    backend.routeToUnifiedPostDuelChoice = true;
    await _settle();
    final controller = setup.alice;
    expect(controller.activeSpice, 1);
    expect(controller.auctionCards.map((c) => c.identity), unorderedEquals([
      kiss.usageId, striptease.usageId,
    ]));
    expect(controller.auctionCards.every(controller.isAuctionCardPlayable), isTrue);
    expect(controller.auctionCards.map((c) => c.identity),
      isNot(contains(exhausted.usageId)));
    expect(controller.auctionCards.map((c) => c.identity),
      isNot(contains(tooSpicy.usageId)));
    expect(controller.usageCheckpoint.availableFor('003'), 2);
    expect(controller.usageCheckpoint.availableFor('010'), 2);
    for (final usage in [kiss, striptease]) {
      final snapshot = usage.resolvedAction;
      expect(history.any((r) => r.usageId == usage.usageId &&
        r.usage.ownerPlayerId == 'alice' && r.roundNumber < controller.roundNumber), isTrue);
      expect(controller.choicesFor(usage.conceptId).any((option) =>
        option.choice.actionId == snapshot['stage_id'] &&
        option.choice.zoneId == snapshot['zone_id']), isTrue);
    }

    final sql = File(
      'supabase/migrations/202610100002_network_corruption_replacement.sql',
    ).readAsStringSync();
    expect(
      sql,
      contains(
        'A compromise/corruption argument must be a server-verifiable discard',
      ),
    );
    expect(sql, contains("previous.final_resolution->'compromise'"));
    expect(sql, contains("action->>'status'='COMPLETED'"));
    expect(sql, contains("recovery->>'completed'"));
    expect(
      RegExp(r"raise exception 'ROUND_CORRUPTION_FORBIDDEN'").allMatches(sql),
      isNotEmpty,
    );

  });

  test(
    'unified post-duel choice rejects an empty compromise on client and server',
    () async {
      for (final scenario in ['pa', 'inversion', 'card']) {
        final setup = scenario == 'card'
            ? await _setupCorruption(session, catalog)
            : await _setup(session, catalog);
        try {
          if (scenario == 'card') {
            await _reachSecondResolved(setup);
            setup.backend.round.phase = NetworkGamePhase.corruptionDecision;
            setup.backend.notify();
          } else {
            await _playUnequal(setup, requireInvertibleWinner: true);
            setup.backend.routeToUnifiedPostDuelChoice = true;
          }
          await _settle();
          final actor = setup.alice.isNegotiationProposer
              ? setup.alice
              : setup.bob;
          expect(actor.viewState, NetworkGameViewState.corruptionDecision);
          expect(actor.isNegotiationProposer, isTrue);
          final canonical = setup.backend.state(actor.playerId).toJson();
          final checkpoint = actor.usageCheckpoint.encode();
          final usageIds = actor.usageCheckpoint.usagesByIntent.values
              .map((u) => u.usageId)
              .toSet();
          final local = (await actor.privateStore.loadGame(
            sessionId: session.id,
            playerId: actor.playerId,
          ))!.toJson();
          final commands = Set<String>.of(setup.backend.commands);
          final calls = setup.backend.negotiationProposalCalls;
          for (var attempt = 0; attempt < 2; attempt++) {
            await expectLater(
              actor.proposeNegotiation(
                directPa: 0,
                inversion: false,
                cardIds: const {},
              ),
              throwsArgumentError,
            );
            await _settle();
            expect(setup.backend.negotiationProposalCalls, calls);
            expect(setup.backend.commands, commands);
            expect(setup.backend.state(actor.playerId).toJson(), canonical);
            expect(actor.usageCheckpoint.encode(), checkpoint);
            expect(
              (await actor.privateStore.loadGame(
                sessionId: session.id,
                playerId: actor.playerId,
              ))!.toJson(),
              local,
            );
          }
          await expectLater(
            (setup.backend.repository(actor.playerId)
                    as NetworkNegotiationRepository)
                .submitNegotiationProposal(
                  command: _command(
                    'empty-$scenario',
                    actor.playerId,
                    'NEGOTIATION_PROPOSAL',
                    setup.backend.round.id,
                  ),
                  offer: NetworkNegotiationOfferDto(
                    inversionRequested: false,
                    directPa: 0,
                    cards: const [],
                  ),
                ),
            throwsA(
              isA<NetworkRoundException>().having(
                (error) => error.code,
                'code',
                'ROUND_NEGOTIATION_INVALID',
              ),
            ),
          );
          expect(setup.backend.commands, commands);
          expect(setup.backend.state(actor.playerId).toJson(), canonical);
          expect(actor.usageCheckpoint.encode(), checkpoint);
          final source = scenario == 'card' ? actor.auctionCards.single : null;
          if (scenario == 'inversion') expect(actor.inversionAllowed, isTrue);
          await actor.proposeNegotiation(
            directPa: scenario == 'pa' ? 2 : 0,
            inversion: scenario == 'inversion',
            cardIds: {if (source != null) source.identity},
          );
          await _settle();
          expect(setup.backend.negotiationProposalCalls, calls + 2);
          expect(setup.backend.phase, NetworkGamePhase.negotiationResponse);
          final proposal = setup.backend.round.negotiation!.proposal!;
          expect(proposal.directPa, scenario == 'pa' ? 2 : 0);
          expect(proposal.inversionRequested, scenario == 'inversion');
          expect(proposal.cards, hasLength(source == null ? 0 : 1));
          expect(
            actor.usageCheckpoint.usagesByIntent.values
                .map((u) => u.usageId)
                .toSet(),
            usageIds,
          );
          // Sending a proposal never permanently consumes quota or debits PA.
          expect(
            actor.usageCheckpoint.stock.toJson(),
            (local['concept_checkpoint']! as Map<String, Object?>)['stock'],
          );
          expect(setup.backend.points, canonical['action_points']);
          if (source != null) {
            final pending = (await actor.privateStore.loadGame(
              sessionId: session.id,
              playerId: actor.playerId,
            ))!;
            final reserved = pending.reservedChoices.values.single;
            expect(reserved.sourceUsageId, source.identity);
            expect(proposal.cards.single.usageId, reserved.usageId);
            expect(
              actor.usageCheckpoint.reservationsByIntent[reserved.intentId],
              source.id,
            );
          } else {
            expect(actor.usageCheckpoint.encode(), checkpoint);
          }
        } finally {
          setup.dispose();
        }
      }
    },
  );

  test('refused compromise preserves the second discard use', () async {
    final backend = _Backend();
    final aliceStore = MemoryNetworkDuelSecretStore();
    final bobStore = MemoryNetworkDuelSecretStore();
    for (final entry in {'alice': aliceStore, 'bob': bobStore}.entries) {
      await entry.value.saveGame(
        sessionId: session.id,
        playerId: entry.key,
        state: privateGameFixture(
          roundNumber: 1,
          ownerPlayerId: entry.key,
          cards: [
            for (final id in ['003', '001', '012', '032'])
              CardRuntimeState(cardId: id, zone: CardZone.HAND),
          ],
        ),
      );
    }
    final preferenceTags = {
      for (final binding in catalog.conceptRules!['bindings']! as List)
        for (final action in binding['actions'] as List)
          for (final tag in action['editorial']['tags'] as List)
            if ((tag as String).startsWith('v3.preference.')) tag,
    };
    NetworkGameController player(String id, int value, NetworkDuelSecretStore store) =>
        NetworkGameController(
          session: session,
          playerId: id,
          repository: backend.repository(id),
          privateStore: store,
          learningStore: MemoryNetworkProfileLearningStore(),
          catalog: catalog,
          privateProfile: PlayerGameProfile(playerId: id, preferences: {
            for (final tag in preferenceTags)
              tag: PreferenceValue(status: PreferenceStatus.ACCEPTED,
                general: value, faire: value, recevoir: value),
          }),
          nonceFactory: () => 'nonce-$id-${backend.currentRound}',
          clock: () => DateTime.utc(2026, 9, 30, 12, backend.currentRound),
        );
    final setup = _Setup(backend, player('alice', 8, aliceStore), player('bob', 12, bobStore));
    addTearDown(setup.dispose);
    await Future.wait([setup.alice.start(), setup.bob.start()]);
    await _settle();
    final initialCapacity = setup.alice.usageCheckpoint.availableFor('003');
    expect(initialCapacity, 3);
    await _playUnequal(setup, forceAliceCard: '003', requireRepeatable: true);
    final source = setup.alice.usageCheckpoint.usagesByIntent.values.single;
    expect(source.conceptId, '003');
    expect(source.usageId, isNotEmpty);
    final originalSnapshot = source.toJson();
    final firstLoser = setup.alice.isInitialLoser ? setup.alice : setup.bob;
    await firstLoser.skipCorruption();
    await _settle();
    await _completeResolvedAction(setup);
    await _settle();

    expect(setup.alice.roundNumber, 2);
    final afterFirst = (await aliceStore.loadGame(sessionId: session.id, playerId: 'alice'))!;
    final historical = afterFirst.publicDiscards.singleWhere((r) => r.usageId == source.usageId);
    expect(historical.roundNumber, 1);
    expect(historical.usage.ownerPlayerId, 'alice');
    expect(historical.usage.conceptId, '003');
    final historicalSnapshot = historical.toJson();
    expect(afterFirst.conceptCheckpoint!.usageForIntent(source.intentId)!.toJson(), originalSnapshot);
    expect(setup.alice.usageCheckpoint.usageForIntent(source.intentId)!.toJson(), originalSnapshot);
    expect(setup.alice.usageCheckpoint.stock.remainingFor('003'), initialCapacity - 1);
    expect(setup.alice.usageCheckpoint.availableFor('003'), initialCapacity - 1);
    expect(setup.alice.usageCheckpoint.usagesByIntent.values.where((u) => u.conceptId == '003'), hasLength(1));

    // Play another concept so the historical source remains an unused replay.
    await _playUnequal(setup, forceAliceCard: '001', avoidBobCard: '003');
    backend.routeToUnifiedPostDuelChoice = true;
    expect(setup.alice.isInitialLoser, isTrue);
    await _settle();
    final loser = setup.alice;
    final winner = setup.bob;
    final offered = loser.auctionCards.singleWhere((c) => c.identity == source.usageId);
    expect(loser.isAuctionCardPlayable(offered), isTrue);
    final beforeProposal = loser.usageCheckpoint.encode();
    final engagedIds = loser.usageCheckpoint.usagesByIntent.values.map((u) => u.usageId).toSet();
    final remaining = loser.usageCheckpoint.stock.remainingFor('003');
    expect(remaining, initialCapacity - 1);
    await loser.proposeNegotiation(directPa: 0, inversion: false, cardIds: {source.usageId});
    await _settle();
    final pending = (await aliceStore.loadGame(sessionId: session.id, playerId: 'alice'))!;
    final draft = pending.reservedChoices.values.singleWhere((u) => u.sourceUsageId == source.usageId);
    expect(draft.usageId, isNot(source.usageId));
    expect(pending.conceptCheckpoint!.reservationsByIntent[draft.intentId], '003');
    expect(loser.usageCheckpoint.stock.remainingFor('003'), remaining);
    expect(loser.usageCheckpoint.availableFor('003'), remaining - 1);
    expect(loser.usageCheckpoint.usagesByIntent.values.map((u) => u.usageId).toSet(), engagedIds);
    expect(loser.usageCheckpoint.usagesByIntent.values.any((u) => u.usageId == draft.usageId), isFalse);
    expect(winner.viewState, NetworkGameViewState.negotiationResponse);
    await winner.respondNegotiation(accepted: false);
    await _settle();

    final refused = (await aliceStore.loadGame(sessionId: session.id, playerId: 'alice'))!;
    expect(refused.reservedChoices, isEmpty);
    expect(loser.usageCheckpoint.reservationsByIntent, isEmpty);
    expect(loser.usageCheckpoint.encode(), beforeProposal);
    expect(refused.conceptCheckpoint!.encode(), beforeProposal);
    expect(loser.usageCheckpoint.usagesByIntent.values.map((u) => u.usageId).toSet(), engagedIds);
    expect(loser.usageCheckpoint.stock.remainingFor('003'), remaining);
    expect(loser.usageCheckpoint.availableFor('003'), remaining);
    expect(refused.publicDiscards.singleWhere((r) => r.usageId == source.usageId).toJson(), historicalSnapshot);
    expect(loser.usageCheckpoint.usageForIntent(source.intentId)!.toJson(), originalSnapshot);
    expect(loser.auctionCards.any((c) => c.identity == source.usageId && loser.isAuctionCardPlayable(c)), isTrue);
    expect(backend.consumedCompromiseOccurrences['alice'], isNot(contains(draft.usageId)));
  });

  test(
    'accepted compromise consumes discard and learns once after both completions',
    () async {
      final backend = _Backend();
      final aliceStore = MemoryNetworkDuelSecretStore();
      final bobStore = MemoryNetworkDuelSecretStore();
      final aliceLearning = MemoryNetworkProfileLearningStore();
      final bobLearning = MemoryNetworkProfileLearningStore();
      for (final entry in {'alice': aliceStore, 'bob': bobStore}.entries) {
        await entry.value.saveGame(
          sessionId: session.id,
          playerId: entry.key,
          state: privateGameFixture(
            roundNumber: 1,
            ownerPlayerId: entry.key,
            cards: [
              for (final id in ['003', '001', '012', '032'])
                CardRuntimeState(cardId: id, zone: CardZone.HAND),
            ],
          ),
        );
      }
      final preferenceTags = {
        for (final binding in catalog.conceptRules!['bindings']! as List)
          for (final action in binding['actions'] as List)
            for (final tag in action['editorial']['tags'] as List)
              if ((tag as String).startsWith('v3.preference.')) tag,
      };
      NetworkGameController player(String id, int value, NetworkDuelSecretStore store) =>
          NetworkGameController(
            session: session,
            playerId: id,
            repository: backend.repository(id),
            privateStore: store,
            learningStore: id == 'alice' ? aliceLearning : bobLearning,
            catalog: catalog,
            privateProfile: PlayerGameProfile(playerId: id, preferences: {
              for (final tag in preferenceTags)
                tag: PreferenceValue(status: PreferenceStatus.ACCEPTED,
                  general: value, faire: value, recevoir: value),
            }),
            nonceFactory: () => 'nonce-$id-${backend.currentRound}',
            clock: () => DateTime.utc(2026, 9, 30, 12, backend.currentRound),
          );
      final setup = _Setup(backend, player('alice', 8, aliceStore), player('bob', 12, bobStore));
      var originalAliceDisposed = false;
      addTearDown(() {
        if (!originalAliceDisposed) setup.alice.dispose();
        setup.bob.dispose();
      });
      await Future.wait([setup.alice.start(), setup.bob.start()]);
      await _settle();
      final initialCapacity = setup.alice.usageCheckpoint.availableFor('003');
      expect(initialCapacity, 3);
      await _playUnequal(setup, forceAliceCard: '003', requireRepeatable: true);
      final source = setup.alice.usageCheckpoint.usagesByIntent.values.single;
      expect(source.conceptId, '003');
      expect(source.usageId, isNotEmpty);
      final originalSnapshot = source.toJson();
      final firstLoser = setup.alice.isInitialLoser ? setup.alice : setup.bob;
      await firstLoser.skipCorruption();
      await _settle();
      await _completeResolvedAction(setup);
      await _settle();

      expect(setup.alice.roundNumber, 2);
      final afterFirst = (await aliceStore.loadGame(sessionId: session.id, playerId: 'alice'))!;
      final historical = afterFirst.publicDiscards.singleWhere((r) => r.usageId == source.usageId);
      expect(historical.roundNumber, 1);
      expect(historical.usage.ownerPlayerId, 'alice');
      expect(historical.usage.conceptId, '003');
      final historicalSnapshot = historical.toJson();
      expect(afterFirst.conceptCheckpoint!.usageForIntent(source.intentId)!.toJson(), originalSnapshot);
      expect(setup.alice.usageCheckpoint.usageForIntent(source.intentId)!.toJson(), originalSnapshot);
      expect(setup.alice.usageCheckpoint.stock.remainingFor('003'), initialCapacity - 1);
      expect(setup.alice.usageCheckpoint.availableFor('003'), initialCapacity - 1);
      expect(setup.alice.usageCheckpoint.usagesByIntent.values.where((u) => u.conceptId == '003'), hasLength(1));

      // Play another concept so the historical source remains an unused replay.
      await _playUnequal(setup, forceAliceCard: '001', avoidBobCard: '003');
      backend.routeToUnifiedPostDuelChoice = true;
      expect(setup.alice.isInitialLoser, isTrue);
      await _settle();
      final loser = setup.alice;
      final winner = setup.bob;
      final offered = loser.auctionCards.singleWhere((c) => c.identity == source.usageId);
      expect(loser.isAuctionCardPlayable(offered), isTrue);
      final engagedIds = loser.usageCheckpoint.usagesByIntent.values.map((u) => u.usageId).toSet();
      final remaining = loser.usageCheckpoint.stock.remainingFor('003');
      expect(remaining, initialCapacity - 1);
      final eventId = '${session.id}/${loser.round!.roundId}/alice';
      final learnedBefore = jsonEncode((await aliceLearning.load('alice'))?.toJson());
      final eventsBefore = {...?aliceLearning.appliedEventIds['alice']};
      expect(eventsBefore, isNot(contains(eventId)));
      await loser.proposeNegotiation(directPa: 0, inversion: false, cardIds: {source.usageId});
      await _settle();
      final pending = (await aliceStore.loadGame(sessionId: session.id, playerId: 'alice'))!;
      final draft = pending.reservedChoices.values.singleWhere((u) => u.sourceUsageId == source.usageId);
      expect(draft.usageId, isNot(source.usageId));
      expect(pending.conceptCheckpoint!.reservationsByIntent[draft.intentId], '003');
      expect(loser.usageCheckpoint.stock.remainingFor('003'), remaining);
      expect(loser.usageCheckpoint.availableFor('003'), remaining - 1);
      expect(loser.usageCheckpoint.usagesByIntent.values.map((u) => u.usageId).toSet(), engagedIds);
      expect(loser.usageCheckpoint.usagesByIntent.values.any((u) => u.usageId == draft.usageId), isFalse);
      expect(winner.viewState, NetworkGameViewState.negotiationResponse);
      await winner.respondNegotiation(accepted: true);
      await _settle();

      final replay = loser.usageCheckpoint.usagesByIntent.values
          .singleWhere((u) => u.sourceUsageId == source.usageId);
      expect(replay.usageId, draft.usageId);
      expect(replay.usageId, isNot(source.usageId));
      expect(replay.conceptId, source.conceptId);
      expect(replay.action.toJson(), source.action.toJson());
      expect(loser.usageCheckpoint.usagesByIntent.values.map((u) => u.usageId).toSet(),
        {...engagedIds, replay.usageId});
      expect(loser.usageCheckpoint.stock.remainingFor('003'), remaining - 1);
      expect(loser.usageCheckpoint.availableFor('003'), remaining - 1);
      expect(loser.usageCheckpoint.reservationsByIntent, isEmpty);
      final accepted = (await aliceStore.loadGame(sessionId: session.id, playerId: 'alice'))!;
      expect(accepted.reservedChoices, isEmpty);
      expect(accepted.conceptCheckpoint!.usageForIntent(replay.intentId)!.toJson(), replay.toJson());
      expect(accepted.publicDiscards.singleWhere((r) => r.usageId == source.usageId).toJson(), historicalSnapshot);
      expect(loser.usageCheckpoint.usageForIntent(source.intentId)!.toJson(), originalSnapshot);
      final acceptedCard = loser.finalResolution!.compromise.singleWhere(
        (c) => c.origin == NetworkCompromiseOrigin.AUCTION && c.usageId == replay.usageId);
      expect(acceptedCard.usage.toJson()['source_usage_id'], source.usageId);
      expect(jsonEncode((await aliceLearning.load('alice'))?.toJson()), learnedBefore);
      expect(aliceLearning.appliedEventIds['alice'], eventsBefore);
      final acceptedCheckpoint = loser.usageCheckpoint.encode();

      await loser.completeAction();
      await _settle();
      expect(jsonEncode((await aliceLearning.load('alice'))?.toJson()), learnedBefore);
      expect(aliceLearning.appliedEventIds['alice'], eventsBefore);
      final waiting = (await aliceStore.loadGame(sessionId: session.id, playerId: 'alice'))!;
      expect(waiting.pendingLearning!['event_id'], eventId);
      expect((waiting.pendingLearning!['accepted']! as List).where(
        (u) => u['usage_id'] == replay.usageId), hasLength(1));
      expect(backend.round.ready, {'alice'});
      await winner.completeAction();
      await _settle();

      expect(aliceLearning.appliedEventIds['alice'], {...eventsBefore, eventId});
      final learned = (await aliceLearning.load('alice'))!;
      expect(learned.appliedRoundEvents, {...eventsBefore, eventId});
      final learnedOnce = jsonEncode(learned.toJson());
      final completed = (await aliceStore.loadGame(sessionId: session.id, playerId: 'alice'))!;
      expect(completed.pendingLearning, isNull);
      expect(completed.learningRecordedRounds, contains(2));
      expect(completed.conceptCheckpoint!.encode(), acceptedCheckpoint);
      expect(completed.conceptCheckpoint!.usagesByIntent.values.where(
        (u) => u.conceptId == '003'), hasLength(2));
      expect(initialCapacity - completed.conceptCheckpoint!.stock.remainingFor('003'), 2);
      expect(completed.publicDiscards.singleWhere((r) => r.usageId == source.usageId).toJson(), historicalSnapshot);
      expect(completed.publicDiscards.singleWhere((r) => r.usageId == replay.usageId).usage.toJson()['source_usage_id'], source.usageId);
      expect(backend.consumedCompromiseOccurrences['alice'], contains(replay.usageId));

      backend.notifyTwice();
      await _settle();
      expect(jsonEncode((await aliceLearning.load('alice'))?.toJson()), learnedOnce);
      expect(loser.usageCheckpoint.encode(), acceptedCheckpoint);
      await expectLater(
        (backend.repository('alice') as NetworkNegotiationRepository).submitNegotiationProposal(
          command: _command('repropose-consumed', 'alice', 'NEGOTIATION_PROPOSAL', backend.round.id),
          offer: NetworkNegotiationOfferDto(inversionRequested: false, directPa: 0,
            cards: [acceptedCard]),
        ),
        throwsA(isA<NetworkRoundException>()),
      );
      loser.dispose();
      originalAliceDisposed = true;
      final reconnected = player('alice', 8, aliceStore);
      addTearDown(reconnected.dispose);
      await reconnected.start();
      await _settle();
      expect(reconnected.usageCheckpoint.encode(), acceptedCheckpoint);
      expect(reconnected.usageCheckpoint.usagesByIntent.values.where(
        (u) => u.sourceUsageId == source.usageId), hasLength(1));
      expect(reconnected.usageCheckpoint.usageForIntent(source.intentId)!.toJson(), originalSnapshot);
      expect(reconnected.usageCheckpoint.usageForIntent(replay.intentId)!.toJson(), replay.toJson());
      expect(reconnected.usageCheckpoint.stock.remainingFor('003'), initialCapacity - 2);
      expect(aliceLearning.appliedEventIds['alice'], {...eventsBefore, eventId});
      expect(jsonEncode((await aliceLearning.load('alice'))?.toJson()), learnedOnce);
    },
  );

  test('migration persists and rejects consumed compromise occurrences', () {
    final sql = File(
      'supabase/migrations/202610100007_consume_accepted_compromise_occurrences.sql',
    ).readAsStringSync();
    expect(sql, contains('v4_consumed_occurrences jsonb'));
    expect(sql, contains("old.phase='FINAL_RESOLVED'"));
    expect(sql, contains("new.phase='WAITING_NEXT'"));
    expect(sql, contains("value->>'origin'='AUCTION'"));
    expect(sql, contains('game.v4_consumed_occurrences'));
    expect(sql, contains("raise exception 'ROUND_CORRUPTION_FORBIDDEN'"));
    expect(sql, contains("then '{}'::jsonb"));
  });

  test('public round DTO removes opponent values and compromise snapshots', () {
    final opponentReveal = ChoiceRevealDto(
      sessionRound: 'session-multi.round-1',
      playerId: 'alice',
      choice: ChoicePayload(
        cardId: 'card.v4.024',
        variantId: 'variant.v4.024.base',
        parameters: const {'personal_value': 17, 'opposite_personal_value': 6},
      ),
      nonce: 'opponent-secret',
    );
    final state = NetworkGameRoundStateDto(
      roundId: 'round-1',
      sessionId: 'session-multi',
      sessionRound: 'session-multi.round-1',
      roundNumber: 1,
      phase: NetworkGamePhase.finalResolved,
      playerId: 'bob',
      commits: const {},
      actionPoints: const {'alice': 100, 'bob': 100},
      readyNextPlayerIds: const {},
      tieDecisions: const {},
      opponentReveal: opponentReveal,
      initialResolution: NetworkInitialResolutionDto(
        tied: false,
        winnerPlayerId: 'alice',
        loserPlayerId: 'bob',
        gap: 9,
        gapCost: 9,
        highValue: 17,
        actionPoints: const {'alice': 100, 'bob': 100},
      ),
      negotiation: NetworkNegotiationDto(
        proposal: NetworkNegotiationOfferDto(
          inversionRequested: false,
          directPa: 3,
          cards: [
            compromiseFixture(
              usageId: 'alice-auction-occurrence',
              conceptId: 'card.v4.025',
              actionId: 'variant.v4.025.base',
              ownerPlayerId: 'alice',
              nativeDirection: NetworkCardDirection.FAIRE,
              effectiveDirection: NetworkCardDirection.FAIRE,
              origin: NetworkCompromiseOrigin.AUCTION,
              snapshotValue: 14,
            ),
          ],
        ),
      ),
      finalResolution: NetworkFinalResolutionDto(
        retainedPlayerId: 'alice',
        compromise: [
          compromiseFixture(
            usageId: 'alice-occurrence',
            conceptId: 'card.v4.024',
            actionId: 'variant.v4.024.base',
            ownerPlayerId: 'alice',
            nativeDirection: NetworkCardDirection.FAIRE,
            effectiveDirection: NetworkCardDirection.FAIRE,
            origin: NetworkCompromiseOrigin.INITIAL_DUEL,
            snapshotValue: 17,
          ),
        ],
      ),
    );

    final publicJson = state.toJson();
    expect(publicJson['opponent_reveal'], isNull);
    expect(
      publicJson['initial_resolution'],
      isNot(containsPair('high_value', anything)),
    );
    expect(
      publicJson['initial_resolution'],
      isNot(containsPair('gap', anything)),
    );
    final compromise =
        ((publicJson['final_resolution']! as Map)['compromise']! as List).single
            as Map;
    expect(compromise, isNot(contains('snapshot_value')));
    final auctionCard =
        ((((publicJson['negotiation']! as Map)['proposal']! as Map)['cards']!
                    as List)
                .single)
            as Map;
    expect(auctionCard, isNot(contains('snapshot_value')));
    final encoded = jsonEncode(publicJson);
    expect(encoded, isNot(contains('personal_value')));
    expect(encoded, isNot(contains('opposite_personal_value')));
    expect(encoded, isNot(contains('snapshot_value')));
    final injected = Map<String, Object?>.from(publicJson)
      ..['opponent_reveal'] = opponentReveal.toJson();
    expect(NetworkGameRoundStateDto.fromJson(injected).opponentReveal, isNull);
  });

  test('Realtime observes only revision-only public round events', () {
    final migration = File(
      'supabase/migrations/202610080001_v4_action_completion.sql',
    ).readAsStringSync();
    final gameRepository = File(
      'lib/data/remote/supabase_network_game_repository.dart',
    ).readAsStringSync();
    final roundRepository = File(
      'lib/data/remote/supabase_network_round_repository.dart',
    ).readAsStringSync();

    expect(migration, contains('network_round_public_events'));
    final eventTable = RegExp(
      r'create table if not exists public\.network_round_public_events \((.*?)\);',
      dotAll: true,
    ).firstMatch(migration)!.group(1)!;
    expect(eventTable, contains('round_id'));
    expect(eventTable, contains('session_id'));
    expect(eventTable, contains('revision'));
    expect(eventTable, isNot(contains('initial_resolution')));
    expect(eventTable, isNot(contains('negotiation')));
    expect(eventTable, isNot(contains('final_resolution')));
    expect(eventTable, isNot(contains('snapshot_value')));
    expect(
      migration,
      contains(
        'revoke select on public.network_rounds from anon, authenticated',
      ),
    );
    expect(
      migration,
      contains('drop policy if exists "members observe round changes"'),
    );
    expect(
      migration,
      contains(
        'alter publication supabase_realtime drop table public.network_rounds',
      ),
    );
    expect(
      migration,
      contains(
        'alter publication supabase_realtime add table public.network_round_public_events',
      ),
    );
    expect(gameRepository, contains("from('network_round_public_events')"));
    expect(roundRepository, contains("from('network_round_public_events')"));
    expect(gameRepository, isNot(contains("from('network_rounds')")));
    expect(roundRepository, isNot(contains("from('network_rounds')")));
  });

  test('the first zero occurrence signal ends the common cycle', () async {
    final backend = _Backend();
    backend.round.phase = NetworkGamePhase.finalResolved;
    final alice = backend.repository('alice');
    final bob = backend.repository('bob');
    await alice.readyNextRound(
      command: _command('zero-alice', 'alice', 'READY_NEXT', backend.round.id),
      noPlayableOccurrences: true,
    );
    expect(backend.state('alice').cycleExhausted, isTrue);
    expect(backend.state('bob').cycleExhausted, isTrue);
    final waiting = await bob.readyNextRound(
      command: _command('next-bob', 'bob', 'READY_NEXT', backend.round.id),
    );
    expect(waiting.phase, NetworkGamePhase.waitingNext);
    expect(waiting.cycleExhausted, isTrue);
    await expectLater(
      alice.readyNextRound(
        command: _command(
          'close-alice',
          'alice',
          'READY_NEXT',
          backend.round.id,
        ),
      ),
      throwsA(
        isA<NetworkRoundException>().having(
          (error) => error.code,
          'code',
          'ROUND_CYCLE_EXHAUSTED',
        ),
      ),
    );
    expect(backend.currentRound, 1);
  });

  test('canonical cycle exhaustion is shared in hybrid mode', () async {
    final backend = _Backend()
      ..hybridMode = true
      ..cycleExhausted = true
      ..hybridOrientation = HybridDeckOrientation.distance;
    final alice = NetworkGameController(
      session: session,
      playerId: 'alice',
      repository: backend.repository('alice'),
      privateStore: MemoryNetworkDuelSecretStore(),
      learningStore: MemoryNetworkProfileLearningStore(),
      catalog: catalog,
      sessionMode: V4SessionMode.hybrid,
    );
    final bob = NetworkGameController(
      session: session,
      playerId: 'bob',
      repository: backend.repository('bob'),
      privateStore: MemoryNetworkDuelSecretStore(),
      learningStore: MemoryNetworkProfileLearningStore(),
      catalog: catalog,
      sessionMode: V4SessionMode.hybrid,
    );
    addTearDown(alice.dispose);
    addTearDown(bob.dispose);

    await Future.wait([alice.start(), bob.start()]);

    expect(alice.deckExhausted, isTrue);
    expect(bob.deckExhausted, isTrue);
  });

  test(
    'server continuation creates one clean canonical cycle and preserves session state',
    () async {
      final backend = _Backend()
        ..cycleExhausted = true
        ..v4UnlockedSpice = 3
        ..hybridOrientation = HybridDeckOrientation.distance
        ..persistentEffects = const [
          V4PersistentEffect(
            cardId: 'card.v4.033',
            targetPlayerId: 'bob',
            remainingActions: 2,
          ),
        ]
        ..round.phase = NetworkGamePhase.waitingNext
        ..round.ready.addAll(const {'alice', 'bob'});
      backend.points
        ..['alice'] = 87
        ..['bob'] = 76;
      backend.clothingCounts
        ..['alice'] = 3
        ..['bob'] = 4;
      final store = MemoryNetworkDuelSecretStore();
      final bobStore = MemoryNetworkDuelSecretStore();
      final oldSources = <String, ConceptUsageSnapshot>{};
      final oldHistories = <String, NetworkPlayedCardRecord>{};
      for (final entry in {'alice': store, 'bob': bobStore}.entries) {
        final owner = entry.key;
        final action = ResolvedConceptAction.fromJson({
          'concept_id': '018',
          'catalog_version': 1,
          'locale': 'fr-FR',
          'stage_id': '018.stage.1',
          'effective_chili': 1,
          'direction': 'FAIRE',
          'actor_player_ids': [owner],
          'target_player_ids': [owner == 'alice' ? 'bob' : 'alice'],
          'parameters': {'committed_at': '2026-09-29T12:00:00.000Z'},
          'accessories': <Object?>[],
          'effects': <Object?>[],
          'tags': ['v3.preference.simuler', 'v3.direction.faire', 'v3.direction.recevoir'],
          'primary_preference_ids': ['v3.preference.simuler'],
          'personal_values': [{'player_id': owner, 'role': 'FAIRE', 'value': 10}],
          'action_text': catalog.concepts!.concepts.singleWhere((c) => c.id == '018').actionText,
        });
        var checkpoint = ConceptUsageCheckpoint.startCycle(
          sessionId: session.id, ownerPlayerId: owner, cycle: 1,
          catalog: catalog.concepts!, initialClothing: owner == 'alice' ? 3 : 4,
        ).reserve(intentId: 'historical-018', conceptId: '018')
          .engage(intentId: 'historical-018', conceptId: '018',
            resolveAction: () => action, clock: () => DateTime.utc(2026, 9, 29, 12));
        final source = checkpoint.usageForIntent('historical-018')!;
        oldSources[owner] = source;
        final projection = NetworkUsageProjection.fromSnapshot(source,
          sharedParameterKeys: action.parameters.keys.toSet(), sharedEffectIds: const {},
          includePersonalValue: true);
        final record = NetworkPlayedCardRecord(usage: projection, roundNumber: 0);
        oldHistories[owner] = record;
        final draft = ConceptUsageSnapshot.create(sessionId: session.id,
          ownerPlayerId: owner, cycle: 1, intentId: 'round-1:negotiation:pending',
          engagedAt: DateTime.utc(2026, 9, 29, 13), action: action,
          sourceUsageId: source.usageId);
        checkpoint = checkpoint.reserve(intentId: draft.intentId, conceptId: '018');
        await entry.value.saveGame(sessionId: session.id, playerId: owner,
          state: NetworkPrivateGameState(
            roundNumber: 1,
            cards: [CardRuntimeState(cardId: '001', zone: CardZone.HAND)],
            deckCycle: 1, conceptCheckpoint: checkpoint,
            reservedChoices: {draft.intentId: draft}, publicDiscards: [record],
            sessionMode: V4SessionMode.hybrid, presence: V4SessionPresence.distance,
            initialClothing: owner == 'alice' ? 3 : 4,
            clothesByPlayer: const {'alice': 3, 'bob': 4},
            persistentEffects: const [V4PersistentEffect(cardId: 'card.v4.033',
              targetPlayerId: 'bob', remainingActions: 3)],
            accessoryPool: V4SessionAccessoryPool(profileAccessories: [
              V4Accessory(id: 'accessory-1', name: 'Accessoire conservé',
                ownerPlayerId: 'alice', tags: const {V4AccessoryTag.vibrant}),
            ]),
          ));
      }
      final controller = NetworkGameController(
        session: session,
        playerId: 'alice',
        repository: backend.repository('alice'),
        privateStore: store,
        learningStore: MemoryNetworkProfileLearningStore(),
        catalog: catalog,
        sessionMode: V4SessionMode.hybrid,
      );
      final bob = NetworkGameController(
        session: session,
        playerId: 'bob',
        repository: backend.repository('bob'),
        privateStore: bobStore,
        learningStore: MemoryNetworkProfileLearningStore(),
        catalog: catalog,
        sessionMode: V4SessionMode.hybrid,
      );
      addTearDown(controller.dispose);
      addTearDown(bob.dispose);
      await Future.wait([controller.start(), bob.start()]);

      await Future.wait([
        controller.continueDeck(DeckExhaustionChoice.infinite),
        controller.continueDeck(DeckExhaustionChoice.infinite),
      ]);
      await _settle();

      expect(backend.deckCycle, 2);
      expect(backend.infiniteMode, isTrue);
      expect(backend.currentRound, 2);
      expect(controller.actionPoints, {'alice': 87, 'bob': 76});
      expect(controller.activeSpice, 3);
      expect(controller.presence, V4SessionPresence.distance);
      expect(bob.presence, V4SessionPresence.distance);
      expect(controller.runtime, hasLength(const BalanceConfig().handSize));
      expect(controller.runtime, everyElement(isA<CardRuntimeState>()));
      expect(
        controller.runtime.map((card) => card.zone),
        everyElement(CardZone.HAND),
      );

      final saved = (await store.loadGame(
        sessionId: session.id,
        playerId: 'alice',
      ))!;
      expect(saved.deckCycle, 2);
      expect(saved.publicDiscards.single.toJson(), oldHistories['alice']!.toJson());
      expect(saved.clothesByPlayer, {'alice': 3, 'bob': 4});
      expect(saved.accessoryPool.available.single.id, 'accessory-1');
      expect(saved.persistentEffects.single.remainingActions, 2);
      expect(saved.conceptCheckpoint!.cycle, 2);
      expect(saved.cards.where((card) => card.zone != CardZone.HAND), isEmpty);
      for (final player in [controller, bob]) {
        final state = (await player.privateStore.loadGame(sessionId: session.id, playerId: player.playerId))!;
        final fresh = ConceptUsageCheckpoint.startCycle(sessionId: session.id,
          ownerPlayerId: player.playerId, cycle: 2, catalog: catalog.concepts!,
          initialClothing: state.initialClothing);
        expect(state.deckCycle, 2);
        expect(state.conceptCheckpoint!.encode(), fresh.encode());
        expect(state.reservedChoices, isEmpty);
        expect(state.pendingSecondaryCommand, isNull);
        expect(state.activeReveal, isNull);
        expect(state.publicDiscards.single.toJson(), oldHistories[player.playerId]!.toJson());
        expect(state.priorCheckpoints.single.usageForIntent('historical-018')!.toJson(),
          oldSources[player.playerId]!.toJson());
        expect(state.priorCheckpoints.single.reservationsByIntent, isEmpty);
        final oldId = oldSources[player.playerId]!.usageId;
        expect(player.visibleDiscardUsages.any((u) => u.usageId == oldId), isTrue);
        // This source still matches an admissible option and has fresh capacity:
        // the cycle boundary, rather than another eligibility rule, excludes it.
        expect(player.usageCheckpoint.availableFor('018'), 3);
        expect(player.choicesFor('018').any((o) => o.choice.actionId == '018.stage.1' &&
          o.choice.zoneId == null), isTrue);
        expect(player.corruptionCards.any((c) => c.identity == oldId), isFalse);
        expect(player.auctionCards.any((c) => c.identity == oldId), isFalse);
        expect(player.recoveryCards.any((c) => c.identity == oldId), isTrue);
        expect(ConceptUsageSnapshot.identityFor(session.id, player.playerId, 2,
          oldSources[player.playerId]!.intentId), isNot(oldId));
      }
      final setup = _Setup(backend, controller, bob);
      await _playUnequal(setup, requireRepeatable: true);
      final newUsage = controller.usageCheckpoint.usagesByIntent.values.single;
      expect(newUsage.cycle, 2);
      expect(newUsage.usageId, isNot(oldSources['alice']!.usageId));
      final loser = controller.isInitialLoser ? controller : bob;
      await loser.skipCorruption();
      await _settle();
      await _completeResolvedAction(setup);
      await _settle();
      final afterPlay = (await store.loadGame(sessionId: session.id, playerId: 'alice'))!;
      expect(afterPlay.publicDiscards.any((r) => r.usageId == newUsage.usageId), isTrue);
      expect(controller.corruptionCards.any((c) => c.identity == newUsage.usageId), isTrue);
      expect(controller.corruptionCards.any((c) => c.identity == oldSources['alice']!.usageId), isFalse);
      expect(controller.usageCheckpoint.usagesByIntent.values.single.toJson(), newUsage.toJson());
    },
  );

  test(
    'reconnect observes a newer cycle once and rebuilds from its stock',
    () async {
      final backend = _Backend()
        ..deckCycle = 2
        ..v4UnlockedSpice = 2
        ..round.phase = NetworkGamePhase.waitingNext
        ..round.ready.addAll(const {'alice', 'bob'});
      final store = MemoryNetworkDuelSecretStore();
      final oldCards = _handStates(catalog).take(4).toList();
      await store.saveGame(
        sessionId: session.id,
        playerId: 'alice',
        state: privateGameFixture(
          roundNumber: 1,
          cards: [
            oldCards[0].copyWith(zone: CardZone.HAND),
            oldCards[1].copyWith(zone: CardZone.DISCARD),
            oldCards[2].copyWith(zone: CardZone.EXHAUSTED),
            oldCards[3].copyWith(zone: CardZone.RESERVED),
          ],
          deckCycle: 1,
          parametersByUsage: {
            oldCards[1].occurrenceId: const V4ResolvedParameters(
              zoneSelectionSource: V4ZoneSelectionSource.game,
              zoneId: 'zone.old',
            ),
          },
        ),
      );
      final controller = _controller(backend, session, catalog, 'alice', store);
      addTearDown(controller.dispose);

      await controller.start();
      await _settle();

      expect(backend.currentRound, 2);
      final firstSaved = (await store.loadGame(
        sessionId: session.id,
        playerId: 'alice',
      ))!;
      expect(firstSaved.deckCycle, 2);
      expect(
        firstSaved.conceptCheckpoint!.usagesByIntent.values.where(
          (usage) => usage.action.zoneId == 'zone.old',
        ),
        isEmpty,
      );
      expect(
        firstSaved.cards.map((card) => card.zone),
        everyElement(CardZone.HAND),
      );

      final locked = controller.hand.first.identity;
      controller.toggleLock(locked);
      backend.notifyTwice();
      await _settle();

      expect(controller.lockedCardId, locked);
      expect(
        (await store.loadGame(
          sessionId: session.id,
          playerId: 'alice',
        ))!.deckCycle,
        2,
      );
    },
  );

  test('continuation is rejected before canonical cycle exhaustion', () async {
    final backend = _Backend()..round.phase = NetworkGamePhase.waitingNext;
    await expectLater(
      (backend.repository('alice') as NetworkSessionFlowRepository)
          .continueDeckCycle(
            expectedCycle: 1,
            command: _command(
              'early-cycle',
              'alice',
              'CONTINUE_CYCLE',
              backend.round.id,
            ),
            choice: DeckExhaustionChoice.keepStyle,
          ),
      throwsA(
        isA<NetworkRoundException>().having(
          (error) => error.code,
          'code',
          'ROUND_CYCLE_NOT_EXHAUSTED',
        ),
      ),
    );

    final sql = File(
      'supabase/migrations/'
      '202610100011_canonical_deck_cycle_transition.sql',
    ).readAsStringSync();
    expect(sql, contains('cycle_exhausted is true'));
    expect(sql, contains("raise exception 'ROUND_CYCLE_NOT_EXHAUSTED'"));
    expect(sql, contains('return public.get_current_network_game_round'));
  });

  test(
    'cycle continuation retry returns the same canonical increment',
    () async {
      final backend = _Backend()
        ..cycleExhausted = true
        ..round.phase = NetworkGamePhase.waitingNext;
      final repository =
          backend.repository('alice') as NetworkSessionFlowRepository;
      final command = _command(
        'continue-cycle-once',
        'alice',
        'CONTINUE_CYCLE',
        backend.round.id,
      );

      final first = await repository.continueDeckCycle(
        expectedCycle: 1,
        command: command,
        choice: DeckExhaustionChoice.infinite,
      );
      final retry = await repository.continueDeckCycle(
        expectedCycle: 1,
        command: command,
        choice: DeckExhaustionChoice.infinite,
      );

      expect(first.deckCycle, 2);
      expect(retry.deckCycle, 2);
      expect(backend.deckCycle, 2);
    },
  );

  test('player 2 advances after player 1 completed and disconnected', () async {
    final setup = await _setup(session, catalog);
    await _playUnequal(setup);
    final loser = setup.alice.isInitialLoser ? setup.alice : setup.bob;
    await loser.skipCorruption();
    await _settle();

    await setup.alice.completeAction();
    await _settle();
    expect(setup.backend.round.ready, {'alice'});
    setup.alice.dispose();

    await setup.bob.completeAction();
    await _settle();

    expect(setup.backend.currentRound, 2);
    expect(setup.backend.roundCreations, 2);
    expect(setup.bob.roundNumber, 2);
    expect(setup.bob.viewState, NetworkGameViewState.choosing);
    setup.bob.dispose();
  });

  test('concurrent next-round requests create one canonical round', () async {
    final backend = _Backend();
    backend.round
      ..phase = NetworkGamePhase.waitingNext
      ..ready.addAll(const {'alice', 'bob'});
    final oldRoundId = backend.round.id;
    final results = await Future.wait([
      backend
          .repository('alice')
          .readyNextRound(
            command: _command(
              'start-alice',
              'alice',
              'START_NEXT_ROUND',
              oldRoundId,
            ),
          ),
      backend
          .repository('bob')
          .readyNextRound(
            command: _command(
              'start-bob',
              'bob',
              'START_NEXT_ROUND',
              oldRoundId,
            ),
          ),
    ]);

    expect(backend.currentRound, 2);
    expect(backend.roundCreations, 2);
    expect(results.map((state) => state.roundId).toSet(), {'round-2'});
  });

  test('retry after next-round creation returns the canonical round', () async {
    final backend = _Backend();
    backend.round
      ..phase = NetworkGamePhase.waitingNext
      ..ready.addAll(const {'alice', 'bob'});
    final oldRoundId = backend.round.id;
    final repository = backend.repository('bob');
    final command = _command(
      'start-bob',
      'bob',
      'START_NEXT_ROUND',
      oldRoundId,
    );

    final created = await repository.readyNextRound(command: command);
    final retried = await repository.readyNextRound(command: command);

    expect(created.roundId, 'round-2');
    expect(retried.roundId, created.roundId);
    expect(backend.roundCreations, 2);
  });

  test(
    'settled PA spice survives player 2 advancement and legacy publication',
    () async {
      final backend = _Backend();
      backend.round
        ..phase = NetworkGamePhase.waitingNext
        ..ready.addAll(const {'alice', 'bob'});
      final oldRoundId = backend.round.id;
      backend.points['alice'] = 60;

      await backend
          .repository('bob')
          .readyNextRound(
            command: _command(
              'start-bob',
              'bob',
              'START_NEXT_ROUND',
              oldRoundId,
            ),
          );
      final published =
          await (backend.repository('alice') as NetworkSessionFlowRepository)
              .publishUnlockedSpice(
                command: _command(
                  'spice-alice',
                  'alice',
                  'PUBLISH_V4_SPICE',
                  oldRoundId,
                ),
                unlockedSpice: 2,
              );

      expect(backend.currentRound, 2);
      expect(backend.v4UnlockedSpice, 2);
      expect(published.roundId, 'round-2');
      expect(published.v4UnlockedSpice, 2);
    },
  );

  test('next-round migration accepts a concurrent caller after close', () {
    final sql = File(
      'supabase/migrations/'
      '202610100009_player_independent_next_round.sql',
    ).readAsStringSync();

    expect(sql, contains("v_round.phase = 'CLOSED'"));
    expect(sql, contains('state.current_round_number > v_round.round_number'));
    expect(sql, contains('return public.get_current_network_game_round'));
    expect(sql, contains('pg_advisory_xact_lock'));
    expect(sql, contains('on conflict (session_id, round_number) do nothing'));
    expect(sql, contains('publish_network_v4_unlocked_spice'));
    expect(sql, contains('state.current_round_number=v_round.round_number+1'));
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
    final state = privateGameFixture(
      roundNumber: 1,
      cards: const [
        CardRuntimeState(cardId: '001', zone: CardZone.HAND, locked: true),
      ],
      activeReveal: reveal,
      sessionMode: V4SessionMode.hybrid,
      presence: V4SessionPresence.distance,
      parametersByUsage: const {
        'card.hug': V4ResolvedParameters(
          zoneSelectionSource: V4ZoneSelectionSource.game,
          sexualOrIntimateZone: true,
          zoneId: 'zone.intimate',
          accessoryId: 'temp-1',
        ),
      },
      persistentEffects: const [
        V4PersistentEffect(
          cardId: 'card.v4.033',
          targetPlayerId: 'bob',
          remainingActions: 2,
        ),
      ],
      clothesByPlayer: const {'alice': 3, 'bob': 4},
      accessoryPool: V4SessionAccessoryPool(
        profileAccessories: const [],
        temporaryAccessories: [
          V4Accessory(
            id: 'temp-1',
            name: 'Temporaire',
            ownerPlayerId: 'alice',
            tags: const {V4AccessoryTag.vibrant},
            temporary: true,
          ),
        ],
      ),
    );
    final decoded = NetworkPrivateGameState.fromJson(state.toJson());
    expect(decoded.cards.single.locked, isTrue);
    expect(decoded.activeReveal!.nonce, 'private-nonce');
    expect(decoded.sessionMode, V4SessionMode.hybrid);
    expect(decoded.presence, V4SessionPresence.distance);
    expect(decoded.conceptCheckpoint!.stock.remainingFor('001'), 1);
    expect(decoded.persistentEffects.single.remainingActions, 2);
    expect(decoded.clothesByPlayer['alice'], 3);
    expect(decoded.accessoryPool.available.single.id, 'temp-1');
    expect(
      jsonEncode(_Backend().state('bob').toJson()),
      isNot(contains('private-nonce')),
    );
  });

  test('public round DTO carries canonical persistent effects', () {
    final canonical = NetworkGameRoundStateDto(
      roundId: 'round',
      sessionId: 'session',
      sessionRound: 'session.round-1',
      roundNumber: 1,
      phase: NetworkGamePhase.waitingNext,
      playerId: 'alice',
      commits: const {},
      actionPoints: const {'alice': 100, 'bob': 100},
      readyNextPlayerIds: const {'alice', 'bob'},
      tieDecisions: const {},
      v4PersistentEffects: const [
        V4PersistentEffect(
          cardId: 'card.v4.034',
          targetPlayerId: 'bob',
          remainingActions: 2,
        ),
      ],
    );

    final decoded = NetworkGameRoundStateDto.fromJson(canonical.toJson());
    expect(decoded.hasCanonicalPersistentEffects, isTrue);
    expect(
      decoded.v4PersistentEffects.map((effect) => effect.toJson()),
      canonical.v4PersistentEffects.map((effect) => effect.toJson()),
    );

    final legacyJson = Map<String, Object?>.from(canonical.toJson())
      ..remove('v4_persistent_effects');
    final legacy = NetworkGameRoundStateDto.fromJson(legacyJson);
    expect(legacy.hasCanonicalPersistentEffects, isFalse);
    expect(legacy.v4PersistentEffects, isEmpty);
  });

  test('persistent-effect migration owns one canonical close transition', () {
    final sql = File(
      'supabase/migrations/202610100013_canonical_persistent_effects.sql',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    expect(sql, contains('v4_persistent_effects jsonb not null'));
    expect(sql, startsWith('-- Persist duration-card effects'));
    expect(sql, contains('\nbegin;\n'));
    final transactionStart = sql.indexOf('\nbegin;\n');
    final roundLock = sql.indexOf(
      'lock table public.network_rounds in share row exclusive mode',
    );
    final backfill = sql.indexOf('\ndo \$\$');
    final trigger = sql.indexOf(
      'create trigger network_v4_persistent_effects_on_action_close',
    );
    final transactionCommit = sql.lastIndexOf('\ncommit;');
    expect(transactionStart, lessThan(roundLock));
    expect(roundLock, lessThan(backfill));
    expect(backfill, lessThan(trigger));
    expect(trigger, lessThan(transactionCommit));
    expect(
      sql,
      contains('lock table public.network_rounds in share row exclusive mode'),
    );
    for (final cardId in const [
      '033',
      '034',
      '035',
      '060',
      '061',
      '062',
      '063',
    ]) {
      expect(sql, contains("('card.v4.$cardId',3)"));
    }
    expect(
      sql,
      contains("old.phase='FINAL_RESOLVED' and new.phase='WAITING_NEXT'"),
    );
    expect(sql, contains("round.phase in ('WAITING_NEXT','CLOSED')"));
    expect(sql, isNot(contains("round.phase='FINAL_RESOLVED'")));
    expect(sql, contains("'v4_persistent_effects',g.v4_persistent_effects"));
    expect(sql.trimRight(), endsWith('commit;'));
    expect(
      sql,
      contains(
        'revoke update on public.network_game_states\n'
        '  from anon,authenticated',
      ),
    );
    expect(
      sql,
      contains(
        'revoke all on public.network_v4_persistent_effect_definitions\n'
        '  from anon,authenticated',
      ),
    );
    expect(sql, isNot(contains('persistent_effect_event')));
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
    'READY resolves server-side without exposing the opponent reveal',
    () async {
      final backend = _Backend()..redactOpponentReveal = true;
      backend.round
        ..phase = NetworkGamePhase.ready
        ..reveals['alice'] = ChoiceRevealDto(
          sessionRound: 'session-multi.round-1',
          playerId: 'alice',
          choice: _choice('alice', 14),
          nonce: 'nonce-alice',
        )
        ..reveals['bob'] = ChoiceRevealDto(
          sessionRound: 'session-multi.round-1',
          playerId: 'bob',
          choice: _choice('bob', 8),
          nonce: 'nonce-bob',
        );
      final controller = NetworkGameController(
        session: session,
        playerId: 'alice',
        repository: _PrivateResolutionRepository(backend, 'alice'),
        privateStore: MemoryNetworkDuelSecretStore(),
        learningStore: MemoryNetworkProfileLearningStore(),
        catalog: catalog,
      );
      addTearDown(controller.dispose);

      expect(backend.state('alice').opponentReveal, isNull);
      await controller.start();
      await _settle();

      expect(backend.round.initial!.winnerPlayerId, 'alice');
      expect(backend.round.initial!.gap, 6);
      expect(controller.round!.opponentReveal, isNull);
      expect(controller.initialResolution!.winnerPlayerId, 'alice');
    },
  );

  test(
    'controllers keep four private cards and engage without exposing hand',
    () async {
      final setup = await _setup(session, catalog);
      expect(setup.alice.hand, hasLength(4));
      expect(setup.bob.hand, hasLength(4));
      final selected = setup.alice.hand.firstWhere(setup.alice.isCardPlayable);
      final locked = setup.alice.hand
          .firstWhere((card) => card.identity != selected.identity)
          .identity;
      setup.alice.toggleLock(locked);
      expect(setup.alice.lockedCardId, locked);
      final capacityBefore = setup.alice.usageCheckpoint.stock.remainingFor(selected.id);
      setup.alice.selectCard(selected.identity);
      await setup.alice.confirmSelection();
      expect(
        setup.alice.runtime
            .singleWhere(
              (card) =>
                  card.cardId == selected.id && card.zone == CardZone.ENGAGED,
            )
            .zone,
        CardZone.ENGAGED,
      );
      expect(setup.alice.runtime, hasLength(4));
      expect(setup.bob.runtime, hasLength(4));
      expect(setup.alice.hand, hasLength(3));
      expect(setup.bob.hand, hasLength(4));
      expect(setup.alice.runtime.where((c) => c.zone == CardZone.ENGAGED), hasLength(1));
      final checkpoint = setup.alice.usageCheckpoint;
      final usage = checkpoint.usagesByIntent.values.single;
      expect(usage.conceptId, selected.id);
      expect(checkpoint.stock.remainingFor(selected.id), capacityBefore - 1);
      expect(checkpoint.reservationsByIntent, isEmpty);
      expect(usage.usageId, ConceptUsageSnapshot.identityFor(
        session.id, 'alice', checkpoint.cycle, usage.intentId));
      final saved = (await setup.alice.privateStore.loadGame(
        sessionId: session.id, playerId: 'alice'))!;
      expect(saved.conceptCheckpoint!.encode(), checkpoint.encode());
      expect(saved.activeReveal!.choice.usageId, usage.usageId);
      await setup.alice.confirmSelection();
      expect(setup.alice.usageCheckpoint.encode(), checkpoint.encode());
      expect(setup.backend.round.commits, hasLength(1));
      final peerState = setup.backend.state('bob').toJson();
      void expectNoPrivateKeys(Object? value) {
        if (value is Map<String, Object?>) {
          expect(value.keys.toSet().intersection({
            'hand', 'locked', 'profile', 'preferences', 'personal_value', 'nonce',
          }), isEmpty);
          for (final nested in value.values) {
            expectNoPrivateKeys(nested);
          }
        } else if (value is List<Object?>) {
          for (final nested in value) {
            expectNoPrivateKeys(nested);
          }
        }
      }
      expectNoPrivateKeys(peerState);
      expect(peerState['own_reveal'], isNull);
      expect(peerState['opponent_reveal'], isNull);
      expect(peerState['action_projection'], isNull);
      expect(peerState['commits'], {
        'alice': setup.backend.round.commits['alice']!.digest,
      });
      expect(setup.alice.lockedCardId, locked);
      expect(
        jsonEncode(setup.backend.state('bob').toJson()),
        isNot(contains(locked)),
      );
      setup.dispose();
    },
  );

  test(
    'private directional consent constrains resolved and engaged actions',
    () async {
      final focusedCatalog = _catalogWithCards(catalog, {'card.v4.002'});
      for (final allowed in [
        CardOccurrenceDirection.RECEVOIR,
        CardOccurrenceDirection.FAIRE,
        null,
      ]) {
        final backend = _Backend();
        final controller = NetworkGameController(
          session: session,
          playerId: 'alice',
          repository: backend.repository('alice'),
          privateStore: MemoryNetworkDuelSecretStore(),
          learningStore: MemoryNetworkProfileLearningStore(),
          catalog: focusedCatalog,
          privateProfile: PlayerGameProfile(
            playerId: 'alice',
            preferences: {
              'v3.preference.embrasser': PreferenceValue(
                status: PreferenceStatus.ACCEPTED,
                general: 10,
                faire: allowed == CardOccurrenceDirection.FAIRE ? 6 : null,
                recevoir: allowed == CardOccurrenceDirection.RECEVOIR
                    ? 8
                    : null,
              ),
            },
          ),
        );
        addTearDown(controller.dispose);
        await controller.start();
        if (allowed == null) {
          expect(controller.hand, isEmpty);
          expect(controller.choicesFor('002'), isEmpty);
          controller.selectCard('002');
          await controller.confirmSelection();
          expect(controller.usageCheckpoint.usagesByIntent, isEmpty);
          expect(controller.usageCheckpoint.reservationsByIntent, isEmpty);
          expect(controller.usageCheckpoint.stock.remainingFor('002'), 1);
          expect(backend.round.commits, isEmpty);
        } else {
          expect(
            controller.hand.map((c) => c.nativeDirection),
            everyElement(allowed),
          );
          expect(controller.hand.single.oppositePersonalValue, isNull);
          expect(controller.choicesFor('002'), isNotEmpty);
          final card = controller.hand.single;
          controller.selectCard(card.identity);
          controller.chooseAction(controller.choicesFor('002').first);
          expect(controller.selectedCard!.effectiveDirection, allowed);
          await controller.confirmSelection();
          final usage = controller.usageCheckpoint.usagesByIntent.values.single;
          expect(usage.action.direction, allowed);
          expect(usage.invertedAction, isNull);
          expect(
            usage.action.personalValues.single.value,
            allowed == CardOccurrenceDirection.FAIRE ? 6 : 8,
          );
          expect(controller.usageCheckpoint.stock.remainingFor('002'), 0);
          final saved = (await controller.privateStore.loadGame(
            sessionId: session.id,
            playerId: 'alice',
          ))!;
          expect(saved.activeReveal!.choice.usageId, usage.usageId);
          expect(
            saved.conceptCheckpoint!.usageForIntent(usage.intentId)!.toJson(),
            usage.toJson(),
          );
        }
      }
    },
  );
  test('V4 exclusion vetoes the whole concept across directions', () async {
    final focusedCatalog = _catalogWithCards(catalog, {'card.v4.002'});
    for (final excludedRole in [
      ProfilePreferenceRole.faire,
      ProfilePreferenceRole.recevoir,
    ]) {
      final backend = _Backend();
      final preferences = <String, ProfilePreference>{};
      for (final role in [
        ProfilePreferenceRole.faire,
        ProfilePreferenceRole.recevoir,
      ]) {
        final key = ProfilePreferenceKey(tagId: 'embrasser', role: role);
        preferences[key.storageKey] = ProfilePreference(
          profileId: 'alice',
          key: key,
          pa: role == excludedRole ? null : 8,
          excluded: role == excludedRole,
          source: ProfilePreferenceSource.initialQuestionnaire,
        );
      }
      final controller = NetworkGameController(
        session: session,
        playerId: 'alice',
        repository: backend.repository('alice'),
        privateStore: MemoryNetworkDuelSecretStore(),
        learningStore: MemoryNetworkProfileLearningStore(),
        catalog: focusedCatalog,
        v4Profile: V4Profile(profileId: 'alice', preferences: preferences),
        scoringCatalog: scoringCatalog,
      );
      addTearDown(controller.dispose);
      await controller.start();
      expect(controller.hand, isEmpty);
      expect(controller.choicesFor('002'), isEmpty);
      controller.selectCard('002');
      await controller.confirmSelection();
      expect(controller.usageCheckpoint.usagesByIntent, isEmpty);
      expect(controller.usageCheckpoint.reservationsByIntent, isEmpty);
      expect(controller.usageCheckpoint.stock.remainingFor('002'), 1);
      expect(backend.round.commits, isEmpty);
    }
  });
  test('production catalog resolver imposes the canonical intimate zone', () {
    const current = V4ResolvedParameters(accessoryId: 'accessory-1');
    final resolved = const V4CatalogParameterResolver().resolve(
      catalog: scoringCatalog,
      cardId: 'card.v4.024',
      variantId: 'variant.v4.024.base',
      current: current,
    );

    expect(resolved.zoneSelectionSource, V4ZoneSelectionSource.game);
    expect(resolved.sexualOrIntimateZone, isTrue);
    expect(resolved.zoneId, 'zone.intime');
    expect(resolved.accessoryId, 'accessory-1');
    expect(resolved.effectiveSpice(3), 4);
  });

  // Accessory preference calculation is covered by the pure V4 accessory tests;
  // 049–052 remain unavailable pending validated inventory data.

  test(
    'shared adult content uses its explicitly defined RECEVOIR components',
    () async {
      final focusedCatalog = _catalogWithCards(catalog, {'card.v4.053'});
      // Independent canonical session fixtures: no client-local spice override.
      for (final (ceiling, primary, secondary, veto, expected) in const [
        (1, 1.0, 1.0, false, null),
        (2, 1.0, 1.0, false, 1),
        (2, 5.0, 12.0, false, 7),
        (2, 5.0, 12.0, true, null),
      ]) {
        final preferences = <String, ProfilePreference>{};
        void add(
          String tag,
          ProfilePreferenceRole role,
          double pa, {
          bool excluded = false,
        }) {
          final key = ProfilePreferenceKey(tagId: tag, role: role);
          preferences[key.storageKey] = ProfilePreference(
            profileId: 'alice',
            key: key,
            pa: excluded ? null : pa,
            excluded: excluded,
            source: ProfilePreferenceSource.initialQuestionnaire,
          );
        }

        add('contenu_adulte', ProfilePreferenceRole.faire, 20);
        add('regarder', ProfilePreferenceRole.faire, 10, excluded: veto);
        add('contenu_adulte', ProfilePreferenceRole.recevoir, primary);
        add('regarder', ProfilePreferenceRole.recevoir, secondary);
        final backend = _Backend()..v4UnlockedSpice = ceiling;
        final controller = NetworkGameController(
          session: session,
          playerId: 'alice',
          repository: backend.repository('alice'),
          privateStore: MemoryNetworkDuelSecretStore(),
          learningStore: MemoryNetworkProfileLearningStore(),
          catalog: focusedCatalog,
          v4Profile: V4Profile(profileId: 'alice', preferences: preferences),
          scoringCatalog: scoringCatalog,
        );
        try {
          await controller.start();
          await _settle();
          expect(controller.errorMessage, isNull);
          expect(controller.activeSpice, ceiling);
          expect(controller.presence, V4SessionPresence.presentiel);
          expect(controller.usageCheckpoint.stock.capacity['053'], 1);
          expect(controller.usageCheckpoint.stock.remainingFor('053'), 1);
          expect(controller.usageCheckpoint.usagesByIntent, isEmpty);
          if (expected == null) {
            expect(controller.choicesFor('053'), isEmpty);
            expect(controller.hand, isEmpty);
          } else {
            expect(controller.choicesFor('053'), hasLength(1));
            expect(
              controller.choicesFor('053').single.choice.actionId,
              '053.action',
            );
            expect(controller.choicesFor('053').single.choice.chili, 2);
            expect(controller.hand.single.id, '053');
            expect(
              controller.hand.single.effectiveDirection,
              CardOccurrenceDirection.MUTUEL,
            );
            // RECEVOIR only: roundHalfUp((primary * 1 + secondary * .5) / 1.5).
            // The deliberately different FAIRE values do not contribute.
            expect(controller.hand.single.personalValue, expected);
          }
        } finally {
          controller.dispose();
        }
      }
    },
  );

  test('hybrid boundary blocks an empty current context', () async {
    final presentCards = _cardIdsForPresence(
      catalog,
      V4PresenceCompatibility.presentiel,
    ).take(4).toSet();
    final focusedCatalog = _catalogWithCards(catalog, presentCards);
    final store = MemoryNetworkDuelSecretStore();
    await store.saveGame(
      sessionId: session.id,
      playerId: 'alice',
      state: privateGameFixture(
        roundNumber: 1,
        cards: _handStates(focusedCatalog),
        sessionMode: V4SessionMode.hybrid,
        presence: V4SessionPresence.distance,
      ),
    );
    final backend = _Backend()
      ..hybridOrientation = HybridDeckOrientation.distance
      ..round.phase = NetworkGamePhase.waitingNext;
    final controller = NetworkGameController(
      session: session,
      playerId: 'alice',
      repository: backend.repository('alice'),
      privateStore: store,
      learningStore: MemoryNetworkProfileLearningStore(),
      catalog: focusedCatalog,
      sessionMode: V4SessionMode.hybrid,
    );
    addTearDown(controller.dispose);
    await controller.start();

    expect(controller.mustSwitchHybridContext, isTrue);
    expect(controller.canStartNextRound, isFalse);
    await controller.completeAction();
    expect(backend.currentRound, 1);
    expect(backend.round.phase, NetworkGamePhase.waitingNext);
  });

  test(
    'server session mode wins over stale private state on reconnect',
    () async {
      for (final fixedMode in [
        V4SessionMode.presentiel,
        V4SessionMode.distance,
      ]) {
        final expected = fixedMode == V4SessionMode.presentiel
            ? V4SessionPresence.presentiel
            : V4SessionPresence.distance;
        final stale = expected == V4SessionPresence.presentiel
            ? V4SessionPresence.distance
            : V4SessionPresence.presentiel;
        final store = MemoryNetworkDuelSecretStore();
        await store.saveGame(
          sessionId: session.id,
          playerId: 'alice',
          state: privateGameFixture(
            roundNumber: 1,
            cards: const [CardRuntimeState(cardId: '001', zone: CardZone.HAND)],
            sessionMode: V4SessionMode.hybrid,
            presence: stale,
          ),
        );
        final backend = _Backend();
        // Even a contradictory hybrid-orientation cache must not invert a fixed mode.
        backend.hybridOrientation = stale == V4SessionPresence.distance
            ? HybridDeckOrientation.distance
            : HybridDeckOrientation.faceToFace;
        final controller = NetworkGameController(
          session: session,
          playerId: 'alice',
          repository: backend.repository('alice'),
          privateStore: store,
          learningStore: MemoryNetworkProfileLearningStore(),
          catalog: catalog,
          sessionMode: fixedMode,
        );
        try {
          await controller.start();
          await _settle();
          expect(controller.errorMessage, isNull);
          expect(controller.sessionMode, fixedMode);
          expect(controller.presence, expected);
          expect(
            controller.choicesFor('001').isNotEmpty,
            fixedMode == V4SessionMode.presentiel,
          );
          expect(controller.mustSwitchHybridContext, isFalse);
          expect(backend.hybridAvailability, isEmpty);
          expect(backend.currentRound, 1);
        } finally {
          controller.dispose();
        }
      }
    },
  );

  test('hybrid switch returns incompatible hand cards and redraws', () async {
    final presentCards = _cardIdsForPresence(
      catalog,
      V4PresenceCompatibility.presentiel,
    ).take(4).toSet();
    final bothCards = _cardIdsForPresence(
      catalog,
      V4PresenceCompatibility.both,
    ).take(6).toSet();
    final focusedCatalog = _catalogWithCards(catalog, {
      ...presentCards,
      ...bothCards,
    });
    for (final from in [
      HybridDeckOrientation.faceToFace,
      HybridDeckOrientation.distance,
    ]) {
      final to = from == HybridDeckOrientation.faceToFace
          ? HybridDeckOrientation.distance
          : HybridDeckOrientation.faceToFace;
      final initialIds = from == HybridDeckOrientation.faceToFace
          ? _handStates(
              _catalogWithCards(catalog, presentCards),
            ).map((c) => conceptFixtureId(c.cardId)).toSet()
          : {'018', '032', '038', '039'};
      final store = MemoryNetworkDuelSecretStore();
      await store.saveGame(
        sessionId: session.id,
        playerId: 'alice',
        state: privateGameFixture(
          roundNumber: 1,
          cards: [
            for (final id in initialIds)
              CardRuntimeState(cardId: id, zone: CardZone.HAND),
          ],
          sessionMode: V4SessionMode.hybrid,
          presence: from == HybridDeckOrientation.distance
              ? V4SessionPresence.distance
              : V4SessionPresence.presentiel,
        ),
      );
      final backend = _Backend()
        ..hybridMode = true
        ..hybridOrientation = from
        ..hybridAvailabilityOrientation = from
        ..hybridAvailabilityGeneration = 1
        ..hybridAvailability.addAll({
          for (final id in ['alice', 'bob'])
            id: NetworkHybridAvailabilityDto(
              orientation: from,
              hasPlayableCurrentOrientation: false,
              hasPlayableAlternateOrientation: true,
            ),
        })
        ..round.phase = NetworkGamePhase.waitingNext;
      final controller = NetworkGameController(
        session: session,
        playerId: 'alice',
        repository: backend.repository('alice'),
        privateStore: store,
        learningStore: MemoryNetworkProfileLearningStore(),
        catalog: focusedCatalog,
        sessionMode: V4SessionMode.hybrid,
      );
      addTearDown(controller.dispose);
      await controller.start();
      final checkpoint = controller.usageCheckpoint.encode();
      await controller.switchOrientation(to);
      await _settle();
      expect(backend.hybridOrientation, to);
      expect(
        controller.presence,
        to == HybridDeckOrientation.distance
            ? V4SessionPresence.distance
            : V4SessionPresence.presentiel,
      );
      expect(controller.hand, hasLength(4));
      expect(controller.hand.every(controller.isCardPlayable), isTrue);
      expect(controller.usageCheckpoint.encode(), checkpoint);
      if (to == HybridDeckOrientation.distance) {
        expect(
          controller.hand.map((c) => c.id),
          everyElement(isNot(isIn(initialIds))),
        );
        for (final id in ['001', '002', '003']) {
          expect(controller.choicesFor(id), isEmpty);
        }
      } else {
        expect(controller.hand.map((c) => c.id), containsAll(initialIds));
        for (final id in ['001', '002', '003']) {
          expect(controller.choicesFor(id), isNotEmpty);
        }
      }
      expect(backend.hybridAvailability['alice']!.orientation, to);
      expect(
        backend.hybridAvailability['alice']!.hasPlayableCurrentOrientation,
        isTrue,
      );
      expect(backend.currentRound, 1);
    }
  });
  test('hybrid switch refills an underfull compatible hand to four', () async {
    final bothCards = _cardIdsForPresence(
      catalog,
      V4PresenceCompatibility.both,
    ).take(6).toSet();
    final focusedCatalog = _catalogWithCards(catalog, bothCards);
    final savedHand = [
      for (final id in ['018', '032', '021'])
        CardRuntimeState(cardId: id, zone: CardZone.HAND),
    ];
    final savedIds = {'018', '032'};
    expect(savedHand, hasLength(3));
    final store = MemoryNetworkDuelSecretStore();
    await store.saveGame(
      sessionId: session.id,
      playerId: 'alice',
      state: privateGameFixture(
        roundNumber: 1,
        cards: savedHand,
        sessionMode: V4SessionMode.hybrid,
        presence: V4SessionPresence.presentiel,
      ),
    );
    final backend = _Backend()..round.phase = NetworkGamePhase.waitingNext;
    final controller = NetworkGameController(
      session: session,
      playerId: 'alice',
      repository: backend.repository('alice'),
      privateStore: store,
      learningStore: MemoryNetworkProfileLearningStore(),
      catalog: focusedCatalog,
      sessionMode: V4SessionMode.hybrid,
    );
    addTearDown(controller.dispose);
    await controller.start();

    await controller.switchOrientation(HybridDeckOrientation.distance);
    await _settle();

    expect(controller.hand, hasLength(4));
    expect(controller.hand.map((card) => card.id), containsAll(savedIds));
    expect(controller.hand.every(controller.isCardPlayable), isTrue);
    expect(controller.choicesFor('021'), isEmpty);
    expect(controller.hand.map((card) => card.id), isNot(contains('021')));
  });
  test('both hybrid players report availability before waiting-next', () async {
    final presentCards = _cardIdsForPresence(
      catalog,
      V4PresenceCompatibility.presentiel,
    ).take(4).toSet();
    final bothCards = _cardIdsForPresence(
      catalog,
      V4PresenceCompatibility.both,
    ).take(4).toSet();
    final bobCatalog = _catalogWithCards(catalog, presentCards);
    final aliceCatalog = _catalogWithCards(catalog, bothCards);
    final backend = _Backend()
      ..hybridMode = true
      ..hybridOrientation = HybridDeckOrientation.distance
      ..round.phase = NetworkGamePhase.finalResolved;
    final store = MemoryNetworkDuelSecretStore();
    await store.saveGame(
      sessionId: session.id,
      playerId: 'bob',
      state: privateGameFixture(
        roundNumber: 1,
        ownerPlayerId: 'bob',
        cards: _handStates(bobCatalog),
        sessionMode: V4SessionMode.hybrid,
        presence: V4SessionPresence.distance,
      ),
    );
    NetworkGameController bobController() => NetworkGameController(
      session: session,
      playerId: 'bob',
      repository: backend.repository('bob'),
      privateStore: store,
      learningStore: MemoryNetworkProfileLearningStore(),
      catalog: bobCatalog,
      sessionMode: V4SessionMode.hybrid,
    );
    final bob = bobController();
    final alice = NetworkGameController(
      session: session,
      playerId: 'alice',
      repository: backend.repository('alice'),
      privateStore: MemoryNetworkDuelSecretStore(),
      learningStore: MemoryNetworkProfileLearningStore(),
      catalog: aliceCatalog,
      sessionMode: V4SessionMode.hybrid,
    );
    var bobDisposed = false;
    addTearDown(() {
      if (!bobDisposed) bob.dispose();
    });
    addTearDown(alice.dispose);
    await Future.wait([bob.start(), alice.start()]);
    await _settle();
    expect(bob.errorMessage, isNull);
    expect(alice.presence, V4SessionPresence.distance);
    expect(bob.presence, V4SessionPresence.distance);
    expect(bob.hand.where(bob.isCardPlayable), isEmpty);
    expect(alice.hand.where(alice.isCardPlayable), isNotEmpty);
    await alice.completeAction();
    await _settle();
    expect(backend.round.phase, NetworkGamePhase.finalResolved);
    expect(backend.round.ready, {'alice'});
    expect(backend.hybridAvailability.keys, {'alice'});
    expect(
      backend.hybridAvailability['alice']!.hasPlayableCurrentOrientation,
      isTrue,
    );
    expect(backend.cycleExhausted, isFalse);
    await bob.completeAction();
    await _settle();
    expect(backend.round.phase, NetworkGamePhase.waitingNext);
    expect(backend.round.ready, {'alice', 'bob'});
    expect(backend.hybridAvailability.keys, {'alice', 'bob'});
    expect(
      backend.hybridAvailability['bob']!.hasPlayableCurrentOrientation,
      isFalse,
    );
    expect(
      backend.hybridAvailability['bob']!.hasPlayableAlternateOrientation,
      isTrue,
    );
    expect(backend.cycleExhausted, isFalse);
    expect(alice.mustSwitchHybridContext, isTrue);
    expect(alice.canStartNextRound, isFalse);
    // Bob is offline during the switch: Alice's new-generation report alone
    // cannot advance the round, even though she has playable concepts.
    bob.dispose();
    bobDisposed = true;
    await alice.switchOrientation(HybridDeckOrientation.faceToFace);
    await _settle();
    expect(backend.hybridOrientation, HybridDeckOrientation.faceToFace);
    expect(backend.hybridAvailabilityGeneration, 1);
    expect(backend.hybridAvailability.keys, {'alice'});
    expect(backend.currentRound, 1);
    expect(alice.canStartNextRound, isFalse);
    final reconnectedBob = bobController();
    addTearDown(reconnectedBob.dispose);
    await reconnectedBob.start();
    await _settle();
    expect(reconnectedBob.errorMessage, isNull);
    expect(backend.hybridAvailability.keys, {'alice', 'bob'});
    for (final report in backend.hybridAvailability.values) {
      expect(report.orientation, HybridDeckOrientation.faceToFace);
      expect(report.hasPlayableCurrentOrientation, isTrue);
    }
    expect(backend.cycleExhausted, isFalse);
    expect(backend.currentRound, 2);
    expect(backend.roundCreations, 2);
    for (final (player, playerCatalog) in [
      (alice, aliceCatalog),
      (reconnectedBob, bobCatalog),
    ]) {
      expect(player.presence, V4SessionPresence.presentiel);
      final available = playerCatalog.concepts!.concepts
          .where(
            (c) =>
                player.usageCheckpoint.availableFor(c.id) > 0 &&
                player.choicesFor(c.id).isNotEmpty,
          )
          .length;
      expect(player.hand.length, available.clamp(0, 4));
      expect(player.hand, isNotEmpty);
      expect(player.hand.every(player.isCardPlayable), isTrue);
    }
  });

  test('hybrid switch waits for both matching playable reports', () async {
    final backend = _Backend()
      ..hybridMode = true
      ..round.phase = NetworkGamePhase.waitingNext;
    final alice = backend.repository('alice') as NetworkSessionFlowRepository;
    final bob = backend.repository('bob') as NetworkSessionFlowRepository;

    final switched = await alice.setHybridOrientation(
      command: _command(
        'switch-distance',
        'alice',
        'SET_ORIENTATION',
        backend.round.id,
      ),
      orientation: HybridDeckOrientation.distance,
    );
    expect(switched.hybridAvailabilityByPlayer, isEmpty);

    await alice.reportHybridAvailability(
      command: _command(
        'report-alice-distance',
        'alice',
        'REPORT_HYBRID_AVAILABILITY',
        backend.round.id,
      ),
      availability: const NetworkHybridAvailabilityDto(
        orientation: HybridDeckOrientation.distance,
        hasPlayableCurrentOrientation: true,
        hasPlayableAlternateOrientation: true,
      ),
      generation: backend.hybridAvailabilityGeneration,
    );
    await expectLater(
      backend
          .repository('alice')
          .readyNextRound(
            command: _command(
              'start-before-bob',
              'alice',
              'START_NEXT_ROUND',
              backend.round.id,
            ),
          ),
      throwsA(
        isA<NetworkRoundException>().having(
          (error) => error.code,
          'code',
          'ROUND_HYBRID_AVAILABILITY_PENDING',
        ),
      ),
    );
    expect(backend.currentRound, 1);

    await bob.reportHybridAvailability(
      command: _command(
        'report-bob-distance',
        'bob',
        'REPORT_HYBRID_AVAILABILITY',
        backend.round.id,
      ),
      availability: const NetworkHybridAvailabilityDto(
        orientation: HybridDeckOrientation.distance,
        hasPlayableCurrentOrientation: true,
        hasPlayableAlternateOrientation: false,
      ),
      generation: backend.hybridAvailabilityGeneration,
    );
    final next = await backend
        .repository('bob')
        .readyNextRound(
          command: _command(
            'start-after-bob',
            'bob',
            'START_NEXT_ROUND',
            backend.round.id,
          ),
        );

    expect(next.roundNumber, 2);
    expect(backend.roundCreations, 2);
  });

  test('hybrid availability rejects a stale orientation report', () async {
    final backend = _Backend()
      ..hybridMode = true
      ..round.phase = NetworkGamePhase.waitingNext;
    final alice = backend.repository('alice') as NetworkSessionFlowRepository;
    await alice.setHybridOrientation(
      command: _command(
        'switch-distance-stale',
        'alice',
        'SET_ORIENTATION',
        backend.round.id,
      ),
      orientation: HybridDeckOrientation.distance,
    );

    await expectLater(
      alice.reportHybridAvailability(
        command: _command(
          'stale-face-report',
          'alice',
          'REPORT_HYBRID_AVAILABILITY',
          backend.round.id,
        ),
        availability: const NetworkHybridAvailabilityDto(
          orientation: HybridDeckOrientation.faceToFace,
          hasPlayableCurrentOrientation: true,
          hasPlayableAlternateOrientation: true,
        ),
        generation: backend.hybridAvailabilityGeneration,
      ),
      throwsA(
        isA<NetworkRoundException>().having(
          (error) => error.code,
          'code',
          'ROUND_HYBRID_ORIENTATION_STALE',
        ),
      ),
    );
    expect(backend.hybridAvailability, isEmpty);
  });

  test(
    'hybrid availability distinguishes switch from exhausted cycle',
    () async {
      Future<_Backend> report({required bool alternate}) async {
        final backend = _Backend()
          ..hybridMode = true
          ..hybridOrientation = HybridDeckOrientation.distance
          ..hybridAvailabilityOrientation = HybridDeckOrientation.distance
          ..hybridAvailabilityGeneration = 1
          ..round.phase = NetworkGamePhase.waitingNext;
        await (backend.repository('alice') as NetworkSessionFlowRepository)
            .reportHybridAvailability(
              command: _command(
                'availability-$alternate',
                'alice',
                'REPORT_HYBRID_AVAILABILITY',
                backend.round.id,
              ),
              availability: NetworkHybridAvailabilityDto(
                orientation: HybridDeckOrientation.distance,
                hasPlayableCurrentOrientation: false,
                hasPlayableAlternateOrientation: alternate,
              ),
              generation: 1,
            );
        return backend;
      }

      final switchable = await report(alternate: true);
      expect(switchable.cycleExhausted, isFalse);
      final exhausted = await report(alternate: false);
      expect(exhausted.cycleExhausted, isTrue);
    },
  );

  test('late hybrid client rebuilds and reports before progression', () async {
    final bothCards = _cardIdsForPresence(
      catalog,
      V4PresenceCompatibility.both,
    ).take(6).toSet();
    final focusedCatalog = _catalogWithCards(catalog, bothCards);
    final backend = _Backend()
      ..hybridMode = true
      ..hybridOrientation = HybridDeckOrientation.distance
      ..hybridAvailabilityOrientation = HybridDeckOrientation.distance
      ..hybridAvailabilityGeneration = 1
      ..round.phase = NetworkGamePhase.waitingNext;
    final alice = NetworkGameController(
      session: session,
      playerId: 'alice',
      repository: backend.repository('alice'),
      privateStore: MemoryNetworkDuelSecretStore(),
      learningStore: MemoryNetworkProfileLearningStore(),
      catalog: focusedCatalog,
      sessionMode: V4SessionMode.hybrid,
    );
    addTearDown(alice.dispose);
    await alice.start();
    await _settle();

    expect(backend.currentRound, 1);
    expect(backend.hybridAvailability.keys, {'alice'});
    expect(backend.hybridAvailabilityGeneration, 1);
    expect(
      backend.hybridAvailability['alice']!.orientation,
      HybridDeckOrientation.distance,
    );
    expect(
      backend.hybridAvailability['alice']!.hasPlayableCurrentOrientation,
      isTrue,
    );

    final bobStore = MemoryNetworkDuelSecretStore();
    await bobStore.saveGame(
      sessionId: session.id,
      playerId: 'bob',
      state: privateGameFixture(
        roundNumber: 1,
        ownerPlayerId: 'bob',
        cards: _handStates(focusedCatalog).take(2).toList(),
        sessionMode: V4SessionMode.hybrid,
        presence: V4SessionPresence.presentiel,
      ),
    );
    final bob = NetworkGameController(
      session: session,
      playerId: 'bob',
      repository: backend.repository('bob'),
      privateStore: bobStore,
      learningStore: MemoryNetworkProfileLearningStore(),
      catalog: focusedCatalog,
      sessionMode: V4SessionMode.hybrid,
    );
    var bobDisposed = false;
    addTearDown(() {
      if (!bobDisposed) bob.dispose();
    });
    await bob.start();
    await _settle();

    expect(bob.errorMessage, isNull);
    expect(bob.presence, V4SessionPresence.distance);
    expect(bob.hand.every(bob.isCardPlayable), isTrue);
    expect(backend.hybridAvailability.keys, {'alice', 'bob'});
    expect(
      backend.hybridAvailability['bob']!.orientation,
      HybridDeckOrientation.distance,
    );
    expect(
      backend.hybridAvailability['bob']!.hasPlayableCurrentOrientation,
      isTrue,
    );
    expect(backend.hybridAvailabilityGeneration, 1);
    expect(bob.hand, hasLength(4));
    expect(backend.currentRound, 2);
    expect(backend.roundCreations, 2);
    final retry = _command(
      'late-start-retry',
      'alice',
      'START_NEXT_ROUND',
      'round-1',
    );
    await backend.repository('alice').readyNextRound(command: retry);
    await backend.repository('alice').readyNextRound(command: retry);
    backend.notifyTwice();
    await _settle();
    bob.dispose();
    bobDisposed = true;
    final reconnect = NetworkGameController(
      session: session,
      playerId: 'bob',
      repository: backend.repository('bob'),
      privateStore: bobStore,
      learningStore: MemoryNetworkProfileLearningStore(),
      catalog: focusedCatalog,
      sessionMode: V4SessionMode.hybrid,
    );
    addTearDown(reconnect.dispose);
    await reconnect.start();
    await _settle();
    expect(reconnect.errorMessage, isNull);
    expect(reconnect.presence, V4SessionPresence.distance);
    expect(reconnect.hand.every(reconnect.isCardPlayable), isTrue);
    expect(backend.hybridOrientation, HybridDeckOrientation.distance);
    expect(backend.hybridAvailabilityGeneration, 1);
    expect(backend.currentRound, 2);
    expect(backend.roundCreations, 2);
  });

  test('hybrid rebuild guards a full but unplayable retained hand', () async {
    final bothCards = _cardIdsForPresence(
      catalog,
      V4PresenceCompatibility.both,
    ).take(6).toSet();
    final presentCards = _cardIdsForPresence(
      catalog,
      V4PresenceCompatibility.presentiel,
    ).take(4).toSet();
    final focusedCatalog = _catalogWithCards(catalog, {
      ...bothCards,
      ...presentCards,
    });
    final savedHand = _handStates(
      _catalogWithCards(catalog, presentCards),
    ).take(4).toList();
    final savedIds = savedHand
        .map((card) => conceptFixtureId(card.cardId))
        .toSet();
    expect(savedIds, hasLength(4));
    final store = MemoryNetworkDuelSecretStore();
    await store.saveGame(
      sessionId: session.id,
      playerId: 'alice',
      state: privateGameFixture(
        roundNumber: 1,
        cards: savedHand,
        sessionMode: V4SessionMode.hybrid,
        // The cached orientation already matches the canonical one. The new
        // generation must still force a rebuild before availability is sent.
        presence: V4SessionPresence.distance,
      ),
    );
    final backend = _Backend()
      ..hybridMode = true
      ..hybridOrientation = HybridDeckOrientation.distance
      ..hybridAvailabilityOrientation = HybridDeckOrientation.distance
      ..hybridAvailabilityGeneration = 1
      ..round.phase = NetworkGamePhase.waitingNext;
    final controller = NetworkGameController(
      session: session,
      playerId: 'alice',
      repository: backend.repository('alice'),
      privateStore: store,
      learningStore: MemoryNetworkProfileLearningStore(),
      catalog: focusedCatalog,
      sessionMode: V4SessionMode.hybrid,
    );
    addTearDown(controller.dispose);
    await controller.start();
    await _settle();

    expect(controller.hand, hasLength(4));
    expect(controller.hand.where(controller.isCardPlayable), isNotEmpty);
    expect(controller.hand.where(controller.isCardPlayable), hasLength(4));
    expect(
      controller.hand.map((c) => c.id),
      everyElement(isNot(isIn(savedIds))),
    );
    for (final id in savedIds) {
      expect(controller.choicesFor(id), isEmpty);
    }
    expect(
      backend.hybridAvailability['alice']!.hasPlayableCurrentOrientation,
      isTrue,
    );
  });
  test('hybrid availability retries are idempotent', () async {
    final backend = _Backend()
      ..hybridMode = true
      ..hybridOrientation = HybridDeckOrientation.distance
      ..hybridAvailabilityOrientation = HybridDeckOrientation.distance
      ..hybridAvailabilityGeneration = 1
      ..round.phase = NetworkGamePhase.waitingNext;
    final repository =
        backend.repository('alice') as NetworkSessionFlowRepository;
    final command = _command(
      'same-availability-report',
      'alice',
      'REPORT_HYBRID_AVAILABILITY',
      backend.round.id,
    );
    const availability = NetworkHybridAvailabilityDto(
      orientation: HybridDeckOrientation.distance,
      hasPlayableCurrentOrientation: true,
      hasPlayableAlternateOrientation: false,
    );

    await repository.reportHybridAvailability(
      command: command,
      availability: availability,
      generation: 1,
    );
    await repository.reportHybridAvailability(
      command: command,
      availability: availability,
      generation: 1,
    );

    expect(backend.hybridAvailability, hasLength(1));
    expect(backend.currentRound, 1);
  });

  test('hybrid readiness migration enforces the canonical barrier', () {
    final sql = File(
      'supabase/migrations/'
      '202610100010_hybrid_orientation_readiness.sql',
    ).readAsStringSync();

    expect(sql, contains('hybrid_availability_generation'));
    expect(sql, contains('report_network_hybrid_availability'));
    expect(sql, contains("raise exception 'ROUND_HYBRID_ORIENTATION_STALE'"));
    expect(
      sql,
      contains("raise exception 'ROUND_HYBRID_AVAILABILITY_PENDING'"),
    );
    expect(sql, contains("raise exception 'ROUND_HYBRID_SWITCH_REQUIRED'"));
    expect(sql, contains('p_has_playable_alternate'));
    expect(sql, contains("set cycle_exhausted=exists("));
  });

  group('low PA Recovery routing migration', () {
    late String sql;
    late String compactSql;

    setUpAll(() {
      sql = File(
        'supabase/migrations/'
        '202610100016_route_low_pa_to_recovery.sql',
      ).readAsStringSync();
      compactSql = sql.replaceAll(RegExp(r'\s+'), ' ');
    });

    test('two completions with balances above 10 reach WAITING_NEXT', () {
      expect(compactSql, contains("then 'RECOVERY' else 'WAITING_NEXT' end"));
    });

    test('two completions with a 4 PA balance reach RECOVERY', () {
      expect(sql, contains('jsonb_each_text(state.action_points) balance'));
      expect(sql, contains('balance.value::integer <= 10'));
      expect(compactSql, contains("then 'RECOVERY'"));
    });

    test('the 10 PA threshold is inclusive', () {
      expect(sql, contains('balance.value::integer <= 10'));
      expect(sql, isNot(contains('balance.value::integer < 10')));
    });

    test('one completion cannot transition the round', () {
      final playerBarrier = compactSql.indexOf(
        'and not exists( select 1 from public.session_players participant '
        'where participant.session_id = p_session_id '
        'and not (v_ready ? participant.user_id::text) ) then case',
      );
      final recoveryDecision = compactSql.indexOf(
        'jsonb_each_text(state.action_points) balance',
      );

      expect(playerBarrier, greaterThanOrEqualTo(0));
      expect(recoveryDecision, greaterThan(playerBarrier));
    });

    test('clothing and HYBRID barriers remain in the redefined RPC', () {
      expect(sql, contains('required_clothing_player_ids'));
      expect(sql, contains('v4_clothing_resynced'));
      expect(
        sql,
        contains("raise exception 'ROUND_HYBRID_AVAILABILITY_PENDING'"),
      );
      expect(sql, contains("raise exception 'ROUND_HYBRID_SWITCH_REQUIRED'"));
      expect(sql, contains('hybrid_availability_generation'));
    });
  });

  test('network boundary SQL waits for both player reports', () {
    final sql = File(
      'supabase/migrations/202610080001_v4_action_completion.sql',
    ).readAsStringSync();

    expect(sql, contains('participant.session_id = p_session_id'));
    expect(sql, contains('not (v_ready ? participant.user_id::text)'));
    expect(sql, contains("then 'WAITING_NEXT'"));
  });

  test(
    'server commit cancellation retains the definitively consumed conceptual use',
    () async {
      final setup = await _setup(session, catalog);
      addTearDown(setup.dispose);
      final card = setup.alice.hand.firstWhere(setup.alice.isCardPlayable);
      setup.alice.toggleLock(card.identity);
      setup.alice.selectCard(card.identity);
      await setup.alice.confirmSelection();
      await _settle();

      expect(setup.alice.canCancelSelection, isTrue);
      expect(setup.backend.round.commits, contains('alice'));
      expect(await setup.alice.cancelSelection(), isTrue);
      await _settle();

      expect(setup.backend.round.commits, isNot(contains('alice')));
      expect(setup.alice.usageCheckpoint.usagesByIntent, hasLength(1));
      expect(
        setup.alice.usageCheckpoint.stock.remainingFor(card.id),
        setup.alice.usageCheckpoint.stock.capacity[card.id]! - 1,
      );
      expect(setup.alice.lockedCardId, isNull);
      expect(setup.alice.viewState, NetworkGameViewState.choosing);

      setup.alice.selectCard(setup.alice.hand.first.identity);
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

  test('FINISH uses canonical CLOSE_SESSION and is idempotent', () async {
    final setup = await _setup(session, catalog);
    addTearDown(setup.dispose);
    setup.backend
      ..cycleExhausted = true
      ..round.phase = NetworkGamePhase.waitingNext
      ..round.ready.addAll(const {'alice', 'bob'});
    setup.backend.notify();
    await _settle();

    await setup.alice.continueDeck(DeckExhaustionChoice.finish);
    await _settle();
    await setup.alice.continueDeck(DeckExhaustionChoice.finish);
    await _settle();

    expect(setup.backend.phase, NetworkGamePhase.sessionClosed);
    expect(setup.alice.viewState, NetworkGameViewState.sessionEnded);
    expect(setup.bob.viewState, NetworkGameViewState.sessionEnded);
    expect(setup.backend.closeApplications, 1);
    expect(
      setup.backend.commands,
      contains('game:session-multi:round-1:alice:close_session'),
    );
    expect(
      setup.backend.commands.where((id) => id.contains('continue_cycle')),
      isEmpty,
    );
  });

  test(
    'NEW_GAME closes canonically without creating or reusing a session',
    () async {
      final setup = await _setup(session, catalog);
      addTearDown(setup.dispose);
      setup.backend
        ..cycleExhausted = true
        ..round.phase = NetworkGamePhase.waitingNext
        ..round.ready.addAll(const {'alice', 'bob'});
      setup.backend.notify();
      await _settle();

      await setup.alice.continueDeck(DeckExhaustionChoice.newCustomizedGame);
      await _settle();

      expect(setup.backend.phase, NetworkGamePhase.sessionClosed);
      expect(setup.backend.closeApplications, 1);
      expect(setup.backend.roundCreations, 1);
      expect(
        setup.alice.sessionClosureIntent,
        DeckExhaustionChoice.newCustomizedGame,
      );
      expect(setup.bob.sessionClosureIntent, isNull);
      expect(
        setup.backend.commands.where((id) => id.contains('continue_cycle')),
        isEmpty,
      );
    },
  );

  test('legacy FINISH and NEW_GAME cycle commands are rejected', () async {
    for (final choice in [
      DeckExhaustionChoice.finish,
      DeckExhaustionChoice.newCustomizedGame,
    ]) {
      final backend = _Backend()
        ..cycleExhausted = true
        ..round.phase = NetworkGamePhase.waitingNext;
      await expectLater(
        (backend.repository('alice') as NetworkSessionFlowRepository)
            .continueDeckCycle(
              expectedCycle: 1,
              command: _command(
                'legacy-${choice.name}',
                'alice',
                'CONTINUE_CYCLE',
                backend.round.id,
              ),
              choice: choice,
            ),
        throwsA(
          isA<NetworkRoundException>().having(
            (error) => error.code,
            'code',
            'ROUND_INVALID_ARGUMENT',
          ),
        ),
      );
    }

    final sql = File(
      'supabase/migrations/202610100012_canonical_session_closure.sql',
    ).readAsStringSync();
    expect(sql, contains("p_choice in ('NEW_GAME','FINISH')"));
    expect(sql, isNot(contains("status = 'closed'")));
    expect(sql, isNot(contains("phase = 'SESSION_CLOSED'")));
  });

  testWidgets('SESSION_CLOSED uses neutral voluntary ending copy', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final backend = _Backend()..round.phase = NetworkGamePhase.sessionClosed;
    await tester.pumpWidget(
      MaterialApp(
        home: NetworkDuelScreen(
          session: session,
          playerId: 'alice',
          repository: backend.repository('alice'),
          catalog: catalog,
          secretStore: MemoryNetworkDuelSecretStore(),
        ),
      ),
    );
    for (var index = 0; index < 20; index++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(
      find.text('Partie terminée'),
      findsWidgets,
      reason: tester
          .widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data)
          .whereType<String>()
          .join(' | '),
    );
    expect(find.textContaining('déconnexion'), findsNothing);
    expect(
      find.byKey(const Key('return-home-after-session-end')),
      findsOneWidget,
    );
  });

  testWidgets('NEW_GAME clears old local session and returns to normal menu', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final backend = _Backend()
      ..cycleExhausted = true
      ..round.phase = NetworkGamePhase.waitingNext
      ..round.ready.addAll(const {'alice', 'bob'});
    final activeStore = _MemoryActiveSessionStore()..value = session.id;
    final secretStore = MemoryNetworkDuelSecretStore();
    NetworkDuelExit? exit;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              key: const Key('open-duel-for-new-game'),
              onPressed: () async {
                exit = await Navigator.of(context).push<NetworkDuelExit>(
                  MaterialPageRoute<NetworkDuelExit>(
                    builder: (_) => NetworkDuelScreen(
                      session: session,
                      playerId: 'alice',
                      repository: backend.repository('alice'),
                      catalog: catalog,
                      secretStore: secretStore,
                      activeSessionStore: activeStore,
                      historyStore: MemoryGameHistoryStore(),
                    ),
                  ),
                );
              },
              child: const Text('Ouvrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open-duel-for-new-game')));
    for (var index = 0; index < 20; index++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byKey(const Key('new-customized-game')), findsOneWidget);

    await tester.tap(find.byKey(const Key('new-customized-game')));
    for (var index = 0; index < 20; index++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(backend.closeApplications, 1);
    expect(
      activeStore.value,
      isNull,
      reason: tester
          .widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data)
          .whereType<String>()
          .join(' | '),
    );
    expect(
      await secretStore.loadGame(sessionId: session.id, playerId: 'alice'),
      isNull,
    );
    expect(
      exit,
      NetworkDuelExit.newGame,
      reason: tester
          .widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data)
          .whereType<String>()
          .join(' | '),
    );
    expect(backend.roundCreations, 1);
    expect(find.byKey(const Key('open-duel-for-new-game')), findsOneWidget);
  });

  testWidgets(
    'unified post-duel choice keeps empty PA and whitespace disabled in UI',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final backend = _Backend();
      backend.round
        ..phase = NetworkGamePhase.corruptionDecision
        ..initial = NetworkInitialResolutionDto(
          tied: false,
          winnerPlayerId: 'bob',
          loserPlayerId: 'alice',
          gap: 1,
          gapCost: 1,
          highValue: 12,
          actionPoints: const {'alice': 100, 'bob': 100},
        )
        ..finalResolution = NetworkFinalResolutionDto(
          retainedPlayerId: 'bob',
          initialWinnerPlayerId: 'bob',
          finalWinnerPlayerId: 'bob',
        );
      await tester.pumpWidget(
        MaterialApp(
          home: NetworkDuelScreen(
            session: session,
            playerId: 'alice',
            repository: backend.repository('alice'),
            catalog: catalog,
            secretStore: MemoryNetworkDuelSecretStore(),
          ),
        ),
      );
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.tap(find.byKey(const Key('choose-negotiation')));
      await tester.pump();
      final commands = Set<String>.of(backend.commands);
      final canonical = backend.state('alice').toJson();
      for (final text in ['', '   ']) {
        await tester.enterText(
          find.byKey(const Key('negotiation-direct-pa')),
          text,
        );
        await tester.pump();
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('submit-negotiation')))
              .onPressed,
          isNull,
        );
        expect(backend.negotiationProposalCalls, 0);
        expect(backend.commands, commands);
        expect(backend.state('alice').toJson(), canonical);
      }
      await tester.enterText(
        find.byKey(const Key('negotiation-direct-pa')),
        ' 2 ',
      );
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('submit-negotiation')))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byKey(const Key('submit-negotiation')));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(tester.takeException(), isNull);
      expect(backend.negotiationProposalCalls, 1);
      expect(backend.phase, NetworkGamePhase.negotiationResponse);
      expect(backend.round.negotiation!.proposal!.directPa, 2);
      expect(backend.points, {'alice': 100, 'bob': 100});
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'execution renders frozen action snapshots despite catalog divergence',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final backend = _Backend();
      NetworkResolvedActionCardDto frozen(
        String conceptId,
        String actionId,
        String usageId,
        String text, {
        bool accessory = false,
      }) {
        final card = resolvedActionFixture(
          conceptId: conceptId,
          usageId: usageId,
          actionId: actionId,
          direction: NetworkCardDirection.FAIRE,
          targetPlayerIds: const ['bob'],
          effectiveSpice: 1,
        );
        return NetworkResolvedActionCardDto.fromJson({
          ...card.toJson(),
          'resolved_action': {
            ...card.usage.resolvedAction,
            'action_text': text,
            if (accessory)
              'accessories': [
                {
                  'accessory_id': 'historical-link',
                  'label': 'Lien historique figé',
                },
              ],
          },
        });
      }

      final cards = [
        frozen(
          '034',
          '034.stage.1',
          'constraint-light',
          'Entrave figée au stade 1.',
          accessory: true,
        ),
        frozen(
          '034',
          '034.stage.3',
          'constraint-full',
          'Entrave figée au stade 3.',
        ),
        frozen('035', '035.action', 'blindfold', 'Privation visuelle figée.'),
      ];
      final snapshots = jsonEncode(cards.map((c) => c.toJson()).toList());
      _setProjectedAction(backend, cards: cards);
      final changedDocument =
          jsonDecode(jsonEncode(catalog.cardsDocument)) as Map<String, Object?>;
      for (final raw in changedDocument['cards']! as List) {
        final card = raw as Map<String, Object?>;
        card['action_text'] = 'Texte actuel du catalogue modifié';
        card['details_text'] = 'Détails actuels du catalogue modifiés';
        for (final rawVariant in card['variants']! as List) {
          final variant = rawVariant as Map<String, Object?>;
          variant['action_text'] = 'Texte actuel de variante modifié';
          variant['details_text'] = 'Détails actuels de variante modifiés';
        }
      }
      final changedCatalog = Catalog(
        cardsDocument: changedDocument,
        profilesDocument: catalog.profilesDocument,
        tagsDocument: catalog.tagsDocument,
        concepts: catalog.concepts,
        conceptRules: catalog.conceptRules,
      );
      for (final player in ['alice', 'bob']) {
        await tester.pumpWidget(
          MaterialApp(
            home: NetworkDuelScreen(
              key: ValueKey(player),
              session: session,
              playerId: player,
              repository: backend.repository(player),
              catalog: player == 'alice' ? catalog : changedCatalog,
              secretStore: MemoryNetworkDuelSecretStore(),
              profileAccessories: [
                V4Accessory(
                  id: 'historical-link',
                  name: 'Nom actuel différent',
                  ownerPlayerId: player,
                  tags: const {},
                ),
              ],
            ),
          ),
        );
        for (var index = 0; index < 20; index++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(tester.takeException(), isNull);
        for (final card in cards) {
          expect(
            find.text(card.usage.resolvedAction['action_text']! as String),
            findsOneWidget,
          );
        }
        expect(
          find.textContaining('accessoire : Lien historique figé'),
          findsOneWidget,
        );
        expect(
          find.textContaining('accessoire : Nom actuel différent'),
          findsNothing,
        );
        expect(find.text('Texte actuel de variante modifié'), findsNothing);
        expect(find.textContaining('Détails actuels'), findsNothing);
        expect(
          jsonEncode(
            backend.round.actionProjection!.cards
                .map((c) => c.toJson())
                .toList(),
          ),
          snapshots,
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'execution renders a snapshot from the real engagement lifecycle',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final backend = _Backend();
      final focused = _catalogWithCards(catalog, {'card.v4.003'});
      final tags = {
        for (final binding in focused.conceptRules!['bindings']! as List)
          for (final action in binding['actions'] as List)
            for (final tag in action['editorial']['tags'] as List)
              if ((tag as String).startsWith('v3.preference.')) tag,
      };
      PlayerGameProfile profile(String id, int value) => PlayerGameProfile(
        playerId: id,
        preferences: {
          for (final tag in tags)
            tag: PreferenceValue(
              status: PreferenceStatus.ACCEPTED,
              general: value,
              faire: value,
              recevoir: value,
            ),
        },
      );
      final bob = NetworkGameController(
        session: session,
        playerId: 'bob',
        repository: _V4ProjectionRepository(backend, 'bob'),
        privateStore: MemoryNetworkDuelSecretStore(),
        learningStore: MemoryNetworkProfileLearningStore(),
        catalog: focused,
        privateProfile: profile('bob', 12),
      );
      addTearDown(bob.dispose);
      unawaited(bob.start());
      await tester.pumpWidget(
        MaterialApp(
          home: NetworkDuelScreen(
            session: session,
            playerId: 'alice',
            repository: _V4ProjectionRepository(backend, 'alice'),
            catalog: focused,
            privateProfile: profile('alice', 8),
            secretStore: MemoryNetworkDuelSecretStore(),
          ),
        ),
      );
      Future<void> pumpOperations() async {
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
      }

      await pumpOperations();
      final alice =
          (tester.state(find.byType(NetworkDuelScreen)) as dynamic).controller
              as NetworkGameController;
      expect(alice.heldConcepts.single.id, '003');
      expect(bob.heldConcepts.single.id, '003');
      alice.selectCard('003');
      bob.selectCard('003');
      unawaited(alice.confirmSelection());
      await pumpOperations();
      unawaited(bob.confirmSelection());
      await pumpOperations();
      expect(alice.initialResolution, isNotNull);
      final loser = alice.isInitialLoser ? alice : bob;
      unawaited(loser.skipCorruption());
      await pumpOperations();
      expect(tester.takeException(), isNull);
      expect(backend.phase, NetworkGamePhase.finalResolved);
      final projected = backend.round.actionProjection!.cards.single;
      final owner = projected.usage.ownerPlayerId == 'alice' ? alice : bob;
      final engaged = owner.usageCheckpoint.usagesByIntent.values.single;
      expect(projected.usageId, engaged.usageId);
      expect(projected.cardId, '003');
      expect(projected.variantId, engaged.action.stageId);
      expect(
        projected.toJson(),
        NetworkResolvedActionCardDto.fromUsage(
          owner.round!.finalResolution!.compromise.single.usage,
        ).toJson(),
      );
      expect(find.text(engaged.action.actionText), findsOneWidget);
      expect(owner.usageCheckpoint.stock.remainingFor('003'), 2);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test(
    '006 and 007 derive deterministic counts from canonical clothing',
    () async {
      const cases = [
        ('006', '006.action', V4ClothingBehavior.removeOne, 6, 5),
        ('006', '006.action', V4ClothingBehavior.removeOne, 0, 0),
        ('007', '007.action', V4ClothingBehavior.removeTwo, 6, 4),
        ('007', '007.action', V4ClothingBehavior.removeTwo, 1, 0),
      ];
      for (final (cardId, variantId, behavior, initial, expected) in cases) {
        final backend = _Backend()..clothingCounts['alice'] = initial;
        _setProjectedAction(
          backend,
          cards: [
            _projectedCard(
              occurrenceId: '$cardId-$initial',
              cardId: cardId,
              variantId: variantId,
              targetPlayerIds: const ['alice'],
              clothingBehavior: behavior,
            ),
          ],
          requiredClothingPlayerIds: const {'alice'},
        );
        final controller = NetworkGameController(
          session: session,
          playerId: 'alice',
          repository: backend.repository('alice'),
          privateStore: MemoryNetworkDuelSecretStore(),
          learningStore: MemoryNetworkProfileLearningStore(),
          catalog: catalog,
        );
        await controller.start();
        await _settle();
        expect(controller.clothingCounts['alice'], initial);
        final projected = controller.actionProjection!.cards.single;
        expect(projected.cardId, cardId);
        expect(projected.usageId, '$cardId-$initial');
        expect(projected.parameters['clothing_behavior'], behavior.name);
        expect(controller.ownClothingChangeIsDeterministic, isTrue);
        expect(controller.suggestedOwnClothingCount(), expected);
        controller.dispose();
      }
    },
  );

  testWidgets('006 preapplies its deterministic count on Terminé', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final backend = _Backend()..clothingCounts['alice'] = 6;
    _setProjectedAction(
      backend,
      cards: [
        _projectedCard(
          occurrenceId: 'remove-one-ui',
          cardId: '006',
          variantId: '006.action',
          targetPlayerIds: const ['alice'],
          clothingBehavior: V4ClothingBehavior.removeOne,
          actionText: 'Retirez un vêtement. · Retirer un vêtement',
        ),
      ],
      requiredClothingPlayerIds: const {'alice'},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: NetworkDuelScreen(
          session: session,
          playerId: 'alice',
          repository: backend.repository('alice'),
          catalog: catalog,
          secretStore: MemoryNetworkDuelSecretStore(),
        ),
      ),
    );
    for (var index = 0; index < 20; index++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(tester.takeException(), isNull);
    expect(
      find.text('Retirez un vêtement. · Retirer un vêtement'),
      findsOneWidget,
    );
    expect(find.text('Ajuster les vêtements (5)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('complete-network-action')));
    await tester.pump();
    expect(find.byKey(const Key('clothing-resync-count')), findsNothing);
    expect(backend.clothingCounts['alice'], 5);
  });

  test(
    'deterministic clothing count is shared and survives next round reconnect',
    () async {
      final backend = _Backend()..clothingCounts['alice'] = 6;
      _setProjectedAction(
        backend,
        cards: [
          _projectedCard(
            occurrenceId: 'remove-one',
            cardId: '006',
            variantId: '006.action',
            targetPlayerIds: const ['alice'],
            clothingBehavior: V4ClothingBehavior.removeOne,
          ),
        ],
        requiredClothingPlayerIds: const {'alice'},
      );
      var alice = NetworkGameController(
        session: session,
        playerId: 'alice',
        repository: backend.repository('alice'),
        privateStore: MemoryNetworkDuelSecretStore(),
        learningStore: MemoryNetworkProfileLearningStore(),
        catalog: catalog,
      );
      final bob = NetworkGameController(
        session: session,
        playerId: 'bob',
        repository: backend.repository('bob'),
        privateStore: MemoryNetworkDuelSecretStore(),
        learningStore: MemoryNetworkProfileLearningStore(),
        catalog: catalog,
      );
      await Future.wait([alice.start(), bob.start()]);
      await _settle();
      expect(alice.clothingCounts['alice'], 6);
      expect(alice.actionProjection!.cards.single.usageId, 'remove-one');
      expect(
        alice.actionProjection!.cards.single.parameters['clothing_behavior'],
        'removeOne',
      );
      expect(alice.suggestedOwnClothingCount(), 5);
      await alice.updateOwnClothingCount(alice.suggestedOwnClothingCount());
      await alice.completeAction();
      await _settle();
      expect(bob.clothingCounts['alice'], 5);

      await bob.completeAction();
      await _settle();
      expect(backend.clothingCounts['alice'], 5);

      alice.dispose();
      alice = NetworkGameController(
        session: session,
        playerId: 'alice',
        repository: backend.repository('alice'),
        privateStore: MemoryNetworkDuelSecretStore(),
        learningStore: MemoryNetworkProfileLearningStore(),
        catalog: catalog,
      );
      await alice.start();
      await _settle();
      expect(alice.clothingCounts['alice'], 5);
      alice.dispose();
      bob.dispose();
    },
  );

  test('persistent effects advance once per projected action in order', () {
    final activated = _advancePersistentEffects(const [], [
      _projectedCard(
        occurrenceId: 'effect',
        cardId: '034',
        variantId: 'variant.v4.034.s1',
        durationActions: 3,
        targetPlayerIds: const ['bob'],
      ),
    ]);
    expect(activated.single.remainingActions, 3);

    final afterThree = _advancePersistentEffects(activated, [
      _projectedCard(
        occurrenceId: 'x1',
        cardId: '001',
        variantId: 'variant.v4.001.base',
      ),
      _projectedCard(
        occurrenceId: 'x2',
        cardId: '001',
        variantId: 'variant.v4.001.base',
      ),
      _projectedCard(
        occurrenceId: 'x3',
        cardId: '001',
        variantId: 'variant.v4.001.base',
      ),
    ]);
    expect(afterThree, isEmpty);

    final effectFirst = _advancePersistentEffects(const [], [
      _projectedCard(
        occurrenceId: 'effect-first',
        cardId: '034',
        variantId: 'variant.v4.034.s1',
        durationActions: 3,
        targetPlayerIds: const ['bob'],
      ),
      _projectedCard(
        occurrenceId: 'after-1',
        cardId: '001',
        variantId: 'variant.v4.001.base',
      ),
      _projectedCard(
        occurrenceId: 'after-2',
        cardId: '001',
        variantId: 'variant.v4.001.base',
      ),
    ]);
    expect(effectFirst.single.remainingActions, 1);

    final existingAcrossLot = _advancePersistentEffects(
      const [
        V4PersistentEffect(
          cardId: '035',
          targetPlayerId: 'alice',
          remainingActions: 3,
        ),
      ],
      [
        _projectedCard(
          occurrenceId: 'lot-1',
          cardId: '001',
          variantId: 'variant.v4.001.base',
        ),
        _projectedCard(
          occurrenceId: 'lot-2',
          cardId: '001',
          variantId: 'variant.v4.001.base',
        ),
      ],
    );
    expect(existingAcrossLot.single.remainingActions, 1);

    final renewed = _advancePersistentEffects(
      const [
        V4PersistentEffect(
          cardId: '034',
          targetPlayerId: 'bob',
          remainingActions: 1,
        ),
        V4PersistentEffect(
          cardId: '033',
          targetPlayerId: 'alice',
          remainingActions: 3,
        ),
      ],
      [
        _projectedCard(
          occurrenceId: 'renew',
          cardId: '034',
          variantId: 'variant.v4.034.s2',
          durationActions: 3,
          targetPlayerIds: const ['bob', 'alice'],
        ),
      ],
    );
    expect(renewed, hasLength(3));
    expect(
      renewed
          .singleWhere(
            (effect) =>
                effect.cardId == '034' && effect.targetPlayerId == 'bob',
          )
          .remainingActions,
      3,
    );
    expect(
      renewed
          .singleWhere(
            (effect) =>
                effect.cardId == '034' && effect.targetPlayerId == 'alice',
          )
          .remainingActions,
      3,
    );
    expect(
      renewed.singleWhere((effect) => effect.cardId == '033').remainingActions,
      2,
    );
  });

  test(
    'canonical effects wait for both Terminé and survive retry and empty-cache reconnect',
    () async {
      final backend = _Backend();
      _setProjectedAction(
        backend,
        cards: [
          _projectedCard(
            occurrenceId: 'canonical-effect',
            cardId: 'card.v4.034',
            variantId: 'variant.v4.034.s1',
            durationActions: 3,
            targetPlayerIds: const ['bob'],
          ),
        ],
      );
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
      addTearDown(alice.dispose);
      addTearDown(bob.dispose);
      await Future.wait([alice.start(), bob.start()]);

      await alice.completeAction();
      await _settle();
      expect(backend.persistentEffects, isEmpty);
      expect(backend.persistentEffectTransitions, 0);

      await bob.completeAction();
      await _settle();
      expect(backend.persistentEffectTransitions, 1);
      expect(backend.persistentEffects.single.remainingActions, 3);
      expect(alice.persistentEffects, backend.persistentEffects);
      expect(bob.persistentEffects, backend.persistentEffects);

      backend.notifyTwice();
      await _settle();
      expect(backend.persistentEffectTransitions, 1);
      expect(backend.persistentEffects.single.remainingActions, 3);

      final reconnected = _controller(
        backend,
        session,
        catalog,
        'alice',
        MemoryNetworkDuelSecretStore(),
      );
      addTearDown(reconnected.dispose);
      await reconnected.start();
      await _settle();
      expect(reconnected.persistentEffects, backend.persistentEffects);
    },
  );

  test(
    'closing before both Terminé does not mutate persistent effects',
    () async {
      final backend = _Backend();
      _setProjectedAction(
        backend,
        cards: [
          _projectedCard(
            occurrenceId: 'never-executed-effect',
            cardId: 'card.v4.034',
            variantId: 'variant.v4.034.s1',
            durationActions: 3,
          ),
        ],
      );
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
      addTearDown(alice.dispose);
      addTearDown(bob.dispose);
      await Future.wait([alice.start(), bob.start()]);

      await alice.completeAction();
      await alice.closeSession();
      await _settle();

      expect(backend.phase, NetworkGamePhase.sessionClosed);
      expect(backend.persistentEffects, isEmpty);
      expect(backend.persistentEffectTransitions, 0);
    },
  );

  test(
    'all post-duel routes apply only their canonical final projection',
    () async {
      for (final route in const [
        ('normal', 'card.v4.033', null, null),
        ('compromise accepted', 'card.v4.034', true, null),
        ('compromise refused', 'card.v4.035', false, null),
        ('corruption accepted', 'card.v4.060', null, true),
        ('corruption refused', 'card.v4.061', null, false),
      ]) {
        final backend = _Backend();
        _setProjectedAction(
          backend,
          cards: [
            _projectedCard(
              occurrenceId: route.$1,
              cardId: route.$2,
              variantId: catalog.cards
                  .singleWhere((card) => card.stableId == route.$2)
                  .variants
                  .first
                  .stableId,
              durationActions: 3,
            ),
          ],
        );
        if (route.$3 != null) {
          backend.round.negotiation = NetworkNegotiationDto(
            response: NetworkNegotiationResponseDto(accepted: route.$3!),
          );
        }
        final bobStore = MemoryNetworkDuelSecretStore();
        if (route.$4 == true) {
          final conceptId = conceptFixtureId(route.$2);
          final frozen = backend.round.actionProjection!.cards.single;
          final checkpoint =
              ConceptUsageCheckpoint.startCycle(
                    sessionId: session.id,
                    ownerPlayerId: 'bob',
                    cycle: 1,
                    catalog: catalog.concepts!,
                    initialClothing: 6,
                  )
                  .reserve(conceptId: conceptId, intentId: 'accepted-effect')
                  .engage(
                    conceptId: conceptId,
                    intentId: 'accepted-effect',
                    resolveAction: () => ResolvedConceptAction.fromJson({
                      ...frozen.usage.resolvedAction,
                      'actor_player_ids': ['bob'],
                      'target_player_ids': ['alice'],
                      'personal_values': [
                        {'player_id': 'bob', 'role': 'FAIRE', 'value': 10},
                      ],
                    }),
                    clock: () => DateTime.utc(2026, 10, 15),
                  );
          final usage = checkpoint.usagesByIntent.values.single;
          final shared = NetworkUsageProjection.fromSnapshot(
            usage,
            sharedParameterKeys: usage.action.parameters.keys.toSet(),
            sharedEffectIds: usage.action.effects
                .map((e) => e.effectId)
                .toSet(),
            includePersonalValue: true,
          );
          backend.round.actionProjection = NetworkResolvedActionProjectionDto(
            cards: [NetworkResolvedActionCardDto.fromUsage(shared)],
            requiredClothingPlayerIds: const {},
          );
          await bobStore.saveGame(
            sessionId: session.id,
            playerId: 'bob',
            state: NetworkPrivateGameState(
              roundNumber: 1,
              cards: const [],
              conceptCheckpoint: checkpoint,
              initialClothing: 6,
              clothesByPlayer: const {'alice': 6, 'bob': 6},
            ),
          );
        }
        if (route.$4 != null) {
          backend.round.corruption = NetworkCorruptionDto(
            offeredBy: 'bob',
            objective: CorruptionObjective.OWN_INITIAL_ACTION,
            actions: [
              if (route.$4 == true)
                NetworkCorruptionActionDto.fromUsage(
                  backend.round.actionProjection!.cards.single.usage,
                )
              else
                corruptionFixture(
                  conceptId: route.$2,
                  usageId: route.$1,
                  source: CardZone.DISCARD,
                ),
            ],
            accepted: route.$4,
          );
        }
        final alice = _controller(
          backend,
          session,
          catalog,
          'alice',
          MemoryNetworkDuelSecretStore(),
        );
        final bob = _controller(backend, session, catalog, 'bob', bobStore);
        await Future.wait([alice.start(), bob.start()]);
        await alice.completeAction();
        await bob.completeAction();
        await _settle();
        expect(
          backend.persistentEffects.single.cardId,
          conceptFixtureId(route.$2),
        );
        alice.dispose();
        bob.dispose();
      }
    },
  );

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
      final card = controller.hand.firstWhere(controller.isCardPlayable);
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
      expect(controller.usageCheckpoint.usagesByIntent, hasLength(1));
      expect(
        controller.usageCheckpoint.stock.remainingFor(card.id),
        controller.usageCheckpoint.stock.capacity[card.id]! - 1,
      );
      expect((await learning.load('alice'))?.entries ?? const {}, isEmpty);
      expect(backend.points, {'alice': 100, 'bob': 100});

      controller.selectCard(controller.hand.first.identity);
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
    final locked = setup.alice.hand
        .firstWhere(
          (card) => !setup.alice.isCardPlayable(card),
          orElse: () => setup.alice.hand.last,
        )
        .identity;
    setup.alice.toggleLock(locked);
    final initialHand = setup.alice.hand.map((card) => card.id).toSet();
    for (final expected in [1, 2]) {
      await _playUnequal(setup, avoidAliceCard: locked);
      final initial = setup.alice.initialResolution!;
      final loser = initial.loserPlayerId == 'alice' ? setup.alice : setup.bob;
      await loser.skipCorruption();
      await _settle();
      final beforeReady = Map<String, int>.from(setup.alice.actionPoints);
      await setup.alice.completeAction();
      await _settle();
      expect(setup.alice.roundNumber, expected);
      expect(setup.alice.viewState, NetworkGameViewState.actionInProgress);
      expect(setup.bob.viewState, NetworkGameViewState.actionInProgress);
      await setup.bob.completeAction();
      await _settle();
      expect(setup.alice.roundNumber, expected + 1);
      expect(setup.bob.roundNumber, expected + 1);
      expect(setup.alice.viewState, NetworkGameViewState.choosing);
      expect(setup.bob.viewState, NetworkGameViewState.choosing);
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
      final target = setup.alice.hand.firstWhere(setup.alice.isCardPlayable);
      setup.alice.toggleLock(target.identity);
      await _playUnequal(setup, forceAliceCard: target.identity);
      final loser = setup.alice.initialResolution!.loserPlayerId == 'alice'
          ? setup.alice
          : setup.bob;
      await loser.skipCorruption();
      await setup.alice.completeAction();
      await _settle();
      expect(
        setup.alice.usageCheckpoint.usagesByIntent.values.any(
          (usage) => usage.conceptId == target.id,
        ),
        isTrue,
      );
      await setup.bob.completeAction();
      await _settle();
      await _cycleController(setup).completeAction();
      await _settle();
      expect(setup.alice.lockedCardId, isNot(target.identity));
      expect(
        setup.alice.usageCheckpoint.usagesByIntent.values.any(
          (u) => u.conceptId == target.id,
        ),
        isTrue,
      );
      expect(
        setup.alice.usageCheckpoint.stock.remainingFor(target.id),
        lessThan(setup.alice.usageCheckpoint.stock.capacity[target.id]!),
      );
      setup.dispose();
    },
  );



  test(
    'learning waits for both Terminé and remains idempotent after reconnect',
    () async {
      final backend = _Backend();
      final aliceSecrets = MemoryNetworkDuelSecretStore();
      final aliceLearning = MemoryNetworkProfileLearningStore();
      var alice = NetworkGameController(
        session: session,
        playerId: 'alice',
        repository: backend.repository('alice'),
        privateStore: aliceSecrets,
        learningStore: aliceLearning,
        catalog: catalog,
      );
      final bob = NetworkGameController(
        session: session,
        playerId: 'bob',
        repository: backend.repository('bob'),
        privateStore: MemoryNetworkDuelSecretStore(),
        learningStore: MemoryNetworkProfileLearningStore(),
        catalog: catalog,
      );
      await Future.wait([alice.start(), bob.start()]);
      final setup = _Setup(backend, alice, bob);
      await _playUnequal(setup);
      final loser = alice.isInitialLoser ? alice : bob;
      await loser.skipCorruption();
      await _settle();

      expect(backend.phase, NetworkGamePhase.finalResolved);
      expect(aliceLearning.appliedEventIds['alice'], anyOf(isNull, isEmpty));

      backend.notifyTwice();
      await _settle();
      expect(aliceLearning.appliedEventIds['alice'], anyOf(isNull, isEmpty));

      alice.dispose();
      alice = NetworkGameController(
        session: session,
        playerId: 'alice',
        repository: backend.repository('alice'),
        privateStore: aliceSecrets,
        learningStore: aliceLearning,
        catalog: catalog,
      );
      await alice.start();
      await _settle();
      expect(aliceLearning.appliedEventIds['alice'], anyOf(isNull, isEmpty));

      await alice.completeAction();
      await _settle();
      expect(aliceLearning.appliedEventIds['alice'], anyOf(isNull, isEmpty));
      await bob.completeAction();
      await _settle();
      expect(aliceLearning.appliedEventIds['alice'], hasLength(1));
      final learnedOnce = jsonEncode(aliceLearning.values['alice']!.toJson());

      backend.notifyTwice();
      await _settle();
      expect(jsonEncode(aliceLearning.values['alice']!.toJson()), learnedOnce);
      alice.dispose();
      bob.dispose();
    },
  );

  test('closing before both Terminé records no learning', () async {
    final backend = _Backend();
    final learning = MemoryNetworkProfileLearningStore();
    final alice = NetworkGameController(
      session: session,
      playerId: 'alice',
      repository: backend.repository('alice'),
      privateStore: MemoryNetworkDuelSecretStore(),
      learningStore: learning,
      catalog: catalog,
    );
    final bob = NetworkGameController(
      session: session,
      playerId: 'bob',
      repository: backend.repository('bob'),
      privateStore: MemoryNetworkDuelSecretStore(),
      learningStore: MemoryNetworkProfileLearningStore(),
      catalog: catalog,
    );
    addTearDown(alice.dispose);
    addTearDown(bob.dispose);
    await Future.wait([alice.start(), bob.start()]);
    final setup = _Setup(backend, alice, bob);
    await _playUnequal(setup);
    final loser = alice.isInitialLoser ? alice : bob;
    await loser.skipCorruption();
    await _settle();

    await alice.completeAction();
    await alice.closeSession();
    await _settle();

    expect(backend.phase, NetworkGamePhase.sessionClosed);
    expect(learning.appliedEventIds['alice'], anyOf(isNull, isEmpty));
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



  test('reconnect restores the canonical frozen action snapshot', () async {
    final backend = _Backend();
    const parameters = V4ResolvedParameters(
      zoneSelectionSource: V4ZoneSelectionSource.game,
      sexualOrIntimateZone: true,
      zoneId: 'zone.intime',
      accessoryId: 'accessory.persisted',
    );
    final base = actionUsageFixture(
      conceptId: '024',
      usageId: 'bob-history-024',
      actionId: '024.action',
      ownerPlayerId: 'bob',
      nativeDirection: NetworkCardDirection.FAIRE,
      snapshotValue: 8,
      resolvedParameters: parameters,
      effectiveSpice: 4,
    );
    final frozen = NetworkUsageProjection.fromJson({
      ...base.toJson(),
      'resolved_action': {
        ...base.resolvedAction,
        'accessories': [
          {
            'accessory_id': 'accessory.persisted',
            'label': 'Historical accessory',
          },
        ],
        'action_text':
            'Historical frozen action, preserved without catalog reconstruction',
      },
    });
    final original = jsonEncode(frozen.toJson());
    backend.round
      ..phase = NetworkGamePhase.finalResolved
      ..finalResolution = NetworkFinalResolutionDto(
        retainedPlayerId: 'bob',
        initialWinnerPlayerId: 'bob',
        finalWinnerPlayerId: 'bob',
        cardId: '024',
        variantId: '024.action',
        compromise: [
          NetworkCompromiseCardDto.fromUsage(
            frozen,
            origin: NetworkCompromiseOrigin.INITIAL_DUEL,
          ),
        ],
      );
    final controller = NetworkGameController(
      session: session,
      playerId: 'alice',
      repository: _V4ProjectionRepository(backend, 'alice'),
      privateStore: MemoryNetworkDuelSecretStore(),
      learningStore: MemoryNetworkProfileLearningStore(),
      catalog: catalog,
    );
    addTearDown(controller.dispose);
    await controller.start();
    await _settle();
    final projected = backend.round.actionProjection!.cards.single;
    expect(projected.toJson(), frozen.withoutPersonalValues().toJson());
    expect(projected.usageId, frozen.usageId);
    expect(projected.cardId, '024');
    expect(projected.variantId, '024.action');
    expect(projected.direction, NetworkCardDirection.FAIRE);
    expect(projected.targetPlayerIds, ['alice']);
    expect(projected.zoneId, 'zone.intime');
    expect(projected.accessoryId, 'accessory.persisted');
    expect(projected.effectiveSpice, 4);
    expect(projected.parameters, frozen.resolvedAction['parameters']);
    expect(projected.parameters['committed_at'], '2026-10-15T12:00:00.000Z');
    expect(jsonEncode(frozen.toJson()), original);
    expect(backend.round.reveals, isEmpty);
    expect(controller.viewState, NetworkGameViewState.actionInProgress);
  });
  test(
    'reconnect preserves the engaged snapshot without V4 parameter repair',
    () async {
      final backend = _Backend();
      final store = MemoryNetworkDuelSecretStore();
      const parameters = V4ResolvedParameters(
        zoneSelectionSource: V4ZoneSelectionSource.game,
        sexualOrIntimateZone: true,
        zoneId: 'zone.intime',
        accessoryId: 'accessory.frozen',
      );
      final base = actionUsageFixture(
        conceptId: '024',
        actionId: '024.action',
        ownerPlayerId: 'bob',
        nativeDirection: NetworkCardDirection.FAIRE,
        effectiveSpice: 4,
        resolvedParameters: parameters,
      );
      final checkpoint =
          ConceptUsageCheckpoint.startCycle(
                sessionId: session.id,
                ownerPlayerId: 'bob',
                cycle: 1,
                catalog: catalog.concepts!,
                initialClothing: 6,
              )
              .reserve(conceptId: '024', intentId: 'frozen-parameters')
              .engage(
                conceptId: '024',
                intentId: 'frozen-parameters',
                resolveAction: () => ResolvedConceptAction.fromJson({
                  ...base.resolvedAction,
                  'accessories': [
                    {
                      'accessory_id': 'accessory.frozen',
                      'label': 'Frozen accessory',
                    },
                  ],
                  'personal_values': [
                    {'player_id': 'bob', 'role': 'FAIRE', 'value': 8},
                  ],
                  'action_text':
                      'Frozen historical action independent of the catalog',
                }),
                clock: () => DateTime.utc(2026, 10, 15),
              );
      final usage = checkpoint.usagesByIntent.values.single;
      final frozen = NetworkUsageProjection.fromSnapshot(
        usage,
        sharedParameterKeys: usage.action.parameters.keys.toSet(),
        sharedEffectIds: usage.action.effects.map((e) => e.effectId).toSet(),
        includePersonalValue: true,
      );
      final original = jsonEncode(usage.toJson());
      await store.saveGame(
        sessionId: session.id,
        playerId: 'bob',
        state: NetworkPrivateGameState(
          roundNumber: 1,
          cards: [
            CardRuntimeState(
              cardId: '024',
              occurrenceId: usage.usageId,
              variantId: '024.action',
              zone: CardZone.ENGAGED,
            ),
          ],
          conceptCheckpoint: checkpoint,
          initialClothing: 6,
          clothesByPlayer: const {'alice': 6, 'bob': 6},
        ),
      );
      backend.round
        ..phase = NetworkGamePhase.finalResolved
        ..finalResolution = NetworkFinalResolutionDto(
          retainedPlayerId: 'bob',
          compromise: [
            NetworkCompromiseCardDto.fromUsage(
              frozen,
              origin: NetworkCompromiseOrigin.INITIAL_DUEL,
            ),
          ],
        );
      for (var reconnect = 0; reconnect < 2; reconnect++) {
        final controller = NetworkGameController(
          session: session,
          playerId: 'bob',
          repository: _V4ProjectionRepository(backend, 'bob'),
          privateStore: store,
          learningStore: MemoryNetworkProfileLearningStore(),
          catalog: catalog,
        );
        try {
          await controller.start();
          await _settle();
          expect(controller.errorMessage, isNull);
          expect(controller.viewState, NetworkGameViewState.actionInProgress);
          final restored =
              controller.usageCheckpoint.usagesByIntent.values.single;
          expect(restored.usageId, usage.usageId);
          expect(jsonEncode(restored.toJson()), original);
          expect(
            controller.usageCheckpoint.stock.toJson(),
            checkpoint.stock.toJson(),
          );
          final projected = controller.actionProjection!.cards.single;
          expect(projected.toJson(), frozen.withoutPersonalValues().toJson());
          expect(projected.zoneId, 'zone.intime');
          expect(projected.accessoryId, 'accessory.frozen');
          expect(projected.parameters, usage.action.parameters);
          expect(projected.effectiveSpice, 4);
          expect(backend.round.reveals, isEmpty);
          expect(
            backend.commands.where(
              (id) => id.contains('REPAIR_V4_ACTION_PARAMETERS'),
            ),
            isEmpty,
          );
        } finally {
          controller.dispose();
        }
      }
    },
  );

  test(
    'invalid engaged snapshot is rejected without parameter reconstruction',
    () {
      final saved = privateGameFixture(
        roundNumber: 1,
        ownerPlayerId: 'bob',
        cards: const [
          CardRuntimeState(
            cardId: '024',
            occurrenceId: 'engaged-024',
            variantId: '024.action',
            zone: CardZone.ENGAGED,
          ),
        ],
        parametersByUsage: const {
          'engaged-024': V4ResolvedParameters(
            zoneSelectionSource: V4ZoneSelectionSource.game,
            sexualOrIntimateZone: true,
            zoneId: 'zone.intime',
          ),
        },
      );
      // Missing a required JSON object is corruption, not a request to resolve
      // a different action using the current catalogue or an old reveal.
      final invalid =
          jsonDecode(jsonEncode(saved.toJson())) as Map<String, Object?>;
      final checkpoint = invalid['concept_checkpoint']! as Map<String, Object?>;
      final usage =
          (checkpoint['usages']! as List).single as Map<String, Object?>;
      (usage['action']! as Map<String, Object?>).remove('parameters');
      final rejectsMissingParameters = throwsA(
        isA<CatalogException>().having(
          (error) => error.issues.single.property,
          'invalid field',
          endsWith('parameters'),
        ),
      );
      expect(
        () => NetworkPrivateGameState.fromJson(invalid),
        rejectsMissingParameters,
      );
      final shared = actionUsageFixture(conceptId: '024').toJson();
      final invalidProjection =
          jsonDecode(jsonEncode(shared)) as Map<String, Object?>;
      (invalidProjection['resolved_action']! as Map<String, Object?>).remove(
        'parameters',
      );
      expect(
        () => NetworkUsageProjection.fromJson(invalidProjection),
        rejectsMissingParameters,
      );
      // Failed decoding cannot mutate the original checkpoint or its snapshot.
      expect(
        saved
            .conceptCheckpoint!
            .usagesByIntent
            .values
            .single
            .action
            .parameters['zone_id'],
        'zone.intime',
      );
    },
  );

  test(
    'corruption refusal is public, idempotent and leaves discard untouched',
    () async {
      final setup = await _setupCorruption(session, catalog);
      await _reachSecondResolved(setup);
      setup.backend.round.phase = NetworkGamePhase.corruptionDecision;
      setup.backend.notify();
      await _settle();
      final actor = setup.alice.isCorruptionActor ? setup.alice : setup.bob;
      final partner = identical(actor, setup.alice) ? setup.bob : setup.alice;
      final card = actor.corruptionCards.single;
      expect(actor.playerId, 'alice');
      final source = actor.usageCheckpoint.usagesByIntent.values.singleWhere(
        (u) => u.conceptId == '003',
      );
      final sourceJson = source.toJson();
      expect(card.identity, source.usageId);
      final historical = (await actor.privateStore.loadGame(
        sessionId: session.id,
        playerId: actor.playerId,
      ))!.publicDiscards.singleWhere((r) => r.usageId == source.usageId);
      expect(source.action.stageId, '003.stage.1');
      expect(source.action.zoneId, isNull);
      expect(
        source.action.effectiveChili,
        lessThanOrEqualTo(actor.round!.v4UnlockedSpice),
      );
      expect(actor.usageCheckpoint.stock.capacity['003'], 3);
      expect(actor.usageCheckpoint.stock.remainingFor('003'), 2);
      expect(historical.usage.usageId, source.usageId);
      expect(historical.roundNumber, 1);
      expect(historical.usage.ownerPlayerId, actor.playerId);
      final historicalJson = historical.toJson();
      final committedBefore = actor.usageCheckpoint.usagesByIntent.values
          .map((u) => u.usageId)
          .toSet();
      final before = actor.usageCheckpoint.stock.remainingFor(card.id);

      await actor.proposeCorruption({
        card.identity,
      }, CorruptionObjective.OWN_INITIAL_ACTION);
      await _settle();
      final pending = (await actor.privateStore.loadGame(
        sessionId: session.id,
        playerId: actor.playerId,
      ))!;
      final draft = pending.reservedChoices.values.single;
      expect(draft.sourceUsageId, source.usageId);
      expect(draft.usageId, isNot(source.usageId));
      expect(
        pending.conceptCheckpoint!.reservationsByIntent[draft.intentId],
        '003',
      );
      expect(actor.usageCheckpoint.stock.remainingFor('003'), 2);
      expect(actor.usageCheckpoint.availableFor('003'), 1);
      expect(
        actor.usageCheckpoint.usagesByIntent.values
            .map((u) => u.usageId)
            .toSet(),
        committedBefore,
      );
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
      await _settle();
      expect(
        reconnect.usageCheckpoint.encode(),
        actor.usageCheckpoint.encode(),
      );
      reconnect.dispose();

      await partner.respondToCorruption(accepted: false);
      await partner.respondToCorruption(accepted: false);
      await _settle();
      expect(setup.backend.phase, NetworkGamePhase.finalResolved);
      expect(actor.viewState, NetworkGameViewState.actionInProgress);
      expect(actor.usageCheckpoint.stock.remainingFor(card.id), before);
      expect(
        actor.visibleDiscardUsages.map((u) => u.usageId),
        contains(card.identity),
      );
      final refused = (await actor.privateStore.loadGame(
        sessionId: session.id,
        playerId: actor.playerId,
      ))!;
      expect(refused.reservedChoices, isEmpty);
      expect(actor.usageCheckpoint.reservationsByIntent, isEmpty);
      expect(actor.usageCheckpoint.availableFor('003'), 2);
      expect(
        actor.usageCheckpoint.usagesByIntent.values
            .map((u) => u.usageId)
            .toSet(),
        committedBefore,
      );
      expect(
        actor.usageCheckpoint.usageForIntent(source.intentId)!.toJson(),
        sourceJson,
      );
      expect(
        refused.publicDiscards
            .singleWhere((r) => r.usageId == source.usageId)
            .toJson(),
        historicalJson,
      );
      expect(
        actor.corruptionCards.any((c) => c.identity == source.usageId),
        isTrue,
      );
      setup.dispose();
    },
  );

  test(
    'older or unversioned snapshots cannot regress state or lifecycle',
    () async {
      final backend = _Backend();
      backend.round
        ..phase = NetworkGamePhase.corruptionDecision
        ..finalResolution = NetworkFinalResolutionDto(
          retainedPlayerId: 'bob',
          initialWinnerPlayerId: 'bob',
          finalWinnerPlayerId: 'bob',
          cardId: 'card.v4.001',
          variantId: 'variant.v4.001.base',
        );
      final newer = _revisioned(backend.state('bob'), 3);
      final repository = _RevisionRepository(backend, 'bob', newer);
      final controller = NetworkGameController(
        session: session,
        playerId: 'bob',
        repository: repository,
        privateStore: MemoryNetworkDuelSecretStore(),
        learningStore: MemoryNetworkProfileLearningStore(),
        catalog: catalog,
      );
      addTearDown(() async {
        controller.dispose();
        await repository.dispose();
      });

      await controller.start();
      expect(controller.viewState, NetworkGameViewState.corruptionDecision);
      final offered = controller.hand.first;
      final zoneBefore = controller.runtime
          .singleWhere((card) => card.occurrenceId == offered.identity)
          .zone;

      backend.round
        ..phase = NetworkGamePhase.finalResolved
        ..finalResolution = NetworkFinalResolutionDto(
          retainedPlayerId: 'bob',
          initialWinnerPlayerId: 'bob',
          finalWinnerPlayerId: 'bob',
          cardId: offered.id,
          variantId: offered.variant.id,
          compromise: [
            compromiseFixture(
              usageId: offered.identity,
              conceptId: offered.id,
              actionId: offered.variant.id,
              ownerPlayerId: 'bob',
              nativeDirection: NetworkCardDirection.values.byName(
                offered.nativeDirection.name,
              ),
              effectiveDirection: NetworkCardDirection.values.byName(
                offered.effectiveDirection.name,
              ),
              origin: NetworkCompromiseOrigin.AUCTION,
              snapshotValue: offered.personalValue,
            ),
          ],
        );
      final older = _revisioned(backend.state('bob'), 2);

      repository.emit(older);
      await _settle();
      expect(controller.viewState, NetworkGameViewState.corruptionDecision);
      expect(controller.round!.roundRevision, 3);
      expect(
        controller.runtime
            .singleWhere((card) => card.occurrenceId == offered.identity)
            .zone,
        zoneBefore,
      );

      final unversionedJson = older.toJson()..remove('round_revision');
      repository.emit(NetworkGameRoundStateDto.fromJson(unversionedJson));
      await _settle();
      expect(controller.viewState, NetworkGameViewState.corruptionDecision);
      expect(controller.round!.roundRevision, 3);
      expect(
        controller.runtime
            .singleWhere((card) => card.occurrenceId == offered.identity)
            .zone,
        zoneBefore,
      );
    },
  );

  test('an initial unversioned snapshot still loads', () async {
    final backend = _Backend();
    backend.round
      ..phase = NetworkGamePhase.corruptionDecision
      ..finalResolution = NetworkFinalResolutionDto(
        retainedPlayerId: 'bob',
        initialWinnerPlayerId: 'bob',
        finalWinnerPlayerId: 'bob',
        cardId: 'card.v4.001',
        variantId: 'variant.v4.001.base',
      );
    final initial = backend.state('bob');
    final repository = _RevisionRepository(backend, 'bob', initial);
    final controller = NetworkGameController(
      session: session,
      playerId: 'bob',
      repository: repository,
      privateStore: MemoryNetworkDuelSecretStore(),
      learningStore: MemoryNetworkProfileLearningStore(),
      catalog: catalog,
    );
    addTearDown(() async {
      controller.dispose();
      await repository.dispose();
    });

    await controller.start();

    expect(controller.viewState, NetworkGameViewState.corruptionDecision);
    expect(controller.round!.roundRevision, isNull);
  });

  test(
    'invalid Termine phase refreshes the canonical post-duel decision',
    () async {
      final backend = _Backend();
      backend.round
        ..phase = NetworkGamePhase.finalResolved
        ..finalResolution = NetworkFinalResolutionDto(
          retainedPlayerId: 'bob',
          initialWinnerPlayerId: 'bob',
          finalWinnerPlayerId: 'bob',
          cardId: 'card.v4.001',
          variantId: 'variant.v4.001.base',
        );
      final stale = _revisioned(backend.state('bob'), 2);
      final repository = _RevisionRepository(backend, 'bob', stale);
      final controller = NetworkGameController(
        session: session,
        playerId: 'bob',
        repository: repository,
        privateStore: MemoryNetworkDuelSecretStore(),
        learningStore: MemoryNetworkProfileLearningStore(),
        catalog: catalog,
      );
      addTearDown(() async {
        controller.dispose();
        await repository.dispose();
      });

      await controller.start();
      expect(controller.viewState, NetworkGameViewState.actionInProgress);

      backend.round.phase = NetworkGamePhase.corruptionDecision;
      repository
        ..canonical = _revisioned(backend.state('bob'), 3)
        ..rejectNextCompletion = true;
      await controller.completeAction();

      expect(repository.completionAttempts, 1);
      expect(controller.viewState, NetworkGameViewState.corruptionDecision);
      expect(controller.errorMessage, isNull);
      expect(controller.actionCompletionSubmitted, isFalse);
    },
  );

  test(
    'accepted corruption uses normal completion and consumes its batch once',
    () async {
      final learning = MemoryNetworkProfileLearningStore();
      final setup = await _setupCorruption(
        session,
        catalog,
        learning: learning,
      );
      await _reachSecondResolved(setup);
      setup.backend.round.phase = NetworkGamePhase.corruptionDecision;
      setup.backend.notify();
      await _settle();
      final actor = setup.alice.isCorruptionActor ? setup.alice : setup.bob;
      final partner = identical(actor, setup.alice) ? setup.bob : setup.alice;
      final offered = actor.corruptionCards.single;
      expect(actor.playerId, 'alice');
      final source = actor.usageCheckpoint.usagesByIntent.values.singleWhere(
        (u) => u.conceptId == '003',
      );
      final sourceJson = source.toJson();
      expect(offered.identity, source.usageId);
      final historical = (await actor.privateStore.loadGame(
        sessionId: session.id,
        playerId: actor.playerId,
      ))!.publicDiscards.singleWhere((r) => r.usageId == source.usageId);
      expect(source.action.stageId, '003.stage.1');
      expect(source.action.zoneId, isNull);
      expect(
        source.action.effectiveChili,
        lessThanOrEqualTo(actor.round!.v4UnlockedSpice),
      );
      expect(actor.usageCheckpoint.stock.capacity['003'], 3);
      expect(actor.usageCheckpoint.stock.remainingFor('003'), 2);
      expect(historical.usage.usageId, source.usageId);
      expect(historical.roundNumber, 1);
      expect(historical.usage.ownerPlayerId, actor.playerId);
      final historicalJson = historical.toJson();
      final committedBefore = actor.usageCheckpoint.usagesByIntent.values
          .map((u) => u.usageId)
          .toSet();
      final unrelated = actor.runtime
          .where((item) => item.zone == CardZone.HAND)
          .first;
      await actor.proposeCorruption({
        offered.identity,
      }, CorruptionObjective.OWN_INITIAL_ACTION);
      await _settle();
      final pending = (await actor.privateStore.loadGame(
        sessionId: session.id,
        playerId: actor.playerId,
      ))!;
      final draft = pending.reservedChoices.values.single;
      expect(draft.sourceUsageId, source.usageId);
      expect(draft.usageId, isNot(source.usageId));
      expect(
        pending.conceptCheckpoint!.reservationsByIntent[draft.intentId],
        '003',
      );
      expect(actor.usageCheckpoint.stock.remainingFor('003'), 2);
      expect(actor.usageCheckpoint.availableFor('003'), 1);
      expect(
        actor.usageCheckpoint.usagesByIntent.values
            .map((u) => u.usageId)
            .toSet(),
        committedBefore,
      );
      final quotaBefore = actor.usageCheckpoint.stock.remainingFor(offered.id);
      final pointsBeforeCorruption = Map<String, int>.of(setup.backend.points);
      final eventsBefore = Set<String>.of(
        learning.appliedEventIds[actor.playerId] ?? {},
      );
      final eventId = '${session.id}/${actor.round!.roundId}/${actor.playerId}';
      await partner.respondToCorruption(accepted: true);
      await _settle();
      expect(actor.viewState, NetworkGameViewState.actionInProgress);
      expect(partner.viewState, NetworkGameViewState.actionInProgress);
      expect(setup.backend.points, pointsBeforeCorruption);
      final replay = actor.usageCheckpoint.usagesByIntent.values.singleWhere(
        (u) => u.sourceUsageId == source.usageId,
      );
      expect(replay.usageId, draft.usageId);
      expect(replay.usageId, isNot(source.usageId));
      expect(replay.action.toJson(), source.action.toJson());
      expect(actor.usageCheckpoint.stock.remainingFor('003'), 1);
      expect(actor.usageCheckpoint.reservationsByIntent, isEmpty);
      expect(
        actor.usageCheckpoint.usageForIntent(source.intentId)!.toJson(),
        sourceJson,
      );
      expect(
        setup.backend.round.corruption!.actions.single.usageId,
        replay.usageId,
      );
      expect(learning.appliedEventIds[actor.playerId], eventsBefore);

      expect(
        setup.backend.round.corruption!.actions.single.status,
        ActionExecutionStatus.PROPOSED,
      );

      await actor.completeAction();
      await _settle();
      expect(setup.backend.phase, NetworkGamePhase.finalResolved);
      expect(
        setup.backend.round.corruption!.actions.single.status,
        ActionExecutionStatus.PROPOSED,
      );
      expect(learning.appliedEventIds[actor.playerId], eventsBefore);
      await partner.completeAction();
      await _settle();

      expect(setup.backend.currentRound, 3);
      expect(setup.backend.phase, NetworkGamePhase.commit);
      expect(setup.alice.viewState, NetworkGameViewState.choosing);
      expect(setup.bob.viewState, NetworkGameViewState.choosing);
      expect(setup.backend.points, pointsBeforeCorruption);
      expect(
        actor.usageCheckpoint.stock.remainingFor(offered.id),
        quotaBefore - 1,
      );
      expect(
        actor.usageCheckpoint.usagesByIntent.values.where(
          (usage) => usage.sourceUsageId == offered.identity,
        ),
        hasLength(1),
      );
      expect(learning.appliedEventIds[actor.playerId], {
        ...eventsBefore,
        eventId,
      });
      final completed = (await actor.privateStore.loadGame(
        sessionId: session.id,
        playerId: actor.playerId,
      ))!;
      expect(
        completed.publicDiscards
            .singleWhere((r) => r.usageId == source.usageId)
            .toJson(),
        historicalJson,
      );
      expect(
        completed.publicDiscards
            .singleWhere((r) => r.usageId == replay.usageId)
            .usage
            .toJson()['source_usage_id'],
        source.usageId,
      );
      final acceptedCheckpoint = actor.usageCheckpoint.encode();
      final learnedAfterCompletion = jsonEncode(
        (await actor.profileState()).toJson(),
      );
      await partner.completeAction();
      await _settle();
      expect(setup.backend.currentRound, 3);
      expect(setup.backend.points, pointsBeforeCorruption);
      expect(
        actor.usageCheckpoint.usagesByIntent.values.where(
          (usage) => usage.sourceUsageId == offered.identity,
        ),
        hasLength(1),
      );
      expect(
        jsonEncode((await actor.profileState()).toJson()),
        learnedAfterCompletion,
      );
      expect(
        actor.runtime
            .singleWhere((item) => item.occurrenceId == unrelated.occurrenceId)
            .zone,
        CardZone.HAND,
      );
      setup.backend.notifyTwice();
      await _settle();
      final reconnected = _controller(
        setup.backend,
        session,
        catalog,
        actor.playerId,
        actor.privateStore,
        learningStore: learning,
      );
      try {
        await reconnected.start();
        await _settle();
        expect(reconnected.usageCheckpoint.encode(), acceptedCheckpoint);
        expect(
          jsonEncode((await reconnected.profileState()).toJson()),
          learnedAfterCompletion,
        );
        expect(learning.appliedEventIds[actor.playerId], {
          ...eventsBefore,
          eventId,
        });
      } finally {
        reconnected.dispose();
      }
      setup.dispose();
    },
  );

  test(
    'mutual abandon learns completed Recovery once after both completions',
    () async {
      final aliceSecrets = MemoryNetworkDuelSecretStore();
      final aliceLearning = MemoryNetworkProfileLearningStore();
      final bobLearning = MemoryNetworkProfileLearningStore();
      final setup = await _setup(
        session,
        catalog,
        aliceSecrets: aliceSecrets,
        aliceLearning: aliceLearning,
        bobLearning: bobLearning,
      );
      await _playUnequal(setup);
      setup.backend.points
        ..['alice'] = 10
        ..['bob'] = 11;
      setup.backend.round
        ..finalResolution = NetworkFinalResolutionDto(mutualAbandon: true)
        ..actionProjection = null
        ..phase = NetworkGamePhase.finalResolved;
      setup.backend.recoveryAfterNormalCompletion = true;
      setup.backend.notify();
      await _settle();
      final eventId = '${session.id}/${setup.backend.round.id}/alice';
      expect(setup.alice.finalResolution!.mutualAbandon, isTrue);
      expect(setup.backend.round.ready, isEmpty);
      await setup.alice.completeAction();
      await _settle();
      expect(setup.backend.round.ready, {'alice'});
      expect(setup.backend.phase, NetworkGamePhase.finalResolved);
      expect(_totalAcceptance(aliceLearning, 'alice'), 0);
      expect(aliceLearning.appliedEventIds['alice'] ?? {}, isEmpty);
      final pending = (await aliceSecrets.loadGame(
        sessionId: session.id,
        playerId: 'alice',
      ))!;
      expect(pending.pendingLearning!['event_id'], eventId);
      await setup.bob.completeAction();
      await _settle();
      expect(setup.backend.round.ready, {'alice', 'bob'});
      expect(setup.backend.phase, NetworkGamePhase.recovery);
      // Neither abandoned normal usage was executed; Recovery has not run yet.
      expect(_totalAcceptance(aliceLearning, 'alice'), 0);
      expect(aliceLearning.appliedEventIds['alice'] ?? {}, isEmpty);

      final option = setup.alice.recoveryCards.first;
      await setup.alice.recoverWith(option.identity);
      await _settle();
      final proposal = setup.backend.round.recoveries['alice']!;
      final usageId = proposal.usageId;
      final beforeAccept = setup.alice.usageCheckpoint.stock.remainingFor(
        option.id,
      );
      expect(
        setup.alice.usageCheckpoint.usagesByIntent.values.any(
          (u) => u.usageId == usageId,
        ),
        isFalse,
      );
      await setup.bob.respondToRecovery(RecoveryResponse.ACCEPT);
      await _settle();
      final engaged = setup.alice.usageCheckpoint.usagesByIntent.values
          .singleWhere((u) => u.usageId == usageId);
      final frozen = engaged.toJson();
      expect(engaged.action.direction, CardOccurrenceDirection.MUTUEL);
      expect(engaged.conceptId, option.id);
      expect(
        setup.alice.usageCheckpoint.stock.remainingFor(option.id),
        beforeAccept - 1,
      );
      await setup.alice.completeRecovery(completed: true);
      await _settle();
      expect(setup.backend.round.recoveryHistory.single.usageId, usageId);
      expect(setup.backend.round.recoveryHistory.single.completed, isTrue);
      expect(_totalAcceptance(aliceLearning, 'alice'), 0);
      expect(aliceLearning.appliedEventIds['alice'] ?? {}, isEmpty);
      await setup.alice.skipRecovery();
      await _settle();
      expect(setup.backend.phase, NetworkGamePhase.recovery);
      expect(_totalAcceptance(aliceLearning, 'alice'), 0);
      setup.backend.cycleExhausted = true;
      await setup.bob.skipRecovery();
      await _settle();

      expect(setup.backend.phase, NetworkGamePhase.waitingNext);
      expect(_totalAcceptance(aliceLearning, 'alice'), greaterThan(0));
      expect(aliceLearning.appliedEventIds['alice'], {eventId});
      final saved = (await aliceSecrets.loadGame(
        sessionId: session.id,
        playerId: 'alice',
      ))!;
      expect(saved.pendingLearning, isNull);
      expect(saved.learningRecordedRounds, contains(1));
      expect(
        saved.conceptCheckpoint!.usagesByIntent.values
            .singleWhere((u) => u.usageId == usageId)
            .toJson(),
        frozen,
      );
      expect(saved.publicDiscards.any((r) => r.usageId == usageId), isTrue);
      final learnedState = aliceLearning.values['alice']!;
      expect(learnedState.appliedRoundEvents, {eventId});
      for (final tag in engaged.action.primaryPreferenceIds) {
        expect(
          learnedState
              .entry(
                PreferenceLearningKey(
                  preferenceId: tag,
                  role: LearningRole.mutuel,
                ),
              )!
              .acceptanceCount,
          greaterThan(0),
        );
      }
      final learned = jsonEncode(learnedState.toJson());

      setup.backend.notify();
      setup.backend.notify();
      await _settle();
      expect(aliceLearning.appliedEventIds['alice'], {eventId});
      expect(jsonEncode(aliceLearning.values['alice']!.toJson()), learned);

      setup.alice.dispose();
      final reconnected = _controller(
        setup.backend,
        session,
        catalog,
        'alice',
        aliceSecrets,
        learningStore: aliceLearning,
      );
      await reconnected.start();
      await _settle();
      expect(
        reconnected.usageCheckpoint.usagesByIntent.values
            .singleWhere((u) => u.usageId == usageId)
            .toJson(),
        frozen,
      );
      expect(
        reconnected.usageCheckpoint.stock.remainingFor(option.id),
        beforeAccept - 1,
      );
      expect(aliceLearning.appliedEventIds['alice'], {eventId});
      expect(jsonEncode(aliceLearning.values['alice']!.toJson()), learned);
      reconnected.dispose();
      setup.bob.dispose();
    },
  );

  for (final scenario in [
    (name: 'refused', accepted: false, completed: false),
    (name: 'not completed', accepted: true, completed: false),
  ]) {
    test('mutual abandon Recovery ${scenario.name} learns nothing', () async {
      final aliceLearning = MemoryNetworkProfileLearningStore();
      final setup = await _setup(
        session,
        catalog,
        aliceLearning: aliceLearning,
      );
      addTearDown(setup.dispose);
      await _enterMutualAbandonRecovery(setup);

      final option = setup.alice.recoveryCards.first;
      await setup.alice.recoverWith(option.identity);
      await _settle();
      await setup.bob.respondToRecovery(
        scenario.accepted ? RecoveryResponse.ACCEPT : RecoveryResponse.REFUSE,
      );
      await _settle();
      if (scenario.accepted) {
        await setup.alice.completeRecovery(completed: scenario.completed);
        await _settle();
      }
      await setup.alice.skipRecovery();
      setup.backend.cycleExhausted = true;
      await setup.bob.skipRecovery();
      await _settle();

      expect(_totalAcceptance(aliceLearning, 'alice'), 0);
    });
  }

  test('normal non-Recovery action learning remains unchanged', () async {
    final aliceLearning = MemoryNetworkProfileLearningStore();
    final bobLearning = MemoryNetworkProfileLearningStore();
    final setup = await _setup(
      session,
      catalog,
      aliceLearning: aliceLearning,
      bobLearning: bobLearning,
    );
    addTearDown(setup.dispose);
    await _playUnequal(setup);
    final loser = setup.alice.isInitialLoser ? setup.alice : setup.bob;
    await loser.skipCorruption();
    await _settle();
    await _completeResolvedAction(setup);

    expect(aliceLearning.appliedEventIds['alice'], hasLength(1));
    expect(bobLearning.appliedEventIds['bob'], hasLength(1));
    expect(
      _totalAcceptance(aliceLearning, 'alice') +
          _totalAcceptance(bobLearning, 'bob'),
      greaterThan(0),
    );
  });

  test(
    'recovery honors threshold, applies gain once and resumes next round',
    () async {
      final setup = await _setup(session, catalog);
      await _playUnequal(setup);
      final loser = setup.alice.isInitialLoser ? setup.alice : setup.bob;
      await loser.skipCorruption();
      await _settle();
      setup.backend.points['alice'] = 10;
      setup.backend.points['bob'] = 11;
      setup.backend.round.phase = NetworkGamePhase.recovery;
      setup.backend.notify();
      await _settle();

      final playedCardId =
          setup.alice.usageCheckpoint.usagesByIntent.values.first.conceptId;
      expect(
        setup.alice.usageCheckpoint.usagesByIntent.values.any(
          (u) => u.conceptId == playedCardId,
        ),
        isTrue,
      );
      expect(setup.alice.recoveryAvailable, isTrue);
      expect(setup.bob.recoveryAvailable, isFalse);
      final option = setup.alice.recoveryCards.singleWhere(
        (c) => c.id == '001',
      );
      expect(option.personalValue, 14);
      final beforeCheckpoint = setup.alice.usageCheckpoint;
      final quotaBefore = beforeCheckpoint.stock.remainingFor(option.id);
      final idsBefore = beforeCheckpoint.usagesByIntent.values
          .map((u) => u.usageId)
          .toSet();
      final before = setup.backend.points['alice']!;
      await setup.alice.recoverWith(option.identity);
      await setup.alice.recoverWith(option.identity);
      await _settle();
      expect(setup.backend.round.recoveries, hasLength(1));
      expect(
        setup.alice.usageCheckpoint.usagesByIntent.values
            .map((u) => u.usageId)
            .toSet(),
        idsBefore,
      );
      expect(
        setup.alice.usageCheckpoint.stock.remainingFor(option.id),
        quotaBefore,
      );
      expect(
        setup.alice.usageCheckpoint.availableFor(option.id),
        quotaBefore - 1,
      );
      expect(setup.backend.round.recoveries['alice']!.gain, 0);
      expect(setup.backend.round.recoveries['alice']!.completed, isFalse);
      expect(setup.bob.viewState, NetworkGameViewState.recoveryResponse);
      await setup.bob.respondToRecovery(RecoveryResponse.ACCEPT);
      await _settle();
      expect(setup.alice.viewState, NetworkGameViewState.recoveryExecution);
      final proposal = setup.backend.round.recoveries['alice']!;
      final engaged = setup.alice.usageCheckpoint.usagesByIntent.values
          .singleWhere((u) => u.usageId == proposal.usageId);
      expect(engaged.usageId, isNot(option.identity));
      expect(idsBefore, isNot(contains(engaged.usageId)));
      expect(
        setup.alice.usageCheckpoint.usagesByIntent.values
            .map((u) => u.usageId)
            .toSet(),
        {...idsBefore, engaged.usageId},
      );
      expect(
        setup.alice.usageCheckpoint.stock.remainingFor(option.id),
        quotaBefore - 1,
      );
      expect(setup.alice.usageCheckpoint.reservationsByIntent, isEmpty);
      final frozenSnapshot = engaged.toJson();
      expect(engaged.action.direction.name, option.nativeDirection.name);
      expect(engaged.action.personalValues.single.value, option.personalValue);
      await setup.alice.completeRecovery(completed: true);
      await setup.alice.completeRecovery(completed: true);
      await _settle();
      expect(setup.backend.round.recoveryHistory.single.gain, 21);
      expect(setup.backend.points['alice'], before + 21);
      expect(setup.backend.round.recoveryHistory, hasLength(1));
      expect(setup.backend.round.recoveryDone, isNot(contains('alice')));

      final saved = (await setup.alice.privateStore.loadGame(
        sessionId: session.id,
        playerId: 'alice',
      ))!;
      expect(
        saved.conceptCheckpoint!.usageForIntent(engaged.intentId)!.toJson(),
        frozenSnapshot,
      );
      expect(
        saved.conceptCheckpoint!.stock.remainingFor(option.id),
        quotaBefore - 1,
      );
      expect(
        setup.backend.round.recoveryHistory.single.usageId,
        engaged.usageId,
      );
      expect(setup.backend.round.recoveryHistory.single.completed, isTrue);
      final persistedCheckpoint = saved.conceptCheckpoint!.encode();

      setup.alice.dispose();
      final alice = _controller(
        setup.backend,
        session,
        catalog,
        'alice',
        setup.alice.privateStore,
      );
      await alice.start();
      expect(alice.round!.recoveryHistory, hasLength(1));
      await _settle();
      expect(alice.round!.recoveryHistory.single.usageId, engaged.usageId);
      expect(alice.usageCheckpoint.encode(), persistedCheckpoint);
      expect(
        alice.usageCheckpoint.usageForIntent(engaged.intentId)!.toJson(),
        frozenSnapshot,
      );
      expect(setup.backend.points['alice'], before + 21);
      await alice.skipRecovery();
      expect(setup.backend.phase, NetworkGamePhase.recovery);
      await setup.bob.skipRecovery();
      await _settle();
      expect(setup.backend.currentRound, 2);
      expect(setup.backend.phase, NetworkGamePhase.commit);
      expect(
        alice.usageCheckpoint.stock.remainingFor(option.id),
        quotaBefore - 1,
      );
      expect(
        alice.usageCheckpoint.usagesByIntent.values.where(
          (u) => u.usageId == engaged.usageId,
        ),
        hasLength(1),
      );
      expect(setup.backend.points['alice'], before + 21);
      alice.dispose();
      setup.bob.dispose();
    },
  );
  test(
    'the second Recovery exit closes once and advances without FINAL_RESOLVED',
    () async {
      final backend = _Backend();
      _setProjectedAction(
        backend,
        cards: [
          _projectedCard(
            occurrenceId: 'effect-occurrence',
            cardId: 'card.v4.034',
            variantId: 'variant.v4.034.s1',
            durationActions: 3,
          ),
        ],
      );
      final auctionCard = compromiseFixture(
        usageId: 'auction-occurrence',
        conceptId: 'card.v4.025',
        actionId: 'variant.v4.025.base',
        ownerPlayerId: 'alice',
        nativeDirection: NetworkCardDirection.FAIRE,
        effectiveDirection: NetworkCardDirection.FAIRE,
        origin: NetworkCompromiseOrigin.AUCTION,
        snapshotValue: 12,
      );
      backend.round
        ..phase = NetworkGamePhase.recovery
        ..ready.addAll(const {'alice', 'bob'})
        ..negotiation = const NetworkNegotiationDto(
          response: NetworkNegotiationResponseDto(accepted: true),
        )
        ..finalResolution = NetworkFinalResolutionDto(
          retainedPlayerId: 'alice',
          initialWinnerPlayerId: 'bob',
          finalWinnerPlayerId: 'bob',
          cardId: 'card.v4.025',
          variantId: 'variant.v4.025.base',
          compromise: [auctionCard],
        )
        ..recoveryHistory.add(
          recoveryFixture(
            playerId: 'alice',
            conceptId: 'card.v4.001',
            actionId: 'variant.v4.001.base',
            source: RecoverySource.CATALOG,
            completed: true,
            gain: 30,
            response: RecoveryResponse.ACCEPT,
            usageId: 'recovery-occurrence',
          ),
        );
      backend.points['alice'] = 37;
      final alice = backend.repository('alice');
      final bob = backend.repository('bob');
      final aliceExit = _command(
        'recovery-exit-alice',
        'alice',
        'RECOVERY_SKIP',
        backend.round.id,
      );
      final bobExit = _command(
        'recovery-exit-bob',
        'bob',
        'RECOVERY_SKIP',
        backend.round.id,
      );

      final stillRecovering = await alice.skipRecovery(command: aliceExit);
      expect(stillRecovering.phase, NetworkGamePhase.recovery);
      expect(backend.persistentEffectTransitions, 0);
      expect(
        backend.consumedCompromiseOccurrences['alice'],
        isNot(contains(auctionCard.usageId)),
      );

      final waiting = await bob.skipRecovery(command: bobExit);
      expect(waiting.phase, NetworkGamePhase.waitingNext);
      expect(waiting.phase, isNot(NetworkGamePhase.finalResolved));
      expect(backend.points['alice'], 37);
      expect(backend.round.recoveryHistory, hasLength(1));
      expect(backend.persistentEffectTransitions, 1);
      expect(backend.persistentEffects.single.remainingActions, 3);
      expect(
        backend.consumedCompromiseOccurrences['alice'],
        contains(auctionCard.usageId),
      );

      final retried = await bob.skipRecovery(command: bobExit);
      expect(retried.phase, NetworkGamePhase.waitingNext);
      expect(backend.points['alice'], 37);
      expect(backend.round.recoveryHistory, hasLength(1));
      expect(backend.persistentEffectTransitions, 1);
      expect(
        backend.consumedCompromiseOccurrences['alice']!.where(
          (id) => id == auctionCard.usageId,
        ),
        hasLength(1),
      );

      final next = await alice.readyNextRound(
        command: _command(
          'start-after-recovery',
          'alice',
          'START_NEXT_ROUND',
          backend.round.id,
        ),
      );
      expect(next.roundNumber, 2);
      expect(next.phase, NetworkGamePhase.commit);
    },
  );

  test('Recovery completion migration preserves canonical close hooks', () {
    final sql = File(
      'supabase/migrations/'
      '202610100017_complete_recovery_to_waiting_next.sql',
    ).readAsStringSync();

    expect(sql, contains("then 'WAITING_NEXT'"));
    expect(sql, isNot(contains("then 'FINAL_RESOLVED'")));
    expect(sql, contains("old.phase in ('FINAL_RESOLVED','RECOVERY')"));
    expect(sql, contains('v4_consumed_occurrences=jsonb_set('));
    expect(sql, contains('v4_advance_persistent_effects('));
    expect(sql, contains("v_command.kind<>'RECOVERY_SKIP'"));
  });

  test(
    'network Recovery exposes and preserves a never-distributed CATALOG occurrence',
    () async {
      final setup = await _setup(session, catalog);
      await _playUnequal(setup);
      final recovering = setup.alice.isInitialLoser ? setup.alice : setup.bob;
      final partner = identical(recovering, setup.alice)
          ? setup.bob
          : setup.alice;
      await recovering.skipCorruption();
      await _settle();
      setup.backend.points[recovering.playerId] = 10;
      setup.backend.points[partner.playerId] = 11;
      setup.backend.round.phase = NetworkGamePhase.recovery;
      setup.backend.notify();
      await _settle();

      final runtimeIds = recovering.runtime
          .map((item) => item.occurrenceId)
          .toSet();
      final catalogOption = recovering.recoveryCards.firstWhere(
        (card) => !runtimeIds.contains(card.identity),
      );
      final before = setup.backend.points[recovering.playerId]!;
      await recovering.recoverWith(catalogOption.identity);
      await _settle();
      expect(
        setup.backend.round.recoveries[recovering.playerId]!.source,
        RecoverySource.CATALOG,
      );
      await partner.respondToRecovery(RecoveryResponse.ACCEPT);
      await _settle();
      await recovering.completeRecovery(completed: true);
      await recovering.completeRecovery(completed: true);
      await _settle();

      expect(
        setup.backend.points[recovering.playerId],
        before + (catalogOption.personalValue * 1.5).ceil(),
      );
      expect(setup.backend.round.recoveryHistory, hasLength(1));
      expect(
        setup.backend.round.recoveryHistory.single.gain,
        (catalogOption.personalValue * 1.5).ceil(),
      );
      expect(
        recovering.runtime.any(
          (item) => item.occurrenceId == catalogOption.identity,
        ),
        isFalse,
      );
      expect(
        recovering.usageCheckpoint.usagesByIntent.values.where(
          (usage) => usage.conceptId == catalogOption.id,
        ),
        isNotEmpty,
      );
      setup.dispose();
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
          actions: [
            NetworkCorruptionActionDto.fromUsage(
              nativeUsageFixture(conceptId: 'shown-card'),
            ),
          ],
        ),
        recoveryByPlayer: {
          'alice': NetworkRecoveryDto.fromUsage(
            nativeUsageFixture(conceptId: 'recovery-card'),
            source: RecoverySource.CATALOG,
            completed: true,
            gain: 8,
          ),
        },
        recoveryDonePlayerIds: const {'alice'},
      );
      final encoded = jsonEncode(state.toJson());
      final decoded = jsonDecode(encoded) as Map<String, Object?>;
      const privateKeys = {
        'private_hand',
        'hand',
        'locked',
        'profile',
        'private_profile',
        'private_preferences',
        'preferences',
        'draw_history',
        'nonce',
      };
      void expectNoPrivateKeys(Object? value) {
        if (value is Map<String, Object?>) {
          expect(value.keys.toSet().intersection(privateKeys), isEmpty);
          for (final nested in value.values) {
            expectNoPrivateKeys(nested);
          }
        } else if (value is List<Object?>) {
          for (final nested in value) {
            expectNoPrivateKeys(nested);
          }
        }
      }
      expectNoPrivateKeys(decoded);
      expect(decoded['v4_unlocked_spice'], state.v4UnlockedSpice);
      expect(
        ((decoded['corruption']! as Map<String, Object?>)['actions']! as List).single,
        containsPair('concept_id', 'shown-card'),
      );
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
      final completion = File(
        'supabase/migrations/202610080001_v4_action_completion.sql',
      ).readAsStringSync();
      expect(completion, contains("phase = 'CLOSED'"));
      expect(completion, contains("kind <> 'READY_NEXT'"));
      expect(completion, contains('cycle_exhausted'));
      expect(completion, contains('p_no_playable_occurrences'));
      expect(completion, contains('publish_v4_action_projection'));
      expect(completion, contains('v4_action_projection'));
      expect(completion, contains('v4_clothing_resynced'));
      expect(completion, contains('ROUND_CLOTHING_RESYNC_REQUIRED'));
      expect(completion, contains('v4_session_setup_json'));
      expect(
        completion,
        contains('if p_clothing_count is null or p_clothing_count < 0'),
      );
      expect(
        completion,
        contains('if p_clothing_count is not null and p_clothing_count < 0'),
      );
      expect(
        completion,
        contains('if p_clothing_count is null or p_clothing_count < 0 then'),
      );
      expect(completion, isNot(contains('p_clothing_count <= 0')));
      expect(completion, contains("'opponent_reveal',null"));
      expect(completion, contains('resolve_network_initial_private'));
      expect(completion, contains('v4_public_compromise_cards'));
      expect(completion, contains("item.value - 'snapshot_value'"));
      expect(
        completion,
        contains("r.initial_resolution-'gap'-'gap_cost'-'high_value'"),
      );
      expect(completion, contains("raise exception 'ROUND_CYCLE_EXHAUSTED'"));
      expect(completion, contains("v_round.phase <> 'WAITING_NEXT'"));
      expect(completion, contains('persist_v4_resolved_action_parameters'));
      expect(completion, contains('repair_v4_action_parameters'));
      expect(completion, contains('v4_verified_final_resolution'));
      expect(
        completion,
        contains("choice_payload#>>'{parameters,occurrence_id}'"),
      );
      expect(completion, contains("'{parameters,resolved_parameters}'"));
      expect(completion, contains("'{parameters,effective_spice}'"));
      expect(
        completion,
        contains("raise exception 'ROUND_ACTION_PARAMETERS_MISSING'"),
      );
      expect(
        completion,
        contains("raise exception 'ROUND_ACTION_PARAMETERS_MISMATCH'"),
      );
      expect(
        completion,
        contains("raise exception 'ROUND_ACTION_PROJECTION_MISMATCH'"),
      );
      expect(completion, isNot(contains('count(*) from jsonb_object_keys')));
      expect(completion, contains('pg_advisory_xact_lock'));
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

Catalog _catalogWithCards(Catalog source, Set<String> cardIds) {
  final cards = Map<String, Object?>.from(source.cardsDocument);
  cards['cards'] = [
    for (final raw in source.cardsDocument['cards']! as List)
      if (cardIds.contains((raw as Map)['stable_id'])) raw,
  ];
  return Catalog(
    cardsDocument: cards,
    profilesDocument: Map<String, Object?>.from(source.profilesDocument),
    tagsDocument: Map<String, Object?>.from(source.tagsDocument),
    concepts: ConceptCatalog.fromJson({
      ...source.concepts!.reader.json,
      'concepts': [
        for (final concept in source.concepts!.concepts)
          if ((source.conceptRules!['bindings']! as List).any(
            (binding) =>
                binding['concept_id'] == concept.id &&
                (binding['source_card_ids'] as List).any(cardIds.contains),
          ))
            concept.reader.json,
      ],
    }),
    conceptRules: {
      ...source.conceptRules!,
      'bindings': [
        for (final binding in source.conceptRules!['bindings']! as List)
          if ((binding['source_card_ids'] as List).any(cardIds.contains))
            binding,
      ],
    },
  );
}

Iterable<String> _cardIdsForPresence(
  Catalog catalog,
  V4PresenceCompatibility expected,
) sync* {
  for (final card in catalog.cards) {
    final variant = card.variants
        .where(
          (item) =>
              item.chiliLevel == 1 &&
              (item.v4Stage == null || item.v4Stage == 1) &&
              (item.v4RequiredAccessoriesAnyOf ??
                      card.v4?.requiredAccessoriesAnyOf ??
                      const <String>[])
                  .isEmpty,
        )
        .firstOrNull;
    if (variant == null) continue;
    final presence =
        variant.v4Presence ??
        card.v4?.presence ??
        V4PresenceCompatibility.presentiel;
    if (presence == expected) yield card.stableId;
  }
}

List<CardRuntimeState> _handStates(Catalog catalog) => [
  for (final card in catalog.cards)
    if (card.variants
            .where(
              (item) =>
                  item.chiliLevel == 1 &&
                  (item.v4Stage == null || item.v4Stage == 1),
            )
            .firstOrNull
        case final variant?)
      CardRuntimeState(
        cardId: card.stableId,
        occurrenceId: '${card.stableId}::${variant.stableId}::occ-1',
        variantId: variant.stableId,
        zone: CardZone.HAND,
      ),
];

Future<_Setup> _setup(
  LobbySession session,
  Catalog catalog, {
  NetworkDuelSecretStore? aliceSecrets,
  NetworkDuelSecretStore? bobSecrets,
  NetworkProfileLearningStore? aliceLearning,
  NetworkProfileLearningStore? bobLearning,
}) async {
  final backend = _Backend();
  final alice = _controller(
    backend,
    session,
    catalog,
    'alice',
    aliceSecrets ?? MemoryNetworkDuelSecretStore(),
    learningStore: aliceLearning,
  );
  final bob = _controller(
    backend,
    session,
    catalog,
    'bob',
    bobSecrets ?? MemoryNetworkDuelSecretStore(),
    learningStore: bobLearning,
  );
  await Future.wait([alice.start(), bob.start()]);
  return _Setup(backend, alice, bob);
}

NetworkGameController _controller(
  _Backend backend,
  LobbySession session,
  Catalog catalog,
  String playerId,
  NetworkDuelSecretStore store, {
  NetworkProfileLearningStore? learningStore,
}) => NetworkGameController(
  session: session,
  playerId: playerId,
  repository: backend.repository(playerId),
  privateStore: store,
  learningStore: learningStore ?? MemoryNetworkProfileLearningStore(),
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
  bool requireRepeatable = false,
  String? avoidBobCard,
}) async {
  final pairs = [
    for (final a in setup.alice.hand.where(setup.alice.isCardPlayable))
      for (final b in setup.bob.hand.where(setup.bob.isCardPlayable)) (a, b),
  ];
  final pair = pairs.firstWhere((pair) {
    final aWins = pair.$1.personalValue > pair.$2.personalValue;
    final winner = aWins ? pair.$1 : pair.$2;
    return (!requireRepeatable ||
            (setup.alice.usageCheckpoint.stock.capacity[pair.$1.id]! > 1 &&
                setup.bob.usageCheckpoint.stock.capacity[pair.$2.id]! > 1)) &&
        (avoidBobCard == null || pair.$2.identity != avoidBobCard) &&
        pair.$1.personalValue != pair.$2.personalValue &&
        (avoidAliceCard == null || pair.$1.identity != avoidAliceCard) &&
        (forceAliceCard == null || pair.$1.identity == forceAliceCard) &&
        (!requireInvertibleWinner ||
            (winner.variant.invertible &&
                (winner.nativeDirection == CardOccurrenceDirection.FAIRE ||
                    winner.nativeDirection ==
                        CardOccurrenceDirection.RECEVOIR) &&
                winner.oppositePersonalValue != null)) &&
        (!requireNonInvertibleWinner ||
            !winner.variant.invertible ||
            winner.oppositePersonalValue == null);
  });
  setup.alice.selectCard(pair.$1.identity);
  setup.bob.selectCard(pair.$2.identity);
  expect(setup.alice.selectedCard, isNotNull);
  expect(
    setup.bob.selectedCard,
    isNotNull,
    reason:
        'bob view=${setup.bob.viewState}, round=${setup.bob.roundNumber}, '
        'phase=${setup.bob.round?.phase}',
  );
  await setup.alice.confirmSelection();
  expect(
    setup.bob.selectedCard,
    isNotNull,
    reason: 'Bob selection was cleared after Alice committed',
  );
  await setup.bob.confirmSelection();
  await _settle();
  expect(
    setup.alice.initialResolution,
    isNotNull,
    reason:
        'alice=${setup.alice.errorMessage}, bob=${setup.bob.errorMessage}, '
        'phase=${setup.backend.phase}, '
        'views=${setup.alice.viewState}/${setup.bob.viewState}, '
        'selected=${setup.alice.selectedCard?.identity}/'
        '${setup.bob.selectedCard?.identity}',
  );
}

Future<_Setup> _setupCorruption(
  LobbySession session,
  Catalog catalog, {
  MemoryNetworkProfileLearningStore? learning,
}) async {
  final backend = _Backend();
  final stores = {
    'alice': MemoryNetworkDuelSecretStore(),
    'bob': MemoryNetworkDuelSecretStore(),
  };
  for (final entry in stores.entries) {
    await entry.value.saveGame(
      sessionId: session.id,
      playerId: entry.key,
      state: privateGameFixture(
        roundNumber: 1,
        ownerPlayerId: entry.key,
        cards: [
          for (final id in ['003', '001', '012', '032'])
            CardRuntimeState(cardId: id, zone: CardZone.HAND),
        ],
      ),
    );
  }
  final tags = {
    for (final binding in catalog.conceptRules!['bindings']! as List)
      for (final action in binding['actions'] as List)
        for (final tag in action['editorial']['tags'] as List)
          if ((tag as String).startsWith('v3.preference.')) tag,
  };
  NetworkGameController player(String id, int value) => NetworkGameController(
    session: session,
    playerId: id,
    repository: backend.repository(id),
    privateStore: stores[id]!,
    learningStore: learning ?? MemoryNetworkProfileLearningStore(),
    catalog: catalog,
    privateProfile: PlayerGameProfile(
      playerId: id,
      preferences: {
        for (final tag in tags)
          tag: PreferenceValue(
            status: PreferenceStatus.ACCEPTED,
            general: value,
            faire: value,
            recevoir: value,
          ),
      },
    ),
    nonceFactory: () => 'nonce-$id-${backend.currentRound}',
    clock: () => DateTime.utc(2026, 9, 30, 12, backend.currentRound),
  );
  final setup = _Setup(backend, player('alice', 8), player('bob', 12));
  await Future.wait([setup.alice.start(), setup.bob.start()]);
  await _settle();
  return setup;
}

Future<void> _reachSecondResolved(_Setup setup) async {
  await _playUnequal(setup, forceAliceCard: '003', requireRepeatable: true);
  final firstAlice =
      setup.alice.usageCheckpoint.usagesByIntent.values.single.conceptId;
  final firstBob =
      setup.bob.usageCheckpoint.usagesByIntent.values.single.conceptId;
  final firstLoser = setup.alice.isInitialLoser ? setup.alice : setup.bob;
  await firstLoser.skipCorruption();
  await _settle();
  await _completeResolvedAction(setup);
  await _cycleController(setup).completeAction();
  await _settle();
  await _playUnequal(setup, avoidAliceCard: firstAlice, avoidBobCard: firstBob);
  final secondLoser = setup.alice.isInitialLoser ? setup.alice : setup.bob;
  await secondLoser.skipCorruption();
  await _settle();
}

Future<void> _completeResolvedAction(_Setup setup) async {
  await setup.alice.completeAction();
  await _settle();
  await setup.bob.completeAction();
  await _settle();
}

Future<void> _enterMutualAbandonRecovery(_Setup setup) async {
  await _playUnequal(setup);
  setup.backend.points
    ..['alice'] = 10
    ..['bob'] = 11;
  setup.backend.round
    ..finalResolution = NetworkFinalResolutionDto(mutualAbandon: true)
    ..actionProjection = null
    ..phase = NetworkGamePhase.recovery;
  setup.backend.notify();
  await _settle();
  expect(setup.alice.viewState, NetworkGameViewState.recovery);
}

double _totalAcceptance(
  MemoryNetworkProfileLearningStore store,
  String playerId,
) =>
    store.values[playerId]?.entries.values.fold<double>(
      0,
      (total, entry) => total + entry.acceptanceCount,
    ) ??
    0;

NetworkGameController _cycleController(_Setup setup) =>
    setup.alice.isCycleController ? setup.alice : setup.bob;

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

ChoicePayload _choice(String player, int value) => ChoicePayload.fromUsage(
  nativeUsageFixture(
    owner: player,
    value: value,
    usageId: 'test-$player-$value',
  ),
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

NetworkResolvedActionCardDto _projectedCard({
  required String occurrenceId,
  required String cardId,
  required String variantId,
  List<String> targetPlayerIds = const ['bob'],
  V4ClothingBehavior? clothingBehavior,
  int? durationActions,
  String? actionText,
}) {
  final card = resolvedActionFixture(
    usageId: occurrenceId,
    conceptId: cardId,
    actionId: variantId,
    direction: NetworkCardDirection.FAIRE,
    targetPlayerIds: targetPlayerIds,
    effectiveSpice: 1,
  );
  if (clothingBehavior == null && durationActions == null && actionText == null)
    return card;
  // Explicit frozen metadata for clothing/duration projection fixtures only.
  return NetworkResolvedActionCardDto.fromJson({
    ...card.toJson(),
    'resolved_action': {
      ...card.usage.resolvedAction,
      if (actionText != null) 'action_text': actionText,
      'parameters': {
        ...card.parameters,
        if (clothingBehavior != null)
          'clothing_behavior': clothingBehavior.name,
        if (durationActions != null) 'duration_actions': durationActions,
      },
    },
  });
}

NetworkGameRoundStateDto _revisioned(
  NetworkGameRoundStateDto state,
  int revision,
) => state.withRoundRevision(revision);

List<V4PersistentEffect> _advancePersistentEffects(
  List<V4PersistentEffect> active,
  List<NetworkResolvedActionCardDto> cards,
) {
  var result = active;
  for (final card in cards) {
    final duration = card.parameters['duration_actions'] as int?;
    result = const V4PersistentEffectEngine().closeAction(
      activeBeforeAction: result,
      producedEffects: duration != null
          ? const V4PersistentEffectEngine().createForAction(
              cardId: card.cardId,
              targetPlayerIds: card.targetPlayerIds,
              durationActions: duration,
            )
          : const [],
    );
  }
  return result;
}

void _setProjectedAction(
  _Backend backend, {
  required List<NetworkResolvedActionCardDto> cards,
  Set<String> requiredClothingPlayerIds = const {},
}) {
  backend.round
    ..phase = NetworkGamePhase.finalResolved
    ..finalResolution = NetworkFinalResolutionDto(
      retainedPlayerId: 'alice',
      initialWinnerPlayerId: 'alice',
      finalWinnerPlayerId: 'alice',
      cardId: cards.first.cardId,
      variantId: cards.first.variantId,
    )
    ..actionProjection = NetworkResolvedActionProjectionDto(
      cards: cards,
      requiredClothingPlayerIds: requiredClothingPlayerIds,
    );
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
  NetworkNegotiationDto? negotiation;
  NetworkResolvedActionProjectionDto? actionProjection;
  NetworkCorruptionDto? corruption;
  final recoveries = <String, NetworkRecoveryDto>{};
  final recoveryHistory = <NetworkRecoveryDto>[];
  final recoveryDone = <String>{};
  final ready = <String>{};
  final ties = <String, TieDecision>{};
}

final class _MemoryActiveSessionStore implements ActiveSessionStore {
  String? value;

  @override
  Future<void> clear() async => value = null;

  @override
  Future<String?> load() async => value;

  @override
  Future<void> save(String sessionId) async => value = sessionId;
}

final class _Backend {
  String? missedBoundaryPlayer;
  String? delayedCompletionPlayer;
  Completer<void>? completionResponse;
  bool failNextCommit = false;
  bool failNextRecovery = false;
  bool failNextCancellation = false;
  final rounds = <int, _RoundRecord>{1: _RoundRecord(1)};
  final points = <String, int>{'alice': 100, 'bob': 100};
  final commands = <String>{};
  final closedRoundIds = <String>{};
  final consumedCompromiseOccurrences = <String, Set<String>>{
    'alice': <String>{},
    'bob': <String>{},
  };
  final changes = StreamController<void>.broadcast();
  final clothingCounts = <String, int>{'alice': 6, 'bob': 6};
  final clothingResynced = <String>{};
  List<V4PersistentEffect> persistentEffects = const [];
  int persistentEffectTransitions = 0;
  int currentRound = 1;
  int roundCreations = 1;
  int initialApplications = 0;
  int counterApplications = 0;
  int negotiationProposalCalls = 0;
  int defenseApplications = 0;
  int closeApplications = 0;
  bool cycleExhausted = false;
  bool redactOpponentReveal = false;
  bool routeToUnifiedPostDuelChoice = false;
  bool recoveryAfterNormalCompletion = false;
  bool hybridMode = false;
  int deckCycle = 1;
  bool infiniteMode = false;
  PlayerStyle deckStyle = PlayerStyle.SOFT;
  int v4UnlockedSpice = 1;
  PlayerStyle? cycleStyleProposal;
  String? cycleStyleProposer;
  int cycleStyleRevision=0;
  Map<String,bool> cycleStyleVotes={};
  int recoveryCredits = 0;
  int get totalPaSpent =>
      200 + recoveryCredits - points.values.fold(0, (sum, pa) => sum + pa);

  void refreshPaSpice() {
    final thresholds = switch (deckStyle) {
      PlayerStyle.SOFT => [40, 100, 150],
      PlayerStyle.EPICE => [30, 75, 120],
      PlayerStyle.INTENABLE => [20, 55, 90],
    };
    final level = 1 + thresholds.where((pa) => totalPaSpent >= pa).length;
    if (level > v4UnlockedSpice) v4UnlockedSpice = level;
  }

  HybridDeckOrientation hybridOrientation = HybridDeckOrientation.faceToFace;
  HybridDeckOrientation? hybridAvailabilityOrientation;
  int hybridAvailabilityGeneration = 0;
  final hybridAvailability = <String, NetworkHybridAvailabilityDto>{};

  _RoundRecord get round => rounds[currentRound]!;
  NetworkGamePhase get phase => round.phase;
  NetworkGameRepository repository(String player) => _Repository(this, player);

  NetworkGameRoundStateDto state(String player) {
    refreshPaSpice();
    return NetworkGameRoundStateDto(
      usageContractVersion: 1,
      roundId: round.id,
      sessionId: 'session-multi',
      sessionRound: 'session-multi.round-${round.number}',
      roundNumber: round.number,
      phase: round.phase,
      playerId: player,
      commits: {
        for (final entry in round.commits.entries)
          entry.key: entry.value.digest,
      },
      actionPoints: points,
      readyNextPlayerIds: round.ready,
      tieDecisions: round.ties,
      hybridOrientation: hybridOrientation,
      hybridAvailabilityOrientation: hybridAvailabilityOrientation,
      hybridAvailabilityGeneration: hybridAvailabilityGeneration,
      hybridAvailabilityByPlayer: hybridAvailability,
      deckCycle: deckCycle,
      v4UnlockedSpice: v4UnlockedSpice,
      infiniteMode: infiniteMode,
      deckStyle: deckStyle,
      v4ConsumedUsageIds: consumedCompromiseOccurrences[player],
      v4PersistentEffects: persistentEffects,
      cycleExhausted: cycleExhausted,
      cycleStyleProposal:cycleStyleProposal,cycleStyleProposer:cycleStyleProposer,cycleStyleRevision:cycleStyleRevision,cycleStyleVotes:cycleStyleVotes,
      actionProjection: round.actionProjection,
      clothingCounts: clothingCounts,
      clothingResyncedPlayerIds: clothingResynced,
      initialDuelCards: round.initial == null ? const [] : [for (final reveal in round.reveals.values) NetworkUsageProjection.fromJson({...reveal.choice.usage!.toJson()}..remove('snapshot_value')..remove('inverted_resolution'))],
      ownReveal: round.reveals[player],
      opponentReveal: _revealsPublic && !redactOpponentReveal
          ? round.reveals.entries
                .where((entry) => entry.key != player)
                .map((entry) => entry.value)
                .firstOrNull
          : null,
      initialResolution: round.initial,
      counterBid: round.counter,
      finalDefense: round.defense,
      finalResolution: round.finalResolution,
      negotiation: round.negotiation,
      corruption: round.corruption,
      recoveryByPlayer: round.recoveries,
      recoveryDonePlayerIds: round.recoveryDone,
      recoveryHistory: round.recoveryHistory,
    );
  }

  bool get _revealsPublic => round.phase == NetworkGamePhase.ready;

  void notify() => changes.add(null);
  void notifyTwice() {
    notify();
    notify();
  }
}

class _Repository
    implements
        NetworkGameRepository,
        NetworkNegotiationRepository,
        NetworkSessionFlowRepository,
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
  Future<NetworkGameRoundStateDto> getRound({
    required String sessionId,
    required String roundId,
  }) async {
    final record = backend.rounds.values.singleWhere((r) => r.id == roundId);
    final json = backend.state(player).toJson();
    json['round_id'] = record.id;
    json['round_number'] = record.number;
    json['phase'] = record.phase.name.toUpperCase();
    json['ready_next'] = {for (final id in record.ready) id: true};
    return NetworkGameRoundStateDto.fromJson(json);
  }

  @override
  Future<NetworkGameRoundStateDto> setHybridOrientation({
    required NetworkCommandDto command,
    required HybridDeckOrientation orientation,
  }) async {
    if (_accept(command)) {
      backend.hybridMode = true;
      backend.hybridOrientation = orientation;
      backend.cycleExhausted = false;
      backend.hybridAvailabilityOrientation = orientation;
      backend.hybridAvailabilityGeneration++;
      backend.hybridAvailability.clear();
      _notify();
    }
    return backend.state(player);
  }

  @override
  Future<NetworkGameRoundStateDto> reportHybridAvailability({
    required NetworkCommandDto command,
    required NetworkHybridAvailabilityDto availability,
    required int generation,
  }) async {
    if (backend.commands.contains(command.commandId)) {
      return backend.state(player);
    }
    if (backend.phase != NetworkGamePhase.waitingNext ||
        backend.hybridAvailabilityOrientation != availability.orientation ||
        backend.hybridOrientation != availability.orientation ||
        backend.hybridAvailabilityGeneration != generation) {
      throw const NetworkRoundException('ROUND_HYBRID_ORIENTATION_STALE');
    }
    final previous = backend.hybridAvailability[player];
    if (previous != null &&
        previous.toJson().toString() != availability.toJson().toString()) {
      throw const NetworkRoundException('ROUND_HYBRID_AVAILABILITY_CONFLICT');
    }
    backend.commands.add(command.commandId);
    backend.hybridAvailability[player] = availability;
    backend.cycleExhausted = backend.hybridAvailability.values.any(
      (report) =>
          !report.hasPlayableCurrentOrientation &&
          !report.hasPlayableAlternateOrientation,
    );
    _notify();
    return backend.state(player);
  }

  @override
  Future<NetworkGameRoundStateDto> continueDeckCycle({
    required NetworkCommandDto command,
    required DeckExhaustionChoice choice,
    required int expectedCycle,
    int expectedStyleRevision = 0,
  }) async {
    if (choice == DeckExhaustionChoice.finish ||
        choice == DeckExhaustionChoice.newCustomizedGame) {
      throw const NetworkRoundException('ROUND_INVALID_ARGUMENT');
    }
    if (backend.commands.contains(command.commandId)) {
      return backend.state(player);
    }
    if (expectedCycle < backend.deckCycle) return backend.state(player);
    if (expectedCycle != backend.deckCycle)
      throw const NetworkRoundException('ROUND_CYCLE_MISMATCH');
    if (backend.phase != NetworkGamePhase.waitingNext) {
      throw const NetworkRoundException('ROUND_INVALID_PHASE');
    }
    if (!backend.cycleExhausted) {
      throw const NetworkRoundException('ROUND_CYCLE_NOT_EXHAUSTED');
    }
    backend.commands.add(command.commandId);
    if(expectedStyleRevision!=backend.cycleStyleRevision)throw const NetworkRoundException('ROUND_STYLE_STALE');
    final increase=choice==DeckExhaustionChoice.continueSpicier||choice==DeckExhaustionChoice.continueIntenable;
    if(choice==DeckExhaustionChoice.refuseStyle){
      backend.cycleStyleProposal=null;backend.cycleStyleVotes={player:false};backend.cycleStyleRevision++;
    }else if(increase&&backend.deckStyle!=PlayerStyle.INTENABLE&&backend.cycleStyleProposal==null){
      backend.cycleStyleProposal=backend.deckStyle==PlayerStyle.SOFT?PlayerStyle.EPICE:PlayerStyle.INTENABLE;
      backend.cycleStyleProposer=player;backend.cycleStyleVotes={player:true};backend.cycleStyleRevision++;
    }else{
      if(increase&&backend.cycleStyleProposer==player)throw const NetworkRoundException('ROUND_STYLE_NOT_AGREED');
      backend.deckCycle++;
      if(increase)backend.deckStyle=backend.cycleStyleProposal??backend.deckStyle;
      backend.infiniteMode=backend.infiniteMode||choice==DeckExhaustionChoice.infinite;
      backend.cycleStyleProposal=null;backend.cycleStyleVotes={};backend.cycleStyleRevision++;
      backend.consumedCompromiseOccurrences['alice']!.clear();backend.consumedCompromiseOccurrences['bob']!.clear();backend.cycleExhausted=false;
    }
    _notify();
    return backend.state(player);
  }

  @override
  Future<NetworkGameRoundStateDto> publishUnlockedSpice({
    required NetworkCommandDto command,
    required int unlockedSpice,
  }) async {
    // Legacy publication is now a read of the server-managed ceiling.
    return backend.state(player);
  }

  @override
  Future<NetworkGameRoundStateDto> submitNegotiationProposal({
    required NetworkCommandDto command,
    required NetworkNegotiationOfferDto offer,
  }) async {
    backend.negotiationProposalCalls++;
    if (offer.directPa == 0 &&
        !offer.inversionRequested &&
        offer.cards.isEmpty) {
      throw const NetworkRoundException('ROUND_NEGOTIATION_INVALID');
    }
    if (!_accept(command)) return backend.state(player);
    if (backend.phase != NetworkGamePhase.corruptionDecision ||
        offer.cards.any(
          (card) => backend.consumedCompromiseOccurrences[player]!.contains(
            card.usageId,
          ),
        )) {
      throw const NetworkRoundException('ROUND_NEGOTIATION_INVALID');
    }
    backend.round.negotiation = NetworkNegotiationDto(proposal: offer);
    backend.round.phase = NetworkGamePhase.negotiationResponse;
    _notify();
    return backend.state(player);
  }

  @override
  Future<NetworkGameRoundStateDto> respondNegotiation({
    required NetworkCommandDto command,
    required NetworkNegotiationResponseDto response,
  }) async {
    if (!_accept(command)) return backend.state(player);
    if (backend.phase != NetworkGamePhase.negotiationResponse) {
      throw const NetworkRoundException('ROUND_INVALID_PHASE');
    }
    final negotiation = backend.round.negotiation!;
    final offer = negotiation.proposal!;
    backend.round.negotiation = NetworkNegotiationDto(
      proposal: offer,
      response: response,
      finalOffer: response.accepted ? offer : null,
    );
    if (response.accepted) {
      final previous = backend.round.finalResolution!;
      backend.round.finalResolution = NetworkFinalResolutionDto(
        retainedPlayerId: offer.cards.first.ownerPlayerId,
        initialWinnerPlayerId: previous.initialWinnerPlayerId,
        finalWinnerPlayerId: previous.finalWinnerPlayerId,
        cardId: offer.cards.first.cardId,
        variantId: offer.cards.first.variantId,
        inverted: offer.inversionRequested,
        compromise: offer.cards,
      );
    }
    backend.round.phase = NetworkGamePhase.finalResolved;
    _notify();
    return backend.state(player);
  }

  @override
  Future<NetworkGameRoundStateDto> adaptNegotiation({
    required NetworkCommandDto command,
    required NetworkNegotiationOfferDto offer,
  }) async => throw UnimplementedError('Legacy test flow is not exercised');

  @override
  Future<NetworkGameRoundStateDto> validateNegotiation({
    required NetworkCommandDto command,
    required bool accepted,
  }) async => throw UnimplementedError('Legacy test flow is not exercised');

  @override
  Future<NetworkGameRoundStateDto> submitCommit({
    required NetworkCommandDto command,
    required ChoiceCommitmentDto commitment,
  }) async {
    if (backend.failNextCommit) {
      backend.failNextCommit = false;
      throw const NetworkRoundException('TEST_CONNECTION_LOST_BEFORE_COMMIT');
    }
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
    if (backend.commands.contains(command.commandId)) {
      final recorded = backend.rounds.values
          .singleWhere((r) => r.id == command.payload['round_id'])
          .reveals[player];
      if (recorded == null || recorded.nonce != reveal.nonce ||
          recorded.choice.canonicalJson() != reveal.choice.canonicalJson()) {
        throw const NetworkRoundException('ROUND_COMMAND_CONFLICT');
      }
      return backend.state(player);
    }
    if (backend.phase != NetworkGamePhase.reveal) {
      throw const NetworkRoundException('ROUND_REVEAL_CLOSED');
    }
    if (!const CommitRevealContract().verify(
      backend.round.commits[player]!,
      ChoiceRevealDto(sessionRound: backend.state(player).sessionRound,
        playerId: player, choice: reveal.choice, nonce: reveal.nonce),
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
    if (backend.failNextCancellation) {
      backend.failNextCancellation = false;
      throw const NetworkRoundException('TEST_CONNECTION_LOST_BEFORE_CANCEL');
    }
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
    backend.closeApplications++;
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
        : NetworkGamePhase.corruptionDecision;
    if(backend.round.initial?.winnerPlayerId case final winner?){
      backend.points[winner]=backend.points[winner]!-backend.round.initial!.gapCost;
      backend.round.finalResolution=_finalChoice(winner,winner);
    }
    backend.initialApplications++;
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
      initialWinnerPlayerId: backend.round.initial?.winnerPlayerId,
      finalWinnerPlayerId: backend.round.initial?.winnerPlayerId ?? retained,
      cardId: choice.cardId,
      variantId: choice.variantId,
      usageId: choice.usageId,
      compromise: [
        NetworkCompromiseCardDto.fromUsage(
          choice.usage!.resolved(inverted: inverted),
          origin: NetworkCompromiseOrigin.INITIAL_DUEL,
        ),
      ],
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
      backend.round.finalResolution = NetworkFinalResolutionDto(
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
    required List<NetworkCorruptionActionDto> actions,
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
    if (accepted) {
      backend.round.finalResolution = NetworkFinalResolutionDto(
        retainedPlayerId: backend.round.finalResolution?.retainedPlayerId,
        initialWinnerPlayerId:
            backend.round.finalResolution?.initialWinnerPlayerId,
        finalWinnerPlayerId: backend.round.finalResolution?.finalWinnerPlayerId,
        cardId: offer.actions.first.cardId,
        variantId: offer.actions.first.variantId,
        compromise: [
          for (final action in offer.actions)
            NetworkCompromiseCardDto.fromUsage(
              action.usage.withoutPersonalValues(),
              origin: NetworkCompromiseOrigin.CORRUPTION,
            ),
        ],
      );
      backend.round.phase = NetworkGamePhase.finalResolved;
    } else {
      backend.round.phase = NetworkGamePhase.finalResolved;
    }
    _notify();
    return backend.state(player);
  }

  @override
  Future<NetworkGameRoundStateDto> resolveCorruption({
    required NetworkCommandDto command,
    required List<NetworkCorruptionActionDto> actions,
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
    backend.round.phase = NetworkGamePhase.finalResolved;
    _notify();
    return backend.state(player);
  }

  @override
  Future<NetworkGameRoundStateDto> submitRecovery({
    required NetworkCommandDto command,
    required NetworkRecoveryDto recovery,
  }) async {
    if (backend.failNextRecovery) {
      backend.failNextRecovery = false;
      throw const NetworkRoundException('TEST_CONNECTION_LOST_BEFORE_RECOVERY');
    }
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
    backend.round.recoveries[entry.key] = NetworkRecoveryDto.fromUsage(
      proposal.usage,
      source: proposal.source,
      completed: false,
      gain: proposal.gain,
      response: response,
    );
    if (response == RecoveryResponse.REFUSE) {
      backend.round.recoveryHistory.add(
        recoveryFixture(
          playerId: proposal.playerId,
          conceptId: proposal.cardId,
          actionId: proposal.variantId,
          source: proposal.source,
          completed: false,
          gain: 0,
          response: response,
          usageId: proposal.usageId,
        ),
      );
      backend.round.recoveries.remove(entry.key);
      backend.round.phase = NetworkGamePhase.recovery;
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
    backend.recoveryCredits += recovery.gain;
    backend.round.recoveryHistory.add(recovery);
    backend.round.recoveries.remove(recovery.playerId);
    backend.points[recovery.playerId] =
        backend.points[recovery.playerId]! + recovery.gain;
    backend.round.phase = NetworkGamePhase.recovery;
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
      _closeExecutedAction();
      backend.round.phase = NetworkGamePhase.waitingNext;
    }
    _notify();
    return backend.state(player);
  }

  @override
  Future<NetworkGameRoundStateDto> readyNextRound({
    required NetworkCommandDto command,
    bool noPlayableOccurrences = false,
    bool hasPlayableAlternateOrientation = false,
    int? clothingCount,
  }) async {
    if (backend.commands.contains(command.commandId)) {
      return backend.state(player);
    }
    final commandRoundId = command.payload['round_id'];
    if (commandRoundId is String &&
        backend.closedRoundIds.contains(commandRoundId)) {
      return backend.state(player);
    }
    if (backend.phase != NetworkGamePhase.finalResolved &&
        backend.phase != NetworkGamePhase.waitingNext) {
      throw const NetworkRoundException('ROUND_INVALID_PHASE');
    }
    final closesBoundary = backend.round.phase == NetworkGamePhase.waitingNext;
    if (closesBoundary && backend.cycleExhausted) {
      throw const NetworkRoundException('ROUND_CYCLE_EXHAUSTED');
    }
    if (!closesBoundary) {
      backend.commands.add(command.commandId);
      if (clothingCount != null) {
        backend.clothingCounts[player] = clothingCount;
        backend.clothingResynced.add(player);
      }
    }
    if (!closesBoundary && backend.hybridMode) {
      backend.hybridAvailabilityOrientation ??= backend.hybridOrientation;
      backend.hybridAvailability[player] = NetworkHybridAvailabilityDto(
        orientation: backend.hybridOrientation,
        hasPlayableCurrentOrientation: !noPlayableOccurrences,
        hasPlayableAlternateOrientation: hasPlayableAlternateOrientation,
      );
      if (noPlayableOccurrences && !hasPlayableAlternateOrientation) {
        backend.cycleExhausted = true;
      }
    } else {
      backend.cycleExhausted = backend.cycleExhausted || noPlayableOccurrences;
    }
    backend.round.ready.add(player);
    if (!closesBoundary) {
      if (backend.round.ready.length == 2) {
        if (backend.recoveryAfterNormalCompletion) {
          backend.round.phase = NetworkGamePhase.recovery;
        } else {
          _closeExecutedAction();
          backend.round.phase = NetworkGamePhase.waitingNext;
        }
      }
    } else {
      final barrierOrientation = backend.hybridAvailabilityOrientation;
      if (barrierOrientation != null) {
        if (backend.hybridAvailability.length != 2 ||
            backend.hybridAvailability.values.any(
              (report) => report.orientation != barrierOrientation,
            )) {
          throw const NetworkRoundException(
            'ROUND_HYBRID_AVAILABILITY_PENDING',
          );
        }
        if (backend.hybridAvailability.values.any(
          (report) => !report.hasPlayableCurrentOrientation,
        )) {
          throw const NetworkRoundException('ROUND_HYBRID_SWITCH_REQUIRED');
        }
      }
      backend.commands.add(command.commandId);
      backend.closedRoundIds.add(backend.round.id);
      backend.round.phase = NetworkGamePhase.closed;
      backend.currentRound++;
      backend.rounds.putIfAbsent(backend.currentRound, () {
        backend.roundCreations++;
        return _RoundRecord(backend.currentRound);
      });
    }
    _notify();
    if (!closesBoundary && backend.delayedCompletionPlayer == player) {
      await backend.completionResponse!.future;
    }
    return backend.state(player);
  }

  void _closeExecutedAction() {
    backend.persistentEffects = _advancePersistentEffects(
      backend.persistentEffects,
      backend.round.actionProjection?.cards ?? const [],
    );
    backend.persistentEffectTransitions++;
    final corruption = backend.round.corruption;
    if (corruption?.accepted == true) {
      backend.round.corruption = NetworkCorruptionDto(
        offeredBy: corruption!.offeredBy,
        objective: corruption.objective,
        accepted: true,
        actions: [
          for (final action in corruption.actions)
            action.copyWith(status: ActionExecutionStatus.COMPLETED),
        ],
      );
    }
    final negotiation = backend.round.negotiation;
    if (negotiation?.response?.accepted == true) {
      for (final card in backend.round.finalResolution!.compromise.where(
        (card) => card.origin == NetworkCompromiseOrigin.AUCTION,
      )) {
        backend.consumedCompromiseOccurrences[card.ownerPlayerId]!.add(
          card.usageId,
        );
      }
    }
  }

  @override
  Stream<NetworkGameRoundStateDto> watchRound({
    required String sessionId,
    required String roundId,
  }) {
    late final StreamController<NetworkGameRoundStateDto> controller;
    StreamSubscription<void>? subscription;
    var cancelled = false;
    controller = StreamController<NetworkGameRoundStateDto>(
      onListen: () {
        subscription = backend.changes.stream.listen(
          (_) {
            if (!cancelled && !(backend.missedBoundaryPlayer == player &&
                backend.phase == NetworkGamePhase.waitingNext)) {
              controller.add(backend.state(player));
            }
          },
          onError: controller.addError,
          onDone: controller.close,
        );
        controller.add(backend.state(player));
      },
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
      onCancel: () async {
        cancelled = true;
        await subscription?.cancel();
      },
    );
    return controller.stream;
  }
}

final class _RevisionRepository extends _Repository {
  _RevisionRepository(super.backend, super.player, this.canonical);

  final StreamController<NetworkGameRoundStateDto> updates =
      StreamController<NetworkGameRoundStateDto>.broadcast();
  NetworkGameRoundStateDto canonical;
  bool rejectNextCompletion = false;
  int completionAttempts = 0;

  void emit(NetworkGameRoundStateDto value) => updates.add(value);

  Future<void> dispose() => updates.close();

  @override
  Future<NetworkGameRoundStateDto> openCurrentRound({
    required NetworkCommandDto command,
  }) async => canonical;

  @override
  Future<NetworkGameRoundStateDto> getCurrentRound({
    required String sessionId,
  }) async => canonical;

  @override
  Future<NetworkGameRoundStateDto> readyNextRound({
    required NetworkCommandDto command,
    bool noPlayableOccurrences = false,
    bool hasPlayableAlternateOrientation = false,
    int? clothingCount,
  }) async {
    completionAttempts++;
    if (rejectNextCompletion) {
      rejectNextCompletion = false;
      throw const NetworkRoundException('ROUND_INVALID_PHASE');
    }
    return super.readyNextRound(
      command: command,
      noPlayableOccurrences: noPlayableOccurrences,
      hasPlayableAlternateOrientation: hasPlayableAlternateOrientation,
      clothingCount: clothingCount,
    );
  }

  @override
  Stream<NetworkGameRoundStateDto> watchRound({
    required String sessionId,
    required String roundId,
  }) async* {
    yield canonical;
    yield* updates.stream;
  }
}

final class _V4ProjectionRepository extends _Repository
    implements NetworkV4ActionRepository {
  _V4ProjectionRepository(super.backend, super.player);

  @override
  Future<NetworkGameRoundStateDto> repairV4ActionParameters({
    required NetworkCommandDto command,
  }) async {
    if (backend.commands.contains(command.commandId)) {
      return backend.state(player);
    }
    final resolution = backend.round.finalResolution!;
    final json = resolution.toJson();
    final repairedCards = <Map<String, Object?>>[];
    for (final raw in json['compromise']! as List) {
      final card = Map<String, Object?>.from(raw! as Map);
      if (card['resolved_parameters'] == null ||
          card['effective_spice'] == null) {
        final reveal = backend.round.reveals.values
            .where(
              (item) =>
                  item.choice.parameters['occurrence_id'] ==
                  card['occurrence_id'],
            )
            .firstOrNull;
        final parameters = reveal?.choice.parameters['resolved_parameters'];
        final spice = reveal?.choice.parameters['effective_spice'];
        if (parameters is! Map || spice is! int) {
          throw const NetworkRoundException('ROUND_ACTION_PARAMETERS_MISSING');
        }
        card['resolved_parameters'] = Map<String, Object?>.from(parameters);
        card['effective_spice'] = spice;
      }
      repairedCards.add(card);
    }
    json['compromise'] = repairedCards;
    backend.round.finalResolution = NetworkFinalResolutionDto.fromJson(json);
    backend.commands.add(command.commandId);
    _notify();
    return backend.state(player);
  }

  @override
  Future<NetworkGameRoundStateDto> publishV4ActionProjection({
    required NetworkCommandDto command,
    required NetworkResolvedActionProjectionDto projection,
  }) async {
    if (_accept(command)) {
      backend.round.actionProjection = projection;
      _notify();
    }
    return backend.state(player);
  }
}

final class _PrivateResolutionRepository extends _Repository
    implements NetworkPrivateInitialResolutionRepository {
  _PrivateResolutionRepository(super.backend, super.player);

  @override
  Future<NetworkGameRoundStateDto> resolveInitialPrivately({
    required NetworkCommandDto command,
  }) async {
    if (!_accept(command)) return backend.state(player);
    final reveals = backend.round.reveals.values.toList()
      ..sort((a, b) => a.playerId.compareTo(b.playerId));
    if (reveals.length != 2) {
      throw const NetworkRoundException('ROUND_READY_INCOMPLETE');
    }
    final first = reveals[0];
    final second = reveals[1];
    final firstValue = first.choice.parameters['personal_value']! as int;
    final secondValue = second.choice.parameters['personal_value']! as int;
    final tied = firstValue == secondValue;
    final winner = tied
        ? null
        : firstValue > secondValue
        ? first.playerId
        : second.playerId;
    final loser = winner == null
        ? null
        : reveals.singleWhere((item) => item.playerId != winner).playerId;
    final gap = (firstValue - secondValue).abs();
    backend.round.initial = NetworkInitialResolutionDto(
      tied: tied,
      winnerPlayerId: winner,
      loserPlayerId: loser,
      gap: gap,
      gapCost: gap,
      highValue: firstValue > secondValue ? firstValue : secondValue,
      actionPoints: backend.points,
      inversionAllowed: false,
    );
    backend.round.phase = tied
        ? NetworkGamePhase.tieDecision
        : NetworkGamePhase.corruptionDecision;
    if(backend.round.initial?.winnerPlayerId case final winner?){
      backend.points[winner]=backend.points[winner]!-backend.round.initial!.gapCost;
      backend.round.finalResolution=_finalChoice(winner,winner);
    }
    backend.initialApplications++;
    _notify();
    return backend.state(player);
  }
}

final class _PreparedRepository extends _Repository
    implements NetworkSessionSetupRepository {
  _PreparedRepository(super.backend, super.player, this.accepted);
  final bool accepted;
  V4SessionSetupDto get setup => V4SessionSetupDto(
    mode: V4SessionMode.presentiel,
    style: PlayerStyle.SOFT,
    status: accepted ? 'ACCEPTED' : 'DRAFT',
    players: [
      for (final id in ['alice', 'bob'])
        V4PlayerSessionSetupDto(
          playerId: id,
          clothingCount: 2,
          accessories: const [],
        ),
    ],
  );
  @override
  Future<V4SessionSetupDto> registerSetupAccessories({
    required String sessionId,
    required List<V4Accessory> accessories,
  }) async => setup;
  @override
  Stream<V4SessionSetupDto> watchV4SessionSetup(String sessionId) =>
      const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _MenuLobbyRepository implements NetworkLobbyRepository {
  _MenuLobbyRepository(
    LobbySession original,
    this.gameRepository, {
    this.playerId = 'alice',
    this.cancellation,
  }) : session = LobbySession(
         id: original.id,
         joinCode: original.joinCode,
         status: original.status,
         expiresAt: DateTime.utc(2099),
         players: original.players,
       );
  final LobbySession session;
  final String playerId;
  final Completer<void>? cancellation;
  @override
  final NetworkGameRepository gameRepository;
  @override
  NetworkRoundRepository get roundRepository => throw UnimplementedError();
  @override
  Future<String> currentPlayerId() async => playerId;
  @override
  Future<LobbySession> createSession({required String commandId}) async =>
      session;
  @override
  Future<LobbySession> getSession(String sessionId) async => session;
  @override
  Future<LobbySession> joinSession({
    required String code,
    required String commandId,
  }) async => session;
  @override
  Stream<LobbySession> watchSession(String sessionId) {
    // Model realtime/RPC cleanup whose acknowledgement is delayed independently
    // of CLOSE_SESSION. Previous tests used Stream.empty(), masking this race.
    return StreamController<LobbySession>(
      onCancel: () => cancellation?.future,
    ).stream;
  }
}
