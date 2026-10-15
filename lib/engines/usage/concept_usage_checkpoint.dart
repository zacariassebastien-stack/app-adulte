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
  }) : usagesByIntent = Map.unmodifiable(usagesByIntent);

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
    });
    reader.integer('schema_version', min: 1, max: 1);
    final sessionId = reader.string('session_id');
    final owner = reader.string('owner_player_id');
    final cycle = reader.integer('cycle', min: 1);
    final stock = ConceptDeckStock.fromJson(
      reader.child(json['stock'], 'stock', 'ConceptDeckStock').json,
    );
    final usages = reader.objects(
      'usages',
      (r) => ConceptUsageSnapshot.fromJson(r.json),
      'ConceptUsageSnapshot',
    );
    final byIntent = <String, ConceptUsageSnapshot>{};
    final counts = <String, int>{};
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
      counts.update(usage.conceptId, (count) => count + 1, ifAbsent: () => 1);
    }
    for (final entry in stock.capacity.entries) {
      if (stock.remainingFor(entry.key) !=
          entry.value - (counts[entry.key] ?? 0)) {
        reader.fail('stock', 'Usage journal and remaining quota disagree');
      }
    }
    return ConceptUsageCheckpoint._(
      sessionId: sessionId,
      ownerPlayerId: owner,
      cycle: cycle,
      stock: stock,
      usagesByIntent: byIntent,
    );
  }

  final String sessionId;
  final String ownerPlayerId;
  final int cycle;
  final ConceptDeckStock stock;
  final Map<String, ConceptUsageSnapshot> usagesByIntent;

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
    if (stock.remainingFor(conceptId) == 0) {
      throw StateError('Concept quota exhausted: $conceptId');
    }
    final action = resolveAction();
    if (action.conceptId != conceptId) {
      throw ArgumentError('Resolved concept differs from intent');
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
    );
  }

  JsonMap toJson() =>
      freezeJson({
            'schema_version': 1,
            'session_id': sessionId,
            'owner_player_id': ownerPlayerId,
            'cycle': cycle,
            'stock': stock.toJson(),
            'usages': [
              for (final usage in usagesByIntent.values) usage.toJson(),
            ],
          })!
          as JsonMap;

  String encode() => canonicalUsageJson(toJson());
}
