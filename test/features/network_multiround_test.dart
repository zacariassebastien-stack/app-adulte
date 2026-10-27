import 'package:couple_cards/features/profile/catalog_profile_controller.dart';
import 'package:couple_cards/features/profile/radial_appreciation.dart';
import 'package:couple_cards/features/game/ui/card_hand_surface.dart';
import 'package:couple_cards/card_themes/card_renderer.dart';
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
import 'package:couple_cards/features/game/network_duel_controller.dart' show NetworkDuelCard;
import 'package:couple_cards/features/game/network_duel_screen.dart';
import 'package:couple_cards/features/game/network_profile_learning.dart';
import 'package:couple_cards/features/lobby/lobby_models.dart';
import 'package:couple_cards/features/lobby/active_session_store.dart';
import 'package:couple_cards/features/lobby/game_history.dart';
import 'package:couple_cards/sync/sync.dart';
import 'package:couple_cards/sync/rounds/session_consent.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show setEquals;
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


  for (final actor in ['alice', 'bob']) {
    for (final confirmed in [0, 5, 6]) {
      test('Followup clothing $actor=$confirmed requires explicit confirmation and survives reconnect', () async {
        final backend = _Backend();
        _setProjectedAction(backend, cards: [_projectedCard(occurrenceId: 'explicit-$actor', cardId: '006',
          variantId: '006.action', targetPlayerIds: [actor], clothingBehavior: V4ClothingBehavior.removeOne)],
          requiredClothingPlayerIds: {actor});
        final secrets = MemoryNetworkDuelSecretStore();
        var wearer = _controller(backend, session, catalog, actor, secrets);
        final otherId = actor == 'alice' ? 'bob' : 'alice';
        final other = _controller(backend, session, catalog, otherId, MemoryNetworkDuelSecretStore());
        addTearDown(other.dispose);
        await Future.wait([wearer.start(), other.start()]);
        expect(wearer.ownActionClothingConfirmed, isFalse);
        expect(other.ownActionClothingConfirmed, isTrue);
        await wearer.completeAction(); await _settle();
        expect(backend.round.ready, isNot(contains(actor)));
        expect(backend.clothingCounts[actor], 6);
        await other.completeAction(); await _settle();
        expect(backend.round.ready, contains(otherId));
        await wearer.updateOwnClothingCount(confirmed);
        expect(wearer.ownActionClothingConfirmed, isTrue);
        final saved = (await secrets.loadGame(sessionId: session.id, playerId: actor))!;
        await secrets.saveGame(sessionId: session.id, playerId: actor,
          state: NetworkPrivateGameState.fromJson(jsonDecode(jsonEncode(saved.toJson())) as Map<String, Object?>));
        wearer.dispose();
        wearer = _controller(backend, session, catalog, actor, secrets);
        addTearDown(wearer.dispose);
        await wearer.start(); await _settle();
        expect(wearer.ownActionClothingConfirmed, isTrue);
        expect(wearer.suggestedOwnClothingCount(), confirmed);
        expect(backend.clothingCounts[actor], 6);
        await wearer.completeAction(); await _settle();
        expect(backend.clothingCounts[actor], confirmed);
        expect(backend.clothingCounts[otherId], 6);
      });
    }
  }

  for (final wearer in ['alice', 'bob']) {
    for (final viewerIsWearer in [true, false]) {
      testWidgets('Followup clothing UI wearer=$wearer local=$viewerIsWearer locks only required player', (tester) async {
        SharedPreferences.setMockInitialValues({});
        final backend = _Backend();
        _setProjectedAction(backend, cards: [_projectedCard(occurrenceId: 'ui-confirm-$wearer', cardId: '006',
          variantId: '006.action', targetPlayerIds: [wearer], clothingBehavior: V4ClothingBehavior.removeOne)],
          requiredClothingPlayerIds: {wearer});
        final viewer = viewerIsWearer ? wearer : wearer == 'alice' ? 'bob' : 'alice';
        await tester.pumpWidget(MaterialApp(home: NetworkDuelScreen(session: session, playerId: viewer,
          repository: backend.repository(viewer), catalog: catalog, secretStore: MemoryNetworkDuelSecretStore(),
          anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE})));
        await tester.pumpAndSettle();
        final done = find.byKey(const Key('complete-network-action'));
        final adjust = find.byKey(const Key('adjust-deterministic-clothing-count'));
        expect(tester.widget<FilledButton>(done).onPressed, viewerIsWearer ? isNull : isNotNull);
        expect(adjust, viewerIsWearer ? findsOneWidget : findsNothing);
        if (viewerIsWearer) {
          await _showResolutionControl(tester, 'adjust-deterministic-clothing-count');
          await tester.tap(adjust); await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(TextButton, 'Annuler')); await tester.pumpAndSettle();
          expect(tester.widget<FilledButton>(done).onPressed, isNull);
          await tester.tap(adjust); await tester.pumpAndSettle();
          await tester.enterText(find.byKey(const Key('clothing-resync-count')), '6');
          await tester.tap(find.widgetWithText(FilledButton, 'Valider')); await tester.pumpAndSettle();
          expect(tester.widget<FilledButton>(done).onPressed, isNotNull);
          expect(backend.clothingCounts[wearer], 6);
        }
        await _showResolutionControl(tester, 'complete-network-action');
        await tester.tap(done); await tester.pumpAndSettle();
        expect(backend.round.ready, contains(viewer));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  test('Followup private cleanup can retry a failed local erase', () async {
    final backend = _Backend();
    final secrets = _ControlledSecretStore();
    final controller = _controller(backend, session, catalog, 'alice', secrets);
    addTearDown(controller.dispose); await controller.start();
    secrets.failClearOnce = true;
    await expectLater(controller.clearLocalSessionState(), throwsStateError);
    await controller.clearLocalSessionState();
    expect(await secrets.loadGame(sessionId: session.id, playerId: 'alice'), isNull);
  });

  test('Followup exit waits for an in-flight private save then erases it permanently', () async {
    final backend = _Backend();
    final secrets = _ControlledSecretStore();
    final controller = _controller(backend, session, catalog, 'alice', secrets);
    addTearDown(controller.dispose);
    await controller.start();
    secrets.hold = Completer<void>();
    controller.toggleLock(controller.hand.first.identity);
    await secrets.saveStarted.future;
    var cleaned = false;
    final cleanup = controller.clearLocalSessionState().then((_) => cleaned = true);
    await _settle(); expect(cleaned, isFalse);
    secrets.hold!.complete(); await cleanup;
    expect(await secrets.loadGame(sessionId: session.id, playerId: 'alice'), isNull);
    backend.notify(); await _settle();
    expect(await secrets.loadGame(sessionId: session.id, playerId: 'alice'), isNull);
    expect(secrets.clearCalls, 1);
    await controller.clearLocalSessionState();
    expect(secrets.clearCalls, 1);
  });

  test('Followup exit detaches consent without awaiting a hanging cancellation', () async {
    final backend = _Backend();
    final repository = _HangingConsentRepository(backend, 'alice');
    final secrets = MemoryNetworkDuelSecretStore();
    final controller = NetworkGameController(session: session, playerId: 'alice', repository: repository,
      catalog: catalog, privateStore: secrets,
      anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE});
    addTearDown(controller.dispose);
    await controller.start();
    await controller.clearLocalSessionState().timeout(const Duration(seconds: 1));
    expect(repository.cancel.isCompleted, isFalse);
    expect(await secrets.loadGame(sessionId: session.id, playerId: 'alice'), isNull);
    repository.cancel.complete(); repository.disposeEvents();
  });

  testWidgets('Followup concurrent return-home requests pop only the game route', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final backend = _Backend(); backend.round.phase = NetworkGamePhase.sessionClosed;
    final history = _DeferredHistoryStore();
    final active = _MemoryActiveSessionStore()..value = session.id;
    final observer = _ExitObserver();
    await tester.pumpWidget(MaterialApp(navigatorObservers: [observer], home: Builder(builder: (context) =>
      Scaffold(body: TextButton(onPressed: () => Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => NetworkDuelScreen(session: session, playerId: 'alice', repository: backend.repository('alice'),
          catalog: catalog, activeSessionStore: active, historyStore: history, secretStore: MemoryNetworkDuelSecretStore(),
          anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE}))),
        child: const Text('Accueil test'))))));
    await tester.tap(find.text('Accueil test')); await tester.pumpAndSettle();
    final callback = tester.widget<FilledButton>(find.byKey(const Key('return-home-after-session-end'))).onPressed!;
    callback(); callback();
    await tester.pump();
    expect(active.value, isNull);
    expect(history.calls, 1);
    expect(tester.widget<FilledButton>(find.byKey(const Key('return-home-after-session-end'))).onPressed, isNull);
    history.release.complete(); await tester.pumpAndSettle();
    expect(find.text('Accueil test'), findsOneWidget);
    expect(observer.pops, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('UX spice follows live network progression and Recovery P4 leaves canonical P3', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final backend = _Backend()..canonicalSpiceOverride = 1;
    await tester.pumpWidget(MaterialApp(home: NetworkDuelScreen(session: session, playerId: 'alice',
      repository: backend.repository('alice'), catalog: catalog,
      anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE}, secretStore: MemoryNetworkDuelSecretStore())));
    await tester.pumpAndSettle();
    for (final level in [1, 2, 3, 4, 3]) {
      backend.canonicalSpiceOverride = level;
      backend.notify(); await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('active-spice'))).data,
        List.generate(4, (i) => i < level ? '🌶️' : '○').join());
    }
    backend.round
      ..phase = NetworkGamePhase.recoveryExecution
      ..recoveries['bob'] = NetworkRecoveryDto.fromUsage(
        nativeUsageFixture(owner: 'bob', chili: 4), source: RecoverySource.CATALOG, response: RecoveryResponse.ACCEPT);
    backend.notify(); await tester.pumpAndSettle();
    expect(find.byKey(const Key('network-recovery-execution')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('active-spice'))).data, '🌶️🌶️🌶️○');
    expect(backend.v4UnlockedSpice, 3);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final owner in ['alice', 'bob']) {
    for (final direction in [CardOccurrenceDirection.FAIRE, CardOccurrenceDirection.RECEVOIR]) {
      test('UX Recovery real lifecycle $owner $direction blocks gain until wearer confirms', () async {
        final backend = _Backend()..canonicalSpiceOverride = 2;
        backend.round.phase = NetworkGamePhase.recovery;
        backend.points[owner] = 10;
        final secrets = MemoryNetworkDuelSecretStore();
        await secrets.saveGame(sessionId: session.id, playerId: owner,
          state: privateGameFixture(ownerPlayerId: owner, roundNumber: 1, activeChili: 2,
            cards: [CardRuntimeState(cardId: '009', zone: CardZone.HAND, nativeDirection: direction)]));
        final data = _catalogWithCards(catalog, {'card.v4.009'});
        final proposer = _controller(backend, session, data, owner, secrets);
        final partnerId = owner == 'alice' ? 'bob' : 'alice';
        final partner = _controller(backend, session, data, partnerId, MemoryNetworkDuelSecretStore());
        addTearDown(proposer.dispose); addTearDown(partner.dispose);
        await Future.wait([proposer.start(), partner.start()]);
        await proposer.recoverWith('009'); await _settle();
        await partner.respondToRecovery(RecoveryResponse.ACCEPT); await _settle();
        final frozen = jsonEncode(proposer.pendingRecovery!.usage.toJson());
        final actor = direction == CardOccurrenceDirection.FAIRE ? proposer : partner;
        final observer = identical(actor, proposer) ? partner : proposer;
        expect(actor.ownRecoveryClothingConfirmationRequired, isTrue);
        expect(observer.ownRecoveryClothingConfirmationRequired, isFalse);
        expect(proposer.waitingForRecoveryClothing, isTrue);
        await proposer.completeRecovery(completed: true); await _settle();
        expect(backend.round.recoveryHistory, isEmpty);
        expect(backend.points[owner], 10);
        expect(backend.clothingCounts, {'alice': 6, 'bob': 6});
        await observer.confirmRecoveryClothing(0); await _settle();
        expect(backend.clothingCounts, {'alice': 6, 'bob': 6});
        await actor.confirmRecoveryClothing(0); await _settle();
        expect(proposer.waitingForRecoveryClothing, isFalse);
        expect(jsonEncode(proposer.pendingRecovery!.usage.toJson()), frozen);
        expect(backend.clothingCounts[actor.playerId], 0);
        expect(backend.clothingCounts[observer.playerId], 6);
        await proposer.completeRecovery(completed: true); await _settle();
        expect(backend.round.recoveryHistory, hasLength(1));
        final points = backend.points[owner];
        await proposer.completeRecovery(completed: true); await _settle();
        expect(backend.points[owner], points);
        expect(points, greaterThan(10));
      });
    }
  }

  test('UX SQL preserves tie privacy and authoritative clothing completion gates', () {
    final sql = File('supabase/migrations/202610230001_gameplay_ux_confirmations.sql').readAsStringSync();
    expect(sql, contains("r.phase<>'TIE_DECISION' or v.player_id=p_requester"));
    expect(sql, contains("'opponent_reveal',null"));
    expect(sql, contains("when 'resetThenStrip' then p_action->'actor_player_ids'"));
    expect(sql, contains("when 'removeOne' then p_action->'target_player_ids'"));
    expect(sql, contains("auth.uid()<>p_player_id"));
    expect(sql, contains("v_command.command_payload is distinct from v_payload"));
    expect(sql, contains("ROUND_CLOTHING_ACTOR_REQUIRED"));
    expect(sql, contains("ROUND_CLOTHING_RESYNC_REQUIRED"));
    expect(sql, contains("confirmation.player_id::text=required.id"));
    expect(sql, contains("confirmation.command_payload->>'usage_id'=p_recovery->>'usage_id'"));
    expect(sql, contains('normalize_v4_clothing_projection'));
    expect(sql, isNot(contains('update public.profiles')));
  });

  for (final owner in ['alice', 'bob']) {
    for (final direction in ['FAIRE', 'RECEVOIR']) {
      testWidgets('UX Recovery clothing $owner $direction confirms on actual actor phone', (tester) async {
        SharedPreferences.setMockInitialValues({});
        final backend = _Backend()..canonicalSpiceOverride = 3;
        final original = nativeUsageFixture(owner: owner, conceptId: '009', direction: direction, chili: 4);
        final actor = (original.resolvedAction['actor_player_ids']! as List).single as String;
        final usage = NetworkUsageProjection.fromJson({...original.toJson(), 'resolved_action': {
          ...original.resolvedAction, 'parameters': {...original.resolvedAction['parameters']! as Map<String, Object?>,
            'clothing_behavior': 'resetThenNude'}}});
        // The observer is the other phone, so its fixture needs no private reservation.
        final observer = owner == 'alice' ? 'bob' : 'alice';
        backend.round..phase = NetworkGamePhase.recoveryExecution
          ..recoveries[owner] = NetworkRecoveryDto.fromUsage(usage, source: RecoverySource.CATALOG, response: RecoveryResponse.ACCEPT);
        await tester.pumpWidget(MaterialApp(home: NetworkDuelScreen(session: session, playerId: observer,
          repository: backend.repository(observer), catalog: catalog,
          anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE}, secretStore: MemoryNetworkDuelSecretStore())));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('confirm-recovery-clothing')), actor == observer ? findsOneWidget : findsNothing);
        expect(backend.clothingCounts, {'alice': 6, 'bob': 6});
        final wrong = actor == 'alice' ? 'bob' : 'alice';
        await expectLater((backend.repository(wrong) as NetworkRecoveryClothingRepository).confirmRecoveryClothing(
          command: _command('wrong-clothes', wrong, 'RECOVERY_CLOTHING_CONFIRM', backend.round.id),
          usageId: usage.usageId, clothingCount: 0), throwsA(isA<NetworkRoundException>()));
        final command = _command('actual-clothes', actor, 'RECOVERY_CLOTHING_CONFIRM', backend.round.id);
        await (backend.repository(actor) as NetworkRecoveryClothingRepository).confirmRecoveryClothing(
          command: command, usageId: usage.usageId, clothingCount: 0);
        await (backend.repository(actor) as NetworkRecoveryClothingRepository).confirmRecoveryClothing(
          command: command, usageId: usage.usageId, clothingCount: 0);
        await tester.pumpAndSettle();
        expect(backend.clothingCounts[actor], 0);
        expect(backend.clothingCounts[wrong], 6);
        expect(find.byKey(const Key('confirm-recovery-clothing')), findsNothing);
        final state = NetworkGameRoundStateDto.fromJson(backend.state(observer).toJson());
        expect(state.recoveryClothingConfirmations[usage.usageId], {actor});
        expect(backend.points, {'alice': 100, 'bob': 100});
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  for (final viewer in ['alice', 'bob']) {
    testWidgets('UX persistent reminders distinguish actor and bearer for $viewer', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final backend = _Backend();
      _setProjectedAction(backend, cards: [NetworkResolvedActionCardDto.fromUsage(nativeUsageFixture(conceptId: '035'))]);
      backend.persistentEffects = [const V4PersistentEffect(cardId: '035', targetPlayerId: 'bob', remainingActions: 2,
        actorPlayerIds: ['alice'])];
      await tester.pumpWidget(MaterialApp(home: NetworkDuelScreen(session: session, playerId: viewer,
        participantNames: const {'alice': 'Sébastien', 'bob': 'Julie'},
        repository: backend.repository(viewer), catalog: catalog,
        anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE}, secretStore: MemoryNetworkDuelSecretStore())));
      await tester.pumpAndSettle();
      expect(find.textContaining(viewer == 'alice' ? 'continue « Privation visuelle »' : 'tu es toujours sous l’effet de « Privation visuelle »'), findsOneWidget);
      expect(find.text('2/3'), findsOneWidget);
      expect(find.textContaining('Exécutant'), findsNothing);
      expect(find.textContaining('Julie doit continuer'), findsNothing);
      expect(backend.persistentEffects.single.remainingActions, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final viewer in ['alice', 'bob']) {
    for (final direction in ['FAIRE', 'RECEVOIR']) {
      testWidgets('UX Silence $direction viewed by $viewer follows frozen actor', (tester) async {
        SharedPreferences.setMockInitialValues({});
        final backend = _Backend();
        final original = nativeUsageFixture(conceptId: '061', direction: direction);
        final actor = (original.resolvedAction['actor_player_ids']! as List).single as String;
        final card = NetworkResolvedActionCardDto.fromUsage(NetworkUsageProjection.fromJson({
          ...original.toJson(), 'resolved_action': {...original.resolvedAction,
            'parameters': {...original.resolvedAction['parameters']! as Map<String, Object?>, 'duration_actions': 3}},
        }));
        _setProjectedAction(backend, cards: [card]);
        backend.persistentEffects = [V4PersistentEffect(cardId: '061', targetPlayerId: actor,
          remainingActions: 3, actorPlayerIds: [actor], actionText: 'Owner-relative frozen instruction')];
        final frozen = jsonEncode(card.toJson());
        await tester.pumpWidget(MaterialApp(home: NetworkDuelScreen(session: session, playerId: viewer,
          participantNames: const {'alice': 'Sébastien', 'bob': 'Julie'},
          repository: backend.repository(viewer), catalog: catalog,
          anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE}, secretStore: MemoryNetworkDuelSecretStore())));
        await tester.pumpAndSettle();
        final expected = actor == viewer ? 'Garde un silence complet' : '${actor == 'alice' ? 'Sébastien' : 'Julie'} garde un silence complet';
        expect(find.textContaining(expected), findsWidgets);
        expect(find.textContaining('Owner-relative frozen instruction'), findsNothing);
        expect(jsonEncode(card.toJson()), frozen);
        expect(backend.persistentEffects.single.remainingActions, 3);
        expect(backend.persistentEffects.single.targetPlayerId, actor);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  for (final viewer in ['alice', 'bob']) {
    testWidgets('UX tie $viewer renders only personal frozen card and keeps concession', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final backend = _Backend()..redactOpponentReveal = true;
      await _primeTie(backend);
      final revealB = backend.round.reveals['bob']!;
      backend.round.reveals['bob'] = ChoiceRevealDto(sessionRound: revealB.sessionRound,
        playerId: 'bob', nonce: revealB.nonce, choice: ChoicePayload.fromUsage(
          nativeUsageFixture(conceptId: '032', owner: 'bob', usageId: 'private-bob-card', value: 10)));
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(home: NetworkDuelScreen(
        session: session, playerId: viewer, repository: backend.repository(viewer),
        catalog: catalog, anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
        secretStore: MemoryNetworkDuelSecretStore())));
      await tester.pumpAndSettle();
      final renderers = tester.widgetList<CardRenderer>(find.byType(CardRenderer)).toList();
      expect(renderers, hasLength(1));
      final own = backend.round.reveals[viewer]!.choice.usage!;
      final opposite = backend.round.reveals[viewer == 'alice' ? 'bob' : 'alice']!.choice.usage!;
      expect(renderers.single.definition.cardId, own.conceptId);
      expect(find.byKey(const Key('personal-duel-card')), findsOneWidget);
      final controller = (tester.state(find.byType(NetworkDuelScreen)) as dynamic).controller as NetworkGameController;
      expect(controller.personalDuelCard!.identity, own.usageId);
      expect(controller.personalDuelCard!.identity, isNot(opposite.usageId));
      expect(controller.round!.opponentReveal, isNull);
      expect(controller.round!.initialDuelCards.map((u) => u.ownerPlayerId), [viewer]);
      expect(find.text('Mon appréciation'), findsNothing);
      final pa = Map<String, int>.from(backend.points);
      await controller.concedeTie(); await tester.pumpAndSettle();
      expect(backend.round.finalResolution!.retainedPlayerId, viewer == 'alice' ? 'bob' : 'alice');
      expect(backend.points, pa);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final scenario in [
    (NetworkGamePhase.corruptionDecision, 'alice', 'alice', 'bob', 'response'),
    (NetworkGamePhase.corruptionDecision, 'bob', 'bob', 'alice', 'response'),
    (NetworkGamePhase.negotiationProposal, 'alice', 'alice', 'bob', 'proposal'),
    (NetworkGamePhase.negotiationResponse, 'bob', 'alice', 'alice', 'negotiation-response'),
    (NetworkGamePhase.negotiationAdaptation, 'alice', 'alice', 'bob', 'adaptation'),
    (NetworkGamePhase.negotiationValidation, 'bob', 'alice', 'alice', 'validation'),
    (NetworkGamePhase.corruptionResponse, 'bob', 'alice', 'alice', 'response'),
    (NetworkGamePhase.recoveryResponse, 'bob', 'alice', 'alice', 'consent'),
    (NetworkGamePhase.recoveryExecution, 'alice', 'alice', 'bob', 'execution'),
  ]) {
    for (final names in scenario.$1 == NetworkGamePhase.corruptionDecision
        ? ['named', 'legacy', 'blank'] : ['named']) {
      testWidgets('waiting nickname ${scenario.$1.name} viewer=${scenario.$2} $names', (tester) async {
        SharedPreferences.setMockInitialValues({});
        final namedSession = LobbySession(id: session.id, joinCode: session.joinCode,
          status: session.status, expiresAt: session.expiresAt, players: [
            // Deliberately reverse role order: names are bound to IDs.
            LobbyPlayer(userId: 'bob', role: LobbyPlayerRole.player1,
              gameNickname: names == 'named' ? 'Sexgirl' : names == 'blank' ? '  ' : null),
            LobbyPlayer(userId: 'alice', role: LobbyPlayerRole.player2,
              gameNickname: names == 'named' ? 'Seblegenie' : names == 'blank' ? '  ' : null),
          ]);
        final backend = _Backend();
        final offer = NetworkNegotiationOfferDto(inversionRequested: true, directPa: 0);
        backend.round
          ..phase = scenario.$1
          ..initial = NetworkInitialResolutionDto(tied: false, gap: 1, gapCost: 1,
            actionPoints: backend.points, winnerPlayerId: scenario.$3,
            loserPlayerId: scenario.$3 == 'alice' ? 'bob' : 'alice', inversionAllowed: true)
          ..negotiation = NetworkNegotiationDto(proposal: offer, finalOffer: offer,
            response: const NetworkNegotiationResponseDto(accepted: true, acceptInversion: true))
          ..corruption = NetworkCorruptionDto(offeredBy: 'bob',
            objective: CorruptionObjective.OWN_INITIAL_ACTION, actions: const []);
        if (scenario.$1 == NetworkGamePhase.recoveryResponse ||
            scenario.$1 == NetworkGamePhase.recoveryExecution) {
          backend.round.recoveries['bob'] = NetworkRecoveryDto.fromUsage(
            nativeUsageFixture(owner: 'bob'), source: RecoverySource.HAND,
            response: scenario.$1 == NetworkGamePhase.recoveryExecution ? RecoveryResponse.ACCEPT : null);
        }
        await tester.pumpWidget(MaterialApp(home: NetworkDuelScreen(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE}, session: namedSession,
          playerId: scenario.$2, repository: backend.repository(scenario.$2), catalog: catalog,
          secretStore: MemoryNetworkDuelSecretStore())));
        await tester.pumpAndSettle();
        final name = names != 'named' ? 'ton partenaire' : scenario.$4 == 'alice' ? 'Seblegenie' : 'Sexgirl';
        final subject = names != 'named' ? 'Ton partenaire' : name;
        final expected = switch (scenario.$5) {
          'response' => 'En attente de la réponse de $name…',
          'proposal' => '$subject prépare une proposition…',
          'negotiation-response' => '$subject répond à ta proposition…',
          'adaptation' => '$subject adapte sa proposition…',
          'validation' => '$subject valide le compromis…',
          'consent' => 'En attente du consentement de $name…',
          _ => '$subject exécute l’action Recovery…',
        };
        expect(find.textContaining(expected), findsOneWidget);
        expect(find.byKey(const Key('active-spice')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets('inversion help explains only FAIRE RECEVOIR and fits small viewport', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final backend = _Backend();
    backend.round
      ..phase = NetworkGamePhase.negotiationProposal
      ..initial = NetworkInitialResolutionDto(tied: false, gap: 1, gapCost: 1,
        actionPoints: backend.points, winnerPlayerId: 'alice', loserPlayerId: 'bob', inversionAllowed: true);
    await tester.pumpWidget(MaterialApp(home: NetworkDuelScreen(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE}, session: session, playerId: 'bob',
      repository: backend.repository('bob'), catalog: catalog, secretStore: MemoryNetworkDuelSecretStore())));
    await tester.pumpAndSettle();
    final help = find.byKey(const Key('negotiation-inversion-help'));
    await tester.ensureVisible(help); await tester.pumpAndSettle();
    expect(find.text('Inverse FAIRE ↔ RECEVOIR pour la carte retenue.'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(find.byKey(const Key('negotiation-inversion'))).value, isFalse);
    expect(backend.round.negotiation, isNull);
    expect(backend.round.commits, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  V4Profile stageProfile({int? excluded, ProfilePreferenceRole? role}) {
    final preferences = <String, ProfilePreference>{};
    for (final r in ProfilePreferenceRole.values) {
      final key = ProfilePreferenceKey(tagId: 'degradant', role: r);
      preferences[key.storageKey] = ProfilePreference(profileId: 'alice', key: key, pa: 10,
        excluded: false, source: ProfilePreferenceSource.initialQuestionnaire);
    }
    return V4Profile(sex: ProfileSex.HOMME, profileId: 'alice', preferences: preferences, stageVetoes: [
      if (excluded != null) for (final r in role == null ? [ProfilePreferenceRole.faire, ProfilePreferenceRole.recevoir] : [role])
        StageVeto(conceptId: '056', actionId: '056.stage.$excluded', role: r),
    ]);
  }
  for (final owner in ['alice', 'bob']) {
    for (final direction in ['FAIRE', 'RECEVOIR']) {
      for (final behavior in [V4ClothingBehavior.resetThenNude, V4ClothingBehavior.resetThenStrip,
          V4ClothingBehavior.resetThenUnderwear, V4ClothingBehavior.removeOne, V4ClothingBehavior.chooseOutfit]) {
        test('UX clothing projection $owner $direction ${behavior.name} waits for actual bearer', () async {
          final backend = _Backend();
          final base = nativeUsageFixture(conceptId: '009', owner: owner, direction: direction);
          final usage = NetworkUsageProjection.fromJson({
            ...base.toJson(),
            'resolved_action': {
              ...base.resolvedAction,
              'parameters': {...base.resolvedAction['parameters']! as Map<String, Object?>,
                'clothing_behavior': behavior.name},
            },
          });
          backend.round
            ..phase = NetworkGamePhase.finalResolved
            ..finalResolution = NetworkFinalResolutionDto(retainedPlayerId: owner,
              initialWinnerPlayerId: owner, finalWinnerPlayerId: owner,
              compromise: [NetworkCompromiseCardDto.fromUsage(usage, origin: NetworkCompromiseOrigin.INITIAL_DUEL)]);
          final controller = NetworkGameController(session: session, playerId: owner,
            repository: _V4ProjectionRepository(backend, owner), privateStore: MemoryNetworkDuelSecretStore(),
            catalog: catalog, anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
            learningStore: MemoryNetworkProfileLearningStore());
          addTearDown(controller.dispose);
          await controller.start(); await _settle();
          final actor = (usage.resolvedAction['actor_player_ids']! as List).single as String;
          final target = (usage.resolvedAction['target_player_ids']! as List).single as String;
          final expected = [V4ClothingBehavior.removeOne, V4ClothingBehavior.chooseOutfit].contains(behavior) ? target : actor;
          expect(controller.requiredClothingPlayerIds, {expected});
          expect(backend.clothingCounts, {'alice': 6, 'bob': 6});
          expect(controller.ownClothingResyncRequired, expected == owner);
          const gate = NetworkActionCompletionGate();
          expect(gate.canClose(projection: controller.actionProjection, resyncedPlayerIds: {}), isFalse);
          expect(gate.canClose(projection: controller.actionProjection, resyncedPlayerIds: {expected == 'alice' ? 'bob' : 'alice'}), isFalse);
          expect(gate.canClose(projection: controller.actionProjection, resyncedPlayerIds: {expected}), isTrue);
          final reconstructed = NetworkResolvedActionProjectionDto.fromJson(controller.actionProjection!.toJson());
          expect(reconstructed.requiredClothingPlayerIds, {expected});
          expect(reconstructed.cards.single.clothingPlayerIds, [expected]);
        });
      }
    }
  }

  test('UX in-game appreciation preserves consent exclusions', () async {
    final profiles = MemoryV4ProfileStore(); await profiles.save(stageProfile(excluded: 3));
    final ratings = MemoryV4CardLearningStore();
    final editor = CatalogProfileController(catalog: _catalogWithCards(catalog, {'card.v4.056'}),
      playerId: 'alice', profileStore: profiles, ratingStore: ratings, learningStore: MemoryNetworkProfileLearningStore());
    addTearDown(editor.dispose); await editor.load();
    final item = editor.items.firstWhere((i) => i.actionId == '056.stage.3');
    await editor.rate(item, DetailedPreferenceCategory.love, preserveExclusions: true);
    expect((await profiles.load('alice'))!.excludesStage('056', '056.stage.3', item.direction.name), isTrue);
    expect((await ratings.load('alice')).explicitEstimate(item.ratingKey('alice')), 3.5);
  });

  for (final drag in [false, true]) {
    testWidgets('UX hand rating ${drag ? 'drag' : 'tap'} is visible above a pushed game and freezes current hand through reconnect', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      SharedPreferences.setMockInitialValues({});
      final backend = _Backend()..v4UnlockedSpice = 4;
      final focused = _catalogWithCards(catalog, {'card.v4.056'});
      final profiles = MemoryV4ProfileStore(); await profiles.save(stageProfile());
      final ratings = MemoryV4CardLearningStore();
      final secrets = MemoryNetworkDuelSecretStore();
      final editor = CatalogProfileController(catalog: focused, playerId: 'alice',
        profileStore: profiles, ratingStore: ratings, learningStore: MemoryNetworkProfileLearningStore());
      await editor.load();
      for (final item in editor.items.where((i) => i.actionId == '056.stage.3')) {
        await editor.rate(item, DetailedPreferenceCategory.like);
      }
      final game = NetworkDuelScreen(session: session, playerId: 'alice',
        repository: backend.repository('alice'), catalog: focused,
        anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
        secretStore: secrets, profileStore: profiles, cardLearningStore: ratings, v4Profile: stageProfile());
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
        body: TextButton(onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => game)), child: const Text('Open game'))))));
      await tester.tap(find.text('Open game'));
      await tester.pumpAndSettle();
      final controller = (tester.state(find.byType(NetworkDuelScreen)) as dynamic).controller as NetworkGameController;
      final hand = find.byType(CardHandSurface);
      final item = tester.widget<CardHandSurface>(hand).cards.single;
      final before = controller.hand.single.personalValue;
      final round = jsonEncode(backend.state('alice').toJson());
      final area = tester.getRect(hand);
      await tester.tapAt(Offset(area.center.dx, area.top + area.height * .85));
      await tester.pumpAndSettle();
      await tester.tapAt(tester.getCenter(find.byKey(const Key('hand-card-056'))));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('rate-hand-card-056')), findsOneWidget);
      await tester.tap(find.byKey(const Key('rate-hand-card-056')));
      await tester.pumpAndSettle();
      expect(find.text('Mon appréciation'), findsNWidgets(2));
      expect(find.byKey(const Key('appreciation-radial')), findsOneWidget);
      expect(find.byKey(const Key('appreciation-radial')).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      final wheel = tester.widget<RadialAppreciation>(find.byType(RadialAppreciation));
      expect(wheel.allowExclusion, isFalse);
      expect(wheel.visible, isTrue);
      expect(wheel.initialValue, DetailedPreferenceCategory.like);
      // AlertDialog measures its contents intrinsically before laying out the
      // route. The wheel must not expose LayoutBuilder to that measurement.
      final content = tester.widget<AlertDialog>(find.byType(AlertDialog)).content!;
      final contentBox = tester.renderObject<RenderBox>(find.byWidget(content));
      expect(contentBox.getMinIntrinsicHeight(contentBox.size.width), greaterThan(0));
      expect(contentBox.size.width, contentBox.size.height);
      expect(contentBox.size.shortestSide, greaterThan(0));
      // Closing either explicitly or with Android Back restores the enlarged
      // card, without leaving an invisible modal barrier or stacking dialogs.
      await tester.tap(find.text('Fermer'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byKey(const Key('rate-hand-card-056')).hitTestable(), findsOneWidget);
      await tester.tap(find.byKey(const Key('rate-hand-card-056')));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await tester.tap(find.byKey(const Key('rate-hand-card-056')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      final origin = tester.getCenter(find.byType(RadialAppreciation));
      // One tap on the already-visible profile wheel saves the selected sector.
      final sector = origin + Offset(0, -tester.getSize(find.byType(RadialAppreciation)).width * .33);
      if (drag) {
        final gesture = await tester.startGesture(origin);
        await gesture.moveTo(sector);
        await tester.pump();
        await gesture.up();
      } else {
        await tester.tapAt(sector);
      }
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byKey(const Key('rate-hand-card-056')).hitTestable(), findsOneWidget);
      final target = editor.items.singleWhere((i) => i.concept.id == item.definition.cardId &&
        i.actionId == item.definition.variantId && i.direction.name == item.definition.direction);
      final saved = await ratings.load('alice');
      expect(saved.explicitEstimate(target.ratingKey('alice')), 1.5);
      expect(controller.hand.single.personalValue, before);
      expect(jsonEncode(backend.state('alice').toJson()), round);
      expect(controller.usageCheckpoint.usagesByIntent, isEmpty);
      controller.selectCard('056');
      await controller.confirmSelection();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('rate-hand-card-056')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      final restored = NetworkGameController(session: session, playerId: 'alice',
        repository: backend.repository('alice'), privateStore: secrets, catalog: focused,
        anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
        v4Profile: stageProfile(), cardLearningStore: ratings, learningStore: MemoryNetworkProfileLearningStore());
      editor.dispose();
      await restored.start();
      expect(restored.personalDuelCard!.personalValue, before);
      expect(await restored.cancelSelection(), isFalse);
      final engaged = restored.personalDuelCard!.personalValue;
      expect(engaged, before);
      restored.dispose();
    });
  }

  for (final manual in [false, true]) {
    test(
      'personalization canonical lock and commit survive reconnect manual=$manual',
      () async {
        final backend = _Backend()..v4UnlockedSpice = 4;
        final ratings = MemoryV4CardLearningStore();
        final modes = MemoryPostGameProfileChoiceStore()
          ..values['alice'] = manual
              ? PostGameProfileChoice.customize
              : PostGameProfileChoice.trustGame;
        final secrets = MemoryNetworkDuelSecretStore();
        final focused = _catalogWithCards(catalog, {'card.v4.056'});
        NetworkGameController create() => NetworkGameController(
          session: session,
          playerId: 'alice',
          repository: backend.repository('alice'),
          privateStore: secrets,
          catalog: focused,
          v4Profile: stageProfile(),
          anatomies: const {
            'alice': PlayerAnatomy.PENIS,
            'bob': PlayerAnatomy.VULVE,
          },
          learningStore: MemoryNetworkProfileLearningStore(),
          cardLearningStore: ratings,
          profileChoiceStore: modes,
        );
        var controller = create();
        await controller.start();
        expect(controller.errorMessage, isNull);
        expect(controller.hand, isNotEmpty);
        final card = controller.hand.first;
        final key = CardRatingKey(
          profileId: 'alice',
          cardId: card.id,
          variantId: card.variant.id,
          role: ProfilePreferenceRole.parse(card.nativeDirection.name),
        );
        final value = card.personalValue;
        controller.toggleLock(card.id);
        controller.toggleLock(card.id);
        controller.selectCard(card.id);
        await controller.confirmSelection();
        final state = await ratings.load('alice');
        if (manual) {
          expect(state.values, isEmpty);
        } else {
          expect(state.read(key)!.observationCount, 2);
          expect(state.read(key)!.currentEstimate, value);
          expect(
            (state.read(key)!.personalization['internal']! as num).toDouble(),
            lessThan(value),
          );
        }
        expect(controller.actionPoints['alice'], 100);
        final saved = jsonEncode(state.toJson());
        controller.dispose();
        controller = create();
        await controller.start();
        expect(jsonEncode((await ratings.load('alice')).toJson()), saved);
        expect(controller.personalDuelCard!.personalValue, value);
        controller.dispose();
      },
    );
  }

  test(
    'personalization durable outbox replays a lock after failed profile write once',
    () async {
      final backend = _Backend()..v4UnlockedSpice = 4;
      final ratings = _FailOnceCardRatings();
      final modes = MemoryPostGameProfileChoiceStore()
        ..values['alice'] = PostGameProfileChoice.trustGame;
      final secrets = MemoryNetworkDuelSecretStore();
      final focused = _catalogWithCards(catalog, {'card.v4.056'});
      NetworkGameController create() => NetworkGameController(
        session: session,
        playerId: 'alice',
        repository: backend.repository('alice'),
        privateStore: secrets,
        catalog: focused,
        v4Profile: stageProfile(),
        anatomies: const {
          'alice': PlayerAnatomy.PENIS,
          'bob': PlayerAnatomy.VULVE,
        },
        learningStore: MemoryNetworkProfileLearningStore(),
        cardLearningStore: ratings,
        profileChoiceStore: modes,
      );
      var controller = create();
      await controller.start();
      final card = controller.hand.single;
      final key = CardRatingKey(
        profileId: 'alice',
        cardId: card.id,
        variantId: card.variant.id,
        role: ProfilePreferenceRole.parse(card.nativeDirection.name),
      );
      ratings.failNext = true;
      controller.toggleLock(card.id);
      await controller.flushPersonalization();
      expect(
        (await secrets.loadGame(
          sessionId: session.id,
          playerId: 'alice',
        ))!.personalizationEvents,
        isNotEmpty,
      );
      controller.dispose();
      controller = create();
      await controller.start();
      expect((await ratings.load('alice')).read(key)!.observationCount, 1);
      expect(
        (await secrets.loadGame(
          sessionId: session.id,
          playerId: 'alice',
        ))!.personalizationEvents,
        isEmpty,
      );
      controller.dispose();
    },
  );

  test('personalization compromise decisions are observed before round closure in effective roles', () async {
    final backend = _Backend()..v4UnlockedSpice = 4;
    final ratings = MemoryV4CardLearningStore();
    final modes = MemoryPostGameProfileChoiceStore()
      ..values.addAll({'alice': PostGameProfileChoice.trustGame, 'bob': PostGameProfileChoice.trustGame});
    final focused = _catalogWithCards(catalog, {'card.v4.056'});
    NetworkGameController create(String id) => NetworkGameController(session: session,
      playerId: id, repository: backend.repository(id), privateStore: MemoryNetworkDuelSecretStore(),
      catalog: focused, v4Profile: V4Profile(profileId: id, sex: id == 'alice' ? ProfileSex.HOMME : ProfileSex.FEMME,
        preferences: {for (final r in ProfilePreferenceRole.values)
          'degradant|${r.name}': ProfilePreference(profileId: id,
            key: ProfilePreferenceKey(tagId: 'degradant', role: r), pa: id == 'alice' ? 10 : 18,
            excluded: false, source: ProfilePreferenceSource.initialQuestionnaire)}),
      anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
      learningStore: MemoryNetworkProfileLearningStore(), cardLearningStore: ratings, profileChoiceStore: modes);
    final alice = create('alice'); final bob = create('bob');
    addTearDown(() { alice.dispose(); bob.dispose(); });
    await alice.start(); await bob.start();
    alice.selectCard('056'); bob.selectCard('056');
    await alice.confirmSelection(); await bob.confirmSelection(); await _settle();
    expect(alice.errorMessage, isNull); expect(bob.errorMessage, isNull);
    expect(alice.isNegotiationProposer, true);
    await alice.proposeNegotiation(inversion: false, directPa: 1);
    await _settle();
    final beforeAcceptance = await ratings.load('alice');
    expect(beforeAcceptance.values.expand((s) => (s.personalization['events'] as List?) ?? const [])
      .any((e) => (e as String).contains('compromise-request')), true);
    await bob.respondNegotiation(accepted: true); await _settle();
    expect(alice.errorMessage, isNull); expect(bob.errorMessage, isNull);
    final usage = alice.round!.finalResolution!.compromise.first.usage;
    final actors = (usage.resolvedAction['actor_player_ids'] as List).cast<String>();
    for (final id in ['alice', 'bob']) {
      final role = actors.contains(id) ? ProfilePreferenceRole.faire : ProfilePreferenceRole.recevoir;
      final key = CardRatingKey(profileId: id, cardId: '056', variantId: '056.stage.3', role: role);
      final state = (await ratings.load(id)).read(key)!;
      expect((state.personalization['events'] as List).any((e) => (e as String).contains('/accepted/')), true);
    }
    expect(alice.round!.readyNextPlayerIds, isEmpty);
  });

  testWidgets('personalization tier acceptance UI does not reprice current hand', (tester) async {
    SharedPreferences.setMockInitialValues({'post_game_profile_choice.alice': 'trustGame'});
    final ratings = MemoryV4CardLearningStore();
    final state = CardSpecificLearningStore();
    for (final role in [ProfilePreferenceRole.faire, ProfilePreferenceRole.recevoir]) {
      state.write(CardRatingStateV4(key: CardRatingKey(profileId: 'alice', cardId: '056',
        variantId: '056.stage.3', role: role), initialScore: 10, currentEstimate: 7.5,
        observationCount: 20, acceptanceCount: 0, resistanceCount: 0, source: 'CARD_ESTIMATE',
        personalization: const {'internal': 5.9, 'pending': 'likeALot', 'manual': true}));
    }
    await ratings.save('alice', state);
    final profiles = MemoryV4ProfileStore(); await profiles.save(stageProfile());
    final backend = _Backend()..v4UnlockedSpice = 4;
    await tester.pumpWidget(MaterialApp(home: NetworkDuelScreen(
      session: session, playerId: 'alice', repository: backend.repository('alice'),
      catalog: _catalogWithCards(catalog, {'card.v4.056'}), secretStore: MemoryNetworkDuelSecretStore(),
      cardLearningStore: ratings, profileStore: profiles, v4Profile: stageProfile(),
      anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE})));
    await tester.pumpAndSettle();
    final controller = (tester.state(find.byType(NetworkDuelScreen)) as dynamic).controller as NetworkGameController;
    final card = controller.hand.single;
    final key = CardRatingKey(profileId: 'alice', cardId: card.id, variantId: card.variant.id,
      role: ProfilePreferenceRole.parse(card.nativeDirection.name));
    final before = card.personalValue;
    final network = jsonEncode(backend.state('alice').toJson());
    await tester.tap(find.byKey(const Key('open-private-profile-settings'))); await tester.pumpAndSettle();
    await tester.tap(find.text('Profil privé')); await tester.pumpAndSettle();
    final row = find.byKey(ValueKey('personalization-proposal-${key.storageKey}'));
    await tester.ensureVisible(row); await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: row, matching: find.text('Accepter'))); await tester.pumpAndSettle();
    expect((await ratings.load('alice')).referenceEstimate(key), 5.5);
    expect(controller.hand.single.personalValue, before);
    expect(jsonEncode(backend.state('alice').toJson()), network);
    expect(find.byKey(ValueKey('personalization-proposal-${key.storageKey}')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  V4Profile consentProfile(String id, {ProfilePreferenceRole? excluded,
    String? stage, bool preference = false}) {
    final base = stageProfile();
    final values = Map<String, ProfilePreference>.of(base.preferences);
    if (preference && excluded != null) {
      final key = ProfilePreferenceKey(tagId: 'degradant', role: excluded);
      values[key.storageKey] = ProfilePreference(profileId: id, key: key,
        pa: null, excluded: true, source: ProfilePreferenceSource.manualCustomized);
    }
    return V4Profile(sex: ProfileSex.HOMME, profileId: id, preferences: values, stageVetoes: [
      if (stage != null) StageVeto(conceptId: '056', actionId: stage,
        role: excluded ?? ProfilePreferenceRole.general),
    ]);
  }
  Future<(_Backend, _ConsentBackend, NetworkGameController, NetworkGameController,
      MemoryNetworkDuelSecretStore)> jointPair({V4Profile? initialA,
        V4Profile? initialB, bool fullCatalog = false}) async {
    final backend = _Backend()..v4UnlockedSpice = 4;
    final consent = _ConsentBackend();
    final store = MemoryNetworkDuelSecretStore();
    NetworkGameController player(String id, V4Profile profile) => NetworkGameController(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
      session: session, playerId: id, repository: _ConsentRepository(backend, id, consent),
      privateStore: id == 'bob' ? store : MemoryNetworkDuelSecretStore(),
      learningStore: MemoryNetworkProfileLearningStore(), v4Profile: profile,
      initialClothingCounts: fullCatalog ? const {'alice': 6, 'bob': 6} : const {},
      catalog: fullCatalog ? catalog : _catalogWithCards(catalog, {'card.v4.056'}));
    final a = player('alice', initialA ?? consentProfile('alice'));
    final b = player('bob', initialB ?? consentProfile('bob'));
    addTearDown(() async { a.dispose(); b.dispose(); await consent.close(); });
    await a.start();
    expect(a.hand, isEmpty, reason: 'Missing partner consent must fail closed');
    await b.start();
    await a.synchronizeConsent();
    expect(a.errorMessage, isNull);
    expect(b.errorMessage, isNull);
    return (backend, consent, a, b, store);
  }
  V4Profile completeConsentProfile(String id) {
    final questionnaire = ProfileQuestionnaire.decode(
      File('assets/catalog/source/profile_questions.v1.fr.json').readAsStringSync());
    return const InitialQuestionnaireEngine().initialize(sex: ProfileSex.HOMME, profileId: id,
      questionnaire: questionnaire, responses: {
        for (final question in questionnaire.questions)
          for (final axis in question.axes)
            '${question.stableId}|${axis.axisId}': InitialQuestionResponse.like,
      });
  }
  for (final owner in PlayerAnatomy.values) {
    for (final partner in PlayerAnatomy.values) {
      test('anatomy pipeline draw, direction, inversion, Recovery and reconnect $owner/$partner', () async {
        final backend = _Backend()..v4UnlockedSpice = 4;
        final store = MemoryNetworkDuelSecretStore();
        final anatomy = {'alice': owner, 'bob': partner};
        final data = _catalogWithCards(catalog, {'card.v4.022', 'card.v4.027', 'card.v4.055', 'card.v4.065'});
        NetworkGameController create(V4Profile profile) => NetworkGameController(
          session: session, playerId: 'alice', repository: backend.repository('alice'),
          privateStore: store, learningStore: MemoryNetworkProfileLearningStore(),
          catalog: data, v4Profile: profile, anatomies: anatomy);
        final profile = completeConsentProfile('alice').copyWith(
          sex: owner == PlayerAnatomy.PENIS ? ProfileSex.HOMME : ProfileSex.FEMME);
        final c = create(profile);
        await c.start();
        expect(c.errorMessage, isNull);
        for (final id in ['022', '027']) {
          expect(c.choicesFor(id).isNotEmpty, owner == PlayerAnatomy.VULVE || partner == PlayerAnatomy.VULVE);
          expect(c.recoveryChoicesFor(id).isNotEmpty, owner == PlayerAnatomy.VULVE || partner == PlayerAnatomy.VULVE);
        }
        expect(c.choicesFor('055').isNotEmpty, owner == PlayerAnatomy.PENIS);
        expect(c.choicesFor('065'), isNotEmpty);
        for (final card in [...c.hand, ...c.recoveryCards]) {
          expect(c.anatomyAllowed(card.id, card.variant.id, card.nativeDirection.name), isTrue);
          expect(c.stageExcluded(card.id, card.variant.id, card.nativeDirection.name), isFalse);
          final inverse = card.nativeDirection == CardOccurrenceDirection.FAIRE ? 'RECEVOIR' : 'FAIRE';
          expect(card.oppositePersonalValue != null, c.anatomyAllowed(card.id, card.variant.id, inverse));
        }
        final signature = c.hand.map((card) => '${card.id}/${card.variant.id}/${card.nativeDirection.name}').toList();
        await c.applyStageVetoProfile(profile.copyWith(sex: profile.sex == ProfileSex.HOMME ? ProfileSex.FEMME : ProfileSex.HOMME));
        expect(c.anatomies['alice'], owner);
        expect(c.hand.map((card) => '${card.id}/${card.variant.id}/${card.nativeDirection.name}').toList(), signature);
        c.dispose();
        final resumed = create(profile.copyWith(sex: ProfileSex.FEMME));
        addTearDown(resumed.dispose);
        await resumed.start();
        expect(resumed.errorMessage, isNull);
        expect(resumed.anatomies['alice'], owner);
        expect(resumed.hand.map((card) => '${card.id}/${card.variant.id}/${card.nativeDirection.name}').toList(), signature);
        anatomy['alice'] = owner == PlayerAnatomy.PENIS ? PlayerAnatomy.VULVE : PlayerAnatomy.PENIS;
        expect(resumed.anatomies['alice'], owner, reason: 'caller map cannot mutate session snapshot');
      });
    }
  }
  test('anatomy rejects historical new compromise Corruption Recovery proposals without deleting history', () async {
    final backend = _Backend()..v4UnlockedSpice = 4;
    final store = MemoryNetworkDuelSecretStore();
    final saved = privateGameFixture(roundNumber: 1, activeChili: 4, cards: [
      CardRuntimeState(cardId: '022', variantId: '022.stage.1', occurrenceId: 'historic',
        zone: CardZone.DISCARD, nativeDirection: CardOccurrenceDirection.FAIRE),
    ]);
    await store.saveGame(sessionId: session.id, playerId: 'alice', state: saved);
    final original = saved.conceptCheckpoint!.usagesByIntent.values.single.toJson();
    final c = NetworkGameController(session: session, playerId: 'alice',
      repository: backend.repository('alice'), privateStore: store,
      learningStore: MemoryNetworkProfileLearningStore(), catalog: catalog,
      v4Profile: completeConsentProfile('alice'),
      anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.PENIS});
    addTearDown(c.dispose);
    await c.start();
    expect(c.errorMessage, isNull);
    expect(c.auctionCards.where((card) => card.id == '022'), isEmpty);
    expect(c.corruptionCards.where((card) => card.id == '022'), isEmpty);
    expect(c.recoveryCards.where((card) => card.id == '022'), isEmpty);
    expect(c.usageCheckpoint.usagesByIntent.values.single.toJson(), original);
    expect((await store.loadGame(sessionId: session.id, playerId: 'alice'))!.publicDiscards, isNotEmpty);
  });

  test('anatomy manual zone choices respect the held native direction', () async {
    final backend = _Backend()..v4UnlockedSpice = 4;
    final c = NetworkGameController(session: session, playerId: 'alice',
      repository: backend.repository('alice'), privateStore: MemoryNetworkDuelSecretStore(),
      learningStore: MemoryNetworkProfileLearningStore(),
      catalog: _catalogWithCards(catalog, {'card.v4.002', 'card.v4.004', 'card.v4.005'}),
      v4Profile: completeConsentProfile('alice'),
      anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE});
    addTearDown(c.dispose);
    await c.start();
    expect(c.errorMessage, isNull);
    expect(c.hand, isNotEmpty);
    for (final card in c.hand) {
      for (final option in c.choicesFor(card.id)) {
        expect(c.anatomyAllowed(card.id, option.choice.actionId, card.nativeDirection.name), isTrue);
      }
      final impossibleZone = card.nativeDirection == CardOccurrenceDirection.FAIRE ? 'penis' : 'vulva';
      expect(c.choicesFor(card.id).where((o) => o.choice.zoneId == impossibleZone), isEmpty);
    }
  });

  String occurrenceSignature(NetworkDuelCard card) =>
      '${card.id}/${card.variant.id}/${card.nativeDirection.name}';
  Future<(_ConsentBackend, NetworkGameController, NetworkGameController,
      MemoryV4ProfileStore)> rolePair(String concept, String action,
      CardOccurrenceDirection aDirection, CardOccurrenceDirection bDirection,
      {bool handScreen = false}) async {
    final backend = _Backend()..v4UnlockedSpice = 4;
    final consent = _ConsentBackend();
    final profiles = MemoryV4ProfileStore();
    Future<NetworkGameController> player(String id, CardOccurrenceDirection direction) async {
      final profile = completeConsentProfile(id);
      await profiles.save(profile);
      final store = MemoryNetworkDuelSecretStore();
      await store.saveGame(sessionId: session.id, playerId: id,
        state: NetworkPrivateGameState(roundNumber: 1,
          cards: [CardRuntimeState(cardId: concept, variantId: action,
            zone: CardZone.HAND, nativeDirection: direction)],
          displayedHandActions: {concept: action},
          conceptCheckpoint: ConceptUsageCheckpoint.startCycle(sessionId: session.id,
            ownerPlayerId: id, cycle: 1, catalog: catalog.concepts!, initialClothing: 5)));
      return NetworkGameController(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE}, session: session, playerId: id,
        repository: _ConsentRepository(backend, id, consent), privateStore: store,
        learningStore: MemoryNetworkProfileLearningStore(), v4Profile: profile,
        catalog: catalog);
    }
    final a = await player('alice', aDirection);
    final b = await player('bob', bDirection);
    addTearDown(() async {
      if (!handScreen) a.dispose();
      b.dispose();
      await consent.close();
    });
    await a.start();
    await b.start();
    await a.synchronizeConsent();
    expect(a.hand.singleWhere((c) => c.id == concept).nativeDirection, aDirection);
    expect(b.hand.singleWhere((c) => c.id == concept).nativeDirection, bDirection);
    return (consent, a, b, profiles);
  }
  for (final example in [('004', '004.zone.free'), ('012', '012.action')]) {
    for (final scenario in [
      ('A', CardOccurrenceDirection.FAIRE, CardOccurrenceDirection.FAIRE, ProfilePreferenceRole.faire, true),
      ('B', CardOccurrenceDirection.RECEVOIR, CardOccurrenceDirection.FAIRE, ProfilePreferenceRole.recevoir, false),
      ('C', CardOccurrenceDirection.FAIRE, CardOccurrenceDirection.RECEVOIR, ProfilePreferenceRole.faire, false),
      ('D', CardOccurrenceDirection.FAIRE, CardOccurrenceDirection.FAIRE, ProfilePreferenceRole.faire, true),
      ('E', CardOccurrenceDirection.RECEVOIR, CardOccurrenceDirection.RECEVOIR, ProfilePreferenceRole.recevoir, true),
    ]) {
      test('role-scoped consent ${example.$1} case ${scenario.$1} keeps participant roles independent', () async {
        final pair = await rolePair(example.$1, example.$2, scenario.$2, scenario.$3);
        final originalB = occurrenceSignature(pair.$3.hand.singleWhere((c) => c.id == example.$1));
        final editor = CatalogProfileController(catalog: catalog, playerId: 'alice',
          profileStore: pair.$4, ratingStore: MemoryV4CardLearningStore(),
          learningStore: MemoryNetworkProfileLearningStore());
        addTearDown(editor.dispose);
        await editor.load();
        await editor.excludeCard(example.$1, role: scenario.$4);
        expect(editor.profile.stageVetoes.single.role, scenario.$4);
        await pair.$2.applyStageVetoProfile(editor.profile);
        await pair.$3.synchronizeConsent();
        final faire = sessionConsentKey('alice', example.$1, example.$2, 'FAIRE');
        final recevoir = sessionConsentKey('alice', example.$1, example.$2, 'RECEVOIR');
        final partnerFaire = sessionConsentKey('bob', example.$1, example.$2, 'FAIRE');
        final partnerRecevoir = sessionConsentKey('bob', example.$1, example.$2, 'RECEVOIR');
        final excludesFaire = scenario.$4 == ProfilePreferenceRole.faire;
        // Inspect the exact publication AND the server-shaped intersection.
        final contribution = pair.$1.contributions['alice']!;
        expect(contribution.contains(faire), !excludesFaire);
        expect(contribution.contains(recevoir), excludesFaire);
        expect(contribution.contains(partnerFaire), excludesFaire);
        expect(contribution.contains(partnerRecevoir), !excludesFaire);
        expect(pair.$1.read('alice').allowed.contains(faire), !excludesFaire);
        expect(pair.$1.read('bob').allowed.contains(partnerFaire), excludesFaire);
        expect(pair.$3.occurrenceConsentAllowed(example.$1, example.$2, 'FAIRE'), excludesFaire);
        expect(pair.$3.occurrenceConsentAllowed(example.$1, example.$2, 'RECEVOIR'), !excludesFaire);
        expect(pair.$2.cardExcluded(example.$1, direction: scenario.$2.name), isTrue);
        expect(pair.$2.heldConcepts.any((c) => c.id == example.$1), isTrue);
        if (scenario.$5) {
          expect(pair.$3.hand.map(occurrenceSignature), contains(originalB));
        } else {
          expect(pair.$3.hand.map(occurrenceSignature), isNot(contains(originalB)));
          expect(pair.$3.hand.every(pair.$3.isCardPlayable), isTrue);
          expect(pair.$3.hand.every((c) => !pair.$3.canReplaceForConsent(c.id)), isTrue);
        }
        expect(pair.$2.actionPoints['alice'], 100);
        expect(pair.$3.actionPoints['bob'], 100);
        await editor.excludeCard(example.$1, role: scenario.$4, excluded: false);
        await pair.$2.applyStageVetoProfile(editor.profile);
        final after = pair.$3.hand.map(occurrenceSignature).toList();
        await pair.$3.synchronizeConsent();
        expect(pair.$3.hand.map(occurrenceSignature), after);
        // Freeze a real committed action after undo, not just a permission key.
        pair.$2.selectCard(example.$1);
        await pair.$2.confirmSelection();
        expect(pair.$2.errorMessage, isNull);
        final resolved = pair.$2.usageCheckpoint.usagesByIntent.values.single.action;
        final receiving = scenario.$2 == CardOccurrenceDirection.RECEVOIR;
        expect(resolved.actorPlayerIds, [receiving ? 'bob' : 'alice']);
        expect(resolved.targetPlayerIds, [receiving ? 'alice' : 'bob']);
      });
    }
  }
  for (final example in [('004', '004.zone.free'), ('012', '012.action')]) {
    testWidgets('role-scoped consent hand menu ${example.$1} excludes FAIRE only with both players holding FAIRE', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final pair = await tester.runAsync(() => rolePair(example.$1, example.$2,
        CardOccurrenceDirection.FAIRE, CardOccurrenceDirection.FAIRE, handScreen: true));
      final a = pair!.$2;
      final b = pair.$3;
      final original = occurrenceSignature(b.hand.singleWhere((c) => c.id == example.$1));
      a.dispose();
      await tester.pumpWidget(MaterialApp(home: NetworkDuelScreen(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
        session: session, playerId: 'alice', repository: a.repository,
        catalog: catalog, v4Profile: completeConsentProfile('alice'),
        profileStore: pair.$4, secretStore: a.privateStore,
        cardLearningStore: MemoryV4CardLearningStore())));
      await tester.pumpAndSettle();
      CardHandSurface surface() => tester.widget<CardHandSurface>(find.byType(CardHandSurface));
      final card = surface().cards.singleWhere((c) => c.definition.cardId == example.$1);
      expect(card.definition.direction, 'FAIRE');
      surface().onLongPressCard!(card);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Exclure la carte'));
      await tester.pumpAndSettle();
      await tester.runAsync(b.synchronizeConsent);
      final saved = await tester.runAsync(() => pair.$4.load('alice'));
      expect(saved!.stageVetoes.single.role, ProfilePreferenceRole.faire);
      expect(saved.excludesStage(example.$1, example.$2, 'RECEVOIR'), isFalse);
      expect(surface().cards.singleWhere((c) => c.definition.cardId == example.$1).excluded, isTrue);
      expect(b.hand.map(occurrenceSignature), contains(original));
      expect(b.occurrenceConsentAllowed(example.$1, example.$2, 'FAIRE'), isTrue);
      surface().onLongPressCard!(surface().cards.singleWhere((c) => c.definition.cardId == example.$1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annuler l’exclusion de la carte'));
      await tester.pumpAndSettle();
      expect(surface().cards.singleWhere((c) => c.definition.cardId == example.$1).excluded, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  test('private hand remote veto refills four cards atomically without PA stock usage or round changes', () async {
    final own = completeConsentProfile('alice');
    final pair = await jointPair(initialA: own,
      initialB: completeConsentProfile('bob'), fullCatalog: true);
    final bob = pair.$4;
    expect(bob.hand, hasLength(4));
    final original = bob.hand.firstWhere((c) => c.nativeDirection != CardOccurrenceDirection.SOLO);
    final signature = occurrenceSignature(original);
    final points = Map<String, int>.of(bob.actionPoints);
    final stock = bob.usageCheckpoint.stock.toJson();
    final roundId = bob.round!.roundId;
    bob.selectCard(original.id);
    await bob.reserveSelection();
    final observed = <bool>[];
    bob.addListener(() => observed.add(bob.hand.length == 4 && bob.hand.every((c) =>
      bob.occurrenceConsentAllowed(c.id, c.variant.id, c.nativeDirection.name))));
    await pair.$3.applyStageVetoProfile(own.copyWith(stageVetoes: [
      StageVeto(conceptId: original.id, actionId: '*', role: ProfilePreferenceRole.general),
    ]));
    await bob.synchronizeConsent();
    expect(bob.hand, hasLength(4));
    expect(bob.hand.map(occurrenceSignature), isNot(contains(signature)));
    expect(bob.hand.every(bob.isCardPlayable), isTrue);
    expect(observed, isNotEmpty);
    expect(observed.every((valid) => valid), isTrue,
      reason: 'No notification may expose an incompatible intermediate hand');
    expect(bob.actionPoints, points);
    expect(bob.usageCheckpoint.stock.toJson(), stock);
    expect(bob.usageCheckpoint.usagesByIntent, isEmpty);
    expect(bob.usageCheckpoint.reservationsByIntent, isEmpty);
    expect(bob.selectedCard, isNull);
    expect(bob.round!.roundId, roundId);
    expect(bob.roundNumber, 1);
    expect(pair.$1.round.commits, isEmpty);
    expect(bob.viewState, NetworkGameViewState.choosing);
    expect(bob.hand.every((c) => !bob.canReplaceForConsent(c.id)), isTrue);
  });
  test('private hand batches simultaneous remote exclusions, keeps an unrelated draft and does not churn on polling or undo', () async {
    final own = completeConsentProfile('alice');
    final pair = await jointPair(initialA: own,
      initialB: completeConsentProfile('bob'), fullCatalog: true);
    final bob = pair.$4;
    final affected = bob.hand.where((c) => c.nativeDirection != CardOccurrenceDirection.SOLO).take(2).toList();
    expect(affected, hasLength(2));
    final signatures = affected.map(occurrenceSignature).toSet();
    final unaffected = bob.hand.firstWhere((c) => !affected.any((a) => a.id == c.id));
    bob.selectCard(unaffected.id);
    await bob.reserveSelection();
    final quota = bob.usageCheckpoint.toJson();
    await pair.$3.applyStageVetoProfile(own.copyWith(stageVetoes: [
      for (final card in affected)
        StageVeto(conceptId: card.id, actionId: '*', role: ProfilePreferenceRole.general),
    ]));
    await bob.synchronizeConsent();
    expect(bob.hand, hasLength(4));
    expect(bob.hand.map(occurrenceSignature).toSet().intersection(signatures), isEmpty);
    expect(bob.selectedCard?.id, unaffected.id);
    expect(bob.usageCheckpoint.toJson(), quota);
    final after = bob.hand.map(occurrenceSignature).toList();
    await bob.synchronizeConsent();
    await bob.synchronizeConsent();
    expect(bob.hand.map(occurrenceSignature), after);
    await pair.$3.applyStageVetoProfile(own);
    await bob.synchronizeConsent();
    expect(bob.hand.map(occurrenceSignature), after);
  });
  test('private hand periodic catch-up replaces remote-incompatible cards with no Realtime event', () async {
    final own = completeConsentProfile('alice');
    final pair = await jointPair(initialA: own,
      initialB: completeConsentProfile('bob'), fullCatalog: true);
    final original = pair.$4.hand.firstWhere((c) => c.nativeDirection != CardOccurrenceDirection.SOLO);
    final signature = occurrenceSignature(original);
    pair.$2.emitEvents = false;
    await pair.$3.applyStageVetoProfile(own.copyWith(stageVetoes: [
      StageVeto(conceptId: original.id, actionId: '*', role: ProfilePreferenceRole.general),
    ]));
    for (var i = 0; i < 160 && pair.$4.hand.map(occurrenceSignature).contains(signature); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    expect(pair.$4.hand, hasLength(4));
    expect(pair.$4.hand.map(occurrenceSignature), isNot(contains(signature)));
    expect(pair.$4.hand.every(pair.$4.isCardPlayable), isTrue);
    expect(pair.$1.points['bob'], 100);
  });
  test('private hand reconstruction replaces stale saved occurrences before display and persists the replacement', () async {
    final own = completeConsentProfile('alice');
    final profileB = completeConsentProfile('bob');
    final pair = await jointPair(initialA: own, initialB: profileB, fullCatalog: true);
    final original = pair.$4.hand.firstWhere((c) => c.nativeDirection != CardOccurrenceDirection.SOLO);
    final signature = occurrenceSignature(original);
    final before = await pair.$5.loadGame(sessionId: session.id, playerId: 'bob');
    final copy = NetworkPrivateGameState.fromJson(jsonDecode(jsonEncode(before!.toJson())) as Map<String, Object?>);
    final store = MemoryNetworkDuelSecretStore();
    await store.saveGame(sessionId: session.id, playerId: 'bob', state: copy);
    await pair.$3.applyStageVetoProfile(own.copyWith(stageVetoes: [
      StageVeto(conceptId: original.id, actionId: '*', role: ProfilePreferenceRole.general),
    ]));
    NetworkGameController restored() => NetworkGameController(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE}, session: session,
      playerId: 'bob', repository: _ConsentRepository(pair.$1, 'bob', pair.$2),
      privateStore: store, learningStore: MemoryNetworkProfileLearningStore(),
      v4Profile: profileB, catalog: catalog);
    final first = restored();
    addTearDown(first.dispose);
    await first.start();
    expect(first.errorMessage, isNull);
    expect(first.hand, hasLength(4));
    expect(first.hand.map(occurrenceSignature), isNot(contains(signature)));
    expect(first.hand.every(first.isCardPlayable), isTrue);
    final after = first.hand.map(occurrenceSignature).toList();
    final second = restored();
    addTearDown(second.dispose);
    await second.start();
    expect(second.hand.map(occurrenceSignature), after);
    expect(second.usageCheckpoint.toJson(), copy.conceptCheckpoint!.toJson());
  });
  test('private hand own exclusion stays visible even if the partner also disallows it', () async {
    final pair = await jointPair();
    final original = pair.$4.hand.single;
    await pair.$4.applyStageVetoProfile(consentProfile('bob', stage: '*'));
    await pair.$3.applyStageVetoProfile(consentProfile('alice', stage: '*'));
    await pair.$4.synchronizeConsent();
    expect(pair.$4.heldConcepts.map((c) => c.id), ['056']);
    expect(pair.$4.runtime.single.nativeDirection, original.nativeDirection);
    expect(pair.$4.canReplaceForConsent('056'), isTrue);
    expect(pair.$4.cardExcluded('056'), isTrue);
    await pair.$4.replaceExcludedCard('056');
    expect(pair.$4.heldConcepts, isEmpty);
    expect(pair.$1.points['bob'], 100);
  });
  test('private hand replacement stage survives persistence and undo does not restore the old stage', () async {
    final pair = await jointPair();
    await pair.$3.applyStageVetoProfile(consentProfile('alice', stage: '056.stage.3'));
    await pair.$4.synchronizeConsent();
    expect(pair.$4.hand.single.variant.id, '056.stage.2');
    final saved = await pair.$5.loadGame(sessionId: session.id, playerId: 'bob');
    final encoded = jsonDecode(jsonEncode(saved!.toJson())) as Map<String, Object?>;
    final roundTrip = NetworkPrivateGameState.fromJson(encoded);
    expect(roundTrip.displayedHandActions['056'], '056.stage.2');
    final store = MemoryNetworkDuelSecretStore();
    await store.saveGame(sessionId: session.id, playerId: 'bob', state: roundTrip);
    final restored = NetworkGameController(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE}, session: session, playerId: 'bob',
      repository: _ConsentRepository(pair.$1, 'bob', pair.$2), privateStore: store,
      learningStore: MemoryNetworkProfileLearningStore(), v4Profile: consentProfile('bob'),
      catalog: _catalogWithCards(catalog, {'card.v4.056'}));
    addTearDown(restored.dispose);
    await restored.start();
    expect(restored.hand.single.variant.id, '056.stage.2');
    await pair.$3.applyStageVetoProfile(consentProfile('alice'));
    await restored.synchronizeConsent();
    expect(restored.hand.single.variant.id, '056.stage.2');
    expect(restored.choicesFor('056').map((o) => o.choice.actionId), contains('056.stage.3'));
    encoded.remove('displayed_hand_actions');
    expect(NetworkPrivateGameState.fromJson(encoded).displayedHandActions, isEmpty);
  });
  test('joint consent initial partner profile veto preserves actual FAIRE only', () async {
    final pair = await jointPair(initialA: consentProfile('alice',
      excluded: ProfilePreferenceRole.recevoir, preference: true));
    final a = pair.$3;
    final b = pair.$4;
    expect(a.hand, isNotEmpty);
    expect(b.hand, isNotEmpty);
    expect(a.hand.every((c) => c.nativeDirection == CardOccurrenceDirection.FAIRE), isTrue);
    expect(b.hand.every((c) => c.nativeDirection == CardOccurrenceDirection.RECEVOIR), isTrue);
    expect(a.hand.single.oppositePersonalValue, isNull);
    expect(b.hand.single.oppositePersonalValue, isNull);
  });
  test('joint consent remote update silently replaces occurrence, clears draft and undo preserves new hand', () async {
    final pair = await jointPair();
    final a = pair.$3;
    final b = pair.$4;
    final original = b.hand.single;
    b.selectCard('056');
    await b.reserveSelection();
    final role = original.nativeDirection == CardOccurrenceDirection.FAIRE
      ? ProfilePreferenceRole.recevoir : ProfilePreferenceRole.faire;
    final stock = b.usageCheckpoint.stock.toJson();
    await a.applyStageVetoProfile(consentProfile('alice', excluded: role,
      stage: original.variant.id));
    await b.synchronizeConsent();
    expect(b.heldConcepts.map((c) => c.id), contains('056'));
    final replacement = b.hand.single;
    expect(replacement.variant.id != original.variant.id ||
      replacement.nativeDirection != original.nativeDirection, isTrue);
    expect(b.isCardPlayable(replacement), isTrue);
    expect(b.canReplaceForConsent('056'), isFalse);
    expect(b.selectedCard, isNull);
    expect(b.usageCheckpoint.usagesByIntent, isEmpty);
    expect(pair.$1.points['bob'], 100);
    expect(b.usageCheckpoint.stock.toJson(), stock);
    await a.applyStageVetoProfile(consentProfile('alice'));
    await b.synchronizeConsent();
    expect(b.choicesFor('056'), isNotEmpty);
    expect(b.hand.single.variant.id, replacement.variant.id);
    expect(b.hand.single.nativeDirection, replacement.nativeDirection,
      reason: 'Undo does not restore the previous occurrence');
  });
  test('joint consent whole-card veto filters replacement and Recovery and survives reconstruction', () async {
    final pair = await jointPair();
    await pair.$3.applyStageVetoProfile(consentProfile('alice', stage: '*'));
    await pair.$4.synchronizeConsent();
    expect(pair.$4.choicesFor('056'), isEmpty);
    expect(pair.$4.recoveryCards, isEmpty);
    expect(pair.$4.hand, isEmpty);
    expect(pair.$3.heldConcepts.map((c) => c.id), contains('056'),
      reason: 'The owner keeps their own excluded card for manual replacement');
    expect(pair.$3.canReplaceForConsent('056'), isTrue);
    final restored = NetworkGameController(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE}, session: session, playerId: 'bob',
      repository: _ConsentRepository(pair.$1, 'bob', pair.$2), privateStore: pair.$5,
      learningStore: MemoryNetworkProfileLearningStore(), v4Profile: consentProfile('bob'),
      catalog: _catalogWithCards(catalog, {'card.v4.056'}));
    addTearDown(restored.dispose);
    await restored.start();
    expect(restored.errorMessage, isNull);
    expect(restored.choicesFor('056'), isEmpty);
    expect(restored.recoveryCards, isEmpty);
  });
  test('joint consent projection has no source, note, tag or partner-owned permissions', () async {
    final pair = await jointPair();
    final projection = pair.$2.read('alice');
    expect(projection.allowed.every((k) => k.startsWith('alice/')), isTrue);
    final wire = jsonEncode({'revision': projection.revision,
      'ready': projection.ready, 'allowed': projection.allowed.toList()});
    for (final private in ['degradant', 'preferences', 'stage_vetoes', 'pa', 'reason', 'source']) {
      expect(wire, isNot(contains(private)));
    }
  });
  test('joint consent idempotent publication and lost acknowledgement cannot resurrect an older veto state', () async {
    final backend = _Backend();
    final consent = _ConsentBackend();
    addTearDown(consent.close);
    final repo = _ConsentRepository(backend, 'alice', consent);
    const key = 'alice/056/056.stage.3/FAIRE';
    await repo.publishSessionConsent(sessionId: session.id, allowed: {key}, commandId: 'first');
    final revision = consent.revision;
    await repo.publishSessionConsent(sessionId: session.id, allowed: {key}, commandId: 'first');
    expect(consent.revision, revision);
    await repo.publishSessionConsent(sessionId: session.id, allowed: {}, commandId: 'veto');
    await repo.publishSessionConsent(sessionId: session.id, allowed: {key}, commandId: 'first');
    expect(consent.contributions['alice'], isEmpty);
    expect(consent.revision, revision + 1);
    await expectLater(repo.publishSessionConsent(sessionId: session.id,
      allowed: {}, commandId: 'first'), throwsStateError);
  });
  test('joint consent SQL isolates contributions and publishes revision-only invalidations', () {
    final sql = File('supabase/migrations/202610220001_session_occurrence_consent.sql').readAsStringSync();
    expect(sql, contains('alter table public.network_session_consent enable row level security'));
    expect(sql, contains('revoke all on public.network_session_consent, public.network_session_consent_revisions'));
    expect(sql, contains('grant select on public.network_session_consent_revisions to authenticated'));
    expect(sql, isNot(contains('grant select on public.network_session_consent to authenticated')));
    expect(sql, contains("split_part(key,'/',1)=auth.uid()::text"));
    expect(sql, contains('v_previous.allowed<>p_allowed'));
    expect(sql, contains('return public.get_session_consent(p_session_id)'));
    expect(sql, contains('alter publication supabase_realtime add table public.network_session_consent_revisions'));
  });
  test('joint consent MUTUEL evaluates both participants and keeps immutable action semantics', () async {
    final consent = _ConsentBackend();
    final setup = await _setupCorruption(session, catalog,
      firstLifeConcept: '003', consent: consent);
    addTearDown(setup.dispose);
    expect(setup.alice.occurrenceConsentAllowed('003', '003.stage.1', 'MUTUEL'), isTrue);
    await setup.bob.applyStageVetoProfile(V4Profile(sex: ProfileSex.HOMME, profileId: 'bob', preferences: {},
      stageVetoes: [StageVeto(conceptId: '003', actionId: '003.stage.1',
        role: ProfilePreferenceRole.recevoir)]));
    await setup.alice.synchronizeConsent();
    expect(setup.alice.occurrenceConsentAllowed('003', '003.stage.1', 'MUTUEL'), isFalse);
    expect(setup.bob.occurrenceConsentAllowed('003', '003.stage.1', 'MUTUEL'), isFalse);
    expect(setup.alice.occurrenceConsentAllowed('003', '003.stage.2', 'MUTUEL'), isTrue);
  });
  test('joint consent refresh fails visibly before engagement and recovers after connectivity returns', () async {
    final pair = await jointPair();
    pair.$4.selectCard('056');
    pair.$2.offline = true;
    await pair.$4.confirmSelection();
    expect(pair.$1.round.commits, isEmpty);
    expect(pair.$4.usageCheckpoint.usagesByIntent, isEmpty);
    pair.$2.offline = false;
    await pair.$4.synchronizeConsent();
    expect(pair.$2.read('bob').ready, isTrue);
  });
  test('joint consent catches up automatically after Realtime channel termination', () async {
    final pair = await jointPair();
    pair.$2.events.addError(StateError('simulated Realtime close 1006'));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await pair.$3.applyStageVetoProfile(consentProfile('alice', stage: '*'));
    for (var i = 0; i < 120 && pair.$4.choicesFor('056').isNotEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    expect(pair.$4.choicesFor('056'), isEmpty);
    expect(pair.$4.heldConcepts, isEmpty);
    expect(pair.$4.canReplaceForConsent('056'), isFalse);
    expect(pair.$2.watchCount, greaterThan(2));
  });
  testWidgets('joint consent UI silently replaces remote-blocked stage without an exclusion badge', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final backend = _Backend()..v4UnlockedSpice = 4;
    final consent = _ConsentBackend();
    final focused = _catalogWithCards(catalog, {'card.v4.056'});
    final profiles = MemoryV4ProfileStore();
    await profiles.save(consentProfile('bob'));
    final alice = NetworkGameController(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE}, session: session, playerId: 'alice',
      repository: _ConsentRepository(backend, 'alice', consent),
      privateStore: MemoryNetworkDuelSecretStore(),
      learningStore: MemoryNetworkProfileLearningStore(),
      v4Profile: consentProfile('alice'), catalog: focused);
    try {
    await alice.start();
    await tester.pumpWidget(MaterialApp(home: NetworkDuelScreen(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
      session: session, playerId: 'bob', repository: _ConsentRepository(backend, 'bob', consent),
      catalog: focused, v4Profile: consentProfile('bob'),
      profileStore: profiles,
      secretStore: MemoryNetworkDuelSecretStore(),
      cardLearningStore: MemoryV4CardLearningStore())));
    await tester.pumpAndSettle();
    final before = tester.widget<CardHandSurface>(find.byType(CardHandSurface)).cards.single;
    expect(before.definition.variantId, '056.stage.3');
    expect(before.available, isTrue);
    await alice.applyStageVetoProfile(consentProfile('alice', stage: '056.stage.3'));
    await tester.pumpAndSettle();
    final after = tester.widget<CardHandSurface>(find.byType(CardHandSurface)).cards.single;
    expect(after.definition.variantId, isNot(before.definition.variantId));
    expect(after.available, isTrue);
    expect(after.excluded, isFalse);
    expect(after.replaceable, isFalse);
    expect(after.tabs.singleWhere((t) => t.id == '056.stage.3').excluded, isFalse);
    expect(find.textContaining('EXCLUE'), findsNothing);
    expect(find.byKey(const Key('replace-excluded-056')), findsNothing);
    final surface = tester.widget<CardHandSurface>(find.byType(CardHandSurface));
    surface.onLongPressCard!(after);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Exclure ce stade'));
    await tester.pumpAndSettle();
    final local = tester.widget<CardHandSurface>(find.byType(CardHandSurface)).cards.single;
    expect(local.definition.variantId, after.definition.variantId);
    expect(local.available, isFalse);
    expect(local.excluded, isTrue);
    expect(local.replaceable, isTrue);
    expect(find.textContaining('EXCLUE'), findsWidgets);
    expect(tester.takeException(), isNull);
    } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    alice.dispose();
    await consent.close();
    }
  });
  for (final wholeCard in [false, true]) {
    test('joint consent veto before next proposal removes historical Corruption Recovery and compromise whole=$wholeCard', () async {
      final consent = _ConsentBackend();
      final setup = await _setupCorruption(session, catalog, consent: consent);
      addTearDown(setup.dispose);
      await _playUnequal(setup, forceAliceCard: '006', requireRepeatable: true);
      final source = setup.alice.usageCheckpoint.usagesByIntent.values.single;
      final firstBob = setup.bob.usageCheckpoint.usagesByIntent.values.single.conceptId;
      final loser = setup.alice.isInitialLoser ? setup.alice : setup.bob;
      await loser.skipCorruption();
      await _settle();
      await _completeResolvedAction(setup);
      await _cycleController(setup).completeAction();
      await _settle();
      expect(setup.alice.viewState, NetworkGameViewState.choosing);
      expect(setup.alice.corruptionCards.any((c) => c.identity == source.usageId), isTrue);
      final recipientRole = source.action.direction == CardOccurrenceDirection.FAIRE
        ? ProfilePreferenceRole.recevoir : ProfilePreferenceRole.faire;
      // This is an already-existing veto by the next proposal, not a new veto
      // during Corruption or an attempt to cancel the completed action.
      await setup.bob.applyStageVetoProfile(V4Profile(sex: ProfileSex.HOMME, profileId: 'bob', preferences: {},
        stageVetoes: [StageVeto(conceptId: '006',
          actionId: wholeCard ? '*' : source.action.stageId ?? source.action.variantId!,
          role: wholeCard ? ProfilePreferenceRole.general : recipientRole)]));
      await setup.alice.synchronizeConsent();
      expect(setup.alice.corruptionCards.any((c) => c.identity == source.usageId), isFalse);
      expect(setup.alice.recoveryCards.any((c) => c.identity == source.usageId), isFalse);
      expect(setup.alice.auctionCards.any((c) => c.identity == source.usageId), isFalse);
      expect(setup.alice.usageCheckpoint.usagesByIntent.values.single.toJson(), source.toJson());
      expect(firstBob, isNotEmpty);
    });
  }
  test('excluding selected stage prevents commit and consumption; undo restores it', () async {
    final backend = _Backend()..v4UnlockedSpice = 4;
    final c = NetworkGameController(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE}, session: session, playerId: 'alice',
      repository: backend.repository('alice'), privateStore: MemoryNetworkDuelSecretStore(),
      learningStore: MemoryNetworkProfileLearningStore(),
      catalog: _catalogWithCards(catalog, {'card.v4.056'}), v4Profile: stageProfile());
    addTearDown(c.dispose);
    await c.start();
    c.selectCard('056');
    c.chooseAction(c.choicesFor('056').singleWhere((o) => o.choice.actionId == '056.stage.2'));
    await c.reserveSelection();
    await c.applyStageVetoProfile(stageProfile(excluded: 2));
    await c.confirmSelection();
    expect(c.usageCheckpoint.stageConsumed('056', '056.stage.2'), isFalse);
    expect(c.usageCheckpoint.usagesByIntent, isEmpty);
    expect(backend.round.commits, isEmpty);
    await c.applyStageVetoProfile(stageProfile());
    c.selectCard('056');
    c.chooseAction(c.choicesFor('056').singleWhere((o) => o.choice.actionId == '056.stage.2'));
    await c.confirmSelection();
    expect(c.usageCheckpoint.stageConsumed('056', '056.stage.2'), isTrue);
  });

  test('whole-card veto keeps the held card until replacement and overrides locking', () async {
    final backend = _Backend()..v4UnlockedSpice = 4;
    final base = stageProfile();
    final c = NetworkGameController(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE}, session: session, playerId: 'alice',
      repository: backend.repository('alice'), privateStore: MemoryNetworkDuelSecretStore(),
      learningStore: MemoryNetworkProfileLearningStore(),
      catalog: _catalogWithCards(catalog, {'card.v4.056'}), v4Profile: base);
    addTearDown(c.dispose);
    await c.start();
    c.toggleLock('056');
    expect(c.lockedCardId, '056');
    final before = c.usageCheckpoint.stock.toJson();
    await c.applyStageVetoProfile(base.copyWith(stageVetoes: [
      StageVeto(conceptId: '056', actionId: '*', role: ProfilePreferenceRole.general),
    ]));
    expect(c.heldConcepts.map((c) => c.id), contains('056'));
    expect(c.lockedCardId, isNull);
    expect(c.decksEmpty, isTrue);
    await c.replaceExcludedCard('056');
    expect(c.heldConcepts, isEmpty);
    expect(c.usageCheckpoint.stock.toJson(), before);
    expect(backend.points['alice'], 100);
    expect(backend.round.commits, isEmpty);
  });

  for (final recorded in [false, true]) {
    test('offline retry recovers ${recorded ? 'recorded' : 'missing'} commit and rebuilds silent watch', () async {
      final backend = _Backend();
      final repo = _OfflineRepository(backend, 'bob');
      final bob = NetworkGameController(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE}, session: session, playerId: 'bob', repository: repo,
        privateStore: MemoryNetworkDuelSecretStore(), learningStore: MemoryNetworkProfileLearningStore(),
        catalog: catalog);
      final alice = _controller(backend, session, catalog, 'alice', MemoryNetworkDuelSecretStore());
      addTearDown(() { alice.dispose(); bob.dispose(); });
      await alice.start(); await bob.start();
      alice.selectCard(alice.hand.first.identity); await alice.confirmSelection();
      final aliceCommit = backend.round.commits['alice'];
      repo.offline = true; repo.recordBeforeFailure = recorded;
      bob.selectCard(bob.hand.first.identity); await bob.confirmSelection();
      expect(bob.viewState, NetworkGameViewState.error);
      final frozen = bob.usageCheckpoint.encode();
      final watches = repo.watchCount;
      repo.offline = false;
      await bob.retryCurrentAction(); await _settle();
      expect(repo.watchCount, greaterThan(watches));
      expect(repo.readCount, greaterThan(0));
      expect(bob.viewState, isNot(NetworkGameViewState.error));
      expect(bob.errorMessage, isNull);
      expect(backend.round.commits['alice'], aliceCommit);
      expect(repo.commitAttempts, recorded ? 1 : 2);
      expect(bob.usageCheckpoint.encode(), frozen);
      expect(backend.round.commits, hasLength(2));
      expect(backend.round.reveals, hasLength(2));
      expect(backend.round.initial, isNotNull);
      expect(backend.roundCreations, 1);
      final commands = Set<String>.of(backend.commands);
      await bob.retryCurrentAction(); await _settle();
      expect(backend.commands, commands);
      expect(repo.commitAttempts, recorded ? 1 : 2);
    });
  }

  test('retry waits for an in-flight canonical read and ignores repeated clicks', () async {
    final backend = _Backend();
    final repo = _OfflineRepository(backend, 'bob');
    final bob = NetworkGameController(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE}, session: session, playerId: 'bob', repository: repo,
      privateStore: MemoryNetworkDuelSecretStore(), learningStore: MemoryNetworkProfileLearningStore(),
      catalog: catalog, reconciliationInterval: const Duration(milliseconds: 20));
    addTearDown(bob.dispose);
    await bob.start();
    repo.offline = true;
    bob.selectCard(bob.hand.first.identity); await bob.confirmSelection();
    repo.readGate = Completer<void>();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(repo.readCount, 1);
    var finished = false;
    final retry = bob.retryCurrentAction().then((_) { finished = true; });
    await _settle();
    expect(finished, isFalse);
    await bob.retryCurrentAction();
    expect(repo.readCount, 1);
    repo.offline = false; repo.readGate!.complete();
    await retry; await _settle();
    expect(bob.viewState, NetworkGameViewState.waitingForPartner);
    expect(bob.errorMessage, isNull);
    expect(repo.commitAttempts, 2);
    expect(bob.usageCheckpoint.usagesByIntent, hasLength(1));
  });

  test('retry read failure remains recoverable on the next attempt', () async {
    final backend = _Backend();
    final repo = _OfflineRepository(backend, 'bob');
    final bob = NetworkGameController(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE}, session: session, playerId: 'bob', repository: repo,
      privateStore: MemoryNetworkDuelSecretStore(), learningStore: MemoryNetworkProfileLearningStore(), catalog: catalog);
    addTearDown(bob.dispose);
    await bob.start(); repo.offline = true;
    bob.selectCard(bob.hand.first.identity); await bob.confirmSelection();
    await bob.retryCurrentAction();
    expect(bob.viewState, NetworkGameViewState.error);
    expect(bob.retrying, isFalse);
    repo.offline = false;
    await bob.retryCurrentAction();
    expect(bob.viewState, NetworkGameViewState.waitingForPartner);
    expect(repo.commitAttempts, 2);
  });

  test('retry after a recorded REVEAL with lost response never resends it', () async {
    final backend = _Backend();
    final repo = _OfflineRepository(backend, 'bob')..loseRevealResponse = true;
    final bob = NetworkGameController(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE}, session: session, playerId: 'bob', repository: repo,
      privateStore: MemoryNetworkDuelSecretStore(), learningStore: MemoryNetworkProfileLearningStore(), catalog: catalog);
    final alice = _controller(backend, session, catalog, 'alice', MemoryNetworkDuelSecretStore());
    addTearDown(() { alice.dispose(); bob.dispose(); });
    await alice.start(); await bob.start();
    alice.selectCard(alice.hand.first.identity); await alice.confirmSelection();
    bob.selectCard(bob.hand.first.identity); await bob.confirmSelection(); await _settle();
    expect(bob.viewState, NetworkGameViewState.error);
    expect(backend.round.reveals, hasLength(2));
    final frozen = bob.usageCheckpoint.encode();
    await bob.retryCurrentAction(); await _settle();
    expect(bob.viewState, isNot(NetworkGameViewState.error));
    expect(repo.revealAttempts, 1);
    expect(bob.usageCheckpoint.encode(), frozen);
    expect(backend.roundCreations, 1);
  });

  test('periodic reconciliation recovers offline commit without a manual retry', () async {
    final backend = _Backend();
    final repo = _OfflineRepository(backend, 'bob');
    final bob = NetworkGameController(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE}, session: session, playerId: 'bob', repository: repo,
      privateStore: MemoryNetworkDuelSecretStore(), learningStore: MemoryNetworkProfileLearningStore(),
      catalog: catalog, reconciliationInterval: const Duration(milliseconds: 20));
    addTearDown(bob.dispose);
    await bob.start();
    repo.offline = true;
    bob.selectCard(bob.hand.first.identity); await bob.confirmSelection();
    expect(bob.viewState, NetworkGameViewState.error);
    repo.offline = false;
    for (var i = 0; i < 30 && bob.viewState == NetworkGameViewState.error; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(bob.viewState, NetworkGameViewState.waitingForPartner);
    expect(bob.usageCheckpoint.usagesByIntent, hasLength(1));
    expect(repo.commitAttempts, 2);
    expect(backend.roundCreations, 1);
  });

  testWidgets('offline retry button shows progress, disables duplicates and restores the round', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final backend = _Backend();
    final repo = _OfflineRepository(backend, 'bob');
    await tester.pumpWidget(MaterialApp(home: NetworkDuelScreen(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE}, session: session,
      playerId: 'bob', repository: repo, catalog: _catalogWithCards(catalog, {'card.v4.001'}),
      secretStore: MemoryNetworkDuelSecretStore())));
    await tester.pumpAndSettle();
    repo.offline = true;
    final surface = tester.widget<CardHandSurface>(find.byType(CardHandSurface));
    surface.onPlay!(surface.cards.single);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('network-game-error')), findsOneWidget);
    repo.readGate = Completer<void>();
    await tester.tap(find.text('Réessayer'));
    await tester.pump();
    final button = tester.widget<TextButton>(find.descendant(
      of: find.byKey(const Key('network-game-error')), matching: find.byType(TextButton)));
    expect(button.onPressed, isNull);
    expect(find.descendant(of: find.byKey(const Key('network-game-error')),
      matching: find.byType(CircularProgressIndicator)), findsOneWidget);
    repo.offline = false; repo.readGate!.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('network-game-error')), findsNothing);
    expect(repo.watchCount, 2);
    expect(repo.commitAttempts, 2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final interrupted in ['lost', 'error', 'done']) {
    test('canonical reconciliation recovers $interrupted REVEAL without double engagement', () async {
      final backend = _Backend();
      final repo = _InterruptedRepository(backend, 'alice');
      final alice = NetworkGameController(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE}, session: session, playerId: 'alice', repository: repo,
        privateStore: MemoryNetworkDuelSecretStore(), learningStore: MemoryNetworkProfileLearningStore(),
        catalog: catalog, reconciliationInterval: const Duration(milliseconds: 100),
        watchRetryDelay: const Duration(milliseconds: 20));
      final bob = _controller(backend, session, catalog, 'bob', MemoryNetworkDuelSecretStore());
      addTearDown(() async { alice.dispose(); bob.dispose(); await repo.close(); });
      await alice.start(); await bob.start();
      alice.selectCard(alice.hand.first.identity); await alice.confirmSelection();
      final usage = alice.usageCheckpoint.usagesByIntent.values.single;
      if (interrupted == 'error') repo.updates.addError(StateError('simulated connection loss'));
      if (interrupted != 'lost') await repo.updates.close();
      bob.selectCard(bob.hand.first.identity); await bob.confirmSelection();
      for (var i = 0; i < 60 && backend.round.initial == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(backend.round.reveals, hasLength(2));
      expect(backend.round.initial, isNotNull);
      expect(alice.usageCheckpoint.usagesByIntent, hasLength(1));
      expect(alice.usageCheckpoint.usagesByIntent.values.single.usageId, usage.usageId);
      expect(repo.watchCount, interrupted == 'lost' ? 1 : greaterThan(1));
    });
  }
  for (final excluded in [1,2,3]) {
    test('V1 veto stage $excluded leaves other stages consumable and survives profile reload', () async {
      final backend = _Backend()..v4UnlockedSpice = 4;
      final profile = V4Profile.fromJson(jsonDecode(jsonEncode(stageProfile(excluded: excluded).toJson())) as Map<String,Object?>);
      final c = NetworkGameController(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE}, session: session, playerId: 'alice', repository: backend.repository('alice'),
        privateStore: MemoryNetworkDuelSecretStore(), learningStore: MemoryNetworkProfileLearningStore(),
        catalog: _catalogWithCards(catalog, {'card.v4.056'}), v4Profile: profile);
      addTearDown(c.dispose);
      await c.start();
      expect(c.choicesFor('056').map((o) => o.choice.actionId).toSet(),
        {for (final n in [1,2,3]) if(n!=excluded) '056.stage.$n'});
      expect(c.usageCheckpoint.usagesByIntent, isEmpty);
      final allowed = [1,2,3].firstWhere((n) => n != excluded);
      c.selectCard('056');
      c.chooseAction(c.choicesFor('056').singleWhere((o) => o.choice.actionId == '056.stage.$allowed'));
      await c.confirmSelection();
      expect(c.usageCheckpoint.stageConsumed('056', '056.stage.$allowed'), isTrue);
      expect(c.usageCheckpoint.stageConsumed('056', '056.stage.$excluded'), isFalse);
      expect(c.errorMessage, isNull);
    });
  }
  test('V1 stage veto removes only the excluded direction and inverse', () async {
    final backend = _Backend()..v4UnlockedSpice = 4;
    final c = NetworkGameController(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE}, session: session, playerId: 'alice', repository: backend.repository('alice'),
      privateStore: MemoryNetworkDuelSecretStore(), learningStore: MemoryNetworkProfileLearningStore(),
      catalog: _catalogWithCards(catalog, {'card.v4.056'}),
      v4Profile: stageProfile(excluded: 3, role: ProfilePreferenceRole.faire));
    addTearDown(c.dispose); await c.start(); c.selectCard('056');
    c.chooseAction(c.choicesFor('056').singleWhere((o) => o.choice.actionId == '056.stage.3'));
    expect(c.selectedCard!.nativeDirection, CardOccurrenceDirection.RECEVOIR);
    expect(c.selectedCard!.oppositePersonalValue, isNull);
    await c.confirmSelection();
    expect(c.usageCheckpoint.usagesByIntent.values.single.invertedAction, isNull);
  });


  for (final id in ['033','061','034','062','063']) {
    for (final direction in [CardOccurrenceDirection.FAIRE, CardOccurrenceDirection.RECEVOIR]) {
      test('V1 frozen $id $direction records correct effect bearer and context', () async {
        final backend = _Backend()..v4UnlockedSpice = 4;
        final binding = (catalog.conceptRules!['bindings'] as List).cast<Map<String,Object?>>().singleWhere((b) => b['concept_id'] == id);
        final ratings = (binding['actions'] as List).cast<Map<String,Object?>>().map((a) => a['rating'] as Map<String,Object?>);
        final tags = <String>{for (final r in ratings) ...(r['primary_preference_tags'] as List).cast<String>(),
          for (final r in ratings) ...(r['secondary_preference_tags'] as List).cast<String>()};
        final preferences = <String,ProfilePreference>{};
        for(final tag in tags) {
          final key = ProfilePreferenceKey(tagId: tag, role: ProfilePreferenceRole.parse(direction.name));
          preferences[key.storageKey] = ProfilePreference(profileId:'alice', key:key, pa:10, excluded:false,
            source:ProfilePreferenceSource.initialQuestionnaire);
        }
        final c = NetworkGameController(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE}, session:session, playerId:'alice', repository:backend.repository('alice'),
          privateStore:MemoryNetworkDuelSecretStore(), learningStore:MemoryNetworkProfileLearningStore(),
          catalog:_catalogWithCards(catalog, {'card.v4.$id'}),
          v4Profile:V4Profile(sex: ProfileSex.HOMME, profileId:'alice',preferences:preferences),
          initialContext:EngineSessionContext(mode:SessionMode.face_to_face, proximity:ProximityState.TOGETHER,
            chiliActive:4,chiliUnlocked:4,clothesByPlayer:{'alice':6,'bob':6},flags:{'hasConstraintAccessory':true}));
        addTearDown(c.dispose);await c.start();
        expect(c.hand, isNotEmpty);c.selectCard(id);await c.confirmSelection();
        final usage = c.usageCheckpoint.usagesByIntent.values.single;
        final action = usage.action;
        final effect = V4PersistentEffect.fromJson(action.effects.first.parameters);
        final actor = direction==CardOccurrenceDirection.FAIRE ? 'alice':'bob';
        expect(action.actorPlayerIds,[actor]);
        expect(effect.targetPlayerId, {'033','061'}.contains(id) ? actor : (actor=='alice'?'bob':'alice'));
        expect(effect.actorPlayerIds,[actor]);expect(effect.remainingActions,3);
        expect(effect.stageId, action.stageId);
        final restored = ConceptUsageCheckpoint.fromJson(jsonDecode(jsonEncode(c.usageCheckpoint.toJson())) as Map<String,Object?>);
        expect(restored.usagesByIntent.values.single.toJson(),usage.toJson());
      });
    }
  }
  test('V1 Sexting completion is canonical across retry and empty cache reconnect', () async {
    final backend = _Backend();
    _setProjectedAction(backend,cards:[
      resolvedActionFixture(usageId:'sexting',conceptId:'042',actionId:'042.action',effectiveSpice:2,direction:NetworkCardDirection.MUTUEL,targetPlayerIds:['alice','bob']),
      _projectedCard(occurrenceId:'parallel',cardId:'001',variantId:'001.stage.1'),
    ]);
    final alice = _controller(backend,session,catalog,'alice',MemoryNetworkDuelSecretStore());
    final bob = _controller(backend,session,catalog,'bob',MemoryNetworkDuelSecretStore());
    addTearDown(alice.dispose);addTearDown(bob.dispose);
    await Future.wait([alice.start(),bob.start()]);await alice.completeAction();await bob.completeAction();await _settle();
    expect(backend.persistentEffects.map((e)=>e.remainingActions),[3,3]);
    expect(backend.persistentEffects.every((e)=>e.unit=='turns'),isTrue);
    backend.notifyTwice();await _settle();
    final reconnect = _controller(backend,session,catalog,'alice',MemoryNetworkDuelSecretStore());
    addTearDown(reconnect.dispose);await reconnect.start();await reconnect.retryCurrentAction();
    expect(reconnect.persistentEffects.map((e)=>e.remainingActions),[3,3]);
    expect(backend.persistentEffectTransitions,1);
  });


  for (final sex in ProfileSex.values) {
  testWidgets('in-game sex $sex is visible locked while private profile and accessories remain editable', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = MemoryV4ProfileStore();
    final profile = stageProfile().copyWith(sex: sex);
    await store.save(profile);
    final backend = _Backend()..v4UnlockedSpice = 4;
    await tester.pumpWidget(MaterialApp(home: NetworkDuelScreen(
      anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
      session: session, playerId: 'alice', repository: backend.repository('alice'),
      catalog: catalog, secretStore: MemoryNetworkDuelSecretStore(),
      profileStore: store, v4Profile: profile)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-private-profile-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profil privé'));
    await tester.pumpAndSettle();
    final summary = find.byKey(const Key('in-game-profile-sex'));
    expect(summary, findsOneWidget);
    expect(find.descendant(of: summary, matching: find.text(sex.label)), findsOneWidget);
    expect(tester.widget<ListTile>(summary).enabled, isFalse);
    await tester.ensureVisible(find.text('Personnaliser mon profil'));
    await tester.tap(find.text('Personnaliser mon profil'));
    await tester.pumpAndSettle();
    final accessories = find.byKey(const Key('customize-v4-accessories'));
    await tester.ensureVisible(accessories);
    await tester.tap(accessories);
    await tester.pumpAndSettle();
    final accessorySex = find.byKey(const Key('profile-sex-summary'));
    expect(find.descendant(of: accessorySex, matching: find.text(sex.label)), findsOneWidget);
    expect(tester.widget<ListTile>(accessorySex).enabled, isFalse);
    expect(find.text('Non modifiable pendant la partie.'), findsWidgets);
    expect(find.byKey(const Key('add-custom-profile-accessory')), findsOneWidget);
    expect((await store.load('alice'))!.toJson(), profile.toJson());
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  }

  for (final count in [0, 1, 2]) {
    for (final restore in [false, true]) {
      test('clothing eligibility canonical count=$count restored=$restore rejects dead new hands', () async {
        final backend = _Backend()..clothingCounts.updateAll((_, _) => count);
        final store = MemoryNetworkDuelSecretStore();
        if (restore) {
          await store.saveGame(sessionId: session.id, playerId: 'alice',
            state: privateGameFixture(roundNumber: 1,
              cards: const [CardRuntimeState(cardId: '006', zone: CardZone.HAND)],
              clothesByPlayer: const {'alice': 6, 'bob': 6}));
        }
        final controller = NetworkGameController(
          anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
          session: session, playerId: 'alice', repository: backend.repository('alice'),
          catalog: _catalogWithCards(catalog, {'card.v4.006', 'card.v4.001'}),
          privateStore: store, learningStore: MemoryNetworkProfileLearningStore(),
          initialClothingCounts: const {'alice': 6, 'bob': 6},
          v4Profile: completeConsentProfile('alice'));
        addTearDown(controller.dispose);
        await controller.start();
        expect(controller.errorMessage, isNull);
        expect(controller.clothingCounts, {'alice': count, 'bob': count});
        expect(controller.choicesFor('006').isNotEmpty, count > 0);
        expect(controller.heldConcepts.any((c) => c.id == '006'), count > 0);
        expect(controller.heldConcepts.every((c) => controller.choicesFor(c.id).isNotEmpty), isTrue);
        expect(controller.recoveryCards.any((c) => c.id == '006'), count > 0);
        expect(controller.usageCheckpoint.stock.remainingFor('006'), 2);
        expect(controller.actionPoints['alice'], 100);
        if (count == 0) {
          controller.selectCard('006');
          await controller.reserveSelection();
          expect(controller.selectedCard, isNull);
          expect(controller.usageCheckpoint.reservationsByIntent, isEmpty);
        }
      });
    }
  }

  test('clothing eligibility rejects a new reservation after canonical count reaches zero', () async {
    final backend = _Backend();
    final controller = NetworkGameController(
      anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
      session: session, playerId: 'alice', repository: backend.repository('alice'),
      catalog: _catalogWithCards(catalog, {'card.v4.006'}),
      v4Profile: completeConsentProfile('alice'),
      privateStore: MemoryNetworkDuelSecretStore(),
      initialClothingCounts: const {'alice': 6, 'bob': 6},
      learningStore: MemoryNetworkProfileLearningStore());
    addTearDown(controller.dispose);
    await controller.start();
    await _settle();
    controller.selectCard('006');
    expect(controller.selectedCard, isNotNull);
    final stock = controller.usageCheckpoint.stock.toJson();
    backend.clothingCounts.updateAll((_, _) => 0);
    backend.notifyTwice();
    await _settle();
    expect(controller.clothingCounts['alice'], 0);
    await expectLater(controller.reserveSelection(), throwsStateError);
    expect(controller.usageCheckpoint.reservationsByIntent, isEmpty);
    expect(controller.usageCheckpoint.usagesByIntent, isEmpty);
    expect(controller.usageCheckpoint.stock.toJson(), stock);
  });

  test('clothing eligibility replacement refills through current context without dead clothing cards', () async {
    final backend = _Backend()..v4UnlockedSpice = 4;
    final store = MemoryNetworkDuelSecretStore();
    await store.saveGame(sessionId: session.id, playerId: 'alice',
      state: privateGameFixture(roundNumber: 1, cards: const [
        CardRuntimeState(cardId: '006', zone: CardZone.HAND),
        CardRuntimeState(cardId: '001', zone: CardZone.HAND),
        CardRuntimeState(cardId: '012', zone: CardZone.HAND),
        CardRuntimeState(cardId: '032', zone: CardZone.HAND),
      ]));
    final profile = completeConsentProfile('alice');
    final controller = NetworkGameController(
      anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
      session: session, playerId: 'alice', repository: backend.repository('alice'),
      catalog: catalog, v4Profile: profile, privateStore: store,
      initialClothingCounts: const {'alice': 6, 'bob': 6},
      learningStore: MemoryNetworkProfileLearningStore());
    addTearDown(controller.dispose);
    await controller.start();
    expect(controller.heldConcepts.map((c) => c.id), contains('006'));
    final stock = controller.usageCheckpoint.stock.toJson();
    backend.clothingCounts.updateAll((_, _) => 0);
    backend.notifyTwice();
    await _settle();
    await controller.applyResolvedContext(EngineSessionContext(
      mode: SessionMode.face_to_face, proximity: ProximityState.TOGETHER,
      chiliActive: 4, chiliUnlocked: 4, clothesByPlayer: const {'alice': 0, 'bob': 0}));
    await controller.applyStageVetoProfile(profile.copyWith(stageVetoes: const [
      StageVeto(conceptId: '001', actionId: '*', role: ProfilePreferenceRole.general),
    ]));
    expect(controller.clothingCounts, {'alice': 0, 'bob': 0});
    expect(controller.choicesFor('006'), isEmpty);
    await controller.replaceExcludedCard('001');
    expect(controller.clothingCounts, {'alice': 0, 'bob': 0});
    expect(controller.heldConcepts, hasLength(4));
    expect(controller.heldConcepts.map((c) => c.id), isNot(contains('006')));
    expect(controller.heldConcepts.map((c) => c.id), isNot(contains('007')));
    expect(controller.heldConcepts.every((c) => controller.choicesFor(c.id).isNotEmpty), isTrue);
    expect(controller.usageCheckpoint.stock.toJson(), stock);
    expect(controller.actionPoints['alice'], 100);
  });

  test('clothing eligibility removes impossible carry-over cards before both next-round hands', () async {
    final setup = await _setupCorruption(session, catalog);
    addTearDown(setup.dispose);
    await _playUnequal(setup, forceAliceCard: '001', avoidBobCard: '006');
    final loser = setup.alice.isInitialLoser ? setup.alice : setup.bob;
    await loser.skipCorruption();
    await _settle();
    setup.backend.clothingCounts.updateAll((_, _) => 0);
    setup.backend.notifyTwice();
    await _settle();
    await _completeResolvedAction(setup);
    await _cycleController(setup).completeAction();
    await _settle();
    for (final player in [setup.alice, setup.bob]) {
      expect(player.roundNumber, 2);
      expect(player.heldConcepts.map((c) => c.id), isNot(contains('006')));
      expect(player.heldConcepts.map((c) => c.id), isNot(contains('007')));
      expect(player.heldConcepts.every((c) => player.choicesFor(c.id).isNotEmpty), isTrue);
      expect(player.hand, hasLength(4));
    }
  });

  test('clothing eligibility filters historical replay proposals but preserves frozen history', () async {
    final setup = await _setupCorruption(session, catalog);
    addTearDown(setup.dispose);
    await _playUnequal(setup, forceAliceCard: '006', requireRepeatable: true);
    final source = setup.alice.usageCheckpoint.usagesByIntent.values.single;
    final loser = setup.alice.isInitialLoser ? setup.alice : setup.bob;
    await loser.skipCorruption();
    await _settle();
    await _completeResolvedAction(setup);
    await _cycleController(setup).completeAction();
    await _settle();
    expect(setup.alice.corruptionCards.any((c) => c.identity == source.usageId), isTrue);
    final frozen = source.toJson();
    final quota = setup.alice.usageCheckpoint.stock.toJson();
    await setup.alice.applyResolvedContext(EngineSessionContext(
      mode: SessionMode.face_to_face, proximity: ProximityState.TOGETHER,
      chiliActive: setup.alice.activeSpice, chiliUnlocked: setup.alice.activeSpice,
      clothesByPlayer: const {'alice': 0, 'bob': 0}));
    expect(setup.alice.choicesFor('006'), isEmpty);
    expect(setup.alice.corruptionCards.any((c) => c.id == '006'), isFalse);
    expect(setup.alice.recoveryCards.any((c) => c.id == '006'), isFalse);
    expect(setup.alice.auctionCards.any((c) => c.id == '006'), isFalse);
    expect(source.reconstruct().toJson(), frozen['action']);
    expect(setup.alice.usageCheckpoint.stock.toJson(), quota);
    expect(setup.alice.visibleDiscardUsages.any((u) => u.conceptId == '006'), isTrue);
  });

  testWidgets('V1 stage exclusion is editable in the existing private profile and persists', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = MemoryV4ProfileStore();
    await store.save(stageProfile());
    final backend = _Backend()..v4UnlockedSpice = 4;
    await tester.pumpWidget(MaterialApp(home:NetworkDuelScreen(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE}, session:session,playerId:'alice',
      repository:backend.repository('alice'),catalog:_catalogWithCards(catalog,{'card.v4.056'}),
      secretStore:MemoryNetworkDuelSecretStore(),profileStore:store,v4Profile:stageProfile())));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-private-profile-settings')));await tester.pumpAndSettle();
    await tester.tap(find.text('Profil privé'));await tester.pumpAndSettle();
    await tester.tap(find.text('Personnaliser mon profil'));await tester.pumpAndSettle();
    await Scrollable.ensureVisible(tester.element(find.byKey(const Key('stage-veto-list'))),alignment:.5);await tester.pumpAndSettle();
    await tester.tap(find.text('Exclure des stades'));await tester.pumpAndSettle();
    final conceptTile = find.byKey(const Key('stage-veto-concept-056'));
    await Scrollable.ensureVisible(tester.element(conceptTile),alignment:.5);await tester.pumpAndSettle();
    await tester.tap(find.descendant(of:conceptTile,matching:find.text('Paroles dégradantes')));await tester.pumpAndSettle();
    final checkbox = find.byKey(const Key('stage-veto-056.stage.3-FAIRE'));
    await Scrollable.ensureVisible(tester.element(checkbox),alignment:.5);await tester.pumpAndSettle();await tester.tap(checkbox);await tester.pumpAndSettle();
    final saved = (await store.load('alice'))!;
    expect(saved.excludesStage('056','056.stage.3','FAIRE'),isTrue);
    expect(saved.excludesStage('056','056.stage.2','FAIRE'),isFalse);
    expect(saved.excludesStage('056','056.stage.3','RECEVOIR'),isFalse);
    expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });


  test('V1 changing veto before commit refreshes inverse without spending the excluded stage', () async {
    final backend = _Backend()..v4UnlockedSpice = 4;
    final c = NetworkGameController(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE}, session:session,playerId:'alice',repository:backend.repository('alice'),
      privateStore:MemoryNetworkDuelSecretStore(),learningStore:MemoryNetworkProfileLearningStore(),
      catalog:_catalogWithCards(catalog,{'card.v4.056'}),v4Profile:stageProfile());
    addTearDown(c.dispose);await c.start();c.selectCard('056');
    final native = c.selectedCard!.nativeDirection;
    final other = native==CardOccurrenceDirection.FAIRE ? ProfilePreferenceRole.recevoir : ProfilePreferenceRole.faire;
    await c.applyStageVetoProfile(stageProfile(excluded:3,role:other));
    expect(c.selectedCard!.oppositePersonalValue,isNull);
    expect(c.usageCheckpoint.usagesByIntent,isEmpty);
    await c.confirmSelection();
    expect(c.usageCheckpoint.usagesByIntent.values.single.invertedAction,isNull);
  });


  test('explicit private card-stage-role estimates drive PA without changing an engaged snapshot', () async {
    final backend=_Backend()..v4UnlockedSpice=4;
    final focused=_catalogWithCards(catalog,{'card.v4.056'});
    final profiles=MemoryV4ProfileStore();await profiles.save(stageProfile());
    final ratings=MemoryV4CardLearningStore();
    final editor=CatalogProfileController(catalog:focused,playerId:'alice',profileStore:profiles,
      ratingStore:ratings,learningStore:MemoryNetworkProfileLearningStore());
    await editor.load();
    for(final i in editor.items.where((i)=>i.actionId=='056.stage.3')) {
      await editor.rate(i,i.direction==CardOccurrenceDirection.FAIRE?DetailedPreferenceCategory.love:DetailedPreferenceCategory.atMyLimit);
    }
    final c=NetworkGameController(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE}, session:session,playerId:'alice',repository:backend.repository('alice'),
      privateStore:MemoryNetworkDuelSecretStore(),learningStore:MemoryNetworkProfileLearningStore(),
      cardLearningStore:ratings,catalog:focused,v4Profile:editor.profile);
    addTearDown(c.dispose);addTearDown(editor.dispose);await c.start();c.selectCard('056');
    final selected=c.selectedCard!;
    expect(selected.personalValue,selected.nativeDirection==CardOccurrenceDirection.FAIRE?4:18);
    await c.confirmSelection();
    final frozen=c.usageCheckpoint.usagesByIntent.values.single.toJson();
    await editor.rate(editor.items.firstWhere((i)=>i.actionId=='056.stage.3'&&i.direction==selected.nativeDirection),DetailedPreferenceCategory.essential);
    await c.reloadPrivateCardRatings();
    expect(c.usageCheckpoint.usagesByIntent.values.single.toJson(),frozen);
  });
  testWidgets('hand long press offers separate lock stage and whole-card exclusions', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final backend=_Backend()..v4UnlockedSpice=4;
    final profiles=MemoryV4ProfileStore();await profiles.save(stageProfile());
    await tester.pumpWidget(MaterialApp(home:NetworkDuelScreen(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE}, session:session,playerId:'alice',
      repository:backend.repository('alice'),catalog:_catalogWithCards(catalog,{'card.v4.056'}),
      secretStore:MemoryNetworkDuelSecretStore(),profileStore:profiles,v4Profile:stageProfile(),cardLearningStore:MemoryV4CardLearningStore())));
    await tester.pumpAndSettle();
    final box=tester.getRect(find.byKey(const Key('network-game-hand')));
    await tester.longPressAt(Offset(box.center.dx,box.bottom-20));await tester.pumpAndSettle();
    expect(find.text('Verrouiller la carte'),findsOneWidget);
    expect(find.text('Exclure ce stade'),findsOneWidget);expect(find.text('Exclure la carte'),findsOneWidget);
    await tester.tap(find.text('Exclure ce stade'));await tester.pumpAndSettle();
    final saved=(await profiles.load('alice'))!;
    expect(saved.stageVetoes.single.actionId,'056.stage.3');
    expect(backend.round.commits,isEmpty);
    expect(backend.state('bob').toJson().toString(),isNot(contains('stage_vetoes')));
    var surface = tester.widget<CardHandSurface>(find.byType(CardHandSurface));
    expect(surface.cards.single.definition.variantId, '056.stage.3');
    expect(surface.cards.single.available, isFalse);
    surface.onLongPressCard!(surface.cards.single);
    await tester.pumpAndSettle();
    expect(find.text('Annuler l’exclusion de ce stade'), findsOneWidget);
    await tester.tap(find.text('Annuler l’exclusion de ce stade'));
    await tester.pumpAndSettle();
    expect((await profiles.load('alice'))!.stageVetoes, isEmpty);
    surface = tester.widget<CardHandSurface>(find.byType(CardHandSurface));
    expect(surface.cards.single.available, isTrue);
    surface.onLongPressCard!(surface.cards.single);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Exclure la carte'));
    await tester.pumpAndSettle();
    surface = tester.widget<CardHandSurface>(find.byType(CardHandSurface));
    expect(surface.cards.single.excluded, isTrue);
    expect(surface.cards.single.replaceable, isTrue);
    surface.onLongPressCard!(surface.cards.single);
    await tester.pumpAndSettle();
    expect(find.text('Annuler l’exclusion de la carte'), findsOneWidget);
    expect(find.text('Exclure la carte'), findsNothing);
    await tester.tap(find.text('Annuler l’exclusion de la carte'));
    await tester.pumpAndSettle();
    expect((await profiles.load('alice'))!.stageVetoes, isEmpty);
    expect(tester.takeException(),isNull);await tester.pumpWidget(const SizedBox.shrink());
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
        'Choisis librement une partie du corps de ton partenaire à embrasser.',
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

  test(
    'drawn zone occurrence keeps its materialized variant in the hand',
    () async {
      final store = MemoryNetworkDuelSecretStore();
      final setup = await _setup(
        session,
        _catalogWithCards(catalog, {'card.v4.004'}),
        aliceSecrets: store,
      );
      addTearDown(setup.dispose);
      final saved = (await store.loadGame(
        sessionId: session.id,
        playerId: 'alice',
      ))!;
      final handState = saved.cards.singleWhere(
        (card) => card.cardId == '004' && card.zone == CardZone.HAND,
      );
      expect(handState.variantId, isNotNull);
      final displayed = setup.alice.hand.singleWhere(
        (card) => card.id == '004',
      );
      expect(displayed.variant.id, handState.variantId);
      setup.alice.selectCard('004');
      expect(setup.alice.selectedCard!.variant.id, handState.variantId);
      expect(
        setup.alice.materializedAction('004')!.choice.actionId,
        handState.variantId,
      );
    },
  );

  for (final spec in [
    ('002', '002.zone.neck_nape', 'neck_nape', 1),
    ('004', '004.zone.neck_nape', 'neck_nape', 1),
    ('005', '005.zone.neck_nape', 'neck_nape', 1),
  ]) {
    test(
      '${spec.$1} freezes its precise zone occurrence in the snapshot',
      () async {
        final store = MemoryNetworkDuelSecretStore();
        final setup = await _setup(
          session,
          _catalogWithCards(catalog, {'card.v4.${spec.$1}'}),
          aliceSecrets: store,
        );
        addTearDown(setup.dispose);
        final option = setup.alice
            .choicesFor(spec.$1)
            .singleWhere((choice) => choice.choice.actionId == spec.$2);
        setup.alice.selectCard(spec.$1);
        setup.alice.chooseAction(option);
        await setup.alice.confirmSelection();
        final usage = (await store.loadGame(
          sessionId: session.id,
          playerId: 'alice',
        ))!.activeReveal!.choice.usage!;
        expect(usage.resolvedAction['variant_id'], spec.$2);
        expect(usage.resolvedAction['zone_id'], spec.$3);
        expect(usage.resolvedAction['effective_chili'], spec.$4);
        expect(
          (usage.resolvedAction['parameters'] as Map).containsKey('technique'),
          isFalse,
        );
      },
    );
  }

  for (final id in ['004', '005']) {
    test(
      '$id free occurrence stores no anatomical or technique evidence',
      () async {
        final store = MemoryNetworkDuelSecretStore();
        final setup = await _setup(
          session,
          _catalogWithCards(catalog, {'card.v4.$id'}),
          aliceSecrets: store,
        );
        addTearDown(setup.dispose);
        final free = setup.alice
            .choicesFor(id)
            .singleWhere((choice) => choice.choice.actionId == '$id.zone.free');
        setup.alice.selectCard(id);
        setup.alice.chooseAction(free);
        await setup.alice.confirmSelection();
        final usage = (await store.loadGame(
          sessionId: session.id,
          playerId: 'alice',
        ))!.activeReveal!.choice.usage!;
        expect(usage.resolvedAction['variant_id'], '$id.zone.free');
        expect(usage.resolvedAction.containsKey('zone_id'), isFalse);
        expect(usage.resolvedAction['effective_chili'], 1);
        expect(
          (usage.resolvedAction['parameters'] as Map).containsKey('technique'),
          isFalse,
        );
        final evidence = const V3LearningTagProjector().project(
          usageLearningDescriptor(usage),
        );
        expect(evidence.every((entry) => entry.key.zoneId == null), isTrue);
      },
    );
  }

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
          await const SharedPreferencesV4ProfileStore().save(V4Profile(profileId: player, sex: ProfileSex.HOMME, preferences: const {}));
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
  testWidgets('final resolution fits long session names and grows with available height', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final named = LobbySession(id: session.id, joinCode: session.joinCode, status: session.status,
      expiresAt: session.expiresAt, players: const [
        LobbyPlayer(userId: 'alice', role: LobbyPlayerRole.player1, gameNickname: 'ABCDEFGHIJKLMNOPQRST'),
        LobbyPlayer(userId: 'bob', role: LobbyPlayerRole.player2, gameNickname: 'UVWXYZABCDEFGHIJKLMN'),
      ]);
    double? previous;
    for (final size in [const Size(320, 420), const Size(600, 1100)]) {
      await tester.binding.setSurfaceSize(size);
      final backend = _Backend();
      _setProjectedAction(backend, cards: [NetworkResolvedActionCardDto.fromUsage(nativeUsageFixture())]);
      await tester.pumpWidget(MaterialApp(home: NetworkDuelScreen(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE}, session: named, playerId: 'alice',
        repository: backend.repository('alice'), catalog: catalog, secretStore: MemoryNetworkDuelSecretStore())));
      await tester.pumpAndSettle();
      final card = tester.getSize(find.byType(CardRenderer));
      expect(card.width / card.height, closeTo(.68, .01));
      if (previous != null) expect(card.height, greaterThan(previous));
      previous = card.height;
      final description = tester.widget<Text>(find.byKey(const Key('resolution-description-usage-test')));
      expect(description.textAlign, TextAlign.center);
      expect(description.data, contains('ABCDEFGHIJKLMNOPQRST'));
      expect(description.data, contains('UVWXYZABCDEFGHIJKLMN'));
      await tester.ensureVisible(find.byKey(const Key('complete-network-action')));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('miniature replacement uses existing refill and spends zero PA', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = <String, ProfilePreference>{};
    for (final b in catalog.conceptRules!['bindings'] as List) {
      for (final a in (b as Map)['actions'] as List) {
        final rating = (a as Map)['rating'];
        if (rating is! Map) continue;
        for (final tag in [...rating['primary_preference_tags'] as List, ...rating['secondary_preference_tags'] as List]) {
          for (final role in ProfilePreferenceRole.values) {
            final key = ProfilePreferenceKey(tagId: tag as String, role: role);
            preferences[key.storageKey] = ProfilePreference(profileId: 'alice', key: key,
              pa: 10, excluded: false, source: ProfilePreferenceSource.initialQuestionnaire);
          }
        }
      }
    }
    final profile = V4Profile(sex: ProfileSex.HOMME, profileId: 'alice', preferences: preferences);
    final profiles = MemoryV4ProfileStore(); await profiles.save(profile);
    final secrets = MemoryNetworkDuelSecretStore();
    final backend = _Backend();
    await tester.pumpWidget(MaterialApp(home: NetworkDuelScreen(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE}, session: session, playerId: 'alice',
      repository: backend.repository('alice'), catalog: catalog, v4Profile: profile,
      profileStore: profiles, secretStore: secrets)));
    await tester.pumpAndSettle();
    var surface = tester.widget<CardHandSurface>(find.byType(CardHandSurface));
    final oldIds = surface.cards.map((c) => c.id).toSet();
    final target = surface.cards.first;
    surface.onLongPressCard!(target); await tester.pumpAndSettle();
    await tester.tap(find.text('Exclure la carte')); await tester.pumpAndSettle();
    final points = Map<String, int>.of(backend.points);
    final commands = Set<String>.of(backend.commands);
    await tester.tap(find.byKey(Key('replace-excluded-${target.id}')));
    await tester.pumpAndSettle();
    surface = tester.widget<CardHandSurface>(find.byType(CardHandSurface));
    expect(surface.cards.map((c) => c.id), isNot(contains(target.id)));
    expect(surface.cards.length, oldIds.length);
    expect(surface.cards.any((c) => !oldIds.contains(c.id)), isTrue);
    expect(backend.points, points);
    expect(backend.commands, commands);
    final saved = (await secrets.loadGame(sessionId: session.id, playerId: 'alice'))!;
    expect(saved.conceptCheckpoint!.usagesByIntent, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final id in ['alice', 'bob']) {
    for (final direction in ['FAIRE', 'RECEVOIR']) {
      for (final named in [false, true]) {
        testWidgets('resolution $id $direction names=$named preserves actual roles', (tester) async {
          SharedPreferences.setMockInitialValues(<String, Object>{});
          await tester.binding.setSurfaceSize(const Size(320, 568));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final backend = _Backend();
          final usage = nativeUsageFixture(owner: 'alice', conceptId: '032', direction: direction);
          _setProjectedAction(backend, cards: [NetworkResolvedActionCardDto.fromUsage(usage)]);
          await tester.pumpWidget(MaterialApp(home: NetworkDuelScreen(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
            session: named ? LobbySession(id: session.id, joinCode: session.joinCode, status: session.status,
              expiresAt: session.expiresAt, players: [
                const LobbyPlayer(userId: 'alice', role: LobbyPlayerRole.player1, gameNickname: 'Sébastien'),
                const LobbyPlayer(userId: 'bob', role: LobbyPlayerRole.player2, gameNickname: 'Julie'),
              ]) : session, playerId: id, repository: backend.repository(id), catalog: catalog,
            secretStore: MemoryNetworkDuelSecretStore())));
          await tester.pumpAndSettle();
          expect(find.text(id == 'alice' ? 'Tu as gagné !' : 'Tu as perdu'), findsOneWidget);
          expect(find.text(named && id == 'bob' ? 'La carte de Sébastien est retenue.' :
            id == 'alice' ? 'Ta carte est retenue.' : 'La carte de ton partenaire est retenue.'), findsOneWidget);
          final description = tester.widget<Text>(find.byKey(const Key('resolution-description-usage-test'))).data!;
          if (named) {
            expect(description, direction == 'FAIRE' ? 'Sébastien réalise « Ordre » pour Julie.' : 'Julie réalise « Ordre » pour Sébastien.');
          } else {
            final actorIsLocal = (direction == 'FAIRE') == (id == 'alice');
            expect(description, actorIsLocal ? 'Tu réalises « Ordre » pour ton partenaire.' : 'Ton partenaire réalise « Ordre » pour toi.');
          }
          expect(find.text('SUR TOI'), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }
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

  for (final size in [const Size(320, 420), const Size(600, 1100)]) {
  for (final id in ['alice', 'bob']) {
    testWidgets('post duel shows only the complete personal card for $id at $size', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
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
          home: NetworkDuelScreen(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
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
      expect(find.byKey(const Key('personal-duel-card')), findsOneWidget);
      final shown = tester.widget<CardRenderer>(find.byKey(const Key('personal-duel-card'))).definition;
      expect(shown.variantId, backend.round.reveals[id]!.choice.variantId);
      expect(shown.action, backend.round.reveals[id]!.choice.usage!.resolvedAction['action_text']);
      expect(find.byType(CardRenderer), findsOneWidget);
      expect(find.byKey(const Key('initial-duel-cards')), findsNothing);
      final bounds = tester.getRect(
        find.byKey(const Key('personal-duel-card')),
      );
      expect(bounds.width / bounds.height, closeTo(.68, .01));
      expect(bounds.height, greaterThan(0));
      expect(
        find.byKey(const Key('choose-negotiation')),
        winner ? findsNothing : findsOneWidget,
      );
      if (!winner) {
        await tester.tap(find.byKey(const Key('choose-negotiation')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('personal-duel-card')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('initial-duel-cards')), findsNothing);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  }
  test('stage defaults follow highest available stage and consumed stages stay unavailable', () async {
    final backend = _Backend()..v4UnlockedSpice = 2;
    final controller = _controller(backend, session, _catalogWithCards(catalog, {'card.v4.003'}), 'alice', MemoryNetworkDuelSecretStore());
    addTearDown(controller.dispose);
    await controller.start();
    expect(controller.defaultAction('003')!.choice.actionId, '003.stage.3');
    controller.selectCard('003');
    controller.chooseAction(controller.choicesFor('003').singleWhere((o) => o.choice.actionId == '003.stage.2'));
    await controller.confirmSelection();
    expect(controller.usageCheckpoint.stageConsumed('003', '003.stage.2'), isTrue);
    expect(controller.choicesFor('003').map((o) => o.choice.actionId), ['003.stage.1', '003.stage.3']);
    await controller.cancelSelection();
    expect(controller.defaultAction('003')!.choice.actionId, '003.stage.3');
    await controller.applyResolvedContext(EngineSessionContext(mode: SessionMode.face_to_face, proximity: ProximityState.TOGETHER, chiliActive: 1, chiliUnlocked: 1));
    expect(controller.defaultAction('003')!.choice.actionId, '003.stage.1');
    await controller.applyResolvedContext(EngineSessionContext(mode: SessionMode.face_to_face, proximity: ProximityState.TOGETHER, chiliActive: 2, chiliUnlocked: 2));
    expect(controller.defaultAction('003')!.choice.actionId, '003.stage.3');
  });

  for (final conceptId in ['003', '002', '024']) {
    testWidgets(
      'playing $conceptId commits its displayed action without another selection',
      (tester) async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final backend = _Backend()
          ..v4UnlockedSpice = conceptId == '024' ? 3 : 2;
        final store = MemoryNetworkDuelSecretStore();
        await tester.pumpWidget(
          MaterialApp(
            home: NetworkDuelScreen(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
              session: session,
              playerId: 'alice',
              repository: backend.repository('alice'),
              catalog: _catalogWithCards(catalog, {'card.v4.$conceptId'}),
              secretStore: store,
            ),
          ),
        );
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        var surface = tester.widget<CardHandSurface>(
          find.byType(CardHandSurface),
        );
        var item = surface.cards.single;
        if (conceptId == '003') {
          expect(item.definition.variantId, '003.stage.3');
        } else if (conceptId == '002') {
          expect(item.definition.variantId, startsWith('002.zone.'));
        } else {
          expect(item.definition.variantId, '024.action');
          expect(item.definition.zones, ['LIBRE']);
        }
        if (conceptId == '003') {
          expect(item.tabs, hasLength(3));
          surface.onTabChanged!(item, '003.stage.2');
          await tester.pump();
          surface = tester.widget<CardHandSurface>(
            find.byType(CardHandSurface),
          );
          item = surface.cards.single;
          expect(item.definition.variantId, '003.stage.2');
        }
        final shown = item.definition;
        surface.onPlay!(item);
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(find.byType(SimpleDialog), findsNothing);
        final saved = (await store.loadGame(
          sessionId: session.id,
          playerId: 'alice',
        ))!;
        final usage = saved.activeReveal!.choice.usage!;
        expect(
          usage.resolvedAction['stage_id'] ??
              usage.resolvedAction['variant_id'],
          shown.variantId,
        );
        expect(usage.resolvedAction['action_text'], shown.action);
        expect(saved.conceptCheckpoint!.usagesByIntent, hasLength(1));
        if (conceptId == '024') {
          expect(usage.conceptId, '024');
          expect(usage.resolvedAction['effective_chili'], 3);
          expect(
            (usage.resolvedAction['parameters'] as Map).keys.where(
              (k) => (k as String).startsWith('practice_'),
            ),
            isEmpty,
          );
          expect(usage.resolvedAction.containsKey('zone_id'), isFalse);
          final learned = const V3LearningTagProjector().project(
            usageLearningDescriptor(usage),
          );
          expect(learned, isNotEmpty);
          expect(learned.map((e) => e.key.preferenceId).toSet(), {
            'v3.preference.jeu_intime',
          });
        }
        if (conceptId == '002') {
          final isFree = shown.variantId == '002.zone.free';
          expect(
            usage.resolvedAction.containsKey('zone_id'),
            isFree ? isFalse : isTrue,
          );
          if (isFree) {
            expect(usage.resolvedAction['effective_chili'], 1);
          }
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final count in [1, 2]) {
    for (final useProjection in [true, false]) {
      testWidgets(
        'resolution shows $count retained snapshot cards from ${useProjection ? 'projection' : 'compromise'} without PA',
        (tester) async {
          SharedPreferences.setMockInitialValues(<String, Object>{});
          await tester.binding.setSurfaceSize(const Size(600, 1000));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final backend = _Backend();
          final actions = <NetworkResolvedActionCardDto>[];
          for (var index = 0; index < count; index++) {
            final usage = actionUsageFixture(
              conceptId: index == 0 ? '002' : '003',
              usageId: 'retained-$index',
              actionId: index == 0 ? '002.zone.feet' : '003.stage.2',
              nativeDirection: NetworkCardDirection.RECEVOIR,
              effectiveSpice: index + 1,
            );
            final json = Map<String, Object?>.from(usage.toJson());
            json['resolved_action'] = {
              ...usage.resolvedAction,
              if (index == 0) 'zone_id': 'feet',
              'action_text': 'Action exacte du snapshot $index',
              'parameters': {
                'display_title': 'Titre figé $index',
                'display_details': 'Précisions figées $index',
              },
            };
            actions.add(
              NetworkResolvedActionCardDto.fromUsage(
                NetworkUsageProjection.fromJson(json),
              ),
            );
          }
          _setProjectedAction(backend, cards: actions);
          if (!useProjection) {
            backend.round.actionProjection = null;
            backend.round.finalResolution = NetworkFinalResolutionDto(
              retainedPlayerId: 'alice',
              initialWinnerPlayerId: 'alice',
              finalWinnerPlayerId: 'alice',
              compromise: [
                for (final card in actions)
                  NetworkCompromiseCardDto.fromUsage(
                    card.usage,
                    origin: NetworkCompromiseOrigin.INITIAL_DUEL,
                  ),
              ],
            );
          }
          final store = MemoryNetworkDuelSecretStore();
          Future<void> open() async {
            await tester.pumpWidget(
              MaterialApp(
                home: NetworkDuelScreen(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
                  session: session,
                  playerId: 'alice',
                  repository: backend.repository('alice'),
                  catalog: catalog,
                  secretStore: store,
                ),
              ),
            );
            await tester.pumpAndSettle();
          }

          CardRenderer shown() =>
              tester.widget<CardRenderer>(find.byType(CardRenderer));
          await open();
          final controller =
              (tester.state(find.byType(NetworkDuelScreen)) as dynamic)
                      .controller
                  as NetworkGameController;
          final checkpoint = controller.usageCheckpoint.encode();
          final points = Map<String, int>.of(backend.points);
          final before = backend.round.finalResolution!.toJson();
          expect(find.byType(CardRenderer), findsOneWidget);
          expect(shown().showPa, isFalse);
          expect(shown().definition.personalPa, isNull);
          expect(shown().definition.oppositePa, isNull);
          expect(
            shown().definition.action,
            actions.first.usage.resolvedAction['action_text'],
          );
          expect(shown().definition.zones, ['Pieds']);
          expect(shown().definition.details, 'Précisions figées 0');
          expect(
            find.byKey(const Key('complete-network-action')),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: find.byType(CardRenderer),
              matching: find.textContaining('PA'),
            ),
            findsNothing,
          );
          if (count == 1) {
            expect(find.byKey(const Key('resolution-page')), findsNothing);
            expect(find.byKey(const Key('resolution-previous')), findsNothing);
            expect(find.byKey(const Key('resolution-next')), findsNothing);
          } else {
            expect(find.text('1/2'), findsOneWidget);
            expect(
              tester
                  .widget<IconButton>(
                    find.byKey(const Key('resolution-previous')),
                  )
                  .onPressed,
              isNull,
            );
            await tester.tap(find.byKey(const Key('resolution-next')));
            await tester.pump();
            expect(find.text('2/2'), findsOneWidget);
            expect(
              shown().definition.action,
              actions.last.usage.resolvedAction['action_text'],
            );
            expect(shown().definition.variantId, '003.stage.2');
            expect(shown().definition.spice, 2);
            expect(
              tester
                  .widget<IconButton>(find.byKey(const Key('resolution-next')))
                  .onPressed,
              isNull,
            );
            backend.notify();
            await tester.pumpAndSettle();
            expect(find.text('2/2'), findsOneWidget);
            await tester.tap(find.byKey(const Key('resolution-previous')));
            await tester.pump();
            expect(find.text('1/2'), findsOneWidget);
          }
          expect(controller.usageCheckpoint.encode(), checkpoint);
          expect(backend.points, points);
          expect(backend.round.finalResolution!.toJson(), before);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          await open();
          expect(
            shown().definition.action,
            actions.first.usage.resolvedAction['action_text'],
          );
          expect(shown().definition.zones, ['Pieds']);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
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
          NetworkGameController(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
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
          NetworkGameController(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
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
    'reconnection retains commitment after a forbidden cancellation',
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
      expect(saved.cancelCommitRequested, isFalse);
      expect(backend.round.commits, contains('alice'));
      controller.dispose();
      controller = _controller(backend, session, catalog, 'alice', store);
      addTearDown(controller.dispose);
      await controller.start();
      await _settle();
      expect(backend.round.commits, contains('alice'));
      expect(controller.usageCheckpoint.encode(), checkpoint);
      final resumed = (await store.loadGame(
        sessionId: session.id,
        playerId: 'alice',
      ))!;
      expect(resumed.cancelCommitRequested, isFalse);
      expect(resumed.activeReveal, isNotNull);
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
      'card.v4.001', 'card.v4.002', 'card.v4.006',
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
    final kiss = engageHistory('006', '006.action', CardOccurrenceDirection.FAIRE, 1);
    final striptease = engageHistory('010', '010.stage.1', CardOccurrenceDirection.FAIRE, 1);
    final exhausted = engageHistory('002', '002.zone.face_hair', CardOccurrenceDirection.FAIRE, 1,
      zoneId: 'face_hair');
    final tooSpicy = engageHistory('037', '037.stage.1', CardOccurrenceDirection.FAIRE, 2);
    expect(history.map((r) => r.usageId).toSet(), hasLength(4));
    expect(checkpoint.availableFor('006'), 1);
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
    NetworkGameController player(String id, int value) => NetworkGameController(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
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
      kiss.usageId,
    ]));
    expect(controller.auctionCards.every(controller.isAuctionCardPlayable), isTrue);
    expect(controller.auctionCards.map((c) => c.identity),
      isNot(contains(exhausted.usageId)));
    expect(controller.auctionCards.map((c) => c.identity),
      isNot(contains(tooSpicy.usageId)));
    expect(controller.usageCheckpoint.availableFor('006'), 1);
    expect(controller.usageCheckpoint.availableFor('010'), 2);
    for (final usage in [kiss, striptease]) {
      final snapshot = usage.resolvedAction;
      expect(history.any((r) => r.usageId == usage.usageId &&
        r.usage.ownerPlayerId == 'alice' && r.roundNumber < controller.roundNumber), isTrue);
      expect(controller.choicesFor(usage.conceptId).any((option) =>
        option.choice.actionId == (snapshot['stage_id'] ?? snapshot['variant_id']) &&
        option.choice.zoneId == snapshot['zone_id']), usage.usageId == kiss.usageId);
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
            for (final id in ['006', '001', '012', '032'])
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
        NetworkGameController(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
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
    final initialCapacity = setup.alice.usageCheckpoint.availableFor('006');
    expect(initialCapacity, 2);
    await _playUnequal(setup, forceAliceCard: '006', requireRepeatable: true);
    final source = setup.alice.usageCheckpoint.usagesByIntent.values.single;
    expect(source.conceptId, '006');
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
    expect(historical.usage.conceptId, '006');
    final historicalSnapshot = historical.toJson();
    expect(afterFirst.conceptCheckpoint!.usageForIntent(source.intentId)!.toJson(), originalSnapshot);
    expect(setup.alice.usageCheckpoint.usageForIntent(source.intentId)!.toJson(), originalSnapshot);
    expect(setup.alice.usageCheckpoint.stock.remainingFor('006'), initialCapacity - 1);
    expect(setup.alice.usageCheckpoint.availableFor('006'), initialCapacity - 1);
    expect(setup.alice.usageCheckpoint.usagesByIntent.values.where((u) => u.conceptId == '006'), hasLength(1));

    // Play another concept so the historical source remains an unused replay.
    await _playUnequal(setup, forceAliceCard: '001', avoidBobCard: '006');
    backend.routeToUnifiedPostDuelChoice = true;
    expect(setup.alice.isInitialLoser, isTrue);
    await _settle();
    final loser = setup.alice;
    final winner = setup.bob;
    final offered = loser.auctionCards.singleWhere((c) => c.identity == source.usageId);
    expect(loser.isAuctionCardPlayable(offered), isTrue);
    final beforeProposal = loser.usageCheckpoint.encode();
    final engagedIds = loser.usageCheckpoint.usagesByIntent.values.map((u) => u.usageId).toSet();
    final remaining = loser.usageCheckpoint.stock.remainingFor('006');
    expect(remaining, initialCapacity - 1);
    await loser.proposeNegotiation(directPa: 0, inversion: false, cardIds: {source.usageId});
    await _settle();
    final pending = (await aliceStore.loadGame(sessionId: session.id, playerId: 'alice'))!;
    final draft = pending.reservedChoices.values.singleWhere((u) => u.sourceUsageId == source.usageId);
    expect(draft.usageId, isNot(source.usageId));
    expect(pending.conceptCheckpoint!.reservationsByIntent[draft.intentId], '006');
    expect(loser.usageCheckpoint.stock.remainingFor('006'), remaining);
    expect(loser.usageCheckpoint.availableFor('006'), remaining - 1);
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
    expect(loser.usageCheckpoint.stock.remainingFor('006'), remaining);
    expect(loser.usageCheckpoint.availableFor('006'), remaining);
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
              for (final id in ['006', '001', '012', '032'])
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
          NetworkGameController(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
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
      final initialCapacity = setup.alice.usageCheckpoint.availableFor('006');
      expect(initialCapacity, 2);
      await _playUnequal(setup, forceAliceCard: '006', requireRepeatable: true);
      final source = setup.alice.usageCheckpoint.usagesByIntent.values.single;
      expect(source.conceptId, '006');
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
      expect(historical.usage.conceptId, '006');
      final historicalSnapshot = historical.toJson();
      expect(afterFirst.conceptCheckpoint!.usageForIntent(source.intentId)!.toJson(), originalSnapshot);
      expect(setup.alice.usageCheckpoint.usageForIntent(source.intentId)!.toJson(), originalSnapshot);
      expect(setup.alice.usageCheckpoint.stock.remainingFor('006'), initialCapacity - 1);
      expect(setup.alice.usageCheckpoint.availableFor('006'), initialCapacity - 1);
      expect(setup.alice.usageCheckpoint.usagesByIntent.values.where((u) => u.conceptId == '006'), hasLength(1));

      // Play another concept so the historical source remains an unused replay.
      await _playUnequal(setup, forceAliceCard: '001', avoidBobCard: '006');
      backend.routeToUnifiedPostDuelChoice = true;
      expect(setup.alice.isInitialLoser, isTrue);
      await _settle();
      final loser = setup.alice;
      final winner = setup.bob;
      final offered = loser.auctionCards.singleWhere((c) => c.identity == source.usageId);
      expect(loser.isAuctionCardPlayable(offered), isTrue);
      final engagedIds = loser.usageCheckpoint.usagesByIntent.values.map((u) => u.usageId).toSet();
      final remaining = loser.usageCheckpoint.stock.remainingFor('006');
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
      expect(pending.conceptCheckpoint!.reservationsByIntent[draft.intentId], '006');
      expect(loser.usageCheckpoint.stock.remainingFor('006'), remaining);
      expect(loser.usageCheckpoint.availableFor('006'), remaining - 1);
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
      expect(loser.usageCheckpoint.stock.remainingFor('006'), remaining - 1);
      expect(loser.usageCheckpoint.availableFor('006'), remaining - 1);
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
        (u) => u.conceptId == '006'), hasLength(2));
      expect(initialCapacity - completed.conceptCheckpoint!.stock.remainingFor('006'), 2);
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
      expect(reconnected.usageCheckpoint.stock.remainingFor('006'), initialCapacity - 2);
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
    final alice = NetworkGameController(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
      session: session,
      playerId: 'alice',
      repository: backend.repository('alice'),
      privateStore: MemoryNetworkDuelSecretStore(),
      learningStore: MemoryNetworkProfileLearningStore(),
      catalog: catalog,
      sessionMode: V4SessionMode.hybrid,
    );
    final bob = NetworkGameController(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
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
      final controller = NetworkGameController(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
        session: session,
        playerId: 'alice',
        repository: backend.repository('alice'),
        privateStore: store,
        learningStore: MemoryNetworkProfileLearningStore(),
        catalog: catalog,
        sessionMode: V4SessionMode.hybrid,
      );
      final bob = NetworkGameController(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
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
        expect(player.recoveryCards.any((c) => c.identity == oldId),
          oldSources[player.playerId]!.action.effectiveChili >= player.recoveryReferenceSpice!,
          reason: 'Cross-cycle history remains available only within the canonical Recovery range');
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
      final afterPlay = (await store.loadGame(
        sessionId: session.id,
        playerId: 'alice',
      ))!;
      expect(
        afterPlay.publicDiscards.any((r) => r.usageId == newUsage.usageId),
        isTrue,
      );
      expect(
        controller.corruptionCards.any((c) => c.identity == newUsage.usageId),
        isTrue,
      );
      expect(
        controller.corruptionCards.any(
          (c) => c.identity == oldSources['alice']!.usageId,
        ),
        isFalse,
      );
      expect(
        controller.usageCheckpoint.usagesByIntent.values.single.toJson(),
        newUsage.toJson(),
      );
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
      final controller = NetworkGameController(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
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
        final controller = NetworkGameController(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
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
  test('V4 role exclusion preserves the opposite authorized direction', () async {
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
      final controller = NetworkGameController(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
        session: session,
        playerId: 'alice',
        repository: backend.repository('alice'),
        privateStore: MemoryNetworkDuelSecretStore(),
        learningStore: MemoryNetworkProfileLearningStore(),
        catalog: focusedCatalog,
        v4Profile: V4Profile(sex: ProfileSex.HOMME, profileId: 'alice', preferences: preferences),
        scoringCatalog: scoringCatalog,
      );
      addTearDown(controller.dispose);
      await controller.start();
      expect(controller.hand, isNotEmpty);
      expect(controller.choicesFor('002'), isNotEmpty);
      final expectedDirection = excludedRole == ProfilePreferenceRole.faire
        ? CardOccurrenceDirection.RECEVOIR : CardOccurrenceDirection.FAIRE;
      expect(controller.hand.single.nativeDirection, expectedDirection);
      expect(controller.hand.single.oppositePersonalValue, isNull);
      controller.selectCard('002');
      await controller.confirmSelection();
      expect(controller.usageCheckpoint.usagesByIntent, hasLength(1));
      expect(controller.usageCheckpoint.reservationsByIntent, isEmpty);
      expect(controller.usageCheckpoint.stock.remainingFor('002'), 0);
      expect(backend.round.commits, hasLength(1));
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
        (2, 5.0, 12.0, true, 7),
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
        final controller = NetworkGameController(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
          session: session,
          playerId: 'alice',
          repository: backend.repository('alice'),
          privateStore: MemoryNetworkDuelSecretStore(),
          learningStore: MemoryNetworkProfileLearningStore(),
          catalog: focusedCatalog,
          v4Profile: V4Profile(sex: ProfileSex.HOMME, profileId: 'alice', preferences: preferences),
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
    final controller = NetworkGameController(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
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
        final controller = NetworkGameController(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
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
      final controller = NetworkGameController(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
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
    final controller = NetworkGameController(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
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
    NetworkGameController bobController() => NetworkGameController(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
      session: session,
      playerId: 'bob',
      repository: backend.repository('bob'),
      privateStore: store,
      learningStore: MemoryNetworkProfileLearningStore(),
      catalog: bobCatalog,
      sessionMode: V4SessionMode.hybrid,
    );
    final bob = bobController();
    final alice = NetworkGameController(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
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
    final alice = NetworkGameController(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
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
    final bob = NetworkGameController(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
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
    final reconnect = NetworkGameController(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
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
    final controller = NetworkGameController(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
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
    'engagement prevents cancellation and preserves consumed conceptual use',
    () async {
      final setup = await _setup(session, catalog);
      addTearDown(setup.dispose);
      final card = setup.alice.hand.firstWhere(setup.alice.isCardPlayable);
      setup.alice.toggleLock(card.identity);
      setup.alice.selectCard(card.identity);
      await setup.alice.confirmSelection();
      await _settle();

      expect(setup.alice.canCancelSelection, isFalse);
      expect(setup.backend.round.commits, contains('alice'));
      expect(await setup.alice.cancelSelection(), isFalse);
      await _settle();

      expect(setup.backend.round.commits, contains('alice'));
      expect(setup.alice.usageCheckpoint.usagesByIntent, hasLength(1));
      expect(
        setup.alice.usageCheckpoint.stock.remainingFor(card.id),
        setup.alice.usageCheckpoint.stock.capacity[card.id]! - 1,
      );
      expect(setup.alice.lockedCardId, isNull);
      expect(setup.alice.viewState, NetworkGameViewState.waitingForPartner);

      final engaged = setup.alice.personalDuelCard!.identity;
      setup.alice.selectCard(setup.alice.hand.first.identity);
      await setup.alice.confirmSelection();
      expect(setup.alice.personalDuelCard!.identity, engaged);
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
        home: NetworkDuelScreen(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
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
                    builder: (_) => NetworkDuelScreen(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
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
          home: NetworkDuelScreen(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
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
            home: NetworkDuelScreen(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
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
        for (var i = 0; i < cards.length; i++) {
          final card = cards[i];
          if (i > 0) {
            await _showResolutionControl(tester, 'resolution-next');
            await tester.tap(find.byKey(const Key('resolution-next')));
            await tester.pump();
          }
          expect(
            find.text(card.usage.resolvedAction['action_text']! as String),
            findsOneWidget,
          );
        }
        for (var i = 1; i < cards.length; i++) {
          await _showResolutionControl(tester, 'resolution-previous');
          await tester.tap(find.byKey(const Key('resolution-previous')));
          await tester.pump();
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
      final bob = NetworkGameController(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
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
          home: NetworkDuelScreen(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
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
        final controller = NetworkGameController(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
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

  testWidgets('006 requires explicit clothing confirmation before Terminé', (
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
        home: NetworkDuelScreen(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
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
    await _showResolutionControl(tester, 'adjust-deterministic-clothing-count');
    expect(find.text('Ajuster les vêtements (5)'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('complete-network-action'))).onPressed, isNull);
    await tester.tap(find.byKey(const Key('adjust-deterministic-clothing-count')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Valider'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byKey(const Key('complete-network-action'))).onPressed, isNotNull);
    await _showResolutionControl(tester, 'complete-network-action');
    await tester.tap(find.byKey(const Key('complete-network-action')));
    await tester.pump();
    expect(find.byKey(const Key('clothing-resync-count')), findsNothing);
    expect(backend.clothingCounts['alice'], 5);
  });

  for (final cancel in [false, true]) {
    testWidgets(
      'clothing resync keeps its controller alive during ${cancel ? 'cancel' : 'validation'} transition',
      (tester) async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final backend = _Backend()..clothingCounts['alice'] = 6;
        _setProjectedAction(
          backend,
          cards: [
            _projectedCard(
              occurrenceId: 'resync-lifecycle',
              cardId: '006',
              variantId: '006.action',
              targetPlayerIds: const ['alice'],
              clothingBehavior: V4ClothingBehavior.removeOne,
            ),
          ],
          requiredClothingPlayerIds: const {'alice'},
        );
        await tester.pumpWidget(
          MaterialApp(
            home: NetworkDuelScreen(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
              session: session,
              playerId: 'alice',
              repository: backend.repository('alice'),
              catalog: catalog,
              secretStore: MemoryNetworkDuelSecretStore(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await _showResolutionControl(tester, 'adjust-deterministic-clothing-count');
        await tester.tap(
          find.byKey(const Key('adjust-deterministic-clothing-count')),
        );
        await tester.pumpAndSettle();
        final field = find.byKey(const Key('clothing-resync-count'));
        final input = tester.widget<TextField>(field).controller!;
        expect(input.text, '5');
        await tester.enterText(field, '3');
        backend.notify();
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(field).controller, same(input));
        expect(input.text, '3');
        await tester.enterText(field, '-1');
        await tester.tap(find.widgetWithText(FilledButton, 'Valider'));
        await tester.pump();
        expect(field, findsOneWidget);
        await tester.enterText(field, '0');
        await tester.tap(
          cancel
              ? find.widgetWithText(TextButton, 'Annuler')
              : find.widgetWithText(FilledButton, 'Valider'),
        );
        await tester.pump(const Duration(milliseconds: 1));
        // The dialog is still mounted during its reverse animation, although the
        // showDialog future has completed. Rebuild its focused TextField now.
        expect(field, findsOneWidget);
        tester.element(field).markNeedsBuild();
        backend.notify();
        await tester.pump(const Duration(milliseconds: 1));
        expect(tester.takeException(), isNull);
        void listener() {}
        expect(() => input.addListener(listener), returnsNormally);
        input.removeListener(listener);
        await tester.pumpAndSettle();
        expect(field, findsNothing);
        expect(tester.takeException(), isNull);
        expect(
          find.text('Ajuster les vêtements (${cancel ? 5 : 0})'),
          findsOneWidget,
        );
        // Reopening creates a fresh controller with the saved draft/default.
        await _showResolutionControl(tester, 'adjust-deterministic-clothing-count');
        await tester.tap(
          find.byKey(const Key('adjust-deterministic-clothing-count')),
        );
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(field).controller, isNot(same(input)));
        expect(
          tester.widget<TextField>(field).controller!.text,
          cancel ? '5' : '0',
        );
        await tester.tap(find.widgetWithText(TextButton, 'Annuler'));
        await tester.pumpAndSettle();
        await _showResolutionControl(tester, 'complete-network-action');
        await tester.tap(find.byKey(const Key('complete-network-action')));
        await tester.pumpAndSettle();
        expect(backend.clothingCounts['alice'], cancel ? 6 : 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'clothing resync survives viewState change and focused dialog removal',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final backend = _Backend()..clothingCounts['alice'] = 6;
      _setProjectedAction(
        backend,
        cards: [
          _projectedCard(
            occurrenceId: 'resync-strip-lifecycle',
            cardId: '010',
            variantId: '010.stage.2',
            targetPlayerIds: const ['alice'],
            clothingBehavior: V4ClothingBehavior.resetThenStrip,
          ),
        ],
        requiredClothingPlayerIds: const {'alice'},
      );
      await tester.pumpWidget(
        MaterialApp(
          home: NetworkDuelScreen(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
            session: session,
            playerId: 'alice',
            repository: backend.repository('alice'),
            catalog: catalog,
            secretStore: MemoryNetworkDuelSecretStore(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final controller =
          (tester.state(find.byType(NetworkDuelScreen)) as dynamic).controller
              as NetworkGameController;
      final previousView = controller.viewState;
      await _showResolutionControl(tester, 'adjust-deterministic-clothing-count');
      await tester.tap(find.byKey(const Key('adjust-deterministic-clothing-count')));
      await tester.pumpAndSettle();
      final field = find.byKey(const Key('clothing-resync-count'));
      final input = tester.widget<TextField>(field).controller!;
      expect(input.text, '6');
      await tester.enterText(field, '0');
      expect(tester.testTextInput.isVisible, isTrue);
      backend.round.phase = NetworkGamePhase.waitingNext;
      backend.notify();
      await tester.pumpAndSettle();
      expect(controller.viewState, isNot(previousView));
      expect(tester.widget<TextField>(field).controller, same(input));
      expect(input.text, '0');
      expect(tester.takeException(), isNull);
      // Remove the navigator and focused dialog while the input is still active.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(field, findsNothing);
    },
  );

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
      var alice = NetworkGameController(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
        session: session,
        playerId: 'alice',
        repository: backend.repository('alice'),
        privateStore: MemoryNetworkDuelSecretStore(),
        learningStore: MemoryNetworkProfileLearningStore(),
        catalog: catalog,
      );
      final bob = NetworkGameController(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
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
      alice = NetworkGameController(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
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
        ('corruption accepted', 'card.v4.035', null, true),
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
    'reconnect after denied cancellation keeps the engaged card and nonce',
    () async {
      final backend = _Backend();
      final store = MemoryNetworkDuelSecretStore();
      final learning = MemoryNetworkProfileLearningStore();
      var controller = NetworkGameController(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
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
      expect(await controller.cancelSelection(), isFalse);
      controller.dispose();

      controller = NetworkGameController(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
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
      expect(controller.viewState, NetworkGameViewState.waitingForPartner);
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
      expect(newNonce, oldNonce);
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
      var alice = NetworkGameController(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
        session: session,
        playerId: 'alice',
        repository: backend.repository('alice'),
        privateStore: aliceSecrets,
        learningStore: aliceLearning,
        catalog: catalog,
      );
      final bob = NetworkGameController(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
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
      alice = NetworkGameController(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
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
    final alice = NetworkGameController(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
      session: session,
      playerId: 'alice',
      repository: backend.repository('alice'),
      privateStore: MemoryNetworkDuelSecretStore(),
      learningStore: learning,
      catalog: catalog,
    );
    final bob = NetworkGameController(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
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
    final controller = NetworkGameController(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
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
        final controller = NetworkGameController(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
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

  for (final concept in ['002', '003']) {
    test(
      'corruption second life replays exhausted historical $concept without normal stock',
      () async {
        final setup = await _setupCorruption(
          session,
          catalog,
          firstLifeConcept: concept,
        );
        addTearDown(setup.dispose);
        await _playUnequal(setup, forceAliceCard: concept);
        final source = setup.alice.usageCheckpoint.usagesByIntent.values.single;
        final firstLoser = setup.alice.isInitialLoser ? setup.alice : setup.bob;
        await firstLoser.skipCorruption();
        await _settle();
        await _completeResolvedAction(setup);
        await _playUnequal(
          setup,
          avoidAliceCard: concept,
          avoidBobCard: concept,
        );
        final actor = setup.alice;
        expect(actor.isCorruptionActor, isTrue);
        if (source.action.stageId != null) {
          expect(
            actor
                .choicesFor(concept)
                .any((o) => o.choice.actionId == source.action.stageId),
            isFalse,
          );
        }
        if (concept == '002') {
          expect(actor.usageCheckpoint.stock.remainingFor(concept), 0);
        }
        if (source.action.stageId != null) {
          expect(actor.stageConsumed(concept, source.action.stageId!), isTrue);
        }
        final stock = actor.usageCheckpoint.stock.toJson();
        final sourceJson = source.action.toJson();
        final replayCard = actor.corruptionCards.singleWhere(
          (c) => c.identity == source.usageId,
        );
        if (concept == '002') expect(actor.isCardPlayable(replayCard), isFalse);
        await actor.proposeCorruption({
          replayCard.identity,
        }, CorruptionObjective.OWN_INITIAL_ACTION);
        await _settle();
        expect(actor.errorMessage, isNull);
        final offered = setup.bob.corruption!.actions.single.usage;
        expect(offered.toJson()['source_usage_id'], source.usageId);
        expect(
          offered.resolvedAction,
          actor.visibleDiscardUsages
              .singleWhere((u) => u.usageId == source.usageId)
              .resolvedAction,
        );
        expect(actor.usageCheckpoint.stock.toJson(), stock);
        final pendingReconnect = _controller(
          setup.backend,
          session,
          catalog,
          'alice',
          actor.privateStore,
        );
        await pendingReconnect.start();
        await _settle();
        expect(pendingReconnect.errorMessage, isNull);
        expect(pendingReconnect.usageCheckpoint.stock.toJson(), stock);
        expect(
          pendingReconnect.viewState,
          NetworkGameViewState.corruptionResponse,
        );
        pendingReconnect.dispose();
        await setup.bob.respondToCorruption(accepted: true);
        await _settle();
        expect(setup.backend.phase, NetworkGamePhase.finalResolved);
        final replay = actor.usageCheckpoint.usagesByIntent.values.singleWhere(
          (u) => u.sourceUsageId == source.usageId,
        );
        expect(replay.action.toJson(), sourceJson);
        expect(replay.usageId, isNot(source.usageId));
        expect(actor.usageCheckpoint.stock.toJson(), stock);
        expect(
          actor.corruptionCards.any(
            (c) => c.identity == source.usageId || c.identity == replay.usageId,
          ),
          isFalse,
        );
        final reconnected = _controller(
          setup.backend,
          session,
          catalog,
          'alice',
          actor.privateStore,
        );
        await reconnected.start();
        await _settle();
        expect(reconnected.errorMessage, isNull);
        expect(reconnected.usageCheckpoint.stock.toJson(), stock);
        expect(
          reconnected.usageCheckpoint.usageForIntent(replay.intentId)!.toJson(),
          replay.toJson(),
        );
        expect(
          reconnected.corruptionCards.any(
            (c) => c.identity == source.usageId || c.identity == replay.usageId,
          ),
          isFalse,
        );
        reconnected.dispose();
      },
    );
  }

  testWidgets('post duel choice disables only persisted refused mechanisms', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    for (final (negotiationRefused, corruptionRefused) in [
      (true, false),
      (false, true),
      (true, true),
    ]) {
      final backend = _Backend();
      backend.round
        ..phase = NetworkGamePhase.corruptionDecision
        ..finalResolution = NetworkFinalResolutionDto(
          retainedPlayerId: 'bob',
          initialWinnerPlayerId: 'bob',
          finalWinnerPlayerId: 'bob',
          cardId: '003',
          variantId: '003.stage.1',
        )
        ..negotiation = negotiationRefused
            ? NetworkNegotiationDto(
                response: NetworkNegotiationResponseDto(accepted: false),
              )
            : null
        ..corruption = corruptionRefused
            ? NetworkCorruptionDto(
                offeredBy: 'alice',
                objective: CorruptionObjective.OWN_INITIAL_ACTION,
                actions: const [],
                accepted: false,
              )
            : null;
      await tester.pumpWidget(
        MaterialApp(
          home: NetworkDuelScreen(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
            session: session,
            playerId: 'alice',
            repository: backend.repository('alice'),
            catalog: catalog,
            secretStore: MemoryNetworkDuelSecretStore(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
                .widget<FilledButton>(
                  find.byKey(const Key('choose-negotiation')),
                )
                .onPressed ==
            null,
        negotiationRefused,
      );
      expect(
        tester
                .widget<FilledButton>(
                  find.byKey(const Key('choose-corruption')),
                )
                .onPressed ==
            null,
        corruptionRefused,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const Key('accept-final-result')),
            )
            .onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });

  for (final compromiseFirst in [true, false]) {
    test(
      'post duel refuses both mechanisms in ${compromiseFirst ? 'compromise' : 'corruption'} first order and reconnects',
      () async {
        final setup = await _setupCorruption(session, catalog);
        addTearDown(setup.dispose);
        await _reachSecondResolved(setup, acceptSecond: false);
        setup.backend.round.phase = NetworkGamePhase.corruptionDecision;
        setup.backend.notify();
        await _settle();
        final actor = setup.alice;
        final partner = setup.bob;
        final original = setup.backend.round.finalResolution!.toJson();
        final points = Map<String, int>.of(setup.backend.points);
        final source = actor.corruptionCards.first.identity;
        Future<void> refuse(bool compromise) async {
          if (compromise) {
            await actor.proposeNegotiation(inversion: false, directPa: 10);
            await _settle();
            await partner.respondNegotiation(accepted: false);
          } else {
            await actor.proposeCorruption({
              source,
            }, CorruptionObjective.OWN_INITIAL_ACTION);
            await _settle();
            await partner.respondToCorruption(accepted: false);
          }
          await _settle();
          expect(actor.viewState, NetworkGameViewState.corruptionDecision);
          expect(setup.backend.points, points);
          expect(setup.backend.round.finalResolution!.toJson(), original);
        }

        await refuse(compromiseFirst);
        expect(actor.canAttemptNegotiation, !compromiseFirst);
        expect(actor.canAttemptCorruption, compromiseFirst);
        final reconnect = _controller(
          setup.backend,
          session,
          catalog,
          'alice',
          actor.privateStore,
        );
        await reconnect.start();
        await _settle();
        expect(reconnect.canAttemptNegotiation, !compromiseFirst);
        expect(reconnect.canAttemptCorruption, compromiseFirst);
        reconnect.dispose();
        await refuse(!compromiseFirst);
        expect(actor.canAttemptNegotiation, isFalse);
        expect(actor.canAttemptCorruption, isFalse);
        await actor.proposeNegotiation(inversion: false, directPa: 10);
        await actor.proposeCorruption({
          source,
        }, CorruptionObjective.OWN_INITIAL_ACTION);
        expect(actor.viewState, NetworkGameViewState.corruptionDecision);
        await actor.skipCorruption();
        await _settle();
        expect(setup.backend.phase, NetworkGamePhase.finalResolved);
        expect(setup.backend.round.finalResolution!.toJson(), original);
        expect(setup.backend.points, points);
      },
    );
  }

  test(
    'corruption refusal is public, idempotent and leaves discard untouched',
    () async {
      final setup = await _setupCorruption(session, catalog);
      await _reachSecondResolved(setup, acceptSecond: false);
      setup.backend.round.phase = NetworkGamePhase.corruptionDecision;
      setup.backend.notify();
      await _settle();
      final actor = setup.alice.isCorruptionActor ? setup.alice : setup.bob;
      final partner = identical(actor, setup.alice) ? setup.bob : setup.alice;
      final card = actor.corruptionCards.single;
      expect(actor.playerId, 'alice');
      final source = actor.usageCheckpoint.usagesByIntent.values.singleWhere(
        (u) => u.conceptId == '006',
      );
      final sourceJson = source.toJson();
      expect(card.identity, source.usageId);
      final historical = (await actor.privateStore.loadGame(
        sessionId: session.id,
        playerId: actor.playerId,
      ))!.publicDiscards.singleWhere((r) => r.usageId == source.usageId);
      expect(source.action.variantId, '006.action');
      expect(source.action.zoneId, isNull);
      expect(
        source.action.effectiveChili,
        lessThanOrEqualTo(actor.round!.v4UnlockedSpice),
      );
      expect(actor.usageCheckpoint.stock.capacity['006'], 2);
      expect(actor.usageCheckpoint.stock.remainingFor('006'), 1);
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
        isNull,
      );
      expect(actor.usageCheckpoint.stock.remainingFor('006'), 1);
      expect(actor.usageCheckpoint.availableFor('006'), 1);
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
      expect(setup.backend.phase, NetworkGamePhase.corruptionDecision);
      expect(actor.viewState, NetworkGameViewState.corruptionDecision);
      expect(actor.canAttemptCorruption, isFalse);
      expect(actor.canAttemptNegotiation, isTrue);
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
      expect(actor.usageCheckpoint.availableFor('006'), 1);
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
      final controller = NetworkGameController(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
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
    final controller = NetworkGameController(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
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
      final controller = NetworkGameController(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
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
        (u) => u.conceptId == '006',
      );
      final sourceJson = source.toJson();
      expect(offered.identity, source.usageId);
      final historical = (await actor.privateStore.loadGame(
        sessionId: session.id,
        playerId: actor.playerId,
      ))!.publicDiscards.singleWhere((r) => r.usageId == source.usageId);
      expect(source.action.variantId, '006.action');
      expect(source.action.zoneId, isNull);
      expect(
        source.action.effectiveChili,
        lessThanOrEqualTo(actor.round!.v4UnlockedSpice),
      );
      expect(actor.usageCheckpoint.stock.capacity['006'], 2);
      expect(actor.usageCheckpoint.stock.remainingFor('006'), 1);
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
        isNull,
      );
      expect(actor.usageCheckpoint.stock.remainingFor('006'), 1);
      expect(actor.usageCheckpoint.availableFor('006'), 1);
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
      expect(actor.usageCheckpoint.stock.remainingFor('006'), 1);
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
      expect(actor.usageCheckpoint.stock.remainingFor(offered.id), quotaBefore);
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

      await setup.alice.applyResolvedContext(EngineSessionContext(
        mode: SessionMode.face_to_face, proximity: ProximityState.TOGETHER,
        chiliActive: setup.alice.activeSpice, chiliUnlocked: setup.alice.activeSpice,
        clothesByPlayer: setup.alice.clothingCounts,
        mediaCapabilitiesByPlayer: {
          for (final id in ['alice', 'bob']) id: MediaCapability.values.toSet(),
        }));
      final option = setup.alice.recoveryCards.firstWhere(
        (c) => c.nativeDirection == CardOccurrenceDirection.MUTUEL);
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

  for (final eligibleCount in [0, 1, 2, 3, 4, 5]) {
    testWidgets('Recovery visual choice shows up to four real cards from $eligibleCount eligible concepts', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final backend = _Backend()..canonicalSpiceOverride = 1;
      backend.points['alice'] = 10;
      backend.round.phase = NetworkGamePhase.recovery;
      final ids = ['012', '030', '037', '018', '019'].take(eligibleCount).toList();
      if (eligibleCount == 0) {
        ids.add('006');
        backend.clothingCounts.updateAll((_, _) => 0);
      }
      final data = _catalogWithCards(catalog, {for (final id in ids) 'card.v4.$id'});
      await tester.pumpWidget(MaterialApp(home: NetworkDuelScreen(
        anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
        session: session, playerId: 'alice', repository: backend.repository('alice'),
        catalog: data, v4Profile: completeConsentProfile('alice'),
        secretStore: MemoryNetworkDuelSecretStore())));
      await tester.pumpAndSettle();
      final selection = find.byKey(const Key('network-recovery'));
      expect(selection, findsOneWidget);
      final cards = find.descendant(of: selection, matching: find.byType(CardRenderer));
      expect(cards, findsNWidgets(eligibleCount > 4 ? 4 : eligibleCount));
      expect(find.descendant(of: selection, matching: find.text('FAIRE')), findsNothing);
      expect(find.descendant(of: selection, matching: find.text('RECEVOIR')), findsNothing);
      for (final renderer in tester.widgetList<CardRenderer>(cards)) {
        expect(renderer.showDirection, isFalse);
        expect(renderer.showPa, isFalse);
        expect(renderer.definition.direction, isNotNull);
        expect(ids, contains(renderer.definition.cardId));
        expect(find.byKey(Key('recover-with-${renderer.definition.cardId}')), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final direction in [CardOccurrenceDirection.FAIRE, CardOccurrenceDirection.RECEVOIR]) {
    testWidgets('Recovery visual selection preserves internal $direction and frozen action', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final backend = _Backend()..canonicalSpiceOverride = 1;
      backend.points['alice'] = 10;
      backend.round.phase = NetworkGamePhase.recovery;
      final store = MemoryNetworkDuelSecretStore();
      await store.saveGame(sessionId: session.id, playerId: 'alice',
        state: privateGameFixture(roundNumber: 1, cards: [
          CardRuntimeState(cardId: '012', zone: CardZone.HAND, nativeDirection: direction),
        ]));
      final data = _catalogWithCards(catalog, {'card.v4.012'});
      await tester.pumpWidget(MaterialApp(home: NetworkDuelScreen(
        anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
        session: session, playerId: 'alice', repository: backend.repository('alice'),
        catalog: data, v4Profile: completeConsentProfile('alice'), secretStore: store)));
      await tester.pumpAndSettle();
      final renderer = tester.widget<CardRenderer>(find.byKey(const Key('recovery-choice-card-012')));
      final shown = renderer.definition;
      expect(shown.direction, direction.name);
      expect(find.text(direction.name), findsNothing);
      final before = (await store.loadGame(sessionId: session.id, playerId: 'alice'))!;
      expect(before.cards.single.nativeDirection, direction);
      await tester.tap(find.byKey(const Key('recover-with-012')));
      await tester.pumpAndSettle();
      final proposal = backend.round.recoveries['alice']!;
      expect(proposal.source, RecoverySource.HAND);
      expect(proposal.usage.toJson()['native_direction'], direction.name);
      expect(proposal.usage.resolvedAction['direction'], direction.name);
      expect(proposal.usage.resolvedAction['variant_id'], shown.variantId);
      expect(proposal.usage.resolvedAction['action_text'], shown.action);
      expect(proposal.usage.resolvedAction['effective_chili'], shown.spice);
      expect(proposal.usage.resolvedAction['actor_player_ids'],
        [direction == CardOccurrenceDirection.FAIRE ? 'alice' : 'bob']);
      expect(proposal.usage.resolvedAction['target_player_ids'],
        [direction == CardOccurrenceDirection.FAIRE ? 'bob' : 'alice']);
      expect(proposal.gain, 0);
      expect(find.byKey(const Key('network-recovery-response')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('Recovery visual cards fit a small screen with enlarged text', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(320, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final backend = _Backend()..canonicalSpiceOverride = 4;
    backend.points['alice'] = 10;
    backend.round.phase = NetworkGamePhase.recovery;
    await tester.pumpWidget(MaterialApp(home: MediaQuery(
      data: const MediaQueryData(size: Size(320, 480), textScaler: TextScaler.linear(1.4)),
      child: NetworkDuelScreen(
        anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
        session: session, playerId: 'alice', repository: backend.repository('alice'),
        catalog: catalog, v4Profile: completeConsentProfile('alice'),
        secretStore: MemoryNetworkDuelSecretStore()))));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byKey(const Key('network-recovery')),
      matching: find.byType(CardRenderer)), findsNWidgets(4));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final reference in [1, 2, 3, 4]) {
    test('Recovery canonical spice P$reference survives stale private cache and reconnect', () async {
      final backend = _Backend()..canonicalSpiceOverride = reference;
      backend.points['alice'] = 10;
      backend.round.phase = NetworkGamePhase.recovery;
      final store = MemoryNetworkDuelSecretStore();
      final profile = completeConsentProfile('alice');
      NetworkGameController create() => NetworkGameController(
        anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
        session: session, playerId: 'alice', repository: backend.repository('alice'),
        privateStore: store, learningStore: MemoryNetworkProfileLearningStore(),
        v4Profile: profile, catalog: catalog,
        initialClothingCounts: const {'alice': 6, 'bob': 6});
      final first = create();
      await first.start();
      await _settle();
      expect(first.recoveryAvailable, isTrue);
      expect(first.recoveryReferenceSpice, reference);
      expect(first.recoveryCards, isNotEmpty);
      expect(first.recoveryCards.every((c) => c.chiliLevel >= reference && c.chiliLevel <= 4), isTrue);
      for (final card in first.recoveryCards.where((c) => c.identity == c.id)) {
        final expected = first.defaultAction(card.id, first.recoveryChoicesFor(card.id));
        expect(card.variant.id, expected!.choice.actionId,
          reason: 'HAND and CATALOG use the same deterministic default');
      }
      if (reference < 4) expect(first.recoveryCards.any((c) => c.chiliLevel > reference), isTrue);
      final signature = first.recoveryCards.map(occurrenceSignature).toList();
      first.dispose();
      final saved = (await store.loadGame(sessionId: session.id, playerId: 'alice'))!;
      final stale = saved.toJson()..['active_chili'] = 1;
      await store.saveGame(sessionId: session.id, playerId: 'alice',
        state: NetworkPrivateGameState.fromJson(stale));
      final resumed = create();
      addTearDown(resumed.dispose);
      await resumed.start();
      await _settle();
      expect(resumed.errorMessage, isNull);
      expect(resumed.recoveryReferenceSpice, reference);
      expect(resumed.recoveryCards.map(occurrenceSignature), signature);
      expect(resumed.round!.toJson()['v4_unlocked_spice'], reference);
    });
  }

  test('Recovery trigger uses progressed canonical spice rather than initial private spice', () async {
    final backend = _Backend()..canonicalSpiceOverride = 1;
    final controller = NetworkGameController(
      anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
      session: session, playerId: 'alice', repository: backend.repository('alice'),
      catalog: catalog, v4Profile: completeConsentProfile('alice'),
      privateStore: MemoryNetworkDuelSecretStore(),
      learningStore: MemoryNetworkProfileLearningStore());
    addTearDown(controller.dispose);
    await controller.start();
    await _settle();
    expect(controller.activeSpice, 1);
    backend.canonicalSpiceOverride = 3;
    backend.points['alice'] = 10;
    backend.round.phase = NetworkGamePhase.recovery;
    backend.notifyTwice();
    await _settle();
    expect(controller.viewState, NetworkGameViewState.recovery);
    expect(controller.recoveryReferenceSpice, 3);
    await controller.applyResolvedContext(EngineSessionContext(
      mode: SessionMode.face_to_face, proximity: ProximityState.TOGETHER,
      chiliActive: 1, chiliUnlocked: 1,
      clothesByPlayer: const {'alice': 6, 'bob': 6}));
    expect(controller.recoveryCards, isNotEmpty);
    expect(controller.recoveryCards.every((c) => c.chiliLevel >= 3), isTrue);
    expect(controller.recoveryReferenceSpice, 3);
  });

  test('Recovery canonical range preserves joint consent anatomy clothing and roles', () async {
    final backend = _Backend()..canonicalSpiceOverride = 1;
    backend.points['alice'] = 10;
    backend.round.phase = NetworkGamePhase.recovery;
    backend.clothingCounts.updateAll((_, _) => 0);
    final consent = _ConsentBackend();
    final profileA = completeConsentProfile('alice');
    final profileB = completeConsentProfile('bob');
    NetworkGameController create(String id, V4Profile profile) => NetworkGameController(
      anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.PENIS},
      session: session, playerId: id, repository: _ConsentRepository(backend, id, consent),
      catalog: catalog, v4Profile: profile, privateStore: MemoryNetworkDuelSecretStore(),
      learningStore: MemoryNetworkProfileLearningStore());
    final a = create('alice', profileA);
    final b = create('bob', profileB);
    addTearDown(() async { a.dispose(); b.dispose(); await consent.close(); });
    await a.start();
    await b.start();
    await a.synchronizeConsent();
    expect(a.recoveryChoicesFor('030'), isNotEmpty);
    expect(a.recoveryChoicesFor('022'), isEmpty);
    expect(a.recoveryChoicesFor('027'), isEmpty);
    expect(a.recoveryChoicesFor('006'), isEmpty);
    await b.applyStageVetoProfile(profileB.copyWith(stageVetoes: const [
      StageVeto(conceptId: '030', actionId: '*', role: ProfilePreferenceRole.general),
    ]));
    await a.synchronizeConsent();
    expect(a.recoveryChoicesFor('030'), isEmpty);
    expect(a.recoveryCards.any((c) => c.id == '030'), isFalse);
    expect(a.recoveryCards.every((c) => a.occurrenceAllowed(c.id, c.variant.id, c.nativeDirection.name)), isTrue);
  });

  test('Recovery canonical range does not resurrect consumed stages', () async {
    final backend = _Backend()..canonicalSpiceOverride = 3;
    backend.points['alice'] = 10;
    backend.round.phase = NetworkGamePhase.recovery;
    final store = MemoryNetworkDuelSecretStore();
    await store.saveGame(sessionId: session.id, playerId: 'alice',
      state: privateGameFixture(roundNumber: 1, cards: const [
        CardRuntimeState(cardId: '030', variantId: '030.stage.3',
          occurrenceId: 'used-030', nativeDirection: CardOccurrenceDirection.FAIRE,
          zone: CardZone.EXHAUSTED),
      ]));
    final controller = NetworkGameController(
      anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
      session: session, playerId: 'alice', repository: backend.repository('alice'),
      catalog: catalog, v4Profile: completeConsentProfile('alice'), privateStore: store,
      learningStore: MemoryNetworkProfileLearningStore());
    addTearDown(controller.dispose);
    await controller.start();
    expect(controller.stageConsumed('030', '030.stage.3'), isTrue);
    expect(controller.recoveryChoicesFor('030').map((o) => o.choice.actionId),
      isNot(contains('030.stage.3')));
    expect(controller.recoveryCards.singleWhere((c) => c.id == '030').variant.id, '030.stage.2');
  });

  test('Recovery filters frozen discard intensity below canonical floor without altering history', () async {
    final backend = _Backend()..canonicalSpiceOverride = 1;
    backend.points['alice'] = 10;
    backend.round.phase = NetworkGamePhase.recovery;
    final store = MemoryNetworkDuelSecretStore();
    final saved = privateGameFixture(roundNumber: 1, cards: const [
      CardRuntimeState(cardId: '006', variantId: '006.action',
        occurrenceId: 'used-006', nativeDirection: CardOccurrenceDirection.FAIRE,
        zone: CardZone.DISCARD),
    ]);
    await store.saveGame(sessionId: session.id, playerId: 'alice', state: saved);
    final controller = NetworkGameController(
      anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
      session: session, playerId: 'alice', repository: backend.repository('alice'),
      catalog: catalog, v4Profile: completeConsentProfile('alice'), privateStore: store,
      learningStore: MemoryNetworkProfileLearningStore());
    addTearDown(controller.dispose);
    await controller.start();
    await _settle();
    final source = controller.visibleDiscardUsages.singleWhere((u) => u.conceptId == '006');
    expect(controller.recoveryCards.any((c) => c.identity == source.usageId), isTrue);
    final checkpoint = controller.usageCheckpoint.encode();
    backend.canonicalSpiceOverride = 2;
    backend.notifyTwice();
    await _settle();
    expect(controller.recoveryCards.any((c) => c.id == '006'), isFalse);
    await controller.recoverWith(source.usageId);
    expect(backend.round.recoveries, isEmpty);
    expect(controller.usageCheckpoint.encode(), checkpoint);
    expect(controller.visibleDiscardUsages.singleWhere((u) => u.conceptId == '006').toJson(), source.toJson());
  });

  test('Recovery default stage agrees across hand, catalog, dialog choices and reservation', () async {
    final backend = _Backend()..canonicalSpiceOverride = 3;
    backend.points['alice'] = 10;
    backend.round.phase = NetworkGamePhase.recovery;
    final profile = completeConsentProfile('alice');
    Future<NetworkGameController> player(bool held) async {
      final store = MemoryNetworkDuelSecretStore();
      await store.saveGame(sessionId: session.id, playerId: 'alice',
        state: privateGameFixture(roundNumber: 1, activeChili: 1,
          cards: held ? const [CardRuntimeState(cardId: '030', zone: CardZone.HAND)] : const []));
      final controller = NetworkGameController(
        anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
        session: session, playerId: 'alice', repository: backend.repository('alice'),
        catalog: catalog, v4Profile: profile, privateStore: store,
        learningStore: MemoryNetworkProfileLearningStore());
      await controller.start();
      await _settle();
      return controller;
    }
    final held = await player(true);
    final outside = await player(false);
    addTearDown(held.dispose);
    addTearDown(outside.dispose);
    for (final controller in [held, outside]) {
      final card = controller.recoveryCards.singleWhere((c) => c.id == '030');
      expect(card.variant.id, '030.stage.3');
      expect(controller.defaultAction('030', controller.recoveryChoicesFor('030'))!.choice.actionId, card.variant.id);
    }
    await held.recoverWith('030');
    await _settle();
    final proposed = backend.round.recoveries['alice']!;
    expect(proposed.source, RecoverySource.HAND);
    expect(proposed.usage.resolvedAction['stage_id'], '030.stage.3');
    expect(proposed.usage.resolvedAction['effective_chili'], 4);
    expect(held.recoveryReferenceSpice, 3);
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
      final option = setup.alice.recoveryCards.firstWhere((c) => c.identity == c.id);
      expect(option.chiliLevel, greaterThanOrEqualTo(setup.alice.recoveryReferenceSpice!));
      final expectedGain = (option.personalValue * 1.5).ceil();
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
      expect(setup.backend.round.recoveryHistory.single.gain, expectedGain);
      expect(setup.backend.points['alice'], before + expectedGain);
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
      expect(setup.backend.points['alice'], before + expectedGain);
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
      expect(setup.backend.points['alice'], before + expectedGain);
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

Future<void> _showResolutionControl(WidgetTester tester, String key) async {
  await tester.scrollUntilVisible(
    find.byKey(Key(key)),
    200,
    scrollable: find.descendant(
      of: find.byKey(const Key('network-action-in-progress')),
      matching: find.byType(Scrollable),
    ).first,
  );
  await tester.pumpAndSettle();
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

class _FailOnceCardRatings implements V4CardLearningStore {
  final delegate = MemoryV4CardLearningStore();
  bool failNext = false;
  @override
  Future<CardSpecificLearningStore> load(String id) => delegate.load(id);
  @override
  Future<void> save(String id, CardSpecificLearningStore state) async {
    if (failNext) {
      failNext = false;
      throw StateError('simulated profile write failure');
    }
    await delegate.save(id, state);
  }
}

NetworkGameController _controller(
  _Backend backend,
  LobbySession session,
  Catalog catalog,
  String playerId,
  NetworkDuelSecretStore store, {
  NetworkProfileLearningStore? learningStore,
}) => NetworkGameController(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
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
  String firstLifeConcept = '006',
  _ConsentBackend? consent,
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
          for (final id in [firstLifeConcept, '001', '012', '032'])
            CardRuntimeState(
              cardId: id,
              zone: CardZone.HAND,
              variantId: id == '002' ? '002.zone.feet' : null,
            ),
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
  NetworkGameController player(String id, int value) => NetworkGameController(anatomies: const {'alice': PlayerAnatomy.PENIS, 'bob': PlayerAnatomy.VULVE},
    session: session,
    playerId: id,
    repository: consent == null ? backend.repository(id) : _ConsentRepository(backend, id, consent),
    privateStore: stores[id]!,
    learningStore: learning ?? MemoryNetworkProfileLearningStore(),
    catalog: catalog,
    initialClothingCounts: const {'alice': 6, 'bob': 6},
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
    nonceFactory: consent == null ? () => 'nonce-$id-${backend.currentRound}' : null,
    clock: () => DateTime.utc(2026, 9, 30, 12, backend.currentRound),
  );
  final setup = _Setup(backend, player('alice', 8), player('bob', 12));
  await Future.wait([setup.alice.start(), setup.bob.start()]);
  if (consent != null) {
    addTearDown(consent.close);
    await setup.alice.synchronizeConsent();
    await setup.bob.synchronizeConsent();
  }
  await _settle();
  return setup;
}

Future<void> _reachSecondResolved(
  _Setup setup, {
  bool acceptSecond = true,
}) async {
  await _playUnequal(setup, forceAliceCard: '006', requireRepeatable: true);
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
  if (acceptSecond) await secondLoser.skipCorruption();
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
  var result = const V4PersistentEffectEngine().beginTurnClose(active);
  for (final card in cards) {
    final duration = card.cardId == '042' ? 3 : card.parameters['duration_actions'] as int?;
    result = const V4PersistentEffectEngine().closeAction(
      activeBeforeAction: result,
      producedEffects: duration != null
          ? const V4PersistentEffectEngine().createForAction(
              cardId: card.cardId,
              targetPlayerIds: const {'033', '061'}.contains(card.cardId)
                ? (card.usage.resolvedAction['actor_player_ids'] as List).cast<String>() : card.targetPlayerIds,
              durationActions: duration,
              unit: card.cardId == '042' ? 'turns' : 'actions',
              stageId: card.usage.resolvedAction['stage_id'] as String?,
              actorPlayerIds: (card.usage.resolvedAction['actor_player_ids'] as List).cast<String>(),
              actionText: card.usage.resolvedAction['action_text'] as String?,
              instruction: card.parameters['persistent_instruction'] as String?,
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
  final recoveryClothingConfirmations = <String, Set<String>>{};
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
  // Explicit canonical DTO fixture for the P1..P4 Recovery contract tests.
  int? canonicalSpiceOverride;
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
    if (canonicalSpiceOverride == null) {
      refreshPaSpice();
    } else {
      v4UnlockedSpice = canonicalSpiceOverride!;
    }
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
      recoveryClothingConfirmations: recoveryClothingConfirmations,
      initialDuelCards: round.initial == null ? const [] : [for (final reveal in round.reveals.values) if (round.phase != NetworkGamePhase.tieDecision || reveal.playerId == player) NetworkUsageProjection.fromJson({...reveal.choice.usage!.toJson()}..remove('snapshot_value')..remove('inverted_resolution'))],
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
        NetworkSessionClosureRepository,
        NetworkRecoveryClothingRepository {
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
      final retainedCards = offer.cards.isEmpty ? previous.compromise : offer.cards;
      backend.round.finalResolution = NetworkFinalResolutionDto(
        retainedPlayerId: retainedCards.first.ownerPlayerId,
        initialWinnerPlayerId: previous.initialWinnerPlayerId,
        finalWinnerPlayerId: previous.finalWinnerPlayerId,
        cardId: retainedCards.first.cardId,
        variantId: retainedCards.first.variantId,
        inverted: offer.inversionRequested,
        compromise: retainedCards,
      );
    }
    backend.round.phase = response.accepted
        ? NetworkGamePhase.finalResolved
        : NetworkGamePhase.corruptionDecision;
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
      backend.round.phase = NetworkGamePhase.corruptionDecision;
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
  Future<NetworkGameRoundStateDto> confirmRecoveryClothing({
    required NetworkCommandDto command, required String usageId, required int clothingCount,
  }) async {
    if (backend.commands.contains(command.commandId)) return backend.state(player);
    final proposal = backend.round.recoveries.values.singleWhere((r) => r.usage.usageId == usageId);
    final required = NetworkResolvedActionCardDto.fromUsage(proposal.usage).clothingPlayerIds;
    if (backend.phase != NetworkGamePhase.recoveryExecution || !required.contains(player)) {
      throw const NetworkRoundException('ROUND_CLOTHING_ACTOR_REQUIRED');
    }
    backend.commands.add(command.commandId);
    backend.recoveryClothingConfirmations.putIfAbsent(usageId, () => {}).add(player);
    backend.clothingCounts[player] = clothingCount;
    _notify(); return backend.state(player);
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

final class _OfflineRepository extends _Repository {
  _OfflineRepository(super.backend, super.player);
  bool offline = false;
  bool recordBeforeFailure = false;
  int commitAttempts = 0;
  int readCount = 0;
  int watchCount = 0;
  Completer<void>? readGate;
  bool loseRevealResponse = false;
  int revealAttempts = 0;

  @override
  Future<NetworkGameRoundStateDto> submitReveal({required NetworkCommandDto command, required ChoiceRevealDto reveal}) async {
    revealAttempts++;
    final result = await super.submitReveal(command: command, reveal: reveal);
    if (loseRevealResponse) {
      loseRevealResponse = false;
      throw StateError('lost reveal response');
    }
    return result;
  }

  @override
  Stream<NetworkGameRoundStateDto> watchRound({required String sessionId, required String roundId}) {
    watchCount++;
    // A stream may remain open without delivering either data or an error.
    return Stream<NetworkGameRoundStateDto>.multi((_) {});
  }

  @override
  Future<NetworkGameRoundStateDto> getCurrentRound({required String sessionId}) async {
    readCount++;
    await readGate?.future;
    if (offline) throw StateError('offline read');
    return super.getCurrentRound(sessionId: sessionId);
  }

  @override
  Future<NetworkGameRoundStateDto> submitCommit({required NetworkCommandDto command, required ChoiceCommitmentDto commitment}) async {
    commitAttempts++;
    if (offline) {
      if (recordBeforeFailure) await super.submitCommit(command: command, commitment: commitment);
      throw StateError('offline commit or lost response');
    }
    return super.submitCommit(command: command, commitment: commitment);
  }
}

final class _ConsentBackend {
  final contributions = <String, Set<String>>{};
  final commands = <String, String>{};
  int revision = 0;
  bool offline = false;
  bool emitEvents = true;
  final events = StreamController<int>.broadcast();
  Future<void> close() => events.close();
  int watchCount = 0;
  SessionConsentState read(String player) {
    if (offline) throw StateError('simulated offline consent transport');
    return SessionConsentState(revision: revision, ready: contributions.length == 2,
      allowed: contributions.length != 2 ? <String>{} :
        contributions.values.first.intersection(contributions.values.last)
          .where((key) => key.startsWith('$player/')));
  }
}

final class _ConsentRepository extends _Repository implements NetworkSessionConsentRepository, NetworkSessionConsentEvents {
  _ConsentRepository(super.backend, super.player, this.consent);
  final _ConsentBackend consent;
  @override
  Stream<int> watchSessionConsent(String sessionId) {
    consent.watchCount++;
    return consent.events.stream;
  }
  @override
  Future<SessionConsentState> getSessionConsent(String sessionId) async => consent.read(player);
  @override
  Future<SessionConsentState> publishSessionConsent({required String sessionId,
    required Set<String> allowed, required String commandId}) async {
    if (consent.offline) throw StateError('simulated offline consent transport');
    final payload = '$player/${(allowed.toList()..sort()).join(',')}';
    final previous = consent.commands[commandId];
    if (previous != null && previous != payload) throw StateError('command conflict');
    if (previous == null) {
      consent.commands[commandId] = payload;
      if (!setEquals(consent.contributions[player], allowed)) {
        consent.contributions[player] = Set.of(allowed);
        consent.revision++;
        if (consent.emitEvents) consent.events.add(consent.revision);
      }
    }
    return consent.read(player);
  }
}

final class _InterruptedRepository extends _Repository {
  _InterruptedRepository(super.backend, super.player);
  StreamController<NetworkGameRoundStateDto> updates = StreamController.broadcast();
  int watchCount = 0;
  @override
  Stream<NetworkGameRoundStateDto> watchRound({required String sessionId, required String roundId}) {
    watchCount++;
    if (updates.isClosed) updates = StreamController.broadcast();
    return updates.stream;
  }
  Future<void> close() => updates.close();
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
        V4PlayerSessionSetupDto(anatomy: PlayerAnatomy.PENIS,
          playerId: id,
          clothingCount: 2,
          accessories: const [],
        ),
    ],
  );
  @override
  Future<V4SessionSetupDto> getV4SessionSetup(String sessionId) async => setup;
  @override
  Future<V4SessionSetupDto> registerSetupAccessories({
    required PlayerAnatomy anatomy,
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

final class _ControlledSecretStore implements NetworkDuelSecretStore {
  final delegate = MemoryNetworkDuelSecretStore();
  Completer<void>? hold;
  final saveStarted = Completer<void>();
  int clearCalls = 0;
  bool failClearOnce = false;
  @override
  Future<void> saveGame({required String sessionId, required String playerId, required NetworkPrivateGameState state}) async {
    if (hold != null) {
      if (!saveStarted.isCompleted) saveStarted.complete();
      await hold!.future;
    }
    await delegate.saveGame(sessionId: sessionId, playerId: playerId, state: state);
  }
  @override
  Future<NetworkPrivateGameState?> loadGame({required String sessionId, required String playerId}) => delegate.loadGame(sessionId: sessionId, playerId: playerId);
  @override
  Future<void> clearGame({required String sessionId, required String playerId}) async {
    clearCalls++;
    if (failClearOnce) { failClearOnce = false; throw StateError('simulated local erase failure'); }
    await delegate.clearGame(sessionId: sessionId, playerId: playerId);
  }
  @override
  Future<void> save({required String sessionId, required String playerId, required ChoiceRevealDto reveal}) => delegate.save(sessionId: sessionId, playerId: playerId, reveal: reveal);
  @override
  Future<ChoiceRevealDto?> load({required String sessionId, required String playerId}) => delegate.load(sessionId: sessionId, playerId: playerId);
  @override
  Future<void> clear({required String sessionId, required String playerId}) => delegate.clear(sessionId: sessionId, playerId: playerId);
}

final class _DeferredHistoryStore implements GameHistoryStore {
  final release = Completer<void>();
  int calls = 0;
  @override
  Future<void> add(GameHistoryEntry entry) async { calls++; await release.future; }
  @override
  Future<List<GameHistoryEntry>> load() async => [];
}
final class _ExitObserver extends NavigatorObserver {
  int pops = 0;
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) { pops++; }
}
final class _HangingConsentRepository extends _Repository implements NetworkSessionConsentRepository, NetworkSessionConsentEvents {
  _HangingConsentRepository(super.backend, super.player) {
    events = StreamController<int>(onCancel: () => cancel.future);
  }
  final cancel = Completer<void>();
  late final StreamController<int> events;
  void disposeEvents() { unawaited(events.close()); }
  @override
  Stream<int> watchSessionConsent(String sessionId) => events.stream;
  @override
  Future<SessionConsentState> getSessionConsent(String sessionId) async => SessionConsentState(revision: 1, ready: false, allowed: const []);
  @override
  Future<SessionConsentState> publishSessionConsent({required String sessionId, required Set<String> allowed, required String commandId}) => getSessionConsent(sessionId);
}
