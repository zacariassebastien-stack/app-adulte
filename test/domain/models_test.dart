import 'dart:convert';
import 'dart:io';
import 'package:couple_cards/domain/domain.dart';
import 'package:test/test.dart';
import '../fixtures/catalog_fixture.dart';

void main() {
  test('all catalogue documents round-trip without losing fields or IDs', () {
    final f = fixture();
    card(f)['editorial_metadata'] = {
      'revision': 2,
      'notes': ['example'],
    };
    final c = loadFixture(f);
    expect(c.cardsDocument, f['cards']);
    expect(c.profilesDocument, f['profiles']);
    expect(c.tagsDocument, f['tags']);
    for (final c in c.cards) {
      expect(CardDefinition.fromJson(c.toJson()).toJson(), c.toJson());
      for (final v in c.variants) {
        expect(CardVariantDefinition.fromJson(v.toJson()).toJson(), v.toJson());
      }
      for (final p in c.parameters) {
        expect(
          CardParameterDefinition.fromJson(p.toJson()).toJson(),
          p.toJson(),
        );
      }
      for (final r in c.profileRequirements) {
        expect(ProfileRequirement.fromJson(r.toJson()).toJson(), r.toJson());
      }
    }
    for (final p in c.profileElements) {
      expect(
        ProfileElementDefinition.fromJson(p.toJson()).toJson(),
        p.toJson(),
      );
    }
    for (final t in c.tags) {
      expect(TagDefinition.fromJson(t.toJson()).toJson(), t.toJson());
    }
  });
  test('changing translation has no effect on identity', () {
    final f = fixture();
    final before = loadFixture(f);
    card(f)['title'] = 'Draw together';
    card(f)['title_key'] = 'renamed.translation.key';
    final after = loadFixture(f);
    expect(after.cards.single.stableId, before.cards.single.stableId);
    expect(
      after.cards.single.variants.single.stableId,
      before.cards.single.variants.single.stableId,
    );
  });
  test(
    'models deeply freeze input, nested lists, and serialization output',
    () {
      final f = fixture();
      final c = CardDefinition.fromJson(card(f));
      card(f)['stable_id'] = 'changed';
      (variant(f)['technical_requirements']! as List<Object?>).clear();
      expect(c.stableId, 'card.draw');
      expect(c.variants.single.technicalRequirements.length, 1);
      expect(() => c.variants.clear(), throwsUnsupportedError);
      expect(() => c.toJson()['stable_id'] = 'changed', throwsUnsupportedError);
      expect(
        () => (c.toJson()['variants']! as List<Object?>).clear(),
        throwsUnsupportedError,
      );
      expect(() => c.parameters.single.values.add(1), throwsUnsupportedError);
    },
  );
  test('private preferences and immutable snapshot round-trip exactly', () {
    final p = UserPreference.fromJson(preferenceJson());
    final o = CardPreferenceOverride.fromJson(overrideJson());
    final s = CombatValueSnapshot.fromJson(snapshotJson());
    expect(p.toJson(), preferenceJson());
    expect(o.toJson(), overrideJson());
    expect(s.toJson(), snapshotJson());
    expect(
      UserPreference.fromJson(
        jsonDecode(jsonEncode(p.toJson())) as JsonMap,
      ).toJson(),
      p.toJson(),
    );
    expect(CardPreferenceOverride.fromJson(o.toJson()).toJson(), o.toJson());
    expect(CombatValueSnapshot.fromJson(s.toJson()).toJson(), s.toJson());
    expect(() => s.toJson()['personal_value'] = 1, throwsUnsupportedError);
    expect(s.personalValue, 14);
  });
  for (final bad in <Object?>[0, 21, '10', 1.1]) {
    test('reject private ratings outside 1..20 or wrong type: $bad', () {
      expect(
        () =>
            UserPreference.fromJson(preferenceJson()..['general_value'] = bad),
        throwsA(isA<CatalogException>()),
      );
      expect(
        () => CardPreferenceOverride.fromJson(
          overrideJson()..['faire_value'] = bad,
        ),
        throwsA(isA<CatalogException>()),
      );
      expect(
        () => CombatValueSnapshot.fromJson(
          snapshotJson()..['personal_value'] = bad,
        ),
        throwsA(isA<CatalogException>()),
      );
    });
  }
  test('malformed private IDs fail with typed error, not CastError', () {
    expect(
      () =>
          UserPreference.fromJson(preferenceJson()..['profile_element_id'] = 1),
      throwsA(isA<CatalogException>()),
    );
    expect(
      () => CardPreferenceOverride.fromJson(
        overrideJson()..['card_or_variant_id'] = 1,
      ),
      throwsA(isA<CatalogException>()),
    );
    expect(
      () => CombatValueSnapshot.fromJson(snapshotJson()..['card_id'] = 1),
      throwsA(isA<CatalogException>()),
    );
  });
  test('timestamps require explicit timezone', () {
    expect(
      () => UserPreference.fromJson(
        preferenceJson()..['updated_at'] = '2026-09-27',
      ),
      throwsA(isA<CatalogException>()),
    );
  });
  final technical = <JsonMap>[
    {
      'type': 'SESSION_MODE_IN',
      'values': ['face_to_face', 'distance', 'hybrid'],
    },
    {'type': 'PHYSICAL_STATE_IS', 'value': 'state.near'},
    {'type': 'CLOTHES_AT_LEAST', 'target': 'ACTOR', 'value': 1},
    {'type': 'ACCESSORY_AVAILABLE', 'accessory_id': 'accessory.pencil'},
    {'type': 'MEDIA_CAPABILITY_AVAILABLE', 'capability_id': 'capability.audio'},
    {'type': 'TEMPORARY_MEETING_ALLOWED'},
    {'type': 'SESSION_FLAG_IS', 'flag_id': 'flag.ready', 'value': true},
  ];
  for (final payload in technical) {
    test(
      'technical ${payload['type']} round-trip and unknown fields rejected',
      () {
        final r = TechnicalRequirement.fromJson(payload);
        expect(r.toJson(), payload);
        expect(TechnicalRequirement.fromJson(r.toJson()).type, r.type);
        expect(
          () =>
              TechnicalRequirement.fromJson({...payload, 'script': 'anything'}),
          throwsA(isA<CatalogException>()),
        );
      },
    );
  }
  final effects = <JsonMap>[
    {'type': 'CLOTHES_DELTA', 'target': 'PARTNER', 'delta': -1},
    {'type': 'SET_PHYSICAL_STATE_TEMPORARY', 'value': 'state.near'},
    {'type': 'RESTORE_PHYSICAL_STATE_AFTER_ACTION'},
    {'type': 'SET_SESSION_FLAG', 'flag_id': 'flag.ready', 'value': true},
    {'type': 'CLEAR_SESSION_FLAG', 'flag_id': 'flag.ready'},
  ];
  for (final payload in effects) {
    test(
      'effect ${payload['type']} round-trip and unknown fields rejected',
      () {
        final e = StateEffect.fromJson(payload);
        expect(StateEffect.fromJson(e.toJson()).toJson(), payload);
        expect(
          () => StateEffect.fromJson({...payload, 'script': 'anything'}),
          throwsA(isA<CatalogException>()),
        );
      },
    );
  }
  for (final type in ParameterType.values) {
    test('parameter ${type.name} typed values', () {
      final p = parameter(fixture())..remove('range');
      p['type'] = type.name;
      p['values'] = switch (type) {
        ParameterType.INTEGER => [1, 2],
        ParameterType.BOOLEAN => [true, false],
        ParameterType.ENUM || ParameterType.DURATION_HINT => ['short', 'long'],
      };
      expect(CardParameterDefinition.fromJson(p).toJson(), p);
    });
  }
  test('domain, engines and loader have no Flutter or dart:ui dependency', () {
    for (final dir in ['lib/core', 'lib/domain', 'lib/engines', 'lib/data']) {
      for (final file
          in Directory(dir)
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))) {
        expect(
          file.readAsStringSync(),
          isNot(
            matches(
              RegExp(
                r'''(?:import|export)\s+['"](?:package:flutter|dart:ui)''',
              ),
            ),
          ),
          reason: file.path,
        );
      }
    }
  });
}
