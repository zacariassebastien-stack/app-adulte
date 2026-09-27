import 'dart:convert';
import 'package:couple_cards/data/catalog_loader/catalog_loader.dart';
import 'package:couple_cards/domain/domain.dart';

/// Entirely fictional data: a cooperative drawing activity.
JsonMap fixture() => jsonDecode(jsonEncode(_fixture())) as JsonMap;

JsonMap _fixture() => {
  'cards': {
    'schema_version': 1,
    'catalog_version': 2,
    'locale': 'fr-FR',
    'locale_version': 1,
    'cards': [
      {
        'stable_id': 'card.draw',
        'content_version': 1,
        'title_key': 'cards.draw.title',
        'title': 'Dessiner ensemble',
        'description_key': 'cards.draw.description',
        'precision': 'OPEN',
        'frequency': 'COMMON',
        'repeatability': 'REPEATABLE',
        'base_tags': ['tag.activity.drawing'],
        'participants': ['ACTOR', 'PARTNER'],
        'profile_requirements': [
          {
            'element_id': 'profile.drawing',
            'role': 'GENERAL',
            'requirement': 'REQUIRED',
            'minimum_status': 'ACCEPTED',
          },
        ],
        'technical_requirements': <Object?>[],
        'inversion_policy': 'NONE',
        'enabled': true,
        'variants': [
          {
            'stable_id': 'variant.draw.pencil',
            'card_id': 'card.draw',
            'content_version': 1,
            'instruction_key': 'variants.draw.pencil.instruction',
            'chili_level': 1,
            'additional_tags': <Object?>[],
            'removed_tags': <Object?>[],
            'profile_requirements': <Object?>[],
            'technical_requirements': [
              {
                'type': 'SESSION_MODE_IN',
                'values': ['face_to_face'],
              },
            ],
            'parameters': <Object?>[],
            'state_effects': <Object?>[],
            'enabled': true,
          },
        ],
        'parameters': [
          {
            'stable_id': 'parameter.draw.colors',
            'type': 'INTEGER',
            'range': {'min': 1, 'max': 5},
            'selection_by': 'BOTH',
            'visibility': 'PUBLIC',
            'consent_relevant': false,
            'state_relevant': false,
          },
        ],
      },
    ],
  },
  'profiles': {
    'schema_version': 1,
    'profile_version': 1,
    'elements': [
      {
        'stable_id': 'profile.activities',
        'parent_id': null,
        'title_key': 'profiles.activities.title',
        'kind': 'PREFERENCE',
        'directionality': 'GENERAL_ONLY',
        'explicit_acceptance_required': true,
        'enabled': true,
      },
      {
        'stable_id': 'profile.drawing',
        'parent_id': 'profile.activities',
        'title_key': 'profiles.drawing.title',
        'kind': 'PRACTICE',
        'directionality': 'GENERAL_ONLY',
        'explicit_acceptance_required': true,
        'enabled': true,
      },
    ],
  },
  'tags': {
    'schema_version': 1,
    'tags': [
      {
        'stable_id': 'tag.activity.drawing',
        'namespace': 'activity',
        'title_key': 'tags.drawing.title',
        'technical_only': false,
      },
    ],
  },
};
JsonMap document(JsonMap f, String key) => f[key]! as JsonMap;
List<Object?> rows(JsonMap f, String doc, String key) =>
    document(f, doc)[key]! as List<Object?>;
JsonMap card(JsonMap f) => rows(f, 'cards', 'cards').first! as JsonMap;
JsonMap variant(JsonMap f) =>
    (card(f)['variants']! as List<Object?>).first! as JsonMap;
JsonMap profile(JsonMap f, int index) =>
    rows(f, 'profiles', 'elements')[index]! as JsonMap;
JsonMap parameter(JsonMap f) =>
    (card(f)['parameters']! as List<Object?>).first! as JsonMap;
Catalog loadFixture(JsonMap f) => const CatalogLoader().loadJson(
  cardsJson: jsonEncode(f['cards']),
  profilesJson: jsonEncode(f['profiles']),
  tagsJson: jsonEncode(f['tags']),
);

JsonMap preferenceJson() => {
  'profile_element_id': 'profile.drawing',
  'status': 'ACCEPTED',
  'general_value': 12,
  'faire_value': null,
  'recevoir_value': 8,
  'updated_at': '2026-09-27T12:00:00+02:00',
  'source': 'ONBOARDING',
};
JsonMap overrideJson() => {
  'card_or_variant_id': 'variant.draw.pencil',
  'status': 'ACCEPTED',
  'faire_value': 20,
  'recevoir_value': 1,
  'updated_at': '2026-09-27T10:00:00Z',
};
JsonMap snapshotJson() => {
  'player_id': 'player.a',
  'card_id': 'card.draw',
  'variant_id': 'variant.draw.pencil',
  'role_at_commit': 'FAIRE',
  'personal_value': 14,
  'committed_at': '2026-09-27T10:00:00Z',
};
