import 'package:test/test.dart';
import 'dart:convert';
import 'package:couple_cards/engines/runtime/v4_runtime_engine.dart';
import 'package:couple_cards/sync/protocol/network_usage_projection.dart';
import '../support/native_usage_fixture.dart';

void main() {
  test('retired 060 public snapshots remain self-contained and readable', () {
    final json =
        jsonDecode(jsonEncode(nativeUsageFixture(conceptId: '060').toJson()))
            as Map<String, Object?>;
    final action = json['resolved_action']! as Map<String, Object?>;
    action.remove('stage_id');
    action['variant_id'] = '060.action';
    final inverse =
        (json['inverted_resolution']!
                as Map<String, Object?>)['resolved_action']!
            as Map<String, Object?>;
    inverse.remove('stage_id');
    inverse['variant_id'] = '060.action';
    final restored = NetworkUsageProjection.fromJson(json);
    expect(restored.conceptId, '060');
    expect(restored.toJson(), json);
    expect(restored.resolvedAction['action_text'], 'Frozen test action');
  });
  const engine = V4PersistentEffectEngine();
  for (final id in ['034', '062', '063']) {
    test(
      '$id retains stage executor target and frozen instruction after reload and ticks',
      () {
        var active = engine.createForAction(
          cardId: id,
          targetPlayerIds: ['bob'],
          durationActions: 3,
          stageId: '$id.stage.2',
          actorPlayerIds: ['alice'],
          actionText: 'Frozen stage 2',
          instruction: 'Keep holding',
        );
        for (var n = 3; n > 0; n--) {
          active = active
              .map((e) => V4PersistentEffect.fromJson(e.toJson()))
              .toList();
          expect(active.single.remainingActions, n);
          expect(active.single.stageId, '$id.stage.2');
          expect(active.single.actorPlayerIds, ['alice']);
          expect(active.single.targetPlayerId, 'bob');
          expect(active.single.instruction, 'Keep holding');
          active = engine.closeAction(activeBeforeAction: active);
        }
        expect(active, isEmpty);
      },
    );
  }
  test(
    'Sexting skips activation and ticks once per round regardless of action count',
    () {
      var active = engine.closeAction(
        activeBeforeAction: engine.beginTurnClose([]),
        producedEffects: engine.createForAction(
          cardId: '042',
          targetPlayerIds: ['alice', 'bob'],
          durationActions: 3,
          unit: 'turns',
        ),
      );
      active = engine.closeAction(activeBeforeAction: active);
      expect(active.map((e) => e.remainingActions), [3, 3]);
      for (var n = 2; n >= 0; n--) {
        active = active
            .map((e) => V4PersistentEffect.fromJson(e.toJson()))
            .toList();
        active = engine.beginTurnClose(active);
        active = engine.closeAction(activeBeforeAction: active);
        active = engine.closeAction(activeBeforeAction: active);
        if (n > 0) {
          expect(active.map((e) => e.remainingActions), [n, n]);
        } else {
          expect(active, isEmpty);
        }
      }
    },
  );
  test('legacy retired effects remain readable without metadata', () {
    final old = V4PersistentEffect.fromJson({
      'card_id': '060',
      'target_player_id': 'alice',
      'remaining_actions': 2,
    });
    expect(old.unit, 'actions');
    expect(
      engine.closeAction(activeBeforeAction: [old]).single.remainingActions,
      1,
    );
  });
}
