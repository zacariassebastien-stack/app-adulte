import 'package:couple_cards/engines/corruption/corruption_engine.dart';
import 'package:couple_cards/engines/lifecycle/lifecycle_engine.dart';
import 'package:couple_cards/engines/recovery/recovery_engine.dart';
import 'dart:convert';
import 'dart:io';
import 'package:couple_cards/domain/catalog/concept_catalog.dart';
import 'package:couple_cards/domain/profile/adaptive_profile.dart';
import 'package:couple_cards/domain/round/concept_usage_snapshot.dart';
import 'package:couple_cards/engines/profile/profile_learning_engine.dart';
import 'package:couple_cards/engines/profile/completed_round_learning.dart';
import 'package:couple_cards/sync/projection/usage_learning_projection.dart';
import 'package:couple_cards/engines/usage/concept_usage_checkpoint.dart';
import 'package:couple_cards/sync/rounds/network_game.dart';
import 'package:couple_cards/sync/protocol/network_usage_projection.dart';
import '../../support/native_usage_fixture.dart';

void check(bool value, String reason) {
  if (!value) throw StateError(reason);
}

Map<String, void Function()> conceptSecondaryChecks() {
  final catalog = ConceptCatalog.fromJson(
    (jsonDecode(
              File('assets/catalog/concepts/active.fr.json').readAsStringSync(),
            )
            as Map)
        .cast<String, Object?>(),
  );
  ConceptUsageCheckpoint start() => ConceptUsageCheckpoint.startCycle(
    sessionId: 'session',
    ownerPlayerId: 'alice',
    cycle: 1,
    catalog: catalog,
    initialClothing: 5,
  );
  ResolvedConceptAction action() => ResolvedConceptAction.fromJson({
    ...nativeUsageFixture().resolvedAction,
    'personal_values': [
      {'player_id': 'alice', 'role': 'FAIRE', 'value': 10},
    ],
  });
  ConceptUsageCheckpoint engage(
    ConceptUsageCheckpoint state,
    String intent, {
    String? source,
  }) => state.engage(
    intentId: intent,
    conceptId: '019',
    resolveAction: action,
    clock: () => DateTime.utc(2026, 10, 15),
    sourceUsageId: source,
  );
  final hand = HandLearningEvent(playerId: 'alice', availableCards: []);
  AdaptiveProfileState learn(
    AdaptiveProfileState state,
    Set<String> done,
    List<NetworkUsageProjection> usages, {
    String event = 'session/round/alice',
  }) => recordCompletedUsageRound(
    state: state,
    eventId: event,
    expectedPlayers: {'alice', 'bob'},
    completedPlayers: done,
    hand: hand,
    accepted: usages.map(usageLearningOutcome).toList(),
  );
  return {
    'secondary proposal reserves a capacity and refusal releases it without a debit':
        () {
          final before = start();
          final reserved = before.reserve(intentId: 'offer', conceptId: '019');
          check(
            reserved.stock.remainingFor('019') ==
                before.stock.remainingFor('019'),
            'proposal spent quota',
          );
          check(
            reserved.availableFor('019') == before.availableFor('019') - 1,
            'capacity not reserved',
          );
          check(
            reserved.releaseReservation('offer').encode() == before.encode(),
            'refusal altered stock',
          );
        },
    'acceptance after serialized reservation consumes one and retry never resolves twice':
        () {
          final reserved = start().reserve(intentId: 'offer', conceptId: '019');
          final restored = ConceptUsageCheckpoint.fromJson(
            jsonDecode(reserved.encode()) as Map<String, Object?>,
          );
          final accepted = engage(restored, 'offer');
          final retry = accepted.engage(
            intentId: 'offer',
            conceptId: '019',
            resolveAction: () =>
                throw StateError('retry resolved current data'),
            clock: () => throw StateError('retry changed engagement time'),
          );
          check(retry.encode() == accepted.encode(), 'retry changed usage');
          check(
            retry.stock.remainingFor('019') ==
                reserved.stock.remainingFor('019') - 1,
            'wrong debit',
          );
        },
    'replay cannot create a new usage for a consumed stage': () {
      final first = engage(start(), 'duel');
      final original = first.usageForIntent('duel')!;
      var rejected = false;
      try {
        engage(first, 'replay', source: original.usageId);
      } on StateError {
        rejected = true;
      }
      check(rejected, 'Consumed stage replay accepted');
      check(
        first.stock.remainingFor('019') == 2,
        'Rejected replay spent quota',
      );
    },
    'including an engaged usage in a compromise preserves identity without a second debit':
        () {
          final accepted = engage(start(), 'duel');
          final usage = accepted.usageForIntent('duel')!;
          final projection = NetworkUsageProjection.fromSnapshot(
            usage,
            sharedParameterKeys: {},
            sharedEffectIds: {},
            includePersonalValue: true,
          );
          final card = NetworkCompromiseCardDto.fromUsage(
            projection,
            origin: NetworkCompromiseOrigin.INITIAL_DUEL,
          );
          final read = NetworkCompromiseCardDto.fromJson(card.toJson());
          check(read.usageId == usage.usageId, 'compromise changed usage');
          check(
            engage(accepted, 'duel').encode() == accepted.encode(),
            'same action consumed twice',
          );
        },
    'compromise inversion selects frozen roles value and action with the same usage':
        () {
          final original = nativeUsageFixture();
          final json = Map<String, Object?>.from(original.toJson());
          json['inverted_resolution'] = <String, Object?>{
            ...Map<String, Object?>.from(json['inverted_resolution']! as Map),
            'snapshot_value': 17,
          };
          final card = NetworkCompromiseCardDto.fromUsage(
            NetworkUsageProjection.fromJson(json),
            origin: NetworkCompromiseOrigin.INITIAL_DUEL,
          );
          final inverse = card.copyWith(
            effectiveDirection: NetworkCardDirection.RECEVOIR,
          );
          check(
            inverse.usageId == card.usageId && inverse.snapshotValue == 17,
            'inverse recomputed data',
          );
          check(
            inverse.usage.resolvedAction['direction'] == 'RECEVOIR',
            'inverse DTO inconsistent',
          );
          check(
            inverse.usage.resolvedAction['stage_id'] ==
                card.usage.resolvedAction['stage_id'],
            'inverse changed stage',
          );
          check(card.snapshotValue == 10, 'original mutated');
        },
    'corruption codec preserves distinct usages of one concept and source links':
        () {
          final actions = [
            for (final id in ['one', 'two'])
              NetworkCorruptionActionDto.fromUsage(
                nativeUsageFixture(usageId: id, sourceUsageId: 'past-$id'),
              ),
          ];
          final dto = NetworkCorruptionDto(
            offeredBy: 'alice',
            objective: CorruptionObjective.OWN_INITIAL_ACTION,
            actions: actions,
          );
          final read = NetworkCorruptionDto.fromJson(
            jsonDecode(jsonEncode(dto.toJson())) as Map<String, Object?>,
          );
          check(
            read.actions.map((a) => a.identity).toSet().length == 2,
            'same concept conflated',
          );
          check(
            read.actions.first.usage.toJson()['source_usage_id'] == 'past-one',
            'source lost',
          );
          check(
            !jsonEncode(dto.toJson()).contains('occurrence_id'),
            'legacy alias emitted',
          );
        },
    'corruption status update retains the frozen action without private values':
        () {
          final action = NetworkCorruptionActionDto.fromUsage(
            nativeUsageFixture(),
          );
          final done = action.copyWith(status: ActionExecutionStatus.COMPLETED);
          check(
            jsonEncode(done.usage.toJson()) ==
                jsonEncode(action.usage.toJson()),
            'completion changed snapshot',
          );
          check(done.status == ActionExecutionStatus.COMPLETED, 'status lost');
        },
    'Recovery codec preserves identity action and gain without disclosing personal values':
        () {
          final usage = nativeUsageFixture(
            value: 13,
            usageId: 'recovery',
            sourceUsageId: 'past',
          );
          final dto = NetworkRecoveryDto.fromUsage(
            usage,
            source: RecoverySource.DISCARD,
            response: RecoveryResponse.ACCEPT,
            completed: true,
            gain: 20,
          );
          final read = NetworkRecoveryDto.fromJson(
            jsonDecode(jsonEncode(dto.toJson())) as Map<String, Object?>,
          );
          check(
            read.usageId == 'recovery' &&
                read.usage.snapshotValue == null &&
                read.gain == 20,
            'Recovery reinterpreted',
          );
          check(
            !jsonEncode(dto.toJson()).contains('occurrence_id'),
            'Recovery legacy alias',
          );
        },
    'one completion acknowledgement produces no learning or receipt': () {
      final state = AdaptiveProfileState(profileId: 'alice');
      check(
        identical(learn(state, {'alice'}, [nativeUsageFixture()]), state),
        'early learning',
      );
    },
    'both completion acknowledgements learn once including after aggregate reload':
        () {
          final state = learn(
            AdaptiveProfileState(profileId: 'alice'),
            {'alice', 'bob'},
            [nativeUsageFixture()],
          );
          check(
            state.entries.isNotEmpty && state.appliedRoundEvents.length == 1,
            'missing learning',
          );
          final restored = AdaptiveProfileState.fromJson(
            jsonDecode(jsonEncode(state.toJson())) as Map<String, Object?>,
          );
          final retry = learn(
            restored,
            {'alice', 'bob'},
            [nativeUsageFixture(value: 20, chili: 4)],
          );
          check(
            identical(restored, retry),
            'retry learned twice or used current values',
          );
        },
    'learning distinguishes repeated usages of a concept but deduplicates the same usage':
        () {
          final initial = AdaptiveProfileState(profileId: 'alice');
          final one = nativeUsageFixture(usageId: 'one');
          final two = nativeUsageFixture(usageId: 'two');
          final single = learn(initial, {'alice', 'bob'}, [one]);
          final duplicate = learn(initial, {'alice', 'bob'}, [one, one]);
          final repeated = learn(initial, {'alice', 'bob'}, [one, two]);
          check(
            jsonEncode(single.toJson()) == jsonEncode(duplicate.toJson()),
            'same usage counted twice',
          );
          check(
            repeated.entries.values.single.acceptanceCount ==
                single.entries.values.single.acceptanceCount * 2,
            'distinct usages conflated',
          );
        },
    'learning projects final inverted participants and immutable spice from snapshot':
        () {
          final inverse = nativeUsageFixture(chili: 4).resolved(inverted: true);
          final descriptor = usageLearningDescriptor(inverse);
          final outcome = usageLearningOutcome(inverse);
          check(
            descriptor.spiceLevel == 4 && descriptor.usageId == inverse.usageId,
            'frozen metadata lost',
          );
          check(
            outcome.performerPlayerId == 'bob' &&
                outcome.receiverPlayerId == 'alice',
            'wrong effective roles',
          );
        },
    'native secondary DTOs refuse occurrence-only historical reconstruction':
        () {
          var rejected = 0;
          for (final parse in [
            NetworkCompromiseCardDto.fromJson,
            NetworkRecoveryDto.fromJson,
            NetworkCorruptionActionDto.fromJson,
          ]) {
            try {
              parse({'occurrence_id': 'old', 'card_id': '019'});
            } catch (_) {
              rejected++;
            }
          }
          check(rejected == 3, 'legacy reconstruction survived');
        },
  };
}
