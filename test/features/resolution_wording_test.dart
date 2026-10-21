import 'package:couple_cards/features/game/ui/resolution_wording.dart';
import 'package:couple_cards/sync/sync.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/native_usage_fixture.dart';

void main() {
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
        'FAIRE' || 'GENERAL' => 'Sébastien réalise « Massage » pour Julie.',
        'RECEVOIR' => 'Julie réalise « Massage » pour Sébastien.',
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
      'Julie réalise « Massage » pour Sébastien.',
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
      'Tu réalises « Massage » pour ton partenaire.',
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
