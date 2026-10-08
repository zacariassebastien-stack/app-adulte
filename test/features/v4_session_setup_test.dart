import 'dart:async';
import 'dart:convert';

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
        NetworkResolvedActionCardDto(
          occurrenceId: 'occ-1',
          cardId: 'card.006',
          variantId: 'variant.006',
          direction: NetworkCardDirection.FAIRE,
          targetPlayerIds: const ['bob'],
          effectiveSpice: 2,
          zoneId: 'zone.torse',
          accessoryId: 'accessory.a',
          parameters: const {'zone_selection_source': 'game'},
          effects: const [],
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

  testWidgets('setup requires a non-negative clothing count and accepts zero', (
    tester,
  ) async {
    final repository = _SetupRepository();
    addTearDown(repository.close);
    await tester.pumpWidget(
      MaterialApp(
        home: V4SessionSetupScreen(
          session: _session,
          playerId: 'alice',
          repository: repository,
          profile: null,
        ),
      ),
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('initial-clothing-count')),
      '-1',
    );
    await tester.tap(find.byKey(const Key('submit-v4-session-setup')));
    await tester.pump();
    expect(find.byKey(const Key('setup-error')), findsOneWidget);
    expect(repository.submittedCount, isNull);

    await tester.enterText(
      find.byKey(const Key('initial-clothing-count')),
      '0',
    );
    await tester.tap(find.text('HYBRID'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('submit-v4-session-setup')));
    await tester.pump();
    expect(repository.submittedCount, 0);
    expect(repository.submittedMode, V4SessionMode.hybrid);
    expect(find.text('En attente de ton partenaire…'), findsOneWidget);
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

final class _SetupRepository implements NetworkSessionSetupRepository {
  final updates = StreamController<V4SessionSetupDto>.broadcast();
  int? submittedCount;
  V4SessionMode? submittedMode;

  Future<void> close() => updates.close();

  V4SessionSetupDto get incomplete =>
      V4SessionSetupDto(mode: null, players: const []);

  @override
  Future<V4SessionSetupDto> getV4SessionSetup(String sessionId) async =>
      incomplete;

  @override
  Future<V4SessionSetupDto> submitV4SessionSetup({
    required String sessionId,
    required String playerId,
    required int clothingCount,
    required List<V4Accessory> accessories,
    V4SessionMode? mode,
  }) async {
    submittedCount = clothingCount;
    submittedMode = mode;
    return V4SessionSetupDto(
      mode: mode,
      players: [
        V4PlayerSessionSetupDto(
          playerId: playerId,
          clothingCount: clothingCount,
          accessories: accessories,
        ),
      ],
    );
  }

  @override
  Stream<V4SessionSetupDto> watchV4SessionSetup(String sessionId) =>
      updates.stream;
}
