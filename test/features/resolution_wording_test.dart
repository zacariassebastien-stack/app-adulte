import 'package:couple_cards/features/game/ui/resolution_wording.dart';
import 'package:couple_cards/sync/sync.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/native_usage_fixture.dart';

void main() {
  test(
    'persistent reminder uses real bearer and second person even with own nickname',
    () {
      const wording = ResolutionWording(
        localPlayerId: 'alice',
        names: {'alice': 'Sébastien', 'bob': 'Julie'},
      );
      expect(wording.reminder('alice'), 'Tu dois continuer cette action.');
      expect(wording.reminder('bob'), 'Julie doit continuer cette action.');
      expect(wording.participant('alice'), 'toi');
      expect(wording.participant('bob'), 'Julie');
      const fallback = ResolutionWording(
        localPlayerId: 'bob',
        names: {'alice': '  '},
      );
      expect(
        fallback.reminder('alice'),
        'Ton partenaire doit continuer cette action.',
      );
      expect(fallback.reminder('bob'), 'Tu dois continuer cette action.');
      expect(
        wording.silenceInstruction('alice', 3),
        startsWith(
          'Garde un silence complet pendant les 3 prochaines actions.',
        ),
      );
      expect(
        wording.silenceInstruction('bob', 2),
        startsWith(
          'Julie garde un silence complet pendant les 2 prochaines actions.',
        ),
      );
    },
  );

  for (final id in ['006', '007', '008', '009', '010', '033', '061']) {
    test('actor-centred $id never invents a recipient', () {
      final card = NetworkResolvedActionCardDto.fromUsage(
        nativeUsageFixture(conceptId: id),
      );
      const wording = ResolutionWording(
        localPlayerId: 'bob',
        names: {'alice': 'Zizi', 'bob': 'Zezette'},
      );
      expect(
        wording.describe(card, 'Retirer un vêtement'),
        'Zizi réalise « Retirer un vêtement ».',
      );
    });
  }
  test('hair pulling names the real target and its frozen activation duration', () {
    final base = nativeUsageFixture(conceptId: '063', direction: 'RECEVOIR');
    final card = NetworkResolvedActionCardDto.fromUsage(
      NetworkUsageProjection.fromJson({
        ...base.toJson(),
        'resolved_action': {
          ...base.resolvedAction,
          'parameters': {
            ...base.resolvedAction['parameters']! as Map<String, Object?>,
            'duration_actions': 3,
          },
        },
      }),
    );
    final frozen = card.toJson();
    expect(
      const ResolutionWording(
        localPlayerId: 'alice',
        names: {'alice': 'Zizi', 'bob': 'Zezette'},
      ).describe(card, 'Tirage des cheveux'),
      'Zezette réalise « Tirage des cheveux » sur Zizi pendant les 3 prochaines actions.',
    );
    expect(card.toJson(), frozen);
    expect(
      ResolutionWording.silenceDetails,
      'Ne parle pas et ne fais volontairement aucun bruit. Tu peux uniquement rompre le silence lorsqu’une décision de jeu nécessite de communiquer.',
    );
  });

  const names = {'alice': 'Sébastien', 'bob': 'Julie'};
  for (final direction in [
    'FAIRE',
    'RECEVOIR',
    'MUTUEL',
    'SOLO',
    'SIMULTANE',
    'GENERAL',
  ]) {
    test('wording describes canonical $direction independently of viewer', () {
      final json = Map<String, Object?>.from(
        nativeUsageFixture(direction: direction).toJson(),
      );
      json['resolved_action'] = Map<String, Object?>.from(
        json['resolved_action']! as Map,
      );
      if (direction == 'SIMULTANE') {
        (json['resolved_action']! as Map)['actor_player_ids'] = [
          'alice',
          'bob',
        ];
      }
      final card = NetworkResolvedActionCardDto.fromUsage(
        NetworkUsageProjection.fromJson(json),
      );
      final expected = switch (direction) {
        'FAIRE' || 'GENERAL' => 'Sébastien réalise « Massage » sur Julie.',
        'RECEVOIR' => 'Julie réalise « Massage » sur Sébastien.',
        'MUTUEL' => 'Sébastien et Julie réalisent « Massage » ensemble.',
        'SOLO' => 'Sébastien réalise « Massage » en solo.',
        _ =>
          'Sébastien et Julie réalisent « Massage » simultanément, chacun de son côté.',
      };
      for (final viewer in ['alice', 'bob']) {
        expect(
          ResolutionWording(
            localPlayerId: viewer,
            names: names,
          ).describe(card, 'Massage'),
          expected,
        );
      }
    });
  }

  test('inversion uses the resolved actors rather than the native role', () {
    final usage = nativeUsageFixture(
      direction: 'FAIRE',
    ).resolved(inverted: true);
    final card = NetworkResolvedActionCardDto.fromUsage(usage);
    expect(
      const ResolutionWording(
        localPlayerId: 'alice',
        names: names,
      ).describe(card, 'Massage'),
      'Julie réalise « Massage » sur Sébastien.',
    );
  });

  test('zone action names the actual target', () {
    final json = Map<String, Object?>.from(nativeUsageFixture().toJson());
    json['resolved_action'] = Map<String, Object?>.from(
      json['resolved_action']! as Map,
    );
    (json['resolved_action']! as Map)['zone_id'] = 'back';
    final card = NetworkResolvedActionCardDto.fromUsage(
      NetworkUsageProjection.fromJson(json),
    );
    expect(
      const ResolutionWording(
        localPlayerId: 'alice',
        names: names,
      ).describe(card, 'Massage'),
      'Sébastien réalise « Massage » sur Julie.',
    );
  });

  for (final id in ['044', '046']) {
    test('$id identifies subject without assigning the camera operator', () {
      final card = NetworkResolvedActionCardDto.fromUsage(
        nativeUsageFixture(conceptId: id, direction: 'RECEVOIR'),
      );
      expect(
        const ResolutionWording(
          localPlayerId: 'alice',
          names: names,
        ).describe(card, 'Capture'),
        'Julie est le sujet de « Capture » pour Sébastien. La personne qui tient l’appareil est libre.',
      );
    });
  }

  test('empty names fall back with correct French agreement', () {
    final wording = const ResolutionWording(
      localPlayerId: 'alice',
      names: {'alice': '  '},
    );
    expect(
      wording.describe(
        NetworkResolvedActionCardDto.fromUsage(nativeUsageFixture()),
        'Massage',
      ),
      'Tu réalises « Massage » sur ton partenaire.',
    );
    expect(
      wording.describe(
        NetworkResolvedActionCardDto.fromUsage(
          nativeUsageFixture(direction: 'MUTUEL'),
        ),
        'Action',
      ),
      'Toi et ton partenaire réalisez « Action » ensemble.',
    );
    expect(wording.retained('bob'), 'La carte de ton partenaire est retenue.');
  });
}
