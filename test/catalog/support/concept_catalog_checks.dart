import 'dart:convert';
import 'dart:io';

import 'package:couple_cards/core/errors/catalog_error.dart';
import 'package:couple_cards/core/json.dart';
import 'package:couple_cards/domain/catalog/concept_catalog.dart';
import 'package:couple_cards/domain/catalog/enums.dart';

const activePath = 'assets/catalog/concepts/active.fr.json';
const reservedPath = 'docs/catalog/reserved_concepts.fr.json';

JsonMap _document(String path) =>
    (jsonDecode(File(path).readAsStringSync()) as Map).cast<String, Object?>();

ConceptCatalog _load() => ConceptCatalog.fromJson(_document(activePath));

void _check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void _reject(void Function(JsonMap) mutate) {
  final json = _document(activePath);
  mutate(json);
  try {
    ConceptCatalog.fromJson(json);
  } on CatalogException {
    return;
  }
  throw StateError('Malformed catalogue was accepted');
}

JsonMap _concept(JsonMap root, String id) => (root['concepts']! as List)
    .cast<JsonMap>()
    .singleWhere((concept) => concept['id'] == id);

/// The same pure checks are registered with package:test and the audit CLI.
/// The CLI needs neither Flutter nor database/network packages.
Map<String, void Function()> conceptCatalogChecks() => {
  '55 active identities exclude retired and reserved concepts':
      () {
        final ids = _load().concepts.map((concept) => concept.id).toSet();
        final excluded = {
          '011',
          '014',
          '015',
          '017',
          '036',
          '040',
          '041',
          '059',
          '060',
          '064',
        };
        final expected = {
          for (var number = 1; number <= 65; number++)
            if (!excluded.contains(number.toString().padLeft(3, '0')))
              number.toString().padLeft(3, '0'),
        };
        _check(
          ids.length == 55 && ids.containsAll(expected),
          'Wrong active identities',
        );
      },
  'reserved concepts are separate and retained for the future common system':
      () {
        final reserved = _document(reservedPath);
        _check(reserved['schema_version'] == 1, 'Reserved schema');
        final entries = (reserved['concepts']! as List).cast<JsonMap>();
        _check(entries.length == 3, 'Reserved count');
        final names = {
          for (final entry in entries) entry['id']: entry['title'],
        };
        _check(
          names['036'] == 'Température' &&
              names['059'] == 'Texture' &&
              names['064'] == 'Dégustation sensuelle',
          'Reserved identities',
        );
        _check(
          reserved['future_system'] == 'Température / Texture / Dégustation',
          'Future common system',
        );
        _check(
          entries.every(
            (entry) =>
                !entry.containsKey('variants') && !entry.containsKey('stages'),
          ),
          'Reserves must not be playable definitions',
        );
      },
  'all evolution chili sequences match the consolidated specification': () {
    const expected = <String, List<int>>{
      '003': [1, 2, 2],
      '010': [1, 2, 2],
      '018': [1, 2, 2],
      '019': [3, 3, 3],
      '022': [3, 4, 4],
      '023': [3, 4, 4],
      '025': [3, 3, 3],
      '027': [4, 4, 4],
      '030': [3, 3, 4],
      '034': [1, 2, 3],
      '037': [2, 2, 3],
      '043': [1, 2, 2],
      '044': [1, 2, 3],
      '045': [1, 2, 4],
      '046': [1, 2, 3],
      '047': [1, 2, 4],
      '056': [2, 3, 4],
      '057': [1, 2, 3],
      '062': [1, 2, 3],
      '063': [1, 2, 3],
    };
    final evolutions = _load().concepts.where(
      (c) => c.kind == ConceptKind.evolution,
    );
    _check(evolutions.length == expected.length, 'Evolution count');
    for (final concept in evolutions) {
      _check(
        concept.stages.map((stage) => stage.chili).join('/') ==
            expected[concept.id]!.join('/'),
        'Wrong stages: ${concept.id}',
      );
      _check(
        concept.variants.isEmpty,
        'Stages must not be duplicated as variants',
      );
    }
  },
  'all simple action chili values match the specification': () {
    const expected = {
      '001': 1,
      '006': 1,
      '007': 1,
      '008': 2,
      '009': 2,
      '012': 1,
      '013': 1,
      '016': 1,
      '020': 3,
      '021': 3,
      '024': 3,
      '026': 3,
      '028': 4,
      '029': 3,
      '031': 3,
      '032': 1,
      '033': 1,
      '035': 2,
      '038': 1,
      '039': 1,
      '042': 2,
      '048': 2,
      '053': 2,
      '054': 2,
      '055': 3,
      '058': 1,
      '061': 2,
      '065': 3,
    };
    final actions = _load().concepts.where((c) => c.kind == ConceptKind.action);
    _check(actions.length == expected.length, 'Simple action count');
    for (final concept in actions) {
      _check(
        concept.variants.single.chili == expected[concept.id],
        'Wrong simple action chili: ${concept.id}',
      );
      _check(
        concept.stages.isEmpty && concept.intrinsicChili == null,
        'Intrinsic practices must not acquire a zone modifier',
      );
    }
  },
  'generic zone definitions cover all modifiers without clothing as a zone':
      () {
        final catalog = _load();
        const expected = {
          'face_hair': 0,
          'neck_nape': 0,
          'arms_hands': 0,
          'back_shoulders': 0,
          'belly': 0,
          'legs': 0,
          'feet': 0,
          'thighs': 1,
          'buttocks': 1,
          'chest': 1,
          'penis': 2,
          'vulva': 2,
          'anus': 2,
        };
        _check(catalog.zones.length == expected.length, 'Zone count');
        for (final zone in catalog.zones) {
          _check(
            zone.modifier == expected[zone.id],
            'Wrong modifier: ${zone.id}',
          );
        }
        final generic = catalog.concepts.where(
          (c) => c.kind == ConceptKind.zones,
        );
        _check(
          generic.map((c) => c.id).join('/') == '002/004/005',
          'Generic concepts',
        );
        for (final concept in generic) {
          _check(
            concept.stages.isEmpty && concept.intrinsicChili == 1,
            'Zone choices are not evolutions',
          );
          final fixed = concept.variants
              .where((variant) => !variant.freeZone)
              .toList();
          _check(
            fixed.length == expected.length &&
                fixed
                    .map((variant) => variant.zoneId)
                    .toSet()
                    .containsAll(expected.keys),
            'Missing fixed zone on ${concept.id}',
          );
          _check(
            concept.variants.where((v) => v.freeZone).length == 1,
            'Exactly one free zone choice',
          );
        }
      },
  'zone chili uses the intrinsic value plus modifier capped at four': () {
    final zones = {for (final z in _load().zones) z.id: z};
    _check(zones['arms_hands']!.effectiveChili(1) == 1, 'Arms chili');
    _check(zones['thighs']!.effectiveChili(1) == 2, 'Thigh chili');
    _check(zones['vulva']!.effectiveChili(1) == 3, 'Intimate chili');
    _check(zones['anus']!.effectiveChili(3) == 4, 'Chili cap');
  },
  'accessory variants do not imply evolutions or additional zone modifiers':
      () {
        final concepts = _load().concepts.where(
          (c) => c.kind == ConceptKind.accessory,
        );
        _check(
          concepts.map((c) => c.id).join('/') == '049/050/051/052',
          'Toy concepts',
        );
        for (final concept in concepts) {
          _check(
            concept.stages.isEmpty && concept.intrinsicChili == null,
            'Toy variants are not evolution stages',
          );
          final levels = {for (final v in concept.variants) v.id: v.chili};
          _check(
            levels.length == 4 &&
                levels['${concept.id}.external'] == 3 &&
                levels['${concept.id}.phallus'] == 3 &&
                levels['${concept.id}.vaginal_insertion'] == 4 &&
                levels['${concept.id}.anal_insertion'] == 4,
            'Toy chili levels',
          );
        }
      },
  'entry levels give 26/10/17/2 concepts and 26/36/53/55 cumulatively': () {
    final counts = <int, int>{1: 0, 2: 0, 3: 0, 4: 0};
    for (final concept in _load().concepts) {
      final levels = concept.kind == ConceptKind.zones
          ? [concept.intrinsicChili!]
          : [
              ...concept.stages.map((s) => s.chili),
              ...concept.variants.map((v) => v.chili!),
            ];
      final minimum = levels.reduce((a, b) => a < b ? a : b);
      counts[minimum] = counts[minimum]! + 1;
    }
    _check(counts.values.join('/') == '26/10/17/2', 'Entry distribution');
    var cumulative = 0;
    final totals = [for (final count in counts.values) cumulative += count];
    _check(totals.join('/') == '26/36/53/55', 'Cumulative availability');
  },
  '006 and 007 stay distinct non-evolving concepts with capacity references':
      () {
        final concepts = {for (final c in _load().concepts) c.id: c};
        _check(
          concepts['006']!.capacityRule ==
              ConceptCapacityRule.initial_clothing_single,
          '006 capacity reference',
        );
        _check(
          concepts['007']!.capacityRule ==
              ConceptCapacityRule.initial_clothing_double,
          '007 capacity reference',
        );
        _check(
          concepts.values.where((c) => c.capacityRule != null).length == 2,
          'Only 006 and 007 have special capacity references',
        );
      },
  'required distinctions and persistent definitions remain explicit': () {
    final concepts = {for (final c in _load().concepts) c.id: c};
    _check(
      concepts['002']!.detailsText ==
              'À une ou plusieurs reprises, cela dépend de toi.' &&
          concepts['002']!.composedDetailsText ==
              'Tu peux choisir l’une des deux ou les deux.',
      'Body kissing editorial precision',
    );
    _check(
      concepts['004']!.actionText.contains('librement ta bouche') &&
          concepts['004']!.detailsText!.contains('lécher') &&
          concepts['005']!.actionText.contains('librement tes mains') &&
          concepts['005']!.detailsText!.contains('masser'),
      'Mouth/hand distinction',
    );
    _check(
      concepts['024']!.detailsText ==
          'Les pratiques choisies doivent être consenties par les deux partenaires.',
      '024 consent wording',
    );
    _check(
      concepts['010']!.detailsText!.contains('rhabiller complètement'),
      'Strip-tease while already nude',
    );
    _check(
      concepts['013']!.actionText.contains('vous-même') &&
          concepts['039']!.actionText.contains('vous-même'),
      'Who chooses',
    );
    _check(
      concepts['016']!.detailsText!.contains('vêtements actuels'),
      'Posture clothing',
    );
    _check(
      concepts['025']!.detailsText!.contains('Sexe oral anal'),
      'Separate oral anal concept',
    );
    _check(
      concepts['029']!.actionText.contains('réalisez-la à deux'),
      'Execute position',
    );
    _check(
      concepts['042']!.actionText.contains('3 tours') &&
          concepts['043']!.actionText.contains('ponctuel'),
      'Sexting versus message',
    );
    _check(
      concepts['054']!.detailsText!.contains('non consentantes'),
      'Exposure scope',
    );
    _check(
      concepts['062']!.detailsText!.contains('ne doit pas gêner la respiration') &&
          concepts['063']!.detailsText!.contains('Maintiens cette prise'),
      'Controlled actions',
    );
    _check(
      concepts['058']!.sessionModes.single == SessionMode.face_to_face,
      '058 is face-to-face only',
    );
    _check(
      concepts.values
              .where((c) => c.persistentEffect)
              .map((c) => c.id)
              .join('/') ==
          '033/034/035/061/062/063',
      'Persistent definitions',
    );
  },
  'round trip is lossless and data is immutable': () {
    final json = _document(activePath);
    final catalog = ConceptCatalog.fromJson(json);
    _check(
      jsonEncode(catalog.toJson()) == jsonEncode(json),
      'Lossless round trip',
    );
    (_concept(json, '001'))['title'] = 'Changed outside';
    _check(catalog.concepts.first.title == 'Câlin', 'Defensive copy');
    try {
      catalog.concepts.clear();
    } on UnsupportedError {
      return;
    }
    throw StateError('Concept list is mutable');
  },
  'reject duplicate concept identity': () => _reject((json) {
    (json['concepts']! as List).add(_concept(json, '001'));
  }),
  'reject duplicate action identity': () => _reject((json) {
    final stages = _concept(json, '003')['stages']! as List;
    (stages[1] as JsonMap)['id'] = (stages[0] as JsonMap)['id'];
  }),
  'reject action identity owned by another concept': () => _reject((json) {
    ((_concept(json, '001')['variants']! as List).first as JsonMap)['id'] =
        '003.action';
  }),
  'reject chili outside 1 to 4': () => _reject((json) {
    ((_concept(json, '003')['stages']! as List).first as JsonMap)['chili'] = 5;
  }),
  'reject unknown zone references': () => _reject((json) {
    ((_concept(json, '002')['variants']! as List).first as JsonMap)['zone_id'] =
        'clothing';
  }),
  'reject stages on non-evolving zone variants': () => _reject((json) {
    _concept(json, '002')['stages'] = _concept(json, '003')['stages'];
  }),
  'reject variants duplicated alongside evolution stages': () =>
      _reject((json) {
        _concept(json, '003')['variants'] = _concept(json, '001')['variants'];
      }),
  'reject missing free zone choice': () => _reject((json) {
    (_concept(json, '002')['variants']! as List).removeLast();
  }),
  'reject duplicate fixed zones': () => _reject((json) {
    final variants = _concept(json, '002')['variants']! as List;
    (variants[1] as JsonMap)['zone_id'] = (variants[0] as JsonMap)['zone_id'];
  }),
  'reject zone modifiers added to intrinsically intimate practices': () =>
      _reject((json) {
        _concept(json, '022')['intrinsic_chili'] = 3;
      }),
  'reject historical deck fields and editorial drawSpice': () =>
      _reject((json) {
        _concept(json, '001')['drawSpice'] = 2;
      }),
  'reject obsolete deck activation flags': () => _reject((json) {
    _concept(json, '001')['v3_deck_enabled'] = false;
  }),
};
