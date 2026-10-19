import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:couple_cards/core/json.dart';
import 'package:couple_cards/domain/catalog/concept_catalog.dart';
import 'package:couple_cards/domain/game/game_models.dart' show PlayerStyle;
import 'package:couple_cards/engines/deck/concept_deck_engine.dart';

const _engine = ConceptDeckEngine();

void _check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void _close(double actual, double expected) =>
    _check((actual - expected).abs() < 1e-10, '$actual != $expected');

void _throws<T extends Object>(void Function() action) {
  try {
    action();
  } catch (error) {
    if (error is T) return;
    rethrow;
  }
  throw StateError('Expected $T');
}

ConceptCatalog _catalog([Set<String>? ids]) {
  final json =
      jsonDecode(
            File('assets/catalog/concepts/active.fr.json').readAsStringSync(),
          )
          as JsonMap;
  if (ids != null) {
    (json['concepts']! as List).removeWhere(
      (value) => !ids.contains((value as JsonMap)['id']),
    );
  }
  return ConceptCatalog.fromJson(json);
}

/// Explicit allow-all is a test fixture, never a production engine default.
ConceptDeckEligibility _eligible(
  ConceptCatalog catalog, {
  Set<String>? concepts,
  Map<String, Set<String>> actionOverrides = const {},
  Map<String, Set<String>> zoneOverrides = const {},
}) => ConceptDeckEligibility(
  actionIdsByConcept: {
    for (final concept in catalog.concepts)
      if (concepts == null || concepts.contains(concept.id))
        concept.id:
            actionOverrides[concept.id] ??
            {
              ...concept.stages.map((stage) => stage.id),
              ...concept.variants.map((variant) => variant.id),
            },
  },
  zoneIdsByConcept: {
    for (final concept in catalog.concepts)
      concept.id:
          zoneOverrides[concept.id] ?? catalog.zones.map((z) => z.id).toSet(),
  },
);

ConceptDeckPool _pool(
  ConceptCatalog catalog, {
  ConceptDeckStock? stock,
  ConceptDeckEligibility? eligibility,
  int global = 4,
  PlayerStyle style = PlayerStyle.SOFT,
  Set<String> unavailable = const {},
}) => _engine.prepare(
  catalog: catalog,
  stock:
      stock ??
      ConceptDeckStock.startCycle(catalog: catalog, initialClothing: 5),
  eligibility: eligibility ?? _eligible(catalog),
  globalChili: global,
  style: style,
  unavailableConceptIds: unavailable,
);

ConceptCatalog _synthetic(List<JsonMap> concepts) => ConceptCatalog.fromJson({
  'schema_version': 1,
  'catalog_version': 1,
  'locale': 'fr-FR',
  'source': 'Independent deck test fixtures',
  'zones': <Object?>[],
  'concepts': concepts,
});

JsonMap _action(String id, int chili) => {
  'id': id,
  'title': id,
  'kind': 'action',
  'action_text': 'Test',
  'variants': [
    {'id': '$id.action', 'title': id, 'chili': chili},
  ],
};

JsonMap _evolution(String id, List<int> chilis) => {
  'id': id,
  'title': id,
  'kind': 'evolution',
  'action_text': 'Test',
  'stages': [
    for (var i = 0; i < chilis.length; i++)
      {'id': '$id.stage.$i', 'title': 'Stage $i', 'chili': chilis[i]},
  ],
};

ConceptCatalog _fourClasses() => _synthetic([
  for (var chili = 1; chili <= 4; chili++) _action('level$chili', chili),
]);

final class _RandomAt implements Random {
  _RandomAt(this.point, this.index, {this.expectedSize});
  final double point;
  final int index;
  final int? expectedSize;
  int doubleCalls = 0;
  int intCalls = 0;

  @override
  double nextDouble() {
    doubleCalls++;
    return point;
  }

  @override
  int nextInt(int max) {
    intCalls++;
    if (expectedSize != null) {
      _check(max == expectedSize, 'Wrong concept count');
    }
    _check(index >= 0 && index < max, 'Test index outside class');
    return index;
  }

  @override
  bool nextBool() =>
      throw StateError('No direction/variant random draw expected');
}

Map<String, void Function()> conceptDeckChecks() => {
  'one stock entry and one candidate per active concept': () {
    final catalog = _catalog();
    final stock = ConceptDeckStock.startCycle(
      catalog: catalog,
      initialClothing: 5,
    );
    final candidates = _pool(catalog, stock: stock).candidates.toList();
    _check(
      stock.capacity.length == 56 && candidates.length == 56,
      'Logical stock size',
    );
    _check(
      candidates.map((c) => c.concept.id).toSet().length == 56,
      'Duplicate concepts',
    );
  },
  'evolution quota counts stages, never variants or currently unlocked stages':
      () {
        final catalog = _catalog();
        final stock = ConceptDeckStock.startCycle(
          catalog: catalog,
          initialClothing: 5,
        );
        for (final concept in catalog.concepts) {
          if (concept.capacityRule != null) continue;
          _check(
            stock.capacity[concept.id] ==
                (concept.kind == ConceptKind.evolution
                    ? concept.stages.length
                    : 1),
            'Wrong capacity: ${concept.id}',
          );
        }
        _check(
          _pool(
                catalog,
                stock: stock,
                global: 1,
              ).candidates.any((c) => c.concept.id == '045') &&
              stock.remainingFor('045') == 3,
          'Locked stages must not reduce cycle capacity',
        );
      },
  '006 and 007 clothing capacities match the validated formula including zero':
      () {
        final catalog = _catalog({'006', '007'});
        const expected = [
          (0, 0),
          (1, 0),
          (2, 0),
          (2, 1),
          (2, 1),
          (2, 2),
          (2, 2),
          (2, 3),
          (2, 3),
        ];
        for (var clothing = 0; clothing < expected.length; clothing++) {
          final stock = ConceptDeckStock.startCycle(
            catalog: catalog,
            initialClothing: clothing,
          );
          _check(
            stock.capacity.length == 2,
            'Clothing must not materialize copies',
          );
          _check(
            stock.remainingFor('006') == expected[clothing].$1 &&
                stock.remainingFor('007') == expected[clothing].$2,
            'Clothing $clothing',
          );
          final pool = _pool(catalog, stock: stock);
          _check(
            pool.candidates.length ==
                (expected[clothing].$1 > 0 ? 1 : 0) +
                    (expected[clothing].$2 > 0 ? 1 : 0),
            'Zero capacity must not become a candidate',
          );
        }
      },
  'pool contains only the unconsumed stages supplied by action eligibility':
      () {
        final catalog = _catalog({'019'});
        final stock = ConceptDeckStock.startCycle(
          catalog: catalog,
          initialClothing: 5,
        ).consume('019');
        final candidate = _pool(
          catalog,
          stock: stock,
          eligibility: _eligible(
            catalog,
            actionOverrides: {
              '019': {'019.stage.1', '019.stage.3'},
            },
          ),
        ).candidates.single;
        _check(
          candidate.choices.map((c) => c.actionId).join('/') ==
              '019.stage.1/019.stage.3',
          'Consumed stage returned to pool',
        );
        _check(
          _pool(
            catalog,
            stock: stock,
            eligibility: _eligible(catalog, actionOverrides: {'019': {}}),
          ).isEmpty,
          'No playable stages must produce an empty pool',
        );
      },
  'consuming a concept changes only its own shared counter': () {
    final catalog = _catalog({'001', '019'});
    final stock = ConceptDeckStock.startCycle(
      catalog: catalog,
      initialClothing: 5,
    );
    final next = stock.consume('019').consume('019');
    _check(
      next.remainingFor('019') == 1 && next.remainingFor('001') == 1,
      'Counter independence',
    );
    _check(stock.remainingFor('019') == 3, 'Original counter mutated');
  },
  'drawing consumes neither quota nor an action definition': () {
    final catalog = _catalog({'045'});
    final stock = ConceptDeckStock.startCycle(
      catalog: catalog,
      initialClothing: 5,
    );
    final pool = _pool(catalog, stock: stock);
    final random = _RandomAt(0, 0, expectedSize: 1);
    final drawn = pool.draw(random)!;
    _check(
      drawn.concept.id == '045' && drawn.choices.length == 3,
      'Premature stage selection',
    );
    _check(stock.remainingFor('045') == 3, 'Drawing consumed quota');
    _check(
      random.doubleCalls == 1 && random.intCalls == 1,
      'Unexpected extra random choices',
    );
  },
  'held or reserved concepts can be excluded without creating more copies': () {
    final catalog = _catalog({'001', '019'});
    final pool = _pool(catalog, unavailable: {'019'});
    _check(
      pool.candidates.single.concept.id == '001',
      'Held concept was redrawn',
    );
    _check(
      _pool(catalog, unavailable: {'001', '019'}).isEmpty,
      'All held must give no candidate',
    );
  },
  'exhausted stock does not resurrect, draw or advance a cycle': () {
    final catalog = _catalog({'001'});
    final initial = ConceptDeckStock.startCycle(
      catalog: catalog,
      initialClothing: 5,
    );
    final exhausted = initial.consume('001');
    final pool = _pool(catalog, stock: exhausted);
    final random = _RandomAt(0, 0);
    _check(
      pool.isEmpty && pool.probabilities.isEmpty && pool.draw(random) == null,
      'Empty pool fallback',
    );
    _check(
      random.doubleCalls == 0 && random.intCalls == 0,
      'Empty pool used random',
    );
    _check(_pool(catalog, stock: exhausted).isEmpty, 'Implicit cycle reset');
  },
  'eligibility is explicit and missing actions are never admitted': () {
    final catalog = _catalog({'001', '019'});
    final none = ConceptDeckEligibility(
      actionIdsByConcept: {},
      zoneIdsByConcept: {},
    );
    _check(
      _pool(catalog, eligibility: none).isEmpty,
      'Missing eligibility allowed content',
    );
    final one = _eligible(catalog, concepts: {'019'});
    _check(
      _pool(catalog, eligibility: one).candidates.single.concept.id == '019',
      'Filtered concept survived',
    );
  },
  'changing context eligibility changes candidates without any hybrid weighting':
      () {
        final catalog = _catalog({'001', '043'});
        // Simulated current eligibility: physical-only hug excluded at distance.
        final distance = _eligible(catalog, concepts: {'043'});
        final together = _eligible(catalog, concepts: {'001', '043'});
        final distancePool = _pool(catalog, eligibility: distance);
        _check(
          distancePool.candidates.single.concept.id == '043',
          'Distance filter',
        );
        final togetherPool = _pool(catalog, eligibility: together, global: 1);
        _check(togetherPool.classes[1]!.length == 2, 'Together candidates');
        _close(togetherPool.probabilities[1]!, 1);
        for (var index = 0; index < 2; index++) {
          _check(
            togetherPool.draw(_RandomAt(0, index, expectedSize: 2)) ==
                togetherPool.classes[1]![index],
            'Orientation biased within-class draw',
          );
        }
      },
  'Photo mutuelle class follows accessible piments 1,2,2,4': () {
    final catalog = _catalog({'045'});
    const classes = [1, 2, 2, 4];
    const available = [1, 2, 2, 3];
    for (var global = 1; global <= 4; global++) {
      final candidate = _pool(catalog, global: global).candidates.single;
      _check(
        candidate.drawClass == classes[global - 1] &&
            candidate.choices.length == available[global - 1],
        'Photo global $global',
      );
    }
  },
  'Entrave class follows 1,2,3,3': () {
    final catalog = _catalog({'034'});
    for (var global = 1; global <= 4; global++) {
      _check(
        _pool(catalog, global: global).candidates.single.drawClass ==
            min(global, 3),
        'Entrave global $global',
      );
    }
  },
  'stage number does not imply chili and all permitted stages remain choices':
      () {
        final catalog = _catalog({'003', '019', '027'});
        final atTwo = _pool(catalog, global: 2).candidates.single;
        _check(
          atTwo.concept.id == '003' &&
              atTwo.choices.length == 3 &&
              atTwo.drawClass == 2,
          'Third stage with piment two was locked',
        );
        final atThree = _pool(catalog, global: 3);
        _check(
          atThree.candidates
                  .singleWhere((c) => c.concept.id == '019')
                  .choices
                  .length ==
              3,
          'Masturbation stages',
        );
        _check(
          !atThree.candidates.any((c) => c.concept.id == '027'),
          'Intrinsic piment four leaked',
        );
      },
  'classes use currently eligible stages rather than all editorial stages': () {
    final catalog = _catalog({'045'});
    final eligibility = _eligible(
      catalog,
      actionOverrides: {
        '045': {'045.stage.1'},
      },
    );
    final candidate = _pool(
      catalog,
      eligibility: eligibility,
    ).candidates.single;
    _check(
      candidate.drawClass == 1 && candidate.choices.single.chili == 1,
      'Excluded upper stages changed class',
    );
  },
  'free-zone class follows 1,1,2,2 without changing actual action chili': () {
    final catalog = _catalog({'002', '004', '005'});
    for (var global = 1; global <= 4; global++) {
      for (final candidate in _pool(catalog, global: global).candidates) {
        _check(candidate.drawClass == (global < 3 ? 1 : 2), 'Zone draw class');
        _check(
          candidate.choices.every((choice) => choice.chili <= global),
          'Zone ceiling',
        );
        _check(
          candidate.choices.map((c) => c.chili).reduce(max) == min(global, 3),
          'The minus one changed real chili',
        );
      }
    }
  },
  'free zones stay unspecified at base chili with no zone modifier': () {
    final catalog = _catalog({'005'});
    final eligibility = _eligible(
      catalog,
      actionOverrides: {
        '005': {'005.zone.free'},
      },
      zoneOverrides: {
        '005': {'vulva', 'unlisted_zone'},
      },
    );
    for (final global in [1, 2, 3, 4]) {
      final candidate = _pool(
        catalog,
        eligibility: eligibility,
        global: global,
      ).candidates.single;
      _check(
        candidate.choices.single.zoneId == null &&
            candidate.choices.single.chili == 1 &&
            candidate.drawClass == 1,
        'Free action inferred an anatomical zone or modifier',
      );
    }
    _check(
      _pool(
        catalog,
        eligibility: _eligible(catalog, zoneOverrides: {'005': {}}),
      ).isEmpty,
      'No eligible zone must still exclude the concept',
    );
    _check(
      _pool(
        catalog,
        eligibility: _eligible(catalog, actionOverrides: {'005': {}}),
      ).isEmpty,
      'Excluded action admitted',
    );
  },
  'fixed zones keep their modifier and free variant remains a separate choice':
      () {
        final catalog = _catalog({'005'});
        final eligibility = _eligible(
          catalog,
          zoneOverrides: {
            '005': {'vulva'},
          },
        );
        final low = _pool(
          catalog,
          eligibility: eligibility,
          global: 1,
        ).candidates.single;
        _check(
          low.choices.length == 1 && low.choices.single.zoneId == null,
          'Fixed intimate zone admitted below its ceiling',
        );
        final high = _pool(
          catalog,
          eligibility: eligibility,
          global: 3,
        ).candidates.single;
        _check(
          high.choices.length == 2 &&
              high.choices.any((c) => c.zoneId == 'vulva' && c.chili == 3) &&
              high.choices.any((c) => c.zoneId == null && c.chili == 1),
          'Fixed zone modifier or free base chili changed',
        );
      },
  'toy variants use intrinsic 3/4 without zone discount or evolution quota':
      () {
        final catalog = _catalog({'049'});
        final atThree = _pool(catalog, global: 3).candidates.single;
        _check(
          atThree.drawClass == 3 &&
              atThree.choices.length == 2 &&
              atThree.choices.every((c) => c.chili == 3),
          'External toy class',
        );
        final atFour = _pool(catalog).candidates.single;
        _check(
          atFour.drawClass == 4 && atFour.choices.length == 4,
          'Insertion toy class',
        );
        final externalOnly = _eligible(
          catalog,
          actionOverrides: {
            '049': {'049.external'},
          },
        );
        _check(
          _pool(
                catalog,
                eligibility: externalOnly,
              ).candidates.single.drawClass ==
              3,
          'Excluded insertion still raised class',
        );
      },
  'all real-catalog choices respect ceilings with availability 26,37,54,56':
      () {
        final catalog = _catalog();
        const expected = [26, 37, 54, 56];
        for (var global = 1; global <= 4; global++) {
          final pool = _pool(catalog, global: global);
          _check(
            pool.candidates.length == expected[global - 1],
            'Availability at $global',
          );
          _check(
            pool.candidates.every(
              (candidate) =>
                  candidate.drawClass <= global &&
                  candidate.choices.every((choice) => choice.chili <= global),
            ),
            'Ceiling violation',
          );
        }
      },
  'three styles preserve exactly the validated four-class probabilities': () {
    final catalog = _fourClasses();
    const expected = {
      PlayerStyle.SOFT: [0.45, 0.40, 0.13, 0.02],
      PlayerStyle.EPICE: [0.20, 0.40, 0.30, 0.10],
      PlayerStyle.INTENABLE: [0.10, 0.25, 0.40, 0.25],
    };
    for (final entry in expected.entries) {
      final pool = _pool(catalog, style: entry.key);
      for (var level = 1; level <= 4; level++) {
        _close(pool.probabilities[level]!, entry.value[level - 1]);
      }
    }
  },
  'locked classes are removed and epic proportions become 20/90,40/90,30/90':
      () {
        final pool = _pool(_fourClasses(), global: 3, style: PlayerStyle.EPICE);
        _check(pool.classes.keys.join('/') == '1/2/3', 'Locked class remained');
        _close(pool.probabilities[1]!, 20 / 90);
        _close(pool.probabilities[2]!, 40 / 90);
        _close(pool.probabilities[3]!, 30 / 90);
      },
  'empty allowed classes redistribute to every remaining nonempty class': () {
    final catalog = _fourClasses();
    final eligibility = _eligible(catalog, concepts: {'level1', 'level3'});
    final pool = _pool(catalog, eligibility: eligibility);
    _check(pool.classes.keys.join('/') == '1/3', 'Empty classes remained');
    _close(pool.probabilities[1]!, 45 / 58);
    _close(pool.probabilities[3]!, 13 / 58);
    _close(
      _pool(catalog, eligibility: eligibility, global: 2).probabilities[1]!,
      1,
    );
  },
  'quota depletion removes a class and renormalizes without resurrecting it':
      () {
        final catalog = _fourClasses();
        var stock = ConceptDeckStock.startCycle(
          catalog: catalog,
          initialClothing: 5,
        );
        stock = stock.consume('level2').consume('level4');
        final pool = _pool(catalog, stock: stock);
        _check(
          pool.classes.keys.join('/') == '1/3',
          'Exhausted class remained',
        );
        _close(pool.probabilities[1]!, 45 / 58);
        _close(pool.probabilities[3]!, 13 / 58);
      },
  'group sizes do not determine probability mass of a class': () {
    final catalog = _synthetic([
      for (var index = 0; index < 20; index++) _action('soft$index', 1),
      _action('explicit', 3),
    ]);
    final pool = _pool(catalog);
    _close(pool.probabilities[1]!, 45 / 58);
    _close(pool.probabilities[3]!, 13 / 58);
    _check(
      pool.draw(_RandomAt(0.99, 0, expectedSize: 1))!.concept.id == 'explicit',
      'Large class captured small class probability',
    );
  },
  'concept selection is uniform within a class regardless of stage count': () {
    final catalog = _synthetic([
      _action('single', 3),
      _evolution('evolving', [3, 3, 3]),
    ]);
    final pool = _pool(catalog);
    _check(pool.classes[3]!.length == 2, 'Stages became candidates');
    _check(
      pool.draw(_RandomAt(0, 0, expectedSize: 2))!.concept.id == 'single',
      'First concept',
    );
    _check(
      pool.draw(_RandomAt(0, 1, expectedSize: 2))!.concept.id == 'evolving',
      'Second concept',
    );
    final stock = ConceptDeckStock.startCycle(
      catalog: catalog,
      initialClothing: 5,
    ).consume('evolving').consume('evolving');
    _check(
      _pool(catalog, stock: stock).classes[3]!.length == 2,
      'Remaining quantity was used as multiplicity',
    );
  },
  'zone variant count does not multiply concept draw probability or stock': () {
    final catalog = _catalog({'001', '005'});
    final stock = ConceptDeckStock.startCycle(
      catalog: catalog,
      initialClothing: 5,
    );
    final pool = _pool(catalog, stock: stock, global: 1);
    final manual = pool.candidates.singleWhere((c) => c.concept.id == '005');
    _check(manual.choices.length > 1, 'Zone fixture has no variants');
    final first = manual.materialize(
      _RandomAt(0, 0, expectedSize: manual.choices.length),
    );
    final free = manual.materialize(
      _RandomAt(
        0,
        manual.choices.length - 1,
        expectedSize: manual.choices.length,
      ),
    );
    _check(
      first.zoneId != null && free.zoneId == null,
      'Fixed/free choices cannot both be materialized',
    );
    _check(
      pool.classes[1]!.length == 2 &&
          pool.draw(_RandomAt(0, 0, expectedSize: 2))!.concept.id == '001' &&
          pool.draw(_RandomAt(0, 1, expectedSize: 2))!.concept.id == '005',
      'Zone variants became draw candidates',
    );
    final consumed = stock.consume('005');
    _check(
      consumed.remainingFor('005') == 0 &&
          !_pool(
            catalog,
            stock: consumed,
            global: 1,
          ).candidates.any((c) => c.concept.id == '005'),
      'A second zone occurrence bypassed concept stock',
    );
  },
  'adding same-chili stages or accessory variants cannot change class probabilities':
      () {
        ConceptCatalog fixture(int count) => _synthetic([
          _action('low', 1),
          _evolution('high', List.filled(count, 3)),
          {
            'id': 'toy',
            'title': 'Toy',
            'kind': 'accessory',
            'action_text': 'Test',
            'selection_axes': ['zone', 'accessory'],
            'variants': [
              for (var i = 0; i < count; i++)
                {'id': 'toy.$i', 'title': 'Variant $i', 'chili': 3},
            ],
          },
        ]);
        final two = _pool(fixture(2));
        final three = _pool(fixture(3));
        _check(
          two.classes[3]!.length == 2 && three.classes[3]!.length == 2,
          'Variant multiplicity',
        );
        _close(two.probabilities[1]!, three.probabilities[1]!);
        _close(two.probabilities[3]!, three.probabilities[3]!);
      },
  'stratified random inputs reproduce class percentages and uniform concept indices':
      () {
        final catalog = _synthetic([
          for (var level = 1; level <= 4; level++) ...[
            _action('a$level', level),
            _evolution('b$level', [level, level, level]),
          ],
        ]);
        final pool = _pool(catalog);
        final counts = <String, int>{};
        for (var i = 0; i < 10000; i++) {
          final drawn = pool.draw(
            _RandomAt((i + 0.5) / 10000, i % 2, expectedSize: 2),
          )!;
          counts.update(
            drawn.concept.id,
            (count) => count + 1,
            ifAbsent: () => 1,
          );
        }
        const expected = [4500, 4000, 1300, 200];
        for (var level = 1; level <= 4; level++) {
          _check(
            counts['a$level'] == expected[level - 1] ~/ 2 &&
                counts['b$level'] == expected[level - 1] ~/ 2,
            'Class $level or concept uniformity',
          );
        }
      },
  'raising global chili immediately exposes choices without redrawing or consuming':
      () {
        final catalog = _catalog({'045'});
        final stock = ConceptDeckStock.startCycle(
          catalog: catalog,
          initialClothing: 5,
        );
        final oldPool = _pool(catalog, stock: stock, global: 1);
        final newPool = _pool(catalog, stock: stock, global: 4);
        _check(
          oldPool.candidates.single.choices.length == 1 &&
              newPool.candidates.single.choices.length == 3 &&
              stock.remainingFor('045') == 3,
          'Unlock required a new concept or changed quota',
        );
      },
  'pool and eligibility are immutable snapshots': () {
    final catalog = _catalog({'001'});
    final ids = {'001.action'};
    final actionMap = {'001': ids};
    final eligibility = ConceptDeckEligibility(
      actionIdsByConcept: actionMap,
      zoneIdsByConcept: {},
    );
    ids.clear();
    actionMap.clear();
    final pool = _pool(catalog, eligibility: eligibility);
    _check(
      pool.candidates.single.concept.id == '001',
      'Eligibility aliases caller data',
    );
    _throws<UnsupportedError>(() => eligibility.actionIdsByConcept.clear());
    _throws<UnsupportedError>(
      () => eligibility.actionIdsByConcept['001']!.clear(),
    );
    _throws<UnsupportedError>(() => pool.classes.clear());
    _throws<UnsupportedError>(() => pool.classes[1]!.clear());
    _throws<UnsupportedError>(() => pool.probabilities.clear());
    _throws<UnsupportedError>(() => pool.candidates.single.choices.clear());
  },
  'unknown concept consumption and invalid inputs fail explicitly': () {
    final catalog = _catalog({'001'});
    final stock = ConceptDeckStock.startCycle(
      catalog: catalog,
      initialClothing: 0,
    );
    _throws<ArgumentError>(() => stock.consume('unknown'));
    _throws<RangeError>(
      () => ConceptDeckStock.startCycle(catalog: catalog, initialClothing: -1),
    );
    _throws<RangeError>(() => _pool(catalog, global: 0));
    _throws<RangeError>(() => _pool(catalog, global: 5));
    _throws<UnsupportedError>(() => stock.remaining.clear());
    _throws<UnsupportedError>(() => stock.capacity.clear());
  },
  'class probability intervals do not depend on catalogue ordering': () {
    final catalog = _synthetic([_action('high', 4), _action('low', 1)]);
    final pool = _pool(catalog);
    _check(
      pool.classes.keys.join('/') == '1/4',
      'Unstable class interval order',
    );
    _check(
      pool.draw(_RandomAt(0, 0))!.concept.id == 'low',
      'Wrong first probability interval',
    );
    _check(
      pool.draw(_RandomAt(0.99999, 0))!.concept.id == 'high',
      'Wrong last probability interval',
    );
  },
};
