import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:couple_cards/core/json.dart';
import 'package:couple_cards/data/catalog_loader/catalog_loader.dart';
import 'package:couple_cards/domain/catalog/concept_catalog.dart';
import 'package:couple_cards/domain/catalog/enums.dart';
import 'package:couple_cards/domain/game/game_models.dart';
import 'package:couple_cards/domain/profile/accessory_compatibility.dart';
import 'package:couple_cards/domain/round/concept_usage_snapshot.dart';
import 'package:couple_cards/engines/deck/concept_deck_engine.dart';
import 'package:couple_cards/engines/eligibility/catalog_engine_adapter.dart';
import 'package:couple_cards/engines/eligibility/concept_runtime_catalog.dart';
import 'package:couple_cards/engines/eligibility/concept_action_options.dart';
import 'package:couple_cards/engines/usage/concept_usage_checkpoint.dart';
import 'package:couple_cards/sync/commit_reveal/commit_reveal.dart';
import 'package:couple_cards/sync/protocol/network_usage_projection.dart';
import 'package:couple_cards/sync/rounds/network_game.dart';

JsonMap _read(String path) =>
    jsonDecode(File(path).readAsStringSync()) as JsonMap;
void _check(bool value, String message) {
  if (!value) throw StateError(message);
}

Map<String, void Function()> conceptRuntimeChecks() {
  final source = const CatalogLoader().loadJson(
    cardsJson: File(
      'assets/catalog/source/cards.v2.fr.json',
    ).readAsStringSync(),
    profilesJson: File(
      'assets/catalog/source/profile_elements.v1.fr.json',
    ).readAsStringSync(),
    tagsJson: File('assets/catalog/source/tags.v1.json').readAsStringSync(),
  );
  final concepts = ConceptCatalog.fromJson(
    _read('assets/catalog/concepts/active.fr.json'),
  );
  final catalog = ConceptRuntimeCatalog(
    concepts: concepts,
    source: source,
    rules: _read('assets/catalog/concepts/runtime_rules.fr.json'),
  );
  final preferences = {
    for (final value
        in _read('assets/catalog/source/catalog_v3_taxonomy.json')['tags']!
            as List)
      if ((value as JsonMap)['category'] == 'PREFERENCE')
        value['stable_id']! as String: const PreferenceValue(
          status: PreferenceStatus.ACCEPTED,
          general: 10,
          faire: 11,
          recevoir: 12,
        ),
  };
  PlayerGameProfile profile(
    String id, [
    Map<String, PreferenceValue> overrides = const {},
  ]) => PlayerGameProfile(
    playerId: id,
    preferences: {...preferences, ...overrides},
  );
  Map<String, List<ConceptActionOption>> options({
    int chili = 4,
    bool distance = false,
    bool media = true,
    bool send = false,
    bool recovery = false,
    Map<String, PreferenceValue> overrides = const {},
    Map<String, bool> flags = const {},
  }) => const ConceptActionOptions().evaluate(
    catalog: catalog,
    context: EngineSessionContext(
      mode: distance ? SessionMode.distance : SessionMode.face_to_face,
      proximity: distance ? ProximityState.SEPARATED : ProximityState.TOGETHER,
      chiliActive: chili,
      chiliUnlocked: chili,
      clothesByPlayer: {'alice': 5, 'bob': 5},
      flags: flags,
      mediaCapabilitiesByPlayer: media
          ? {
              for (final id in ['alice', 'bob'])
                id: MediaCapability.values.toSet(),
            }
          : {},
    ),
    actor: profile('alice', overrides),
    partner: profile('bob'),
    hierarchy: ProfileHierarchy({}),
    mediaSendRequired: send,
    recovery: recovery,
  );
  ConceptUsageCheckpoint start() => ConceptUsageCheckpoint.startCycle(
    sessionId: 'session',
    ownerPlayerId: 'alice',
    cycle: 1,
    catalog: concepts,
    initialClothing: 5,
  );
  ConceptDeckPool pool(
    Map<String, List<ConceptActionOption>> choices,
    ConceptUsageCheckpoint checkpoint, {
    int chili = 4,
    Set<String> held = const {},
  }) => const ConceptDeckEngine().prepare(
    catalog: concepts,
    stock: checkpoint.stock,
    globalChili: chili,
    style: PlayerStyle.SOFT,
    unavailableConceptIds: {
      ...held,
      for (final id in checkpoint.stock.remaining.keys)
        if (checkpoint.availableFor(id) == 0) id,
    },
    eligibility: ConceptDeckEligibility(
      actionIdsByConcept: {
        for (final e in choices.entries)
          e.key: e.value.map((o) => o.choice.actionId).toSet(),
      },
      zoneIdsByConcept: {
        for (final e in choices.entries)
          e.key: e.value.map((o) => o.choice.zoneId).nonNulls.toSet(),
      },
    ),
  );
  final at = DateTime.utc(2026, 10, 15, 12);
  ConceptUsageCheckpoint engage(
    ConceptUsageCheckpoint checkpoint,
    String intent,
  ) => checkpoint.engage(
    intentId: intent,
    conceptId: '019',
    clock: () => at,
    resolveAction: () => ResolvedConceptAction.fromJson({
      'concept_id': '019',
      'catalog_version': 1,
      'locale': 'fr-FR',
      'stage_id': '019.stage.1',
      'effective_chili': 3,
      'direction': 'FAIRE',
      'actor_player_ids': ['alice'],
      'target_player_ids': ['bob'],
      'parameters': {'committed_at': at.toIso8601String()},
      'accessories': <Object?>[],
      'tags': ['v3.preference.masturbation'],
      'primary_preference_ids': ['v3.preference.masturbation'],
      'personal_values': [
        {'player_id': 'alice', 'role': 'FAIRE', 'value': 7},
      ],
      'effects': <Object?>[],
      'action_text': 'Instruction figée',
    }),
  );
  NetworkUsageProjection projection() => NetworkUsageProjection.fromSnapshot(
    engage(start(), 'intent').usageForIntent('intent')!,
    sharedParameterKeys: const {'committed_at'},
    sharedEffectIds: const {},
    includePersonalValue: true,
  );

  return {
    'Recovery keeps its existing spice exception while other eligibility and accessory exclusions remain':
        () {
          final normal = options(chili: 1);
          final recovery = options(chili: 1, recovery: true);
          _check(
            !normal.containsKey('019') && recovery.containsKey('019'),
            'Recovery ceiling exception lost',
          );
          _check(
            !options(
              chili: 1,
              recovery: true,
              distance: true,
            ).containsKey('019'),
            'Recovery bypassed orientation',
          );
          for (final id in ['049', '050', '051', '052']) {
            _check(
              !recovery.containsKey(id),
              'Recovery fabricated an accessory',
            );
          }
        },
    'P4 sextoy metadata preserves self role insertion preferences and validated capabilities':
        () {
          for (final id in ['049', '050', '051', '052']) {
            for (final variant in catalog.definitions[id]!.variants) {
              final rules = variant.v3!;
              final insertion = variant.stableId.endsWith('insertion');
              _check(
                rules.tags.contains('v3.preference.sextoy'),
                'Missing sextoy preference',
              );
              _check(
                rules.tags.contains('v3.preference.penetrer') == insertion,
                'Wrong insertion preference',
              );
              _check(
                variant.chiliLevel == (insertion ? 4 : 3),
                'Wrong accessory spice',
              );
              if (id == '050') {
                _check(
                  rules.tags.toSet().containsAll({
                        'v3.preference.masturbation',
                        'v3.direction.solo',
                      }) &&
                      !rules.requirements.distanceExcluded,
                  'Wrong self action',
                );
              }
              if (id == '052') {
                _check(
                  rules.tags.toSet().containsAll({
                    'v3.preference.vibrant',
                    'v3.preference.controle_distance',
                    'v3.preference.controle',
                  }),
                  'Remote preferences lost',
                );
                _check(
                  rules.requirements.requiresSextoy &&
                      rules.requirements.requiresVibratingToy &&
                      rules.requirements.requiresRemoteControlToy &&
                      !rules.requirements.distanceExcluded,
                  'Remote capabilities lost',
                );
              }
              _check(
                requiredAccessoryTags(id, variant.stableId).length ==
                    (id == '052' ? 2 : 1),
                'Wrong required tag conjunction',
              );
            }
          }
        },
    'round DTO preserves the deployed usage-contract marker': () {
      final round = NetworkGameRoundStateDto(
        usageContractVersion: 1,
        roundId: 'r',
        sessionId: 's',
        sessionRound: 's.r',
        roundNumber: 1,
        phase: NetworkGamePhase.commit,
        playerId: 'alice',
        commits: const {},
        actionPoints: const {'alice': 100, 'bob': 100},
        readyNextPlayerIds: const {},
        tieDecisions: const {},
      );
      _check(
        NetworkGameRoundStateDto.fromJson(
              round.toJson(),
            ).usageContractVersion ==
            1,
        'Contract marker lost',
      );
    },
    'all 56 concepts retain new IDs and every validated stage spice': () {
      _check(catalog.definitions.length == 56, 'Wrong count');
      for (final concept in concepts.concepts) {
        final engine = const CatalogEngineAdapter.v3().card(
          catalog.definitions[concept.id]!,
        );
        _check(
          engine.id == concept.id && engine.enabled,
          'Legacy concept leaked',
        );
        _check(
          engine.variants.every(
            (v) => v.enabled && v.id.startsWith('${concept.id}.'),
          ),
          'Legacy action leaked',
        );
        for (final stage in concept.stages) {
          _check(
            engine.variants.singleWhere((v) => v.id == stage.id).chiliLevel ==
                stage.chili,
            'Source spice leaked',
          );
        }
      }
    },
    'refill holds one concept once regardless of stages without consuming quota':
        () {
          final choices = options();
          final held = <String>{};
          final checkpoint = start();
          final random = Random(5);
          for (var i = 0; i < 4; i++) {
            _check(
              held.add(
                pool(choices, checkpoint, held: held).draw(random)!.concept.id,
              ),
              'Duplicate',
            );
          }
          _check(
            held.length == 4 && checkpoint.usagesByIntent.isEmpty,
            'Draw engaged an action',
          );
        },
    'held concept gains newly accessible stages without being replaced': () {
      final low = options(chili: 1)['045']!;
      final high = options()['045']!;
      _check(low.length == 1 && high.length == 3, 'Wrong choices');
      _check(
        low.single.choice.actionId == high.first.choice.actionId,
        'Identity replaced',
      );
      _check(
        high.map((o) => o.choice.chili).join('/') == '1/2/4',
        'Wrong progression',
      );
    },
    'free zones enforce real spice while only draw class receives minus one':
        () {
          final choices = options(chili: 2);
          _check(
            choices['005']!.every(
              (o) => o.choice.chili <= 2 && o.choice.zoneId != 'vulva',
            ),
            'Zone ceiling bypass',
          );
          final candidate = pool(choices, start(), chili: 2).classes.values
              .expand((v) => v)
              .singleWhere((c) => c.concept.id == '005');
          _check(
            candidate.drawClass == 1 &&
                candidate.choices.any((c) => c.chili == 2),
            'Real spice reduced',
          );
        },
    'P1 fingers uses existing preferences and intrinsic spice without material':
        () {
          final choices = options()['022']!;
          _check(
            choices.map((o) => o.choice.chili).join('/') == '3/4/4',
            'Wrong spice',
          );
          _check(
            choices.every(
              (o) => o.variant.tags.containsAll({
                'v3.preference.penetrer',
                'v3.preference.doigts',
                'v3.zone.vaginal',
              }),
            ),
            'Wrong composition',
          );
          _check(!options(distance: true).containsKey('022'), 'Distance leak');
        },
    'P2 footjob uses masturbation semantic feet and excludes distance': () {
      final choice = options()['065']!.single;
      _check(
        choice.variant.tags.containsAll({
              'v3.preference.masturbation',
              'v3.zone.pieds',
            }) &&
            choice.choice.chili == 3,
        'Wrong rules',
      );
      _check(!options(distance: true).containsKey('065'), 'Distance leak');
    },
    'P3 mutual media never introduces an implicit sexual practice': () {
      for (final id in ['045', '047']) {
        for (final choice in options()[id]!) {
          _check(
            choice.variant.tags.containsAll({
              'v3.direction.mutuel',
              'v3.preference.etre_regarde',
            }),
            'Not mutual',
          );
          _check(
            !choice.variant.tags.contains('v3.preference.penetrer') &&
                !choice.parameters.containsKey('practice_concept_id'),
            'Implicit practice',
          );
        }
      }
    },
    'media sending preferences are conditional on an actual send requirement':
        () {
          _check(
            options()['045']!.every(
              (o) => !o.variant.tags.contains('v3.preference.envoyer'),
            ),
            'Unnecessary send',
          );
          _check(
            options(send: true)['045']!.every(
              (o) => o.variant.tags.contains('v3.preference.envoyer'),
            ),
            'Missing required send',
          );
        },
    'P5 media is available in either orientation only with needed capture capabilities':
        () {
          for (final id in ['044', '045', '046', '047']) {
            _check(
              options(distance: true).containsKey(id) &&
                  options().containsKey(id),
              'Old contradiction',
            );
            _check(
              !options(media: false).containsKey(id),
              'No capture allowed',
            );
          }
        },
    'P6 mouth separates techniques and respects individual exclusions': () {
      final choices = options(chili: 1)['004']!;
      _check(
        choices.map((o) => o.parameters['technique']).toSet().containsAll({
          'lecher',
          'sucer',
        }),
        'Technique missing',
      );
      _check(
        choices.every(
          (o) =>
              !o.variant.tags.contains('v3.zone.parties_intimes') &&
              !o.variant.tags.contains('v3.zone.anal'),
        ),
        'Sexual practice copied',
      );
      final excluded = options(
        overrides: {
          'v3.preference.lecher': const PreferenceValue(
            status: PreferenceStatus.EXCLUDED,
          ),
        },
      )['004']!;
      _check(
        excluded.every((o) => o.parameters['technique'] == 'sucer'),
        'Exclusion bypass',
      );
    },
    'P6 joker borrows compatible rules while retaining 024 identity and quota':
        () {
          final borrowed = options()['024']!.first;
          _check(
            borrowed.choice.actionId == '024.action' &&
                borrowed.parameters['practice_concept_id'] != '024',
            'Wrong identity',
          );
          final checkpoint = start().reserve(
            intentId: 'joker',
            conceptId: '024',
          );
          _check(
            checkpoint.availableFor('024') == 0 &&
                checkpoint.stock.remainingFor('019') == 3,
            'Other quota spent',
          );
          _check(!options(chili: 2).containsKey('024'), 'Ceiling bypass');
        },
    'P6 outfit uses TENUE and self direction in all contexts': () {
      final choice = options()['013']!.single;
      _check(
        choice.variant.tags
                .where((t) => t.startsWith('v3.preference.'))
                .single ==
            'v3.preference.tenue',
        'Unrequested preferences',
      );
      _check(
        choice.variant.tags.contains('v3.direction.solo') &&
            options(distance: true).containsKey('013'),
        'Wrong direction/context',
      );
    },
    'all required preferences need one coherent permitted direction': () {
      final choices = options(
        overrides: {
          'v3.preference.penetrer': const PreferenceValue(
            status: PreferenceStatus.ACCEPTED,
            faire: 10,
          ),
          'v3.preference.doigts': const PreferenceValue(
            status: PreferenceStatus.ACCEPTED,
            recevoir: 10,
          ),
        },
      );
      _check(
        !choices.containsKey('022'),
        'Mixed incompatible directions admitted',
      );
    },
    'orientation filters physical concepts without removing compatible media':
        () {
          _check(
            options().containsKey('001') &&
                !options(distance: true).containsKey('001'),
            'Orientation ignored',
          );
          _check(
            options().containsKey('044') &&
                options(distance: true).containsKey('044'),
            'Compatible media lost',
          );
        },
    'reservation reconnect and pre-engagement cancellation preserve quota': () {
      final saved = start().reserve(intentId: 'pending', conceptId: '019');
      final restored = ConceptUsageCheckpoint.fromJson(
        jsonDecode(saved.encode()) as JsonMap,
      );
      _check(
        restored.availableFor('019') == 2 &&
            restored.stock.remainingFor('019') == 3,
        'Lost reservation',
      );
      _check(
        restored.releaseReservation('pending').availableFor('019') == 3 &&
            restored.usagesByIntent.isEmpty,
        'Cancellation spent quota',
      );
    },
    'same stage can engage three times and retry after exhaustion spends nothing':
        () {
          var checkpoint = start();
          for (final intent in ['a', 'b', 'c']) {
            checkpoint = engage(
              checkpoint.reserve(intentId: intent, conceptId: '019'),
              intent,
            );
          }
          _check(
            checkpoint.stock.remainingFor('019') == 0 &&
                checkpoint.usagesByIntent.values
                        .map((u) => u.usageId)
                        .toSet()
                        .length ==
                    3,
            'Wrong quota or identity',
          );
          _check(
            identical(engage(checkpoint, 'c'), checkpoint),
            'Retry spent again',
          );
          _check(
            !pool(
              options(),
              checkpoint,
            ).classes.values.expand((v) => v).any((c) => c.concept.id == '019'),
            'Exhausted concept drawn',
          );
        },
    'native reveal roundtrip preserves usage and canonical commit digest': () {
      final choice = ChoicePayload.fromUsage(projection());
      final restored = ChoicePayload.fromJson(
        jsonDecode(choice.canonicalJson()) as JsonMap,
      );
      _check(
        restored.usageId == choice.usageId &&
            restored.canonicalJson() == choice.canonicalJson(),
        'Reveal changed',
      );
      _check(
        !choice.toJson().containsKey('card_id') &&
            !choice.toJson().containsKey('occurrence_id'),
        'Legacy aliases leaked',
      );
      const contract = CommitRevealContract();
      _check(
        contract
                .commit(
                  sessionRound: 'r',
                  playerId: 'alice',
                  choice: choice,
                  nonce: 'n',
                )
                .digest ==
            contract
                .commit(
                  sessionRound: 'r',
                  playerId: 'alice',
                  choice: restored,
                  nonce: 'n',
                )
                .digest,
        'Digest changed',
      );
    },
    'initial compromise DTO retains frozen native action without legacy JSON aliases':
        () {
          final native = projection().resolved(inverted: false).toJson();
          final card = NetworkCompromiseCardDto.fromJson({
            ...native,
            'origin': 'INITIAL_DUEL',
            'logical_order': 0,
          });
          _check(
            card.usage.usageId == native['usage_id'] &&
                jsonEncode(card.toJson()['resolved_action']) ==
                    jsonEncode(native['resolved_action']),
            'Frozen action lost',
          );
          _check(
            !card.toJson().containsKey('occurrence_id'),
            'Legacy alias leaked',
          );
        },
    'accessory tags require AND on the same item regardless of owner': () {
      final a = TaggedSessionAccessory(
        id: 'a',
        label: 'A',
        ownerPlayerId: 'bob',
        tags: {AccessoryCompatibilityTag.ANAL},
      );
      final b = TaggedSessionAccessory(
        id: 'b',
        label: 'B',
        ownerPlayerId: 'alice',
        tags: {AccessoryCompatibilityTag.VIBRANT},
      );
      final required = requiredAccessoryTags('052', '052.anal_insertion');
      final untagged = TaggedSessionAccessory(
        id: 'ANAL_VIBRANT',
        label: 'ANAL VIBRANT',
        ownerPlayerId: 'alice',
        tags: {},
      );
      _check(!untagged.supports(required), 'Tags inferred from name or ID');
      _check(
        !a.supports(required) && !b.supports(required),
        'Combined distinct items',
      );
      final both = TaggedSessionAccessory(
        id: 'c',
        label: 'C',
        ownerPlayerId: 'bob',
        tags: required,
      );
      _check(
        both.supports(required) && both.preferenceTagSet == 'ANAL+VIBRANT',
        'Exact set or ownership error',
      );
      _check(
        a.preferenceTagSet != both.preferenceTagSet,
        'Subset treated as same preference',
      );
    },
    'hasSextoy flags cannot fabricate a compatible concrete accessory': () {
      final choices = options(
        flags: {
          'hasSextoy': true,
          'hasVibratingToy': true,
          'hasRemoteControlToy': true,
        },
      );
      _check(
        ['049', '050', '051', '052'].every((id) => !choices.containsKey(id)),
        'Permissive fallback',
      );
    },
  };
}
