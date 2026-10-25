import 'package:couple_cards/engines/runtime/v4_runtime_engine.dart';
import 'package:couple_cards/features/game/ui/persistent_effect_notice.dart';
import 'package:couple_cards/features/game/ui/resolution_wording.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final card in ['063', '061']) {
    for (final viewer in ['alice', 'bob']) {
      for (final remaining in [3, 2, 1]) {
        testWidgets('compact $card viewer=$viewer progress=${4 - remaining}/3', (
          tester,
        ) async {
          final effect = V4PersistentEffect(
            cardId: card,
            targetPlayerId: 'alice',
            remainingActions: remaining,
            actorPlayerIds: [card == '061' ? 'alice' : 'bob'],
            stageId: '$card.stage.1',
            actionText: 'Old full technical instruction',
            instruction: 'Old duplicate details',
          );
          final snapshot = effect.toJson();
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: PersistentEffectNotice(
                  effect: effect,
                  title: card == '061' ? 'Silence' : 'Tirage des cheveux',
                  duration: 3,
                  wording: ResolutionWording(
                    localPlayerId: viewer,
                    names: const {'alice': 'Zizi', 'bob': 'Zezette'},
                  ),
                ),
              ),
            ),
          );
          final expected = card == '061'
              ? viewer == 'alice'
                    ? 'Pendant cette action, garde le silence.'
                    : 'Pendant cette action, Zizi garde le silence.'
              : viewer == 'bob'
              ? 'Pendant cette action, continue « Tirage des cheveux ».'
              : 'Pendant cette action, tu es toujours sous l’effet de « Tirage des cheveux ».';
          expect(find.text('Effet actif'), findsOneWidget);
          expect(find.text(expected), findsOneWidget);
          expect(find.text('${4 - remaining}/3'), findsOneWidget);
          final displayed = tester
              .widgetList<Text>(find.byType(Text))
              .map((text) => text.data ?? '')
              .join(' ');
          expect(displayed, isNot(contains('stage')));
          expect(displayed, isNot(contains('Old')));
          expect(displayed, isNot(contains('Exécutant')));
          expect(effect.toJson(), snapshot);
          expect(tester.takeException(), isNull);
        });
      }
    }
    test(
      'effect $card disappears after exactly its three subsequent actions',
      () {
        const engine = V4PersistentEffectEngine();
        var active = engine.createForAction(
          cardId: card,
          targetPlayerIds: ['alice'],
          durationActions: 3,
        );
        final shown = <int>[];
        while (active.isNotEmpty) {
          shown.add(3 - active.single.remainingActions + 1);
          active = engine.closeAction(activeBeforeAction: active);
        }
        expect(shown, [1, 2, 3]);
        expect(active, isEmpty);
      },
    );
  }
  testWidgets(
    'turn effects retain turn wording and fallback without a nickname',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PersistentEffectNotice(
              effect: const V4PersistentEffect(
                cardId: '042',
                targetPlayerId: 'bob',
                remainingActions: 2,
                unit: 'turns',
              ),
              title: 'Sexting',
              duration: 3,
              wording: const ResolutionWording(localPlayerId: 'alice'),
            ),
          ),
        ),
      );
      expect(
        find.text(
          'Pendant ce tour, ton partenaire reste sous l’effet de « Sexting ».',
        ),
        findsOneWidget,
      );
      expect(find.text('2/3'), findsOneWidget);
    },
  );
}
