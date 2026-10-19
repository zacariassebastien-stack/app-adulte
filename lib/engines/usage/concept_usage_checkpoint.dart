import '../../core/json.dart';
import '../../domain/catalog/concept_catalog.dart';
import '../../domain/round/concept_usage_snapshot.dart';
import '../deck/concept_deck_engine.dart';

/// New-model-only checkpoint for one owner's cycle: usages + quota + retry keys.
/// Serialize and persist this whole value before dispatching external commands.
/// It contains neither a legacy runtime adapter nor a new storage backend.
final class ConceptUsageCheckpoint {
  ConceptUsageCheckpoint._({
    required this.sessionId,
    required this.ownerPlayerId,
    required this.cycle,
    required this.stock,
    required Map<String, ConceptUsageSnapshot> usagesByIntent,
    Map<String, String> reservationsByIntent = const {},
    Map<String, String> reservedStagesByIntent = const {},
    Set<String> replayIntents = const {},
  }) : usagesByIntent = Map.unmodifiable(usagesByIntent),
       reservationsByIntent = Map.unmodifiable(reservationsByIntent),
       reservedStagesByIntent = Map.unmodifiable(reservedStagesByIntent),
       replayIntents = Set.unmodifiable(replayIntents);

  factory ConceptUsageCheckpoint.startCycle({
    required String sessionId,
    required String ownerPlayerId,
    required int cycle,
    required ConceptCatalog catalog,
    required int initialClothing,
  }) {
    ConceptUsageSnapshot.identityFor(
      sessionId,
      ownerPlayerId,
      cycle,
      'scope-check',
    );
    return ConceptUsageCheckpoint._(
      sessionId: sessionId,
      ownerPlayerId: ownerPlayerId,
      cycle: cycle,
      stock: ConceptDeckStock.startCycle(
        catalog: catalog,
        initialClothing: initialClothing,
      ),
      usagesByIntent: {},
    );
  }

  factory ConceptUsageCheckpoint.fromJson(JsonMap json) {
    final reader = JsonReader(json, 'ConceptUsageCheckpoint');
    reader.only({
      'schema_version',
      'session_id',
      'owner_player_id',
      'cycle',
      'stock',
      'usages',
      'reservations',
      'reserved_stages',
      'legacy_stage_duplicates',
      'replay_intents',
    });
    final version = reader.integer('schema_version', min: 1, max: 2);
    final sessionId = reader.string('session_id');
    final owner = reader.string('owner_player_id');
    final cycle = reader.integer('cycle', min: 1);
    var stock = ConceptDeckStock.fromJson(
      reader.child(json['stock'], 'stock', 'ConceptDeckStock').json,
    );
    final usages = reader.objects(
      'usages',
      (r) => ConceptUsageSnapshot.fromJson(r.json),
      'ConceptUsageSnapshot',
    );
    final replayIntents = (json['replay_intents'] as List? ?? const [])
        .cast<String>()
        .toSet();
    final byIntent = <String, ConceptUsageSnapshot>{};
    final counts = <String, int>{};
    final consumed = <String, Set<String>>{};
    for (final usage in usages) {
      if (usage.sessionId != sessionId ||
          usage.ownerPlayerId != owner ||
          usage.cycle != cycle) {
        reader.fail('usages', 'Usage belongs to a different checkpoint scope');
      }
      if (byIntent.containsKey(usage.intentId)) {
        reader.fail('usages', 'Duplicate intent');
      }
      if (!stock.capacity.containsKey(usage.conceptId)) {
        reader.fail('usages', 'Unknown concept');
      }
      byIntent[usage.intentId] = usage;
      if (replayIntents.contains(usage.intentId)) continue;
      counts.update(usage.conceptId, (count) => count + 1, ifAbsent: () => 1);
      if (usage.action.stageId case final stage?
          when !_clothing(usage.conceptId)) {
        final stages = consumed.putIfAbsent(usage.conceptId, () => {});
        if (!stages.add(stage) && version == 2) {
          // Historical duplicates are allowed only when explicitly retained by
          // the v1 upgrade marker, never through a new engagement.
          if (json['legacy_stage_duplicates'] != true) {
            reader.fail('usages', 'Stage engaged twice');
          }
        }
      }
    }
    if (replayIntents.any((id) => byIntent[id]?.sourceUsageId == null)) {
      reader.fail('replay_intents', 'Replay requires its historical source');
    }
    final remaining = <String, int>{};
    for (final entry in stock.capacity.entries) {
      final spent = consumed[entry.key]?.length ?? counts[entry.key] ?? 0;
      final expected = entry.value - spent;
      if (stock.remainingFor(entry.key) != expected &&
          !(version == 1 &&
              stock.remainingFor(entry.key) ==
                  entry.value - (counts[entry.key] ?? 0))) {
        reader.fail('stock', 'Usage journal and remaining quota disagree');
      }
      remaining[entry.key] = expected;
    }
    // v1 spent generic concept quota. Recover distinct remaining stages from
    // its immutable journal; repeated historical snapshots are not rewritten.
    stock = ConceptDeckStock.fromJson({
      ...stock.toJson(),
      'remaining': remaining,
    });
    final reservations = <String, String>{};
    final reservedCounts = <String, int>{};
    if (json.containsKey('reservations')) {
      final saved = reader.child(
        json['reservations'],
        'reservations',
        'ConceptReservations',
      );
      for (final intent in saved.json.keys) {
        ConceptUsageSnapshot.identityFor(sessionId, owner, cycle, intent);
        final concept = saved.string(intent);
        if (byIntent.containsKey(intent) ||
            !stock.capacity.containsKey(concept)) {
          reader.fail('reservations', 'Invalid reserved intention');
        }
        reservations[intent] = concept;
        reservedCounts.update(concept, (n) => n + 1, ifAbsent: () => 1);
        if (reservedCounts[concept]! > stock.remainingFor(concept)) {
          reader.fail('reservations', 'Reservations exceed remaining quota');
        }
      }
    }
    final reservedStages = Map<String, String>.from(
      json['reserved_stages'] as Map? ?? const {},
    );
    if (reservedStages.keys.any((id) => !reservations.containsKey(id))) {
      reader.fail(
        'reserved_stages',
        'Stage reservation has no concept reservation',
      );
    }
    return ConceptUsageCheckpoint._(
      sessionId: sessionId,
      ownerPlayerId: owner,
      cycle: cycle,
      stock: stock,
      usagesByIntent: byIntent,
      replayIntents: replayIntents,
      reservationsByIntent: reservations,
      reservedStagesByIntent: reservedStages,
    );
  }

  final String sessionId;
  final String ownerPlayerId;
  final int cycle;
  final ConceptDeckStock stock;
  final Map<String, ConceptUsageSnapshot> usagesByIntent;
  final Map<String, String> reservationsByIntent;
  final Map<String, String> reservedStagesByIntent;
  final Set<String> replayIntents;

  static bool _clothing(String id) => id == '006' || id == '007';

  bool stageConsumed(String conceptId, String stageId) =>
      !_clothing(conceptId) &&
      usagesByIntent.values.any(
        (u) =>
            !replayIntents.contains(u.intentId) &&
            u.conceptId == conceptId &&
            u.action.stageId == stageId,
      );

  bool stageAvailable(String conceptId, String? stageId, {String? intentId}) =>
      stageId == null ||
      _clothing(conceptId) ||
      (!stageConsumed(conceptId, stageId) &&
          !reservedStagesByIntent.entries.any(
            (e) =>
                e.key != intentId &&
                reservationsByIntent[e.key] == conceptId &&
                e.value == stageId,
          ));

  int availableFor(String conceptId) =>
      stock.remainingFor(conceptId) -
      reservationsByIntent.values.where((id) => id == conceptId).length;

  ConceptUsageCheckpoint reserve({
    required String intentId,
    required String conceptId,
    String? stageId,
  }) {
    ConceptUsageSnapshot.identityFor(sessionId, ownerPlayerId, cycle, intentId);
    if (!stageAvailable(conceptId, stageId, intentId: intentId) &&
        usagesByIntent[intentId] == null) {
      throw StateError('Stage unavailable: $stageId');
    }
    final existing =
        usagesByIntent[intentId]?.conceptId ?? reservationsByIntent[intentId];
    if (existing != null) {
      if (existing != conceptId) {
        throw StateError('Intent refers to a different concept');
      }
      return this;
    }
    if (availableFor(conceptId) == 0) {
      throw StateError('Concept has no unreserved capacity: $conceptId');
    }
    return ConceptUsageCheckpoint._(
      sessionId: sessionId,
      ownerPlayerId: ownerPlayerId,
      cycle: cycle,
      stock: stock,
      usagesByIntent: usagesByIntent,
      replayIntents: replayIntents,
      reservationsByIntent: {...reservationsByIntent, intentId: conceptId},
      reservedStagesByIntent: {...reservedStagesByIntent, intentId: ?stageId},
    );
  }

  /// Only a pending reservation is released; engaged quota is never refunded.
  ConceptUsageCheckpoint releaseReservation(String intentId) {
    if (!reservationsByIntent.containsKey(intentId)) return this;
    return ConceptUsageCheckpoint._(
      sessionId: sessionId,
      ownerPlayerId: ownerPlayerId,
      cycle: cycle,
      stock: stock,
      usagesByIntent: usagesByIntent,
      replayIntents: replayIntents,
      reservationsByIntent: {...reservationsByIntent}..remove(intentId),
      reservedStagesByIntent: {...reservedStagesByIntent}..remove(intentId),
    );
  }

  ConceptUsageSnapshot? usageForIntent(String intentId) =>
      usagesByIntent[intentId];

  /// Only a new logical intent resolves data and spends one concept use.
  /// A retry returns the persisted original, even after profile/context changes.
  ConceptUsageCheckpoint engage({
    required String intentId,
    required String conceptId,
    required ResolvedConceptAction Function() resolveAction,
    required DateTime Function() clock,
    ResolvedConceptAction Function()? resolveInvertedAction,
    String? sourceUsageId,
  }) {
    ConceptUsageSnapshot.identityFor(sessionId, ownerPlayerId, cycle, intentId);
    final existing = usagesByIntent[intentId];
    if (existing != null) {
      if (existing.conceptId != conceptId) {
        throw StateError('Retry intent refers to a different concept');
      }
      return this;
    }
    final reserved = reservationsByIntent[intentId];
    if (reserved != null && reserved != conceptId) {
      throw StateError('Reserved intent refers to a different concept');
    }
    if ((reserved == null && availableFor(conceptId) == 0) ||
        stock.remainingFor(conceptId) == 0) {
      throw StateError('Concept quota exhausted: $conceptId');
    }
    final action = resolveAction();
    if (action.conceptId != conceptId) {
      throw ArgumentError('Resolved concept differs from intent');
    }
    if (!stageAvailable(conceptId, action.stageId, intentId: intentId)) {
      throw StateError('Stage already consumed or reserved: ${action.stageId}');
    }
    final reservedStage = reservedStagesByIntent[intentId];
    if (reservedStage != null && reservedStage != action.stageId) {
      throw StateError('Engagement differs from reserved stage');
    }
    final usage = ConceptUsageSnapshot.create(
      sessionId: sessionId,
      ownerPlayerId: ownerPlayerId,
      cycle: cycle,
      intentId: intentId,
      engagedAt: clock(),
      action: action,
      invertedAction: resolveInvertedAction?.call(),
      sourceUsageId: sourceUsageId,
    );
    return ConceptUsageCheckpoint._(
      sessionId: sessionId,
      ownerPlayerId: ownerPlayerId,
      cycle: cycle,
      stock: stock.consume(conceptId),
      usagesByIntent: {...usagesByIntent, intentId: usage},
      replayIntents: replayIntents,
      reservationsByIntent: {...reservationsByIntent}..remove(intentId),
      reservedStagesByIntent: {...reservedStagesByIntent}..remove(intentId),
    );
  }

  /// A corruption replay is journalled for retries and learning, not drawn
  /// from normal capacity. Historical checkpoints without this marker retain
  /// their original accounting.
  ConceptUsageCheckpoint engageReplay(ConceptUsageSnapshot usage) {
    if (usagesByIntent.containsKey(usage.intentId)) return this;
    return ConceptUsageCheckpoint._(
      sessionId: sessionId,
      ownerPlayerId: ownerPlayerId,
      cycle: cycle,
      stock: stock,
      usagesByIntent: {...usagesByIntent, usage.intentId: usage},
      reservationsByIntent: reservationsByIntent,
      reservedStagesByIntent: reservedStagesByIntent,
      replayIntents: {...replayIntents, usage.intentId},
    );
  }

  JsonMap toJson() =>
      freezeJson({
            'schema_version': 2,
            'session_id': sessionId,
            'owner_player_id': ownerPlayerId,
            'cycle': cycle,
            'stock': stock.toJson(),
            if (replayIntents.isNotEmpty)
              'replay_intents': replayIntents.toList(),
            'reservations': reservationsByIntent,
            'reserved_stages': reservedStagesByIntent,
            if (usagesByIntent.values
                    .where(
                      (u) =>
                          !replayIntents.contains(u.intentId) &&
                          u.action.stageId != null &&
                          !_clothing(u.conceptId),
                    )
                    .map((u) => '${u.conceptId}/${u.action.stageId}')
                    .toSet()
                    .length <
                usagesByIntent.values
                    .where(
                      (u) =>
                          !replayIntents.contains(u.intentId) &&
                          u.action.stageId != null &&
                          !_clothing(u.conceptId),
                    )
                    .length)
              'legacy_stage_duplicates': true,
            'usages': [
              for (final usage in usagesByIntent.values) usage.toJson(),
            ],
          })!
          as JsonMap;

  String encode() => canonicalUsageJson(toJson());
}
