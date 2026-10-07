import 'dart:convert';
import 'package:couple_cards/data/catalog_loader/catalog_loader.dart';
import 'package:couple_cards/domain/domain.dart';
import 'package:test/test.dart';
import '../fixtures/catalog_fixture.dart';

void main() {
  test('loads a valid fictional catalogue with unchanged stable IDs', () {
    final c = loadFixture(fixture());
    expect(c.cards.single.stableId, 'card.draw');
    expect(c.cards.single.variants.single.stableId, 'variant.draw.pencil');
    expect(c.cards.single.participants, [
      ParticipantRole.ACTOR,
      ParticipantRole.PARTNER,
    ]);
  });
  void invalid(
    String name,
    void Function(JsonMap) change,
    String code,
    String property, {
    String? id,
  }) {
    test(name, () {
      final f = fixture();
      change(f);
      expect(
        () => loadFixture(f),
        throwsA(
          isA<CatalogException>().having(
            (e) => e.issues.any(
              (i) =>
                  i.code == code &&
                  i.property.contains(property) &&
                  (id == null || i.stableId == id),
            ),
            'precise diagnostic',
            isTrue,
          ),
        ),
      );
    });
  }

  invalid(
    'duplicate card ID',
    (f) => rows(f, 'cards', 'cards').add(card(f)),
    'duplicate_id',
    'stable_id',
    id: 'card.draw',
  );
  invalid(
    'duplicate variant ID',
    (f) => (card(f)['variants']! as List<Object?>).add(variant(f)),
    'duplicate_id',
    'stable_id',
    id: 'variant.draw.pencil',
  );
  invalid(
    'duplicate profile ID',
    (f) => rows(f, 'profiles', 'elements').add(profile(f, 1)),
    'duplicate_id',
    'stable_id',
  );
  invalid(
    'duplicate tag ID',
    (f) => rows(f, 'tags', 'tags').add(rows(f, 'tags', 'tags').first),
    'duplicate_id',
    'stable_id',
  );
  invalid(
    'duplicate parameter ID',
    (f) => variant(f)['parameters'] = [parameter(f)],
    'duplicate_id',
    'stable_id',
  );
  for (final value in <Object?>[0, 6, 1.5, '2', null]) {
    invalid(
      'invalid chili $value',
      (f) => variant(f)['chili_level'] = value,
      'invalid_value',
      'chili_level',
      id: 'variant.draw.pencil',
    );
  }
  invalid(
    'missing parent',
    (f) => profile(f, 1)['parent_id'] = 'profile.missing',
    'missing_parent',
    'parent_id',
    id: 'profile.drawing',
  );
  invalid(
    'profile cycle',
    (f) => profile(f, 0)['parent_id'] = 'profile.drawing',
    'profile_cycle',
    'parent_id',
  );
  invalid(
    'self cycle',
    (f) => profile(f, 0)['parent_id'] = 'profile.activities',
    'profile_cycle',
    'parent_id',
  );
  invalid(
    'unknown profile reference',
    (f) => card(f)['profile_requirements'] = [
      {
        'element_id': 'profile.missing',
        'role': 'GENERAL',
        'requirement': 'REQUIRED',
      },
    ],
    'missing_profile',
    'element_id',
  );
  invalid(
    'unknown base tag',
    (f) => card(f)['base_tags'] = ['tag.missing'],
    'missing_tag',
    'base_tags',
  );
  invalid(
    'unknown variant tag',
    (f) => variant(f)['additional_tags'] = ['tag.missing'],
    'missing_tag',
    'additional_tags',
  );
  invalid(
    'unknown removed tag',
    (f) => variant(f)['removed_tags'] = ['tag.missing'],
    'missing_tag',
    'removed_tags',
  );
  invalid(
    'card without variants',
    (f) => card(f)['variants'] = [],
    'missing_variant',
    'variants',
  );
  invalid(
    'unknown precision',
    (f) => card(f)['precision'] = 'UNKNOWN',
    'unknown_enum',
    'precision',
  );
  invalid(
    'unknown participant',
    (f) => card(f)['participants'] = ['UNKNOWN'],
    'unknown_enum',
    'participants',
  );
  invalid(
    'unknown directionality',
    (f) => card(f)['directionality'] = 'UNKNOWN',
    'unknown_enum',
    'directionality',
  );
  invalid(
    'wrong variant parent',
    (f) => variant(f)['card_id'] = 'card.missing',
    'invalid_card_reference',
    'card_id',
  );
  invalid(
    'invalid profile requirement',
    (f) => card(f)['profile_requirements'] = [
      {
        'element_id': 'profile.drawing',
        'role': 'GENERAL',
        'requirement': 'ONE_OF',
      },
    ],
    'invalid_value',
    'one_of_group_id',
  );
  invalid(
    'minimum status cannot relax consent',
    (f) => card(f)['profile_requirements'] = [
      {
        'element_id': 'profile.drawing',
        'role': 'GENERAL',
        'requirement': 'REQUIRED',
        'minimum_status': 'DISCOVER',
      },
    ],
    'invalid_value',
    'minimum_status',
  );
  invalid(
    'applies_to_variant must resolve within card',
    (f) => card(f)['profile_requirements'] = [
      {
        'element_id': 'profile.drawing',
        'role': 'GENERAL',
        'requirement': 'REQUIRED',
        'applies_to_variant_id': 'variant.missing',
      },
    ],
    'invalid_variant_reference',
    'applies_to_variant_id',
  );
  invalid(
    'invalid technical payload gives owning variant and path',
    (f) => variant(f)['technical_requirements'] = [
      {'type': 'CLOTHES_AT_LEAST', 'target': 'ACTOR', 'value': -1},
    ],
    'invalid_value',
    'technical_requirements[0].value',
    id: 'variant.draw.pencil',
  );
  invalid(
    'missing technical target',
    (f) => variant(f)['technical_requirements'] = [
      {'type': 'CLOTHES_AT_LEAST', 'value': 1},
    ],
    'unknown_enum',
    'target',
  );
  invalid(
    'unknown technical type',
    (f) => variant(f)['technical_requirements'] = [
      {'type': 'SCRIPT'},
    ],
    'unknown_enum',
    'type',
  );
  invalid(
    'invalid session mode',
    (f) => variant(f)['technical_requirements'] = [
      {
        'type': 'SESSION_MODE_IN',
        'values': ['unknown'],
      },
    ],
    'unknown_enum',
    'values[0]',
  );
  invalid(
    'invalid effect',
    (f) => variant(f)['state_effects'] = [
      {'type': 'CLOTHES_DELTA', 'target': 'ACTOR', 'delta': 'one'},
    ],
    'invalid_value',
    'delta',
  );
  invalid(
    'unknown effect type',
    (f) => variant(f)['state_effects'] = [
      {'type': 'SCRIPT'},
    ],
    'unknown_enum',
    'type',
  );
  invalid(
    'parameter inverted range',
    (f) => parameter(f)['range'] = {'min': 5, 'max': 1},
    'invalid_value',
    'max',
  );
  invalid(
    'parameter untyped values',
    (f) {
      parameter(f).remove('range');
      parameter(f)['values'] = ['one'];
    },
    'invalid_value',
    'values[0]',
  );
  invalid(
    'parameter ambiguous values and range',
    (f) => parameter(f)['values'] = [1],
    'invalid_value',
    'values/range',
  );
  invalid(
    'unknown parameter enum',
    (f) => parameter(f)['selection_by'] = 'UNKNOWN',
    'unknown_enum',
    'selection_by',
  );
  invalid(
    'malformed variants list',
    (f) => card(f)['variants'] = [null],
    'invalid_value',
    'variants[0]',
  );
  invalid(
    'schema version unsupported',
    (f) => document(f, 'cards')['schema_version'] = 99,
    'invalid_value',
    'schema_version',
  );
  invalid(
    'disabled content is still validated',
    (f) {
      variant(f)['enabled'] = false;
      variant(f)['additional_tags'] = ['tag.missing'];
    },
    'missing_tag',
    'additional_tags',
  );

  test('namespace-relative seed references resolve only existing tags', () {
    final f = fixture();
    card(f)['base_tags'] = ['activity.drawing'];
    expect(loadFixture(f).cards.single.baseTags, ['activity.drawing']);
  });
  test('async reader loads all three source files', () async {
    final f = fixture();
    final paths = <String>[];
    final c = await const CatalogLoader().load((path) async {
      paths.add(path);
      return jsonEncode(
        f[path.contains('cards.v4')
            ? 'cards'
            : path.contains('profile_elements')
            ? 'profiles'
            : 'tags'],
      );
    });
    expect(paths.length, 3);
    expect(c.cards.length, 1);
  });
  test('read failures are typed', () async {
    await expectLater(
      const CatalogLoader().load(
        (_) async => throw const FormatException('unreadable'),
      ),
      throwsA(
        isA<CatalogException>().having(
          (e) => e.issues.first.code,
          'code',
          'read_failed',
        ),
      ),
    );
  });
  test('malformed JSON is typed with document identity', () {
    expect(
      () => const CatalogLoader().decode(
        cardsJson: '{',
        profilesJson: '{}',
        tagsJson: '{}',
      ),
      throwsA(
        isA<CatalogException>().having(
          (e) => e.issues.first.stableId,
          'document',
          'cards',
        ),
      ),
    );
  });
}
