import '../support/native_action_fixtures.dart';
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:couple_cards/domain/game/game_models.dart';

import 'package:couple_cards/domain/profile/v4_profile.dart';
import 'package:couple_cards/engines/runtime/v4_runtime_engine.dart';
import 'package:couple_cards/features/lobby/lobby_models.dart';
import 'package:couple_cards/features/lobby/v4_session_setup_screen.dart';
import 'package:couple_cards/sync/rounds/network_game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('profile accessory persists exact tags and FAIRE RECEVOIR SOI', () {
    final accessory = V4ProfileAccessory(
      id: 'accessory.alice.1',
      name: 'Test',
      ownerProfileId: 'alice',
      tags: const {'ANAL', 'VIBRANT'},
      preferences: const {
        ProfilePreferenceRole.faire: 7,
        ProfilePreferenceRole.recevoir: null,
        ProfilePreferenceRole.soi: 12,
      },
    );
    final restored = V4ProfileAccessory.fromJson(accessory.toJson());
    expect(restored.tags, {'ANAL', 'VIBRANT'});
    expect(restored.preferences[ProfilePreferenceRole.faire], 7);
    expect(restored.preferences[ProfilePreferenceRole.recevoir], isNull);
    expect(restored.preferences[ProfilePreferenceRole.soi], 12);
  });

  test('missing accessory directional values default to 18', () {
    final accessory = V4ProfileAccessory(
      id: 'accessory.alice.2',
      name: 'Inconnu',
      ownerProfileId: 'alice',
      tags: const {'EXTERNE'},
    );
    expect(accessory.preferences.values, everyElement(18));
  });

  test('accessory preferences inherit only from the exact tag set', () {
    final profile = V4Profile(
      profileId: 'alice',
      preferences: const {},
      accessories: [
        V4ProfileAccessory(
          id: 'a',
          name: 'A',
          ownerProfileId: 'alice',
          tags: const {'ANAL'},
          preferences: const {ProfilePreferenceRole.faire: 6},
        ),
      ],
    );
    expect(
      profile.accessoryPreferencesForExactTags(const {
        'ANAL',
      })[ProfilePreferenceRole.faire],
      6,
    );
    expect(
      profile.accessoryPreferencesForExactTags(const {
        'ANAL',
        'VIBRANT',
      })[ProfilePreferenceRole.faire],
      18,
    );
  });

  test('session setup combines both profile and temporary accessories', () {
    final setup = V4SessionSetupDto(
      mode: V4SessionMode.hybrid,
      style: PlayerStyle.EPICE,
      status: 'ACCEPTED',
      players: [
        V4PlayerSessionSetupDto(
          playerId: 'alice',
          clothingCount: 0,
          accessories: [
            V4Accessory(
              id: 'a',
              name: 'A',
              ownerPlayerId: 'alice',
              tags: const {V4AccessoryTag.externe},
            ),
          ],
        ),
        V4PlayerSessionSetupDto(
          playerId: 'bob',
          clothingCount: 4,
          accessories: [
            V4Accessory(
              id: 'temp',
              name: 'Temporaire',
              ownerPlayerId: 'bob',
              tags: const {V4AccessoryTag.vibrant},
              temporary: true,
            ),
          ],
        ),
      ],
    );
    final restored = V4SessionSetupDto.fromJson({
      'mode': setup.mode!.name,
      'style': setup.style!.name,
      'status': setup.status,
      'players': [for (final player in setup.players) player.toJson()],
    });
    expect(restored.complete, isTrue);
    expect(restored.clothingCounts, {'alice': 0, 'bob': 4});
    expect(restored.accessories.map((item) => item.id), ['a', 'temp']);
    expect(restored.accessories.last.temporary, isTrue);
  });

  test('public action projection round-trips without PA or preferences', () {
    final projection = NetworkResolvedActionProjectionDto(
      cards: [
        resolvedActionFixture(
          conceptId: '006',
          usageId: 'usage-1',
          actionId: '006.action',
          direction: NetworkCardDirection.FAIRE,
          targetPlayerIds: const ['bob'],
          effectiveSpice: 2,
          zoneId: 'zone.torse',
          accessoryId: 'accessory.a',
          parameters: const {'zone_selection_source': 'game'},
        ),
      ],
      requiredClothingPlayerIds: const {'bob'},
    );
    final encoded = jsonEncode(projection.toJson());
    final restored = NetworkResolvedActionProjectionDto.fromJson(
      Map<String, Object?>.from(jsonDecode(encoded) as Map),
    );
    expect(restored.cards.single.targetPlayerIds, ['bob']);
    expect(restored.cards.single.zoneId, 'zone.torse');
    expect(restored.requiredClothingPlayerIds, {'bob'});
    expect(encoded, isNot(contains('personal_value')));
    expect(encoded, isNot(contains('preferences')));
    expect(encoded, isNot(contains('snapshot_value')));
  });

  test('normal action closes immediately without clothing resync', () {
    expect(
      const NetworkActionCompletionGate().canClose(
        projection: NetworkResolvedActionProjectionDto(
          cards: const [],
          requiredClothingPlayerIds: const {},
        ),
        resyncedPlayerIds: const {},
      ),
      isTrue,
    );
  });

  test('clothing action waits for the one required player', () {
    final projection = NetworkResolvedActionProjectionDto(
      cards: const [],
      requiredClothingPlayerIds: const {'alice'},
    );
    const gate = NetworkActionCompletionGate();
    expect(
      gate.canClose(projection: projection, resyncedPlayerIds: const {}),
      isFalse,
    );
    expect(
      gate.canClose(projection: projection, resyncedPlayerIds: const {'alice'}),
      isTrue,
    );
  });

  test('clothing action involving both waits for both values', () {
    final projection = NetworkResolvedActionProjectionDto(
      cards: const [],
      requiredClothingPlayerIds: const {'alice', 'bob'},
    );
    const gate = NetworkActionCompletionGate();
    expect(
      gate.canClose(projection: projection, resyncedPlayerIds: const {'alice'}),
      isFalse,
    );
    expect(
      gate.canClose(
        projection: projection,
        resyncedPlayerIds: const {'alice', 'bob'},
      ),
      isTrue,
    );
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final mode in V4SessionMode.values) {
    testWidgets('host configures ${mode.name} and explicitly selects style', (
      tester,
    ) async {
      final repo = _SetupRepository();
      addTearDown(repo.close);
      await tester.pumpWidget(
        MaterialApp(
          home: V4SessionSetupScreen(
            session: _session,
            playerId: 'alice',
            repository: repo,
            profile: null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.text(switch (mode) {
          V4SessionMode.presentiel => 'Présentiel',
          V4SessionMode.distance => 'Distance',
          V4SessionMode.hybrid => 'Hybride',
        }),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('setup-style-EPICE')));
      await tester.ensureVisible(
        find.byKey(const Key('initial-clothing-count')),
      );
      await tester.enterText(
        find.byKey(const Key('initial-clothing-count')),
        '0',
      );
      if (mode != V4SessionMode.distance) {
        await tester.ensureVisible(
          find.byKey(const Key('partner-clothing-count')),
        );
        await tester.enterText(
          find.byKey(const Key('partner-clothing-count')),
          '4',
        );
      } else {
        expect(find.byKey(const Key('partner-clothing-count')), findsNothing);
      }
      await tester.scrollUntilVisible(
        find.byKey(const Key('submit-v4-session-setup')).hitTestable(),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('submit-v4-session-setup')));
      await tester.pumpAndSettle();
      expect(repo.state.mode, mode);
      expect(repo.state.style, PlayerStyle.EPICE);
      expect(
        repo.proposedPlayers.length,
        mode == V4SessionMode.distance ? 1 : 2,
      );
      expect(repo.state.complete, isFalse);
    });
    testWidgets('partner ${mode.name} sees summary and validates', (
      tester,
    ) async {
      final repo = _SetupRepository()..state = _proposal(mode);
      addTearDown(repo.close);
      await tester.pumpWidget(
        MaterialApp(
          home: V4SessionSetupScreen(
            session: _session,
            playerId: 'bob',
            repository: repo,
            profile: null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('setup-style-EPICE')), findsNothing);
      if (mode == V4SessionMode.distance) {
        await tester.ensureVisible(
          find.byKey(const Key('initial-clothing-count')),
        );
        await tester.enterText(
          find.byKey(const Key('initial-clothing-count')),
          '3',
        );
      } else {
        expect(find.byType(TextField), findsNothing);
      }
      await tester.ensureVisible(
        find.byKey(const Key('accept-v4-session-setup')),
      );
      await tester.tap(find.byKey(const Key('accept-v4-session-setup')));
      await tester.pumpAndSettle();
      expect(repo.state.complete, isTrue);
      expect(
        repo.responseEnvironment?.clothingCount,
        mode == V4SessionMode.distance ? 3 : null,
      );
    });
  }
  testWidgets('refusal persists and host can revise without retyping', (
    tester,
  ) async {
    final repo = _SetupRepository()
      ..state = _proposal(V4SessionMode.presentiel);
    addTearDown(repo.close);
    await tester.pumpWidget(
      MaterialApp(
        home: V4SessionSetupScreen(
          session: _session,
          playerId: 'bob',
          repository: repo,
          profile: null,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('refuse-v4-session-setup')),
    );
    await tester.tap(find.byKey(const Key('refuse-v4-session-setup')));
    await tester.pumpAndSettle();
    expect(repo.state.status, 'REFUSED');
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.pumpWidget(
      MaterialApp(
        home: V4SessionSetupScreen(
          session: _session,
          playerId: 'alice',
          repository: repo,
          profile: null,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Configuration refusée'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('initial-clothing-count')))
          .controller!
          .text,
      '2',
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('submit-v4-session-setup')).hitTestable(),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('submit-v4-session-setup')));
    await tester.pumpAndSettle();
    expect(repo.state.status, 'PROPOSED');
    expect(repo.state.revision, 2);
    expect(repo.proposedPlayers.last.clothingCount, 4);
  });
  testWidgets('host assigns a temporary accessory to the partner environment', (
    tester,
  ) async {
    final repo = _SetupRepository();
    addTearDown(repo.close);
    await tester.pumpWidget(
      MaterialApp(
        home: V4SessionSetupScreen(
          session: _session,
          playerId: 'alice',
          repository: repo,
          profile: null,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('setup-style-SOFT')));
    await tester.ensureVisible(find.byKey(const Key('initial-clothing-count')));
    await tester.enterText(
      find.byKey(const Key('initial-clothing-count')),
      '2',
    );
    await tester.ensureVisible(find.byKey(const Key('partner-clothing-count')));
    await tester.enterText(
      find.byKey(const Key('partner-clothing-count')),
      '4',
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('add-partner-temporary-accessory')).hitTestable(),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('add-partner-temporary-accessory')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('temporary-accessory-name')),
      'Accessoire partagé',
    );
    await tester.tap(find.text('EXTERNE'));
    await tester.tap(find.text('Ajouter'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('submit-v4-session-setup')).hitTestable(),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('submit-v4-session-setup')));
    await tester.pumpAndSettle();
    final a = repo.proposedPlayers
        .singleWhere((p) => p.playerId == 'bob')
        .accessories
        .single;
    expect(a.ownerPlayerId, 'bob');
    expect(a.temporary, isTrue);
    expect(a.name, 'Accessoire partagé');
  });
  for (final id in ['alice', 'bob']) {
    testWidgets('accepted configuration automatically leaves setup for $id', (
      tester,
    ) async {
      final repo = _SetupRepository()
        ..state = _proposal(V4SessionMode.presentiel);
      addTearDown(repo.close);
      V4SessionSetupDto? completed;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                completed = await Navigator.of(context).push<V4SessionSetupDto>(
                  MaterialPageRoute(
                    builder: (_) => V4SessionSetupScreen(
                      session: _session,
                      playerId: id,
                      repository: repo,
                      profile: null,
                    ),
                  ),
                );
              },
              child: const Text('Ouvrir'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Ouvrir'));
      await tester.pumpAndSettle();
      if (id == 'alice') {
        await repo.respondSessionSetup(
          sessionId: 'session',
          revision: 1,
          accepted: true,
          commandId: 'peer-approval',
        );
      } else {
        await tester.ensureVisible(
          find.byKey(const Key('accept-v4-session-setup')),
        );
        await tester.tap(find.byKey(const Key('accept-v4-session-setup')));
      }
      await tester.pumpAndSettle();
      expect(completed?.complete, isTrue);
      expect(find.text('Ouvrir'), findsOneWidget);
    });
  }
  testWidgets('unsent setup draft survives screen reconnection', (
    tester,
  ) async {
    final repo = _SetupRepository();
    addTearDown(repo.close);
    Future<void> open() async {
      await tester.pumpWidget(
        MaterialApp(
          home: V4SessionSetupScreen(
            session: _session,
            playerId: 'alice',
            repository: repo,
            profile: null,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await open();
    await tester.tap(find.byKey(const Key('setup-style-INTENABLE')));
    await tester.ensureVisible(find.byKey(const Key('initial-clothing-count')));
    await tester.enterText(
      find.byKey(const Key('initial-clothing-count')),
      '7',
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await open();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('initial-clothing-count')))
          .controller!
          .text,
      '7',
    );
    await tester.ensureVisible(find.byKey(const Key('setup-style-INTENABLE')));
    expect(
      tester
          .widget<ListTile>(find.byKey(const Key('setup-style-INTENABLE')))
          .selected,
      isTrue,
    );
  });
}

final _session = LobbySession(
  id: 'session',
  joinCode: 'ABC123',
  status: LobbyStatus.ready,
  expiresAt: DateTime.utc(2030),
  players: const [
    LobbyPlayer(userId: 'alice', role: LobbyPlayerRole.player1),
    LobbyPlayer(userId: 'bob', role: LobbyPlayerRole.player2),
  ],
);
V4SessionSetupDto _proposal(V4SessionMode mode) => V4SessionSetupDto(
  mode: mode,
  style: PlayerStyle.EPICE,
  status: 'PROPOSED',
  revision: 1,
  players: [
    for (final id in ['alice', 'bob'])
      V4PlayerSessionSetupDto(
        playerId: id,
        clothingCount: id == 'alice' ? 2 : 4,
        accessories: const [],
      ),
  ],
);

final class _SetupRepository implements NetworkSessionSetupRepository {
  final updates = StreamController<V4SessionSetupDto>.broadcast();
  V4SessionSetupDto state = V4SessionSetupDto(
    mode: null,
    players: [
      for (final id in ['alice', 'bob'])
        V4PlayerSessionSetupDto(
          playerId: id,
          clothingCount: 0,
          environmentReady: false,
          accessories: const [],
        ),
    ],
  );
  List<V4PlayerSessionSetupDto> proposedPlayers = [];
  V4PlayerSessionSetupDto? responseEnvironment;
  Future<void> close() => updates.close();
  @override
  Future<V4SessionSetupDto> registerSetupAccessories({
    required String sessionId,
    required List<V4Accessory> accessories,
  }) async => state;
  @override
  Future<V4SessionSetupDto> getV4SessionSetup(String sessionId) async => state;
  @override
  Stream<V4SessionSetupDto> watchV4SessionSetup(String sessionId) =>
      updates.stream;
  @override
  Future<V4SessionSetupDto> proposeSessionSetup({
    required String sessionId,
    required V4SessionMode mode,
    required PlayerStyle style,
    required List<V4PlayerSessionSetupDto> players,
    required int expectedRevision,
    required String commandId,
  }) async {
    proposedPlayers = players;
    state = V4SessionSetupDto(
      mode: mode,
      style: style,
      status: 'PROPOSED',
      revision: expectedRevision + 1,
      players: [
        for (final old in state.players)
          players.where((p) => p.playerId == old.playerId).firstOrNull ?? old,
      ],
    );
    updates.add(state);
    return state;
  }

  @override
  Future<V4SessionSetupDto> respondSessionSetup({
    required String sessionId,
    required int revision,
    required bool accepted,
    V4PlayerSessionSetupDto? environment,
    required String commandId,
  }) async {
    responseEnvironment = environment;
    state = V4SessionSetupDto(
      mode: state.mode,
      style: state.style,
      status: accepted ? 'ACCEPTED' : 'REFUSED',
      revision: revision,
      players: [
        for (final p in state.players)
          environment?.playerId == p.playerId ? environment! : p,
      ],
    );
    updates.add(state);
    return state;
  }
}
