import 'dart:convert';
import 'dart:io';

import 'package:couple_cards/core/errors/catalog_error.dart';
import 'package:couple_cards/core/json.dart';
import 'package:couple_cards/data/repositories/concept_usage_checkpoint_codec.dart';
import 'package:couple_cards/domain/catalog/concept_catalog.dart';
import 'package:couple_cards/domain/round/concept_usage_snapshot.dart';
import 'package:couple_cards/domain/session/session_state.dart';
import 'package:couple_cards/engines/deck/concept_deck_engine.dart';
import 'package:couple_cards/engines/usage/concept_usage_checkpoint.dart';

void _check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void _throws<T extends Object>(void Function() action) {
  try {
    action();
  } catch (error) {
    if (error is T) return;
    rethrow;
  }
  throw StateError('Expected $T');
}

JsonMap _decode(String json) =>
    (jsonDecode(json) as Map).cast<String, Object?>();
final _time = DateTime.utc(2026, 10, 15, 14);

JsonMap _actionJson({
  String conceptId = '019',
  String? variantId,
  int stage = 1,
  int value = 7,
  String? zoneId,
}) => {
  'concept_id': conceptId,
  'catalog_version': 1,
  'locale': 'fr-FR',
  if (variantId == null)
    'stage_id': '$conceptId.stage.$stage'
  else
    'variant_id': variantId,
  'zone_id': ?zoneId,
  'effective_chili': zoneId == null ? 3 : 1,
  'direction': 'FAIRE',
  'actor_player_ids': ['alice'],
  'target_player_ids': ['bob'],
  'parameters': {
    'resolved_option': 'test',
    'nested': {
      'selected': ['first'],
    },
  },
  'accessories': <Object?>[],
  'tags': ['v3.preference.test'],
  'primary_preference_ids': ['v3.preference.test'],
  'personal_values': [
    {'player_id': 'alice', 'role': 'FAIRE', 'value': value},
    {'player_id': 'bob', 'role': 'RECEVOIR', 'value': 11},
  ],
  'effects': <Object?>[],
  'action_text': 'Instruction déjà résolue pour Alice et Bob (fixture).',
};

ResolvedConceptAction _action({int stage = 1, int value = 7}) =>
    ResolvedConceptAction.fromJson(_actionJson(stage: stage, value: value));

ConceptUsageSnapshot _snapshot({
  String intent = 'command-1',
  ResolvedConceptAction? action,
  ResolvedConceptAction? inverted,
}) => ConceptUsageSnapshot.create(
  sessionId: 'session',
  ownerPlayerId: 'alice',
  cycle: 1,
  intentId: intent,
  engagedAt: _time,
  action: action ?? _action(),
  invertedAction: inverted,
);

ConceptUsageCheckpoint _start({
  String session = 'session',
  String owner = 'alice',
  int cycle = 1,
  int clothing = 5,
}) => ConceptUsageCheckpoint.startCycle(
  sessionId: session,
  ownerPlayerId: owner,
  cycle: cycle,
  initialClothing: clothing,
  catalog: ConceptCatalog.fromJson(
    _decode(File('assets/catalog/concepts/active.fr.json').readAsStringSync()),
  ),
);

ConceptUsageCheckpoint _engage(
  ConceptUsageCheckpoint state,
  String intent, {
  int stage = 1,
  int value = 7,
}) => state.engage(
  intentId: intent,
  conceptId: '019',
  resolveAction: () => _action(stage: stage, value: value),
  clock: () => _time,
);

Map<String, void Function()> conceptUsageChecks() => {
  'two engaged uses of the same concept receive distinct stable identities':
      () {
        final checkpoint = _engage(_engage(_start(), 'first'), 'second');
        final a = checkpoint.usageForIntent('first')!;
        final b = checkpoint.usageForIntent('second')!;
        _check(
          a.conceptId == b.conceptId && a.usageId != b.usageId,
          'Usage identity reused',
        );
        _check(checkpoint.stock.remainingFor('019') == 1, 'Concept quota');
      },
  'using the same stage three times creates three usages and spends one shared quota':
      () {
        var checkpoint = _start();
        for (final intent in ['a', 'b', 'c']) {
          checkpoint = _engage(checkpoint, intent);
        }
        final usages = checkpoint.usagesByIntent.values.toList();
        _check(
          usages.map((u) => u.usageId).toSet().length == 3,
          'Duplicate usages',
        );
        _check(
          usages.every((u) => u.action.stageId == '019.stage.1'),
          'Stage was consumed',
        );
        _check(
          checkpoint.stock.remainingFor('019') == 0 &&
              checkpoint.stock.capacity['019'] == 3 &&
              checkpoint.stock.remainingFor('001') == 1,
          'Quota belongs to concept, not stage or usage ID',
        );
        _throws<StateError>(() => _engage(checkpoint, 'd'));
      },
  'usage serialization restores the same identity and complete snapshot': () {
    final original = _snapshot();
    final restored = ConceptUsageSnapshot.fromJson(_decode(original.encode()));
    _check(
      restored.usageId == original.usageId &&
          restored.encode() == original.encode(),
      'Snapshot round trip',
    );
    _check(restored.engagedAt == _time, 'Engagement timestamp');
  },
  'checkpoint serialization restores usages and quota together': () {
    final original = _engage(_start(), 'a');
    final restored = ConceptUsageCheckpoint.fromJson(
      _decode(original.encode()),
    );
    _check(restored.encode() == original.encode(), 'Checkpoint round trip');
    _check(
      restored.stock.remainingFor('019') == 2 &&
          restored.usageForIntent('a')!.usageId ==
              original.usageForIntent('a')!.usageId,
      'Quota/usage checkpoint lost',
    );
  },
  'retry returns original usage before resolver, time or quota are touched':
      () {
        final original = _engage(_start(), 'retry-key');
        final retry = original.engage(
          intentId: 'retry-key',
          conceptId: '019',
          resolveAction: () =>
              throw StateError('Retry re-resolved current state'),
          resolveInvertedAction: () =>
              throw StateError('Retry re-resolved inversion'),
          clock: () => throw StateError('Retry changed engagement time'),
        );
        _check(
          identical(original, retry) && retry.stock.remainingFor('019') == 2,
          'Retry made a new usage or consumed twice',
        );
      },
  'retry after reconstruction remains identical even if current profile changes':
      () {
        final first = _engage(_start(), 'persisted-command', value: 7);
        final restored = ConceptUsageCheckpoint.fromJson(
          _decode(first.encode()),
        );
        final retried = _engage(
          restored,
          'persisted-command',
          stage: 3,
          value: 19,
        );
        final usage = retried.usageForIntent('persisted-command')!;
        _check(
          usage.encode() == first.usageForIntent('persisted-command')!.encode(),
          'Retry changed frozen resolved data',
        );
        _check(
          usage.action.personalValues.first.value == 7 &&
              usage.action.stageId == '019.stage.1',
          'Retry used current preference/stage',
        );
      },
  'retry still succeeds after the last available concept use': () {
    var checkpoint = _start();
    for (final intent in ['a', 'b', 'c']) {
      checkpoint = _engage(checkpoint, intent);
    }
    _check(checkpoint.stock.remainingFor('019') == 0, 'Fixture quota');
    _check(
      identical(_engage(checkpoint, 'c'), checkpoint),
      'Retry checked quota too early',
    );
  },
  'intent scope distinguishes owner session cycle and delimiter-containing keys':
      () {
        final ids = {
          ConceptUsageSnapshot.identityFor('s', 'alice', 1, 'a/b'),
          ConceptUsageSnapshot.identityFor('s', 'bob', 1, 'a/b'),
          ConceptUsageSnapshot.identityFor('s2', 'alice', 1, 'a/b'),
          ConceptUsageSnapshot.identityFor('s', 'alice', 2, 'a/b'),
          ConceptUsageSnapshot.identityFor('s/a', 'b', 1, 'x'),
          ConceptUsageSnapshot.identityFor('s', 'a/b', 1, 'x'),
        };
        _check(ids.length == 6, 'Scoped identity collision');
        _check(
          ConceptUsageSnapshot.identityFor('s', 'alice', 1, 'a/b') == ids.first,
          'Identity is not deterministic',
        );
      },
  'snapshot deeply copies resolved data and exposes immutable nested values':
      () {
        final source = _actionJson();
        final action = ResolvedConceptAction.fromJson(source);
        final snapshot = _snapshot(action: action);
        final before = snapshot.encode();
        (((source['parameters'] as JsonMap)['nested'] as JsonMap)['selected']
                as List)
            .add('changed');
        (source['personal_values'] as List).clear();
        (source['tags'] as List).clear();
        _check(snapshot.encode() == before, 'Snapshot aliases mutable source');
        _throws<UnsupportedError>(() => snapshot.toJson().clear());
        _throws<UnsupportedError>(() => snapshot.action.parameters.clear());
        _throws<UnsupportedError>(
          () =>
              ((snapshot.action.parameters['nested'] as JsonMap)['selected']
                      as List)
                  .clear(),
        );
        _throws<UnsupportedError>(() => snapshot.action.personalValues.clear());
        _throws<UnsupportedError>(
          () => snapshot.action.personalValues.first.toJson().clear(),
        );
        _throws<UnsupportedError>(() => snapshot.action.tags.clear());
      },
  'reconstruction needs no catalogue current profile clothing or inventory':
      () {
        final source = _actionJson(
          conceptId: '005',
          variantId: '005.zone.free',
          zoneId: 'arms_hands',
        );
        source['parameters'] = {
          'clothing_delta': -1,
          'selected_zone': 'arms_hands',
        };
        source['action_text'] =
            'Instruction résolue : zone bras / mains (fixture).';
        final original = _snapshot(
          action: ResolvedConceptAction.fromJson(source),
        );
        final encoded = original.encode();
        source['effective_chili'] = 4;
        source['zone_id'] = 'vulva';
        source['catalog_version'] = 99;
        source['action_text'] = 'Changed catalogue text';
        final restored = ConceptUsageSnapshot.fromJson(_decode(encoded));
        final action = restored.reconstruct();
        _check(
          action.zoneId == 'arms_hands' &&
              action.effectiveChili == 1 &&
              action.parameters['clothing_delta'] == -1 &&
              action.catalogVersion == 1 &&
              action.actionText.contains('bras / mains'),
          'Historical reinterpretation',
        );
      },
  'concrete accessory and resolved effects survive independent of live inventory':
      () {
        final source = _actionJson(conceptId: '049', variantId: '049.external');
        source['accessories'] = [
          {'accessory_id': 'device-17', 'label': 'Appareil choisi'},
        ];
        source['tags'] = ['v3.preference.test', 'equipment.chosen'];
        source['effects'] = [
          {
            'effect_id': 'fixture.effect',
            'parameters': {'duration_actions': 3},
          },
        ];
        final original = _snapshot(
          action: ResolvedConceptAction.fromJson(source),
        );
        (source['accessories'] as List).clear();
        (source['effects'] as List).clear();
        final restored = ConceptUsageSnapshot.fromJson(
          _decode(original.encode()),
        );
        _check(
          restored.action.accessories.single.accessoryId == 'device-17' &&
              restored.action.effects.single.parameters['duration_actions'] ==
                  3 &&
              restored.action.tags.contains('equipment.chosen'),
          'Resolved inventory/effects lost',
        );
        _throws<UnsupportedError>(
          () => restored.action.effects.single.parameters.clear(),
        );
      },
  'optional inverted resolution is frozen without mutating original usage': () {
    final invertedJson = _actionJson(value: 15);
    invertedJson['direction'] = 'RECEVOIR';
    invertedJson['actor_player_ids'] = ['bob'];
    invertedJson['target_player_ids'] = ['alice'];
    (invertedJson['personal_values'] as List)[0] = {
      'player_id': 'alice',
      'role': 'RECEVOIR',
      'value': 15,
    };
    final usage = _snapshot(
      inverted: ResolvedConceptAction.fromJson(invertedJson),
    );
    final before = usage.encode();
    final inverted = usage.reconstruct(inverted: true);
    _check(
      inverted.actorPlayerIds.single == 'bob' &&
          inverted.personalValues.first.value == 15,
      'Inversion read current roles/value',
    );
    _check(
      usage.reconstruct().actorPlayerIds.single == 'alice' &&
          usage.encode() == before,
      'Original snapshot changed',
    );
    final restored = ConceptUsageSnapshot.fromJson(_decode(before));
    _check(
      canonicalUsageJson(restored.reconstruct(inverted: true).toJson()) ==
          canonicalUsageJson(inverted.toJson()),
      'Inverted round trip',
    );
    _throws<StateError>(() => _snapshot().reconstruct(inverted: true));
  },
  'inversion cannot substitute a different stage or concept': () {
    _throws<CatalogException>(() => _snapshot(inverted: _action(stage: 2)));
  },
  'round-state codec preserves unrelated state and round trips the complete checkpoint':
      () {
        const codec = ConceptUsageCheckpointCodec();
        final original = _engage(_start(), 'a');
        final oldState = <String, Object?>{
          'round_marker': 8,
          'existing': {'kept': true},
        };
        final attached = codec.attach(
          roundState: oldState,
          checkpoint: original,
        );
        _check(
          !oldState.containsKey(ConceptUsageCheckpointCodec.key),
          'Legacy state mutated',
        );
        final round = PersistedRoundState(
          roundId: 'r1',
          ordinal: 1,
          status: RoundPersistenceStatus.INTERRUPTED,
          state: attached,
          startedAt: _time,
          updatedAt: _time,
        );
        // SessionRepository already writes this state as JSON in rounds.state_json.
        final restoredState = _decode(jsonEncode(round.state));
        final restored = codec.read(restoredState)!;
        _check(
          restored.encode() == original.encode() &&
              restoredState['round_marker'] == 8 &&
              (restoredState['existing'] as JsonMap)['kept'] == true,
          'Existing JSON checkpoint path',
        );
        _check(
          codec.read({'legacy_only': true}) == null,
          'Implicit legacy conversion',
        );
        _throws<UnsupportedError>(() => attached.clear());
      },
  'local JSON file reopen restores exact snapshot and idempotent retry': () {
    final dir = Directory('.tooling').createTempSync('concept-usage-test-');
    final file = File('${dir.path}/checkpoint.json');
    try {
      final original = _engage(_start(), 'saved-command');
      file.writeAsStringSync(original.encode(), flush: true);
      final restored = ConceptUsageCheckpoint.fromJson(
        _decode(file.readAsStringSync()),
      );
      final retry = _engage(restored, 'saved-command', value: 20);
      _check(
        retry.encode() == original.encode() &&
            retry.stock.remainingFor('019') == 2,
        'Reopen changed usage or double-spent quota',
      );
    } finally {
      if (file.existsSync()) file.deleteSync();
      dir.deleteSync();
    }
  },
  'persisted stock capacities restore without current clothing or catalogue access':
      () {
        final initial = _start(clothing: 7);
        final restored = ConceptUsageCheckpoint.fromJson(
          _decode(initial.encode()),
        );
        _check(
          restored.stock.capacity['006'] == 2 &&
              restored.stock.capacity['007'] == 3,
          'Initial clothing capacity was recalculated',
        );
        final stock = ConceptDeckStock.fromJson(
          _decode(canonicalUsageJson(restored.stock.toJson())),
        );
        _check(stock.capacity['007'] == 3, 'Stock codec needs current clothes');
      },
  'new intent can freeze a new value without altering previous uses': () {
    final checkpoint = _engage(
      _engage(_start(), 'a', value: 7),
      'b',
      stage: 2,
      value: 16,
    );
    _check(
      checkpoint.usageForIntent('a')!.action.personalValues.first.value == 7 &&
          checkpoint.usageForIntent('b')!.action.personalValues.first.value ==
              16 &&
          checkpoint.stock.remainingFor('019') == 1,
      'New use altered history or stage quota',
    );
  },
  'source usage reference is provenance, never identity reuse or automatic replay':
      () {
        final first = _engage(_start(), 'duel');
        final sourceId = first.usageForIntent('duel')!.usageId;
        final next = first.engage(
          intentId: 'secondary',
          conceptId: '019',
          sourceUsageId: sourceId,
          resolveAction: () => _action(stage: 2),
          clock: () => _time,
        );
        final secondary = next.usageForIntent('secondary')!;
        _check(
          secondary.usageId != sourceId &&
              secondary.sourceUsageId == sourceId &&
              next.stock.remainingFor('019') == 1,
          'Secondary provenance reused identity/quota',
        );
      },
  'resolution or clock failure leaves original checkpoint and quota intact':
      () {
        final checkpoint = _start();
        _throws<StateError>(
          () => checkpoint.engage(
            intentId: 'a',
            conceptId: '019',
            resolveAction: () => throw StateError('resolution failed'),
            clock: () => _time,
          ),
        );
        _throws<StateError>(
          () => checkpoint.engage(
            intentId: 'b',
            conceptId: '019',
            resolveAction: _action,
            clock: () => throw StateError('clock failed'),
          ),
        );
        _check(
          checkpoint.usagesByIntent.isEmpty &&
              checkpoint.stock.remainingFor('019') == 3,
          'Partial in-memory engagement',
        );
      },
  'reusing intent for another concept fails without modifying either quota':
      () {
        final checkpoint = _engage(_start(), 'a');
        _throws<StateError>(
          () => checkpoint.engage(
            intentId: 'a',
            conceptId: '001',
            resolveAction: _action,
            clock: () => _time,
          ),
        );
        _check(
          checkpoint.stock.remainingFor('019') == 2 &&
              checkpoint.stock.remainingFor('001') == 1,
          'Conflicting intent spent quota',
        );
      },
  'checkpoint and nested serialized data are immutable': () {
    final checkpoint = _engage(_start(), 'a');
    _throws<UnsupportedError>(() => checkpoint.usagesByIntent.clear());
    final json = checkpoint.toJson();
    _throws<UnsupportedError>(() => (json['usages'] as List).clear());
    _throws<UnsupportedError>(
      () => ((json['stock'] as JsonMap)['remaining'] as JsonMap).clear(),
    );
  },
  'canonical JSON ignores map insertion order without changing action data':
      () {
        final source = _actionJson();
        final reordered = <String, Object?>{
          for (final key in source.keys.toList().reversed) key: source[key],
        };
        _check(
          _snapshot(action: ResolvedConceptAction.fromJson(source)).encode() ==
              _snapshot(
                action: ResolvedConceptAction.fromJson(reordered),
              ).encode(),
          'Canonical encoding',
        );
      },
  'malformed usage identity or unsupported schema is not silently reinterpreted':
      () {
        final badId = _decode(_snapshot().encode());
        badId['usage_id'] = '019';
        _throws<CatalogException>(() => ConceptUsageSnapshot.fromJson(badId));
        final badSchema = _decode(_snapshot().encode());
        badSchema['schema_version'] = 2;
        _throws<CatalogException>(
          () => ConceptUsageSnapshot.fromJson(badSchema),
        );
      },
  'checkpoint rejects duplicate intents and mismatched scope': () {
    final original = _engage(_start(), 'a');
    final duplicate = _decode(original.encode());
    (duplicate['usages'] as List).add((duplicate['usages'] as List).first);
    _throws<CatalogException>(() => ConceptUsageCheckpoint.fromJson(duplicate));
    final wrongScope = _decode(original.encode());
    wrongScope['session_id'] = 'other';
    _throws<CatalogException>(
      () => ConceptUsageCheckpoint.fromJson(wrongScope),
    );
  },
  'checkpoint rejects separated journal and quota updates': () {
    final bad = _decode(_engage(_start(), 'a').encode());
    ((bad['stock'] as JsonMap)['remaining'] as JsonMap)['019'] = 3;
    _throws<CatalogException>(() => ConceptUsageCheckpoint.fromJson(bad));
  },
  'stock codec rejects unmatched keys negative quotas and over-capacity counters':
      () {
        final original = _start().stock.toJson();
        for (final value in [-1, 4]) {
          final bad = _decode(jsonEncode(original));
          (bad['remaining'] as JsonMap)['019'] = value;
          _throws<CatalogException>(() => ConceptDeckStock.fromJson(bad));
        }
        final badKeys = _decode(jsonEncode(original));
        (badKeys['remaining'] as JsonMap).remove('019');
        _throws<CatalogException>(() => ConceptDeckStock.fromJson(badKeys));
      },
  'resolved action requires a chosen definition actor and concrete personal value':
      () {
        final noDefinition = _actionJson()..remove('stage_id');
        _throws<CatalogException>(
          () => ResolvedConceptAction.fromJson(noDefinition),
        );
        final twoDefinitions = _actionJson()..['variant_id'] = '019.other';
        _throws<CatalogException>(
          () => ResolvedConceptAction.fromJson(twoDefinitions),
        );
        final noActor = _actionJson()..['actor_player_ids'] = <Object?>[];
        _throws<CatalogException>(
          () => ResolvedConceptAction.fromJson(noActor),
        );
        final noValue = _actionJson()..['personal_values'] = <Object?>[];
        _throws<CatalogException>(
          () => ResolvedConceptAction.fromJson(noValue),
        );
      },
  'existing media persistence guard still applies to nested resolved parameters':
      () {
        const codec = ConceptUsageCheckpointCodec();
        final bad = _actionJson();
        bad['parameters'] = {'photo_path': 'not-to-be-stored'};
        final checkpoint = _start().engage(
          intentId: 'a',
          conceptId: '019',
          resolveAction: () => ResolvedConceptAction.fromJson(bad),
          clock: () => _time,
        );
        _throws<ArgumentError>(
          () => codec.attach(roundState: {}, checkpoint: checkpoint),
        );
      },
};
