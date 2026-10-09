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
  late V4ScoringCatalog scoringCatalog;
  late LobbySession session;

  setUpAll(() async {
    catalog = await const CatalogLoader().load(
      (path) => File(path).readAsString(),
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

  test('network DTO round-trips without private hand, lock or profile', () {
    final backend = _Backend()..cycleExhausted = true;
    final state = backend.state('alice');
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
    expect(state.cycleExhausted, isTrue);
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
          cards: const [
            NetworkCompromiseCardDto(
              occurrenceId: 'alice-auction-occurrence',
              cardId: 'card.v4.025',
              variantId: 'variant.v4.025.base',
              ownerPlayerId: 'alice',
              nativeDirection: NetworkCardDirection.FAIRE,
              effectiveDirection: NetworkCardDirection.FAIRE,
              origin: NetworkCompromiseOrigin.AUCTION,
              snapshotValue: 14,
            ),
          ],
        ),
      ),
      finalResolution: const NetworkFinalResolutionDto(
        retainedPlayerId: 'alice',
        compromise: [
          NetworkCompromiseCardDto(
            occurrenceId: 'alice-occurrence',
            cardId: 'card.v4.024',
            variantId: 'variant.v4.024.base',
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
        command: _command('close-alice', 'alice', 'READY_NEXT', backend.round.id),
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
      sessionMode: V4SessionMode.hybrid,
      presence: V4SessionPresence.distance,
      resolvedParameters: const {
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
    expect(decoded.history['card.hug'], CardHistoryState.seenUnplayed);
    expect(decoded.activeReveal!.nonce, 'private-nonce');
    expect(decoded.sessionMode, V4SessionMode.hybrid);
    expect(decoded.presence, V4SessionPresence.distance);
    expect(decoded.resolvedParameters['card.hug']!.accessoryId, 'temp-1');
    expect(decoded.persistentEffects.single.remainingActions, 2);
    expect(decoded.clothesByPlayer['alice'], 3);
    expect(decoded.accessoryPool.available.single.id, 'temp-1');
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
      setup.alice.selectCard(selected.identity);
      await setup.alice.confirmSelection();
      expect(
        setup.alice.runtime
            .singleWhere((card) => card.occurrenceId == selected.identity)
            .zone,
        CardZone.RESERVED,
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
    PlayerGameProfile profile({
      required bool allowFaire,
      required bool allowRecevoir,
    }) {
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
              faire: allowFaire ? 6 : null,
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
      privateProfile: profile(allowFaire: false, allowRecevoir: true),
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
      privateProfile: profile(allowFaire: true, allowRecevoir: false),
    );
    addTearDown(excluded.dispose);
    await excluded.start();
    expect(
      excluded.runtime.map((card) => card.nativeDirection),
      contains(CardOccurrenceDirection.FAIRE),
    );
    expect(
      excluded.runtime.map((card) => card.nativeDirection),
      isNot(contains(CardOccurrenceDirection.RECEVOIR)),
    );
  });

  test(
    'V4 exclusion keeps the opposite reversible direction eligible',
    () async {
      final directionalCatalog = _catalogWithCards(catalog, {'card.v4.002'});

      V4Profile profile({required ProfilePreferenceRole excludedRole}) {
        final preferences = <String, ProfilePreference>{};
        for (final role in const [
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
        return V4Profile(profileId: 'alice', preferences: preferences);
      }

      Future<CardOccurrenceDirection> drawnDirection(
        ProfilePreferenceRole excludedRole,
      ) async {
        final backend = _Backend();
        final controller = NetworkGameController(
          session: session,
          playerId: 'alice',
          repository: backend.repository('alice'),
          privateStore: MemoryNetworkDuelSecretStore(),
          learningStore: MemoryNetworkProfileLearningStore(),
          catalog: directionalCatalog,
          v4Profile: profile(excludedRole: excludedRole),
          scoringCatalog: scoringCatalog,
        );
        addTearDown(controller.dispose);
        await controller.start();
        return controller.runtime.single.nativeDirection;
      }

      expect(
        await drawnDirection(ProfilePreferenceRole.recevoir),
        CardOccurrenceDirection.FAIRE,
      );
      expect(
        await drawnDirection(ProfilePreferenceRole.faire),
        CardOccurrenceDirection.RECEVOIR,
      );
    },
  );

  test(
    'resolved V4 spice updates the network hand and guard prevents soft-lock',
    () async {
      final eligibleCards = catalog.cards
          .where(
            (card) => card.variants.any(
              (variant) =>
                  variant.chiliLevel == 1 &&
                  (variant.v4Stage == null || variant.v4Stage == 1) &&
                  (variant.v4RequiredAccessoriesAnyOf ??
                          card.v4?.requiredAccessoriesAnyOf ??
                          const <String>[])
                      .isEmpty &&
                  (variant.v4Presence ??
                          card.v4?.presence ??
                          V4PresenceCompatibility.presentiel)
                      .supports(V4SessionPresence.presentiel),
            ),
          )
          .take(6)
          .map((card) => card.stableId)
          .toSet();
      final focusedCatalog = _catalogWithCards(catalog, eligibleCards);
      final controller = NetworkGameController(
        session: session,
        playerId: 'alice',
        repository: _Backend().repository('alice'),
        privateStore: MemoryNetworkDuelSecretStore(),
        learningStore: MemoryNetworkProfileLearningStore(),
        catalog: focusedCatalog,
      );
      addTearDown(controller.dispose);
      await controller.start();
      final original = controller.hand.map((card) => card.identity).toList();
      expect(original, hasLength(4));

      for (final occurrenceId in original) {
        expect(
          await controller.resolveOccurrenceParameters(
            occurrenceId,
            zoneSelectionSource: V4ZoneSelectionSource.game,
            sexualOrIntimateZone: true,
            zoneId: 'zone.intime',
          ),
          isTrue,
        );
      }

      expect(controller.hand.where(controller.isCardPlayable), isNotEmpty);
      expect(
        original.where(
          (id) => controller.hand.any((card) => card.identity == id),
        ),
        hasLength(3),
      );
      expect(
        controller.hand
            .where((card) => original.contains(card.identity))
            .map((card) => card.chiliLevel),
        everyElement(2),
      );
    },
  );

  test(
    'production commit resolves effective spice and applies the hand guard',
    () async {
      final eligibleCards = catalog.cards
          .where(
            (card) => card.variants.any(
              (variant) =>
                  variant.chiliLevel == 1 &&
                  (variant.v4Stage == null || variant.v4Stage == 1) &&
                  (variant.v4RequiredAccessoriesAnyOf ??
                          card.v4?.requiredAccessoriesAnyOf ??
                          const <String>[])
                      .isEmpty &&
                  (variant.v4Presence ??
                          card.v4?.presence ??
                          V4PresenceCompatibility.presentiel)
                      .supports(V4SessionPresence.presentiel),
            ),
          )
          .take(6)
          .map((card) => card.stableId)
          .toSet();
      final focusedCatalog = _catalogWithCards(catalog, eligibleCards);
      final backend = _Backend();
      var resolutionCalls = 0;
      final controller = NetworkGameController(
        session: session,
        playerId: 'alice',
        repository: backend.repository('alice'),
        privateStore: MemoryNetworkDuelSecretStore(),
        learningStore: MemoryNetworkProfileLearningStore(),
        catalog: focusedCatalog,
        occurrenceParameterResolver: (card, current) {
          resolutionCalls++;
          return const V4ResolvedParameters(
            zoneSelectionSource: V4ZoneSelectionSource.game,
            sexualOrIntimateZone: true,
            zoneId: 'zone.intime',
          );
        },
      );
      addTearDown(controller.dispose);
      await controller.start();
      final selectedId = controller.hand.first.identity;
      controller.selectCard(selectedId);

      await controller.confirmSelection();

      expect(resolutionCalls, 1);
      expect(backend.round.commits, isEmpty);
      expect(controller.viewState, NetworkGameViewState.choosing);
      expect(controller.selectedCard, isNull);
      expect(controller.hand.where(controller.isCardPlayable), isNotEmpty);
      expect(
        controller.hand
            .where((card) => card.identity == selectedId)
            .map((card) => card.chiliLevel),
        everyElement(2),
      );
    },
  );

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

  test(
    'partner accessory uses local exact-tag PA and unknown tags default to 18',
    () async {
      final directionalCatalog = _catalogWithCards(catalog, {'card.v4.002'});

      V4Profile profileWithAccessory(V4ProfileAccessory accessory) {
        final faireKey = ProfilePreferenceKey(
          tagId: 'embrasser',
          role: ProfilePreferenceRole.faire,
        );
        final recevoirKey = ProfilePreferenceKey(
          tagId: 'embrasser',
          role: ProfilePreferenceRole.recevoir,
        );
        return V4Profile(
          profileId: 'alice',
          preferences: {
            faireKey.storageKey: ProfilePreference(
              profileId: 'alice',
              key: faireKey,
              pa: 6,
              excluded: false,
              source: ProfilePreferenceSource.initialQuestionnaire,
            ),
            recevoirKey.storageKey: ProfilePreference(
              profileId: 'alice',
              key: recevoirKey,
              pa: null,
              excluded: true,
              source: ProfilePreferenceSource.initialQuestionnaire,
            ),
          },
          accessories: [accessory],
        );
      }

      Future<int?> resolvedValue(V4ProfileAccessory preferenceSource) async {
        final controller = NetworkGameController(
          session: session,
          playerId: 'alice',
          repository: _Backend().repository('alice'),
          privateStore: MemoryNetworkDuelSecretStore(),
          learningStore: MemoryNetworkProfileLearningStore(),
          catalog: directionalCatalog,
          v4Profile: profileWithAccessory(preferenceSource),
          scoringCatalog: scoringCatalog,
          profileAccessories: [
            V4Accessory(
              id: 'bob-accessory',
              name: 'Accessoire de Bob',
              ownerPlayerId: 'bob',
              tags: const {V4AccessoryTag.anal, V4AccessoryTag.vibrant},
            ),
          ],
        );
        addTearDown(controller.dispose);
        await controller.start();
        expect(controller.sessionAccessories.single.ownerPlayerId, 'bob');
        final occurrenceId = controller.hand.single.identity;
        final resolved = await controller.resolveOccurrenceParameters(
          occurrenceId,
          requiredAccessoryTags: const {
            V4AccessoryTag.anal,
            V4AccessoryTag.vibrant,
          },
        );
        return resolved ? controller.hand.single.personalValue : null;
      }

      expect(
        await resolvedValue(
          V4ProfileAccessory(
            id: 'alice-exact-preference',
            name: 'Préférence exacte',
            ownerProfileId: 'alice',
            tags: const {'ANAL', 'VIBRANT'},
            preferences: const {ProfilePreferenceRole.faire: 4},
          ),
        ),
        5,
      );
      expect(
        await resolvedValue(
          V4ProfileAccessory(
            id: 'alice-other-preference',
            name: 'Préférence non correspondante',
            ownerProfileId: 'alice',
            tags: const {'ANAL'},
            preferences: const {ProfilePreferenceRole.faire: 4},
          ),
        ),
        12,
      );
      expect(
        await resolvedValue(
          V4ProfileAccessory(
            id: 'alice-excluded-preference',
            name: 'Préférence exclue',
            ownerProfileId: 'alice',
            tags: const {'ANAL', 'VIBRANT'},
            preferences: const {ProfilePreferenceRole.faire: null},
          ),
        ),
        isNull,
      );
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
      state: NetworkPrivateGameState(
        roundNumber: 1,
        cards: _handStates(focusedCatalog),
        history: const {},
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
      final store = MemoryNetworkDuelSecretStore();
      await store.saveGame(
        sessionId: session.id,
        playerId: 'alice',
        state: NetworkPrivateGameState(
          roundNumber: 1,
          cards: const [],
          history: const {},
          sessionMode: V4SessionMode.hybrid,
          presence: V4SessionPresence.distance,
        ),
      );
      final backend = _Backend();
      final controller = NetworkGameController(
        session: session,
        playerId: 'alice',
        repository: backend.repository('alice'),
        privateStore: store,
        learningStore: MemoryNetworkProfileLearningStore(),
        catalog: catalog,
        sessionMode: V4SessionMode.presentiel,
      );
      addTearDown(controller.dispose);

      await controller.start();

      expect(controller.sessionMode, V4SessionMode.presentiel);
      expect(controller.presence, V4SessionPresence.presentiel);
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
    final initialHand = _handStates(_catalogWithCards(catalog, presentCards));
    final initialIds = initialHand.map((card) => card.occurrenceId).toSet();
    final store = MemoryNetworkDuelSecretStore();
    await store.saveGame(
      sessionId: session.id,
      playerId: 'alice',
      state: NetworkPrivateGameState(
        roundNumber: 1,
        cards: initialHand,
        history: const {},
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

    expect(controller.presence, V4SessionPresence.distance);
    expect(
      controller.runtime
          .where((card) => card.zone == CardZone.HAND)
          .map((card) => card.occurrenceId),
      everyElement(isNot(isIn(initialIds))),
    );
    expect(controller.hand, hasLength(4));
    for (final card in controller.hand) {
      final definition = focusedCatalog.cards.singleWhere(
        (item) => item.stableId == card.id,
      );
      final variant = definition.variants.singleWhere(
        (item) => item.stableId == card.variant.id,
      );
      final presence =
          variant.v4Presence ??
          definition.v4?.presence ??
          V4PresenceCompatibility.presentiel;
      expect(presence.supports(V4SessionPresence.distance), isTrue);
    }
  });

  test('hybrid switch refills an underfull compatible hand to four', () async {
    final bothCards = _cardIdsForPresence(
      catalog,
      V4PresenceCompatibility.both,
    ).take(6).toSet();
    final focusedCatalog = _catalogWithCards(catalog, bothCards);
    final savedHand = _handStates(focusedCatalog).take(2).toList();
    final savedIds = savedHand.map((card) => card.occurrenceId).toSet();
    final store = MemoryNetworkDuelSecretStore();
    await store.saveGame(
      sessionId: session.id,
      playerId: 'alice',
      state: NetworkPrivateGameState(
        roundNumber: 1,
        cards: savedHand,
        history: const {},
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
    expect(controller.hand.map((card) => card.identity), containsAll(savedIds));
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
      ..hybridOrientation = HybridDeckOrientation.distance
      ..round.phase = NetworkGamePhase.finalResolved;
    final store = MemoryNetworkDuelSecretStore();
    await store.saveGame(
      sessionId: session.id,
      playerId: 'bob',
      state: NetworkPrivateGameState(
        roundNumber: 1,
        cards: _handStates(bobCatalog),
        history: const {},
        sessionMode: V4SessionMode.hybrid,
        presence: V4SessionPresence.distance,
      ),
    );
    final bob = NetworkGameController(
      session: session,
      playerId: 'bob',
      repository: backend.repository('bob'),
      privateStore: store,
      learningStore: MemoryNetworkProfileLearningStore(),
      catalog: bobCatalog,
      sessionMode: V4SessionMode.hybrid,
    );
    final alice = NetworkGameController(
      session: session,
      playerId: 'alice',
      repository: backend.repository('alice'),
      privateStore: MemoryNetworkDuelSecretStore(),
      learningStore: MemoryNetworkProfileLearningStore(),
      catalog: aliceCatalog,
      sessionMode: V4SessionMode.hybrid,
    );
    addTearDown(bob.dispose);
    addTearDown(alice.dispose);
    await bob.start();
    await alice.start();

    await alice.completeAction();
    await _settle();

    expect(backend.round.phase, NetworkGamePhase.finalResolved);
    expect(backend.round.ready, {'alice'});
    expect(backend.cycleExhausted, isFalse);

    await bob.completeAction();
    await _settle();

    expect(backend.round.phase, NetworkGamePhase.waitingNext);
    expect(backend.round.ready, {'alice', 'bob'});
    expect(backend.cycleExhausted, isTrue);
    expect(alice.mustSwitchHybridContext, isTrue);
    expect(alice.canStartNextRound, isFalse);
    await alice.switchOrientation(HybridDeckOrientation.faceToFace);
    await _settle();
    expect(backend.cycleExhausted, isFalse);
    expect(alice.hand, hasLength(4));
    expect(bob.hand, hasLength(4));
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
    'committed choice can be cancelled exactly once before reveal',
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
      await loser.acceptInitialResult();
      await _settle();
      final beforeReady = Map<String, int>.from(setup.alice.actionPoints);
      await setup.alice.completeAction();
      await _settle();
      expect(setup.alice.roundNumber, expected);
      expect(setup.alice.viewState, NetworkGameViewState.actionInProgress);
      expect(setup.bob.viewState, NetworkGameViewState.actionInProgress);
      await setup.bob.completeAction();
      await _settle();
      expect(setup.alice.viewState, NetworkGameViewState.waitingNext);
      expect(setup.bob.viewState, NetworkGameViewState.waitingNext);
      await _cycleController(setup).completeAction();
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
      final target = setup.alice.hand.firstWhere(setup.alice.isCardPlayable);
      setup.alice.toggleLock(target.identity);
      await _playUnequal(setup, forceAliceCard: target.identity);
      final loser = setup.alice.initialResolution!.loserPlayerId == 'alice'
          ? setup.alice
          : setup.bob;
      await loser.acceptInitialResult();
      await setup.alice.completeAction();
      await _settle();
      expect(setup.alice.history[target.id], CardHistoryState.seenUnplayed);
      await setup.bob.completeAction();
      await _settle();
      await _cycleController(setup).completeAction();
      await _settle();
      expect(setup.alice.lockedCardId, isNot(target.identity));
      expect(
        setup.alice.history[target.id],
        CardHistoryState.playedOrDiscarded,
      );
      expect(
        setup.alice.spiceProgression.consumedOccurrenceIds,
        contains(target.identity),
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

  test(
    'FINAL_RESOLVED learning survives duplicate events reconnect and Terminé once',
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
      await loser.acceptInitialResult();
      await _settle();

      expect(backend.phase, NetworkGamePhase.finalResolved);
      expect(aliceLearning.appliedEventIds['alice'], hasLength(1));
      final learnedOnce = jsonEncode(aliceLearning.values['alice']!.toJson());

      backend.notifyTwice();
      await _settle();
      expect(jsonEncode(aliceLearning.values['alice']!.toJson()), learnedOnce);

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
      expect(aliceLearning.appliedEventIds['alice'], hasLength(1));
      expect(jsonEncode(aliceLearning.values['alice']!.toJson()), learnedOnce);

      await alice.completeAction();
      await _settle();
      expect(aliceLearning.appliedEventIds['alice'], hasLength(1));
      expect(jsonEncode(aliceLearning.values['alice']!.toJson()), learnedOnce);
      alice.dispose();
      bob.dispose();
    },
  );

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
      final hasPlayableInvertibleWinner =
          [
            for (final a in setup.alice.hand.where(setup.alice.isCardPlayable))
              for (final b in setup.bob.hand.where(setup.bob.isCardPlayable))
                if (a.personalValue != b.personalValue)
                  (a.personalValue > b.personalValue ? a : b),
          ].any(
            (winner) =>
                winner.variant.invertible &&
                (winner.nativeDirection == CardOccurrenceDirection.FAIRE ||
                    winner.nativeDirection ==
                        CardOccurrenceDirection.RECEVOIR) &&
                winner.oppositePersonalValue != null,
          );
      if (!hasPlayableInvertibleWinner) {
        expect(
          catalog.cards.any(
            (card) => card.inversionPolicy == InversionPolicy.SWAP_ACTOR_TARGET,
          ),
          isTrue,
        );
        setup.dispose();
        return;
      }
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
            .map((card) => const CatalogEngineAdapter.v4().card(card))
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
      alice.selectCard(alice.hand.firstWhere(alice.isCardPlayable).identity);
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
      expect(alice.viewState, NetworkGameViewState.actionInProgress);
      await alice.completeAction();
      await bob.completeAction();
      await _settle();
      alice.dispose();
      alice = _controller(backend, session, catalog, 'alice', aliceStore);
      await alice.start();
      expect(alice.viewState, NetworkGameViewState.waitingNext);
      expect(backend.initialApplications, 1);
      await alice.completeAction();
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
    'reconnect after READY rebuilds the action from persisted V4 parameters',
    () async {
      final backend = _Backend();
      const parameters = V4ResolvedParameters(
        zoneSelectionSource: V4ZoneSelectionSource.game,
        sexualOrIntimateZone: true,
        zoneId: 'zone.intime',
        accessoryId: 'accessory.persisted',
      );
      backend.round
        ..phase = NetworkGamePhase.finalResolved
        ..finalResolution = NetworkFinalResolutionDto.fromJson(
          NetworkFinalResolutionDto(
            retainedPlayerId: 'bob',
            initialWinnerPlayerId: 'bob',
            finalWinnerPlayerId: 'bob',
            cardId: 'card.v4.024',
            variantId: 'variant.v4.024.base',
            compromise: const [
              NetworkCompromiseCardDto(
                occurrenceId: 'bob-occurrence',
                cardId: 'card.v4.024',
                variantId: 'variant.v4.024.base',
                ownerPlayerId: 'bob',
                nativeDirection: NetworkCardDirection.FAIRE,
                effectiveDirection: NetworkCardDirection.FAIRE,
                origin: NetworkCompromiseOrigin.INITIAL_DUEL,
                snapshotValue: 8,
                resolvedParameters: parameters,
                effectiveSpice: 4,
              ),
            ],
          ).toJson(),
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
      expect(projected.variantId, 'variant.v4.024.base');
      expect(projected.direction, NetworkCardDirection.FAIRE);
      expect(projected.targetPlayerIds, ['alice']);
      expect(projected.zoneId, 'zone.intime');
      expect(projected.accessoryId, 'accessory.persisted');
      expect(projected.effectiveSpice, 4);
      expect(projected.parameters, parameters.toJson());
      expect(backend.round.reveals, isEmpty);
      expect(controller.viewState, NetworkGameViewState.actionInProgress);
    },
  );

  test(
    'reconnect repairs missing V4 parameters from the validated reveal',
    () async {
      final backend = _Backend();
      const parameters = V4ResolvedParameters(
        zoneSelectionSource: V4ZoneSelectionSource.game,
        sexualOrIntimateZone: true,
        zoneId: 'zone.intime',
        accessoryId: 'accessory.repaired',
      );
      backend.round
        ..phase = NetworkGamePhase.finalResolved
        ..reveals['bob'] = ChoiceRevealDto(
          sessionRound: 'session-multi.round-1',
          playerId: 'bob',
          choice: ChoicePayload(
            cardId: 'card.v4.024',
            variantId: 'variant.v4.024.base',
            parameters: const {
              'occurrence_id': 'bob-occurrence',
              'role': 'FAIRE',
              'native_direction': 'FAIRE',
              'effective_direction': 'FAIRE',
              'resolved_parameters': {
                'zone_selection_source': 'game',
                'sexual_or_intimate_zone': true,
                'zone_id': 'zone.intime',
                'accessory_id': 'accessory.repaired',
              },
              'effective_spice': 4,
            },
          ),
          nonce: 'server-private-nonce',
        )
        ..finalResolution = const NetworkFinalResolutionDto(
          retainedPlayerId: 'bob',
          compromise: [
            NetworkCompromiseCardDto(
              occurrenceId: 'bob-occurrence',
              cardId: 'card.v4.024',
              variantId: 'variant.v4.024.base',
              ownerPlayerId: 'bob',
              nativeDirection: NetworkCardDirection.FAIRE,
              effectiveDirection: NetworkCardDirection.FAIRE,
              origin: NetworkCompromiseOrigin.INITIAL_DUEL,
              snapshotValue: 8,
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

      final repaired = backend.round.finalResolution!.compromise.single;
      expect(repaired.resolvedParameters, isNotNull);
      expect(repaired.resolvedParameters!.toJson(), parameters.toJson());
      expect(repaired.effectiveSpice, 4);
      expect(backend.state('alice').opponentReveal, isNull);
      expect(
        backend.round.actionProjection!.cards.single.zoneId,
        'zone.intime',
      );
      expect(controller.viewState, NetworkGameViewState.actionInProgress);
    },
  );

  test(
    'final action explicitly fails when persisted data is irreparable',
    () async {
      final backend = _Backend();
      backend.round
        ..phase = NetworkGamePhase.finalResolved
        ..finalResolution = const NetworkFinalResolutionDto(
          retainedPlayerId: 'bob',
          compromise: [
            NetworkCompromiseCardDto(
              occurrenceId: 'unknown-occurrence',
              cardId: 'card.v4.024',
              variantId: 'variant.v4.024.base',
              ownerPlayerId: 'bob',
              nativeDirection: NetworkCardDirection.FAIRE,
              effectiveDirection: NetworkCardDirection.FAIRE,
              origin: NetworkCompromiseOrigin.INITIAL_DUEL,
              snapshotValue: 8,
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

      expect(controller.errorMessage, 'ROUND_ACTION_PARAMETERS_MISSING');
      expect(backend.round.actionProjection, isNull);
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
        setup.backend.round.recoveryHistory.single.gain,
        (option.personalValue * 1.5).ceil(),
      );
      expect(
        setup.backend.points['alice'],
        before + (option.personalValue * 1.5).ceil(),
      );
      expect(setup.backend.round.recoveryHistory, hasLength(1));
      expect(setup.backend.round.recoveryDone, isNot(contains('alice')));

      final saved = (await setup.alice.privateStore.loadGame(
        sessionId: session.id,
        playerId: 'alice',
      ))!;
      final staleJson = saved.toJson();
      for (final raw in staleJson['cards']! as List) {
        final card = raw! as Map<String, Object?>;
        if (card['occurrence_id'] == option.identity) {
          card['zone'] =
              switch (setup.backend.round.recoveryHistory.single.source) {
                RecoverySource.HAND => CardZone.HAND.name,
                RecoverySource.DISCARD => CardZone.DISCARD.name,
                RecoverySource.CATALOG => card['zone'],
              };
        }
      }
      await setup.alice.privateStore.saveGame(
        sessionId: session.id,
        playerId: 'alice',
        state: NetworkPrivateGameState.fromJson(staleJson),
      );

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
      expect(
        alice.runtime
            .singleWhere((card) => card.occurrenceId == option.identity)
            .zone,
        setup.backend.round.recoveryHistory.single.source ==
                RecoverySource.DISCARD
            ? CardZone.EXHAUSTED
            : CardZone.DISCARD,
      );
      await alice.skipRecovery();
      await setup.bob.skipRecovery();
      await _settle();
      expect(setup.backend.phase, NetworkGamePhase.finalResolved);
      await alice.completeAction();
      await setup.bob.completeAction();
      await _settle();
      expect(setup.backend.phase, NetworkGamePhase.waitingNext);
      await alice.completeAction();
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
    for (final a in setup.alice.hand.where(setup.alice.isCardPlayable))
      for (final b in setup.bob.hand.where(setup.bob.isCardPlayable)) (a, b),
  ];
  final pair = pairs.firstWhere((pair) {
    final aWins = pair.$1.personalValue > pair.$2.personalValue;
    final winner = aWins ? pair.$1 : pair.$2;
    return pair.$1.personalValue != pair.$2.personalValue &&
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

Future<void> _chooseUnequalPartner(
  NetworkGameController bob,
  int opponentValue,
) async {
  final partner = bob.hand.firstWhere(
    (card) => bob.isCardPlayable(card) && card.personalValue != opponentValue,
  );
  bob.selectCard(partner.identity);
  await bob.confirmSelection();
}

Future<void> _reachSecondResolved(_Setup setup) async {
  await _playUnequal(setup);
  final firstLoser = setup.alice.isInitialLoser ? setup.alice : setup.bob;
  await firstLoser.acceptInitialResult();
  await _settle();
  await _completeResolvedAction(setup);
  await _cycleController(setup).completeAction();
  await _settle();
  await _playUnequal(setup);
  final secondLoser = setup.alice.isInitialLoser ? setup.alice : setup.bob;
  await secondLoser.acceptInitialResult();
  await _settle();
}

Future<void> _completeResolvedAction(_Setup setup) async {
  await setup.alice.completeAction();
  await _settle();
  await setup.bob.completeAction();
  await _settle();
}

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
  NetworkResolvedActionProjectionDto? actionProjection;
  NetworkCorruptionDto? corruption;
  final recoveries = <String, NetworkRecoveryDto>{};
  final recoveryHistory = <NetworkRecoveryDto>[];
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
  bool cycleExhausted = false;
  bool redactOpponentReveal = false;
  HybridDeckOrientation hybridOrientation = HybridDeckOrientation.faceToFace;

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
    hybridOrientation: hybridOrientation,
    cycleExhausted: cycleExhausted,
    actionProjection: round.actionProjection,
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
    corruption: round.corruption,
    recoveryByPlayer: round.recoveries,
    recoveryDonePlayerIds: round.recoveryDone,
    recoveryHistory: round.recoveryHistory,
  );

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
  Future<NetworkGameRoundStateDto> setHybridOrientation({
    required NetworkCommandDto command,
    required HybridDeckOrientation orientation,
  }) async {
    if (_accept(command)) {
      backend.hybridOrientation = orientation;
      backend.cycleExhausted = false;
      _notify();
    }
    return backend.state(player);
  }

  @override
  Future<NetworkGameRoundStateDto> continueDeckCycle({
    required NetworkCommandDto command,
    required DeckExhaustionChoice choice,
    Map<int, int> deckAdjustment = const {},
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
      backend.round.recoveryHistory.add(
        NetworkRecoveryDto(
          playerId: proposal.playerId,
          cardId: proposal.cardId,
          variantId: proposal.variantId,
          source: proposal.source,
          completed: false,
          gain: 0,
          response: response,
          occurrenceId: proposal.occurrenceId,
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
      backend.round.phase = NetworkGamePhase.finalResolved;
    }
    _notify();
    return backend.state(player);
  }

  @override
  Future<NetworkGameRoundStateDto> readyNextRound({
    required NetworkCommandDto command,
    bool noPlayableOccurrences = false,
    int? clothingCount,
  }) async {
    if (!_accept(command)) return backend.state(player);
    if (backend.phase != NetworkGamePhase.finalResolved &&
        backend.phase != NetworkGamePhase.waitingNext) {
      throw const NetworkRoundException('ROUND_INVALID_PHASE');
    }
    final closesBoundary = backend.round.phase == NetworkGamePhase.waitingNext;
    if (closesBoundary && backend.cycleExhausted) {
      throw const NetworkRoundException('ROUND_CYCLE_EXHAUSTED');
    }
    backend.cycleExhausted = backend.cycleExhausted || noPlayableOccurrences;
    backend.round.ready.add(player);
    if (!closesBoundary) {
      if (backend.round.ready.length == 2) {
        backend.round.phase = NetworkGamePhase.waitingNext;
      }
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
        : NetworkGamePhase.counterDecision;
    backend.initialApplications++;
    _notify();
    return backend.state(player);
  }
}
