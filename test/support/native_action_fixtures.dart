import 'dart:convert';
import 'dart:io';
import 'package:couple_cards/domain/domain.dart';
import 'package:couple_cards/engines/engines.dart';
import 'package:couple_cards/sync/sync.dart';
import 'native_usage_fixture.dart';
import 'package:couple_cards/features/game/network_duel_secret_store.dart';

// Explicit frozen test inputs, never used by a production catalogue/runtime.
final _conceptDefinitions = ConceptCatalog.fromJson(
  jsonDecode(File('assets/catalog/concepts/active.fr.json').readAsStringSync())
      as Map<String, Object?>,
);
String conceptFixtureId(String id) => id.replaceFirst('card.v4.', '');
NetworkUsageProjection actionUsageFixture({
  required String conceptId,
  String? usageId,
  String? actionId,
  String ownerPlayerId = 'alice',
  NetworkCardDirection nativeDirection = NetworkCardDirection.GENERAL,
  NetworkCardDirection? effectiveDirection,
  int snapshotValue = 10,
  int? effectiveSpice,
  V4ResolvedParameters? resolvedParameters,
  List<String>? targetPlayerIds,
  List<V4PersistentEffect> effects = const [],
  String? sourceUsageId,
}) {
  final id = conceptFixtureId(conceptId);
  final concept = _conceptDefinitions.concepts
      .where((c) => c.id == id)
      .firstOrNull;
  final definition = actionId != null && actionId.startsWith('$id.')
      ? actionId
      : concept?.stages.firstOrNull?.id ??
            concept?.variants.firstOrNull?.id ??
            '$id.action';
  final base = Map<String, Object?>.from(
    nativeUsageFixture(
      conceptId: id,
      usageId: usageId ?? 'fixture-$id-$ownerPlayerId',
      owner: ownerPlayerId,
      direction: nativeDirection.name,
      value: snapshotValue == 0 ? 10 : snapshotValue,
      chili:
          effectiveSpice ??
          concept?.stages.firstOrNull?.chili ??
          concept?.variants.firstOrNull?.chili ??
          concept?.intrinsicChili ??
          1,
      sourceUsageId: sourceUsageId,
    ).toJson(),
  );
  Map<String, Object?> action(Map<String, Object?> original) => {
    ...original
      ..remove('stage_id')
      ..remove('variant_id'),
    if (concept?.stages.isNotEmpty ?? false)
      'stage_id': definition
    else
      'variant_id': definition,
    'parameters': {
      ...original['parameters']! as Map<String, Object?>,
      ...?resolvedParameters?.toJson(),
    },
    if (resolvedParameters?.zoneId != null)
      'zone_id': resolvedParameters!.zoneId,
    if (targetPlayerIds != null) 'target_player_ids': targetPlayerIds,
    'effects': [
      for (final effect in effects)
        {'effect_id': effect.identity, 'parameters': effect.toJson()},
    ],
  };
  base['resolved_action'] = action(
    Map<String, Object?>.from(base['resolved_action']! as Map),
  );
  if (base['inverted_resolution'] case final Map<String, Object?> inverse) {
    base['inverted_resolution'] = {
      ...inverse,
      'resolved_action': action(
        Map<String, Object?>.from(inverse['resolved_action']! as Map),
      ),
    };
  }
  final usage = NetworkUsageProjection.fromJson(base).resolved(
    inverted:
        effectiveDirection != null && effectiveDirection != nativeDirection,
  );
  return snapshotValue == 0 ? usage.withoutPersonalValues() : usage;
}

NetworkCompromiseCardDto compromiseFixture({
  required String conceptId,
  String? usageId,
  String? actionId,
  required String ownerPlayerId,
  required NetworkCardDirection nativeDirection,
  NetworkCardDirection? effectiveDirection,
  required NetworkCompromiseOrigin origin,
  int snapshotValue = 10,
  int? logicalOrder,
  int? effectiveSpice,
  V4ResolvedParameters? resolvedParameters,
}) => NetworkCompromiseCardDto.fromUsage(
  actionUsageFixture(
    conceptId: conceptId,
    usageId: usageId,
    actionId: actionId,
    ownerPlayerId: ownerPlayerId,
    nativeDirection: nativeDirection,
    effectiveDirection: effectiveDirection,
    snapshotValue: snapshotValue,
    effectiveSpice: effectiveSpice,
    resolvedParameters: resolvedParameters,
  ),
  origin: origin,
  logicalOrder: logicalOrder,
);
NetworkRecoveryDto recoveryFixture({
  required String conceptId,
  String? usageId,
  String? actionId,
  required String playerId,
  required RecoverySource source,
  bool completed = false,
  int gain = 0,
  RecoveryResponse? response,
}) => NetworkRecoveryDto.fromUsage(
  actionUsageFixture(
    conceptId: conceptId,
    usageId: usageId,
    actionId: actionId,
    ownerPlayerId: playerId,
  ),
  source: source,
  completed: completed,
  gain: gain,
  response: response,
);
NetworkResolvedActionCardDto resolvedActionFixture({
  required String conceptId,
  required String usageId,
  required String actionId,
  required NetworkCardDirection direction,
  required List<String> targetPlayerIds,
  required int effectiveSpice,
  String? zoneId,
  String? accessoryId,
  Map<String, Object?> parameters = const {},
  List<V4PersistentEffect> effects = const [],
}) {
  final usage = actionUsageFixture(
    conceptId: conceptId,
    usageId: usageId,
    actionId: actionId,
    nativeDirection: direction,
    targetPlayerIds: targetPlayerIds,
    effectiveSpice: effectiveSpice,
    effects: effects,
    resolvedParameters: V4ResolvedParameters.fromJson({
      ...parameters,
      'zone_id': zoneId,
      'accessory_id': accessoryId,
    }),
  );
  return NetworkResolvedActionCardDto.fromUsage(usage);
}

NetworkPrivateGameState privateGameFixture({required int roundNumber,
  required List<CardRuntimeState> cards,String ownerPlayerId='alice',
  ChoiceRevealDto? activeReveal,bool nextRoundPrepared=false,
  Set<int> learningRecordedRounds=const {},int deckCycle=1,bool infiniteMode=false,
  PlayerStyle deckStyle=PlayerStyle.SOFT,int choiceVersion=0,int activeChili=1,
  V4SessionMode sessionMode=V4SessionMode.presentiel,V4SessionPresence presence=V4SessionPresence.presentiel,
  Map<String,int> clothesByPlayer=const {'alice':6,'bob':6},
  List<V4PersistentEffect> persistentEffects=const [],V4SessionAccessoryPool? accessoryPool,
  List<NetworkPlayedCardRecord> publicDiscards=const [],
  Map<String,V4ResolvedParameters> parametersByUsage=const {}}) {
  var checkpoint=ConceptUsageCheckpoint.startCycle(sessionId:'session-multi',ownerPlayerId:ownerPlayerId,
    cycle:deckCycle,catalog:_conceptDefinitions,initialClothing:clothesByPlayer[ownerPlayerId] ?? 6);
  final cache=<CardRuntimeState>[];
  final records=[...publicDiscards];
  for(final card in cards){
    final id=conceptFixtureId(card.cardId);
    if(card.zone==CardZone.HAND){
      cache.add(CardRuntimeState(cardId:id,zone:CardZone.HAND,locked:card.locked,
        nativeDirection:card.nativeDirection,effectiveDirection:card.effectiveDirection));continue;
    }
    final projection=actionUsageFixture(conceptId:id,actionId:card.variantId,
      ownerPlayerId:ownerPlayerId,nativeDirection:NetworkCardDirection.values.byName(card.nativeDirection.name),
      resolvedParameters:parametersByUsage[card.occurrenceId]);
    ResolvedConceptAction privateAction(Map<String,Object?> action) => ResolvedConceptAction.fromJson({
      ...action,'personal_values':[{'player_id':ownerPlayerId,
        'role':action['direction']=='FAIRE'?'FAIRE':action['direction']=='RECEVOIR'?'RECEVOIR':'GENERAL','value':10}]});
    final intent='seed:${card.occurrenceId}';
    checkpoint=checkpoint.reserve(conceptId:id,intentId:intent).engage(conceptId:id,intentId:intent,
      resolveAction:()=>privateAction(projection.resolvedAction),clock:()=>DateTime.utc(2026,10,15));
    final engaged=checkpoint.usagesByIntent[intent]!;
    final shared=NetworkUsageProjection.fromSnapshot(engaged,sharedParameterKeys:engaged.action.parameters.keys.toSet(),sharedEffectIds:engaged.action.effects.map((e)=>e.effectId).toSet(),includePersonalValue:true);
    cache.add(CardRuntimeState(cardId:id,occurrenceId:engaged.usageId,variantId:engaged.action.stageId??engaged.action.variantId,
      zone:card.zone,locked:card.locked,nativeDirection:card.nativeDirection,effectiveDirection:card.effectiveDirection));
    if(card.zone==CardZone.DISCARD) records.add(NetworkPlayedCardRecord(usage:shared,roundNumber:roundNumber-1));
  }
  return NetworkPrivateGameState(roundNumber:roundNumber,cards:cache,conceptCheckpoint:checkpoint,
    activeReveal:activeReveal,nextRoundPrepared:nextRoundPrepared,learningRecordedRounds:learningRecordedRounds,
    deckCycle:deckCycle,infiniteMode:infiniteMode,deckStyle:deckStyle,choiceVersion:choiceVersion,
    activeChili:activeChili,initialClothing:clothesByPlayer[ownerPlayerId]??6,
    sessionMode:sessionMode,presence:presence,clothesByPlayer:clothesByPlayer,
    persistentEffects:persistentEffects,accessoryPool:accessoryPool,publicDiscards:records);
}

NetworkCorruptionActionDto corruptionFixture({required String conceptId, String? usageId,String? actionId,int? effectiveSpice,CardZone source=CardZone.DISCARD,ActionExecutionStatus status=ActionExecutionStatus.PROPOSED,String ownerPlayerId='bob'}) => NetworkCorruptionActionDto.fromUsage(actionUsageFixture(conceptId:conceptId,usageId:usageId,actionId:actionId,effectiveSpice:effectiveSpice,ownerPlayerId:ownerPlayerId),source:source,status:status);
