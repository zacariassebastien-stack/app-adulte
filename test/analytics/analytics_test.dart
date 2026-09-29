import 'dart:convert';
import 'package:couple_cards/domain/domain.dart';
import 'package:couple_cards/engines/engines.dart';
import 'package:couple_cards/data/local/app_database.dart';
import 'package:couple_cards/data/repositories/event_log_repository.dart';
import 'package:test/test.dart';
import '../engines/engine_fixture.dart';

void main() {
  late List<StoredEvent> journal;
  late SessionTelemetry telemetry;
  List<GameEvent> events() => journal.map(GameEvent.fromStored).toList();
  AxisMetrics metric(BehaviorAxis axis) => const AnalyticsEngine(
    minimumSamples: 1,
  ).compute('a', events()).axes[axis]!;
  DecisionOpportunity opportunity(
    BehaviorAxis axis, {
    List<String> cards = const [],
  }) => telemetry.opportunity('a', 'TEST', [axis], cards: cards);
  setUp(() {
    journal = [];
    telemetry = SessionTelemetry(
      sessionId: 's',
      clock: () => DateTime.utc(2026),
      sink: journal.add,
    )..roundId = 'r1';
  });
  for (final axis in BehaviorAxis.values) {
    test('${axis.name} exposes counts without a final profile', () {
      final op = opportunity(axis, cards: ['c', 'd']);
      telemetry.decision(
        op,
        GameEventType.DECISION_PASSED,
        {},
        attempted: true,
        accepted: true,
        completed: true,
      );
      final m = metric(axis);
      expect(
        [m.opportunities, m.attempts, m.accepted, m.completed],
        [1, 1, 1, 1],
      );
      expect(m.ratio, 1);
      expect(const AnalyticsEngine().compute('a', events()).axes.length, 19);
    });
  }
  for (final reason in NonPerformanceReason.values.where(
    (r) =>
        r != NonPerformanceReason.NONE && r != NonPerformanceReason.STRATEGIC,
  )) {
    test('$reason excludes numerator and denominator for every axis', () {
      for (final axis in BehaviorAxis.values) {
        final good = opportunity(axis, cards: ['c', 'd']);
        telemetry.decision(
          good,
          GameEventType.ACTION_COMPLETED,
          {},
          attempted: true,
          completed: true,
        );
        final excluded = opportunity(axis, cards: ['c', 'd']);
        telemetry.decision(
          excluded,
          GameEventType.ACTION_SKIPPED,
          {},
          neutralReason: reason,
        );
        expect(metric(axis).ratio, 1);
        expect(metric(axis).opportunities, 1);
        expect(metric(axis).excluded, 1);
      }
    });
  }
  test('three attempts on three versus twenty opportunities', () {
    for (var i = 0; i < 20; i++) {
      final op = opportunity(BehaviorAxis.NEGOCIATION);
      if (i < 3) {
        telemetry.decision(
          op,
          GameEventType.AUCTION_COMMITTED,
          {},
          attempted: true,
        );
      }
      if (i == 2) expect(metric(BehaviorAxis.NEGOCIATION).ratio, 1);
    }
    expect(metric(BehaviorAxis.NEGOCIATION).ratio, 0.15);
  });
  test('missing evidence and legacy records yield insufficient data', () {
    final result = const AnalyticsEngine().compute('a', [
      GameEvent(GameEventType.CARD_COMMITTED),
    ]);
    expect(
      result.axes.values.every(
        (m) =>
            m.status == AnalyticsDataStatus.INSUFFICIENT_DATA &&
            m.ratio == null,
      ),
      isTrue,
    );
  });
  test('single eligible card cannot count against variety', () {
    final op = opportunity(BehaviorAxis.VARIETE, cards: ['c']);
    telemetry.decision(
      op,
      GameEventType.CARD_COMMITTED,
      {},
      attempted: true,
      chosenCardId: 'c',
    );
    expect(metric(BehaviorAxis.VARIETE).opportunities, 0);
    expect(metric(BehaviorAxis.VARIETE).ratio, isNull);
  });
  test('variety uses eligible choices, tags and voluntary repetition', () {
    for (final card in ['c', 'd', 'c']) {
      final op = opportunity(BehaviorAxis.VARIETE, cards: ['c', 'd', 'e']);
      telemetry.decision(
        op,
        GameEventType.CARD_COMMITTED,
        {},
        attempted: true,
        chosenCardId: card,
        chosenTags: ['tag.$card'],
      );
    }
    final m = metric(BehaviorAxis.VARIETE);
    expect(
      [m.uniqueChoices, m.eligibleChoices, m.uniqueTags, m.voluntaryRepeats],
      [2, 3, 2, 1],
    );
    expect(m.topChoiceShare, 2 / 3);
  });
  test('replay and reversed event order are deterministic', () {
    final op = opportunity(BehaviorAxis.NEGOCIATION);
    telemetry.decision(
      op,
      GameEventType.AUCTION_COMMITTED,
      {},
      attempted: true,
    );
    const engine = AnalyticsEngine(minimumSamples: 1);
    expect(
      engine.compute('a', events()).toJson(),
      engine.compute('a', [...events().reversed, ...events()]).toJson(),
    );
    expect(
      engine
          .compute('b', events())
          .axes[BehaviorAxis.NEGOCIATION]!
          .opportunities,
      0,
    );
  });
  test('style and draw and lock remain private', () {
    final op = opportunity(BehaviorAxis.CHANGEMENT_STYLE);
    telemetry.styleChanged(
      op,
      PlayerStyle.values.first,
      PlayerStyle.values.last,
    );
    final card = gameCard();
    telemetry.drawn('a', card, card.variants);
    telemetry.lockChanged('a', card.id, true);
    expect(
      events()[1].payload['previous_style'],
      PlayerStyle.values.first.name,
    );
    expect(events()[2].payload['accessible_variants'], isNotEmpty);
    expect(events().every((e) => e.publicProjection().isEmpty), isTrue);
  });
  for (final increase in [true, false]) {
    for (final accepted in [true, false]) {
      test('chili increase=$increase accepted=$accepted is intensity only', () {
        final op = opportunity(
          increase ? BehaviorAxis.ESCALADE : BehaviorAxis.MODERATION,
        );
        telemetry.chiliProposal(op, 2, increase ? 3 : 1, 'b');
        telemetry.chiliResponse(
          op,
          2,
          increase ? 3 : 1,
          'b',
          accepted: accepted,
        );
        expect(events()[1].type.name, contains('PROPOSED'));
        expect(
          events().last.type.name,
          contains(accepted ? 'ACCEPTED' : 'DECLINED'),
        );
        expect(events().last.payload['decision_kind'], 'INTENSITY_ONLY');
        expect(
          metric(
            increase ? BehaviorAxis.ESCALADE : BehaviorAxis.MODERATION,
          ).excluded,
          0,
        );
      });
    }
  }
  for (final source in ActionSource.values) {
    for (final status in ['COMPLETED', 'SKIPPED', 'STOPPED']) {
      test('$source $status preserves voluntary and actual roles', () {
        final op = opportunity(BehaviorAxis.REALISATION);
        telemetry.executed(
          op,
          actionId: 'action',
          cardId: 'c',
          variantId: 'v',
          source: source,
          voluntaryPlayerId: 'a',
          plannedRoles: {'a': ProfileRole.FAIRE, 'b': ProfileRole.RECEVOIR},
          actualRoles: status == 'COMPLETED'
              ? {'a': ProfileRole.FAIRE, 'b': ProfileRole.RECEVOIR}
              : {},
          status: status,
          reason: NonPerformanceReason.STRATEGIC,
        );
        expect(events().last.payload['source'], source.name);
        expect(events().last.payload['status'], status);
        expect(
          metric(BehaviorAxis.REALISATION).completed,
          status == 'COMPLETED' ? 1 : 0,
        );
        expect(
          metric(BehaviorAxis.REALISATION).opportunities,
          status == 'STOPPED' ? 0 : 1,
        );
      });
    }
  }
  test('commit snapshot survives inversion and serialization unchanged', () {
    final snapshot = CombatValueSnapshot.fromJson({
      'player_id': 'a',
      'card_id': 'c',
      'variant_id': 'v',
      'role_at_commit': 'FAIRE',
      'personal_value': 17,
      'committed_at': DateTime.utc(2026).toIso8601String(),
    });
    final op = opportunity(BehaviorAxis.AUDACE, cards: ['c']);
    telemetry.committed(op, snapshot, ['tag']);
    telemetry.record(GameEventType.INVERSION_RETAINED, {
      'roles_before': {'a': 'FAIRE'},
      'roles_after': {'a': 'RECEVOIR'},
    });
    expect(metric(BehaviorAxis.AUDACE).meanPersonalValue, 17);
    expect(
      events()[1].analytics.first.snapshot!.roleAtCommit,
      ProfileRole.FAIRE,
    );
    expect(
      () => snapshot.toJson()['personal_value'] = 1,
      throwsUnsupportedError,
    );
  });
  test('promised combination preserves discard, repeats and mystery', () {
    final op = opportunity(BehaviorAxis.TENTATION);
    telemetry.corruptionProposed(
      op,
      CorruptionOffer(
        offeredBy: 'a',
        objective: CorruptionObjective.OWN_INITIAL_ACTION,
        actions: [
          const ActionPromise(
            cardId: 'c',
            source: CardZone.DISCARD,
            visibility: PromiseVisibility.MYSTERY,
          ),
          const ActionPromise(cardId: 'c', source: CardZone.DISCARD),
          const ActionPromise(cardId: 'd', source: CardZone.DISCARD),
        ],
      ),
      'b',
    );
    final facts = events().last.payload;
    expect(facts['combination_size'], 3);
    expect(facts['repetition_count'], 1);
    expect(
      (facts['actions'] as List).first,
      containsPair('visibility', 'MYSTERY'),
    );
    expect(
      (facts['actions'] as List).first,
      containsPair('action_id', '${op.id}.action.0'),
    );
  });
  test('mutual extension records equal PA ledger', () {
    final op = opportunity(BehaviorAxis.PROLONGATION);
    telemetry.extension(
      op,
      amount: 20,
      before: {'a': 1, 'b': 5},
      after: {'a': 21, 'b': 25},
    );
    expect(events().last.payload['amount_each'], 20);
    expect(events().last.payload['pa_after'], {'a': 21, 'b': 25});
  });
  test(
    'public allowlist strips all private data even from public envelope',
    () {
      final event = GameEvent.record(GameEventType.CHILI_LEVEL_CHANGED, {
        'previous_level': 1,
        'new_level': 2,
        'hand': ['secret'],
        'personal_value': 20,
        'style': 'secret',
        'consents': <String, Object?>{},
        'exclusion_reason': 'secret',
        'excluded_by': 'b',
        'profile': <String, Object?>{},
      }, visibility: DataVisibility.PUBLIC);
      expect(event.publicProjection(), {
        'type': 'CHILI_LEVEL_CHANGED',
        'previous_level': 1,
        'new_level': 2,
      });
    },
  );
  test('facts are deeply immutable', () {
    final values = ['c'];
    final event = GameEvent.record(GameEventType.CARD_DRAWN_PRIVATE, {
      'cards': values,
    });
    values.add('d');
    expect(event.payload['cards'], ['c']);
    expect(
      () => (event.payload['cards'] as List).add('e'),
      throwsUnsupportedError,
    );
  });
  for (final key in ['photo', 'media_url', 'video_path', 'bytes', 'blob']) {
    test(
      'nested $key is forbidden',
      () => expect(
        () => GameEvent.record(GameEventType.ACTION_COMPLETED, {
          'nested': [
            {key: 'x'},
          ],
        }),
        throwsArgumentError,
      ),
    );
  }
  test('mixed legacy/versioned EventLog is ordered and idempotent', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final repository = EventLogRepository(db);
    final legacy = StoredEvent(
      sessionId: 's',
      eventId: 'old',
      sequence: 0,
      type: 'ROUND_STARTED',
      payload: {'round_id': 'old'},
      createdAt: DateTime.utc(2025),
    );
    opportunity(BehaviorAxis.NEGOCIATION);
    await repository.appendAll([...journal, legacy]);
    await repository.appendAll([...journal, legacy]);
    final loaded = await repository.gameEventsForSession('s');
    expect(loaded.length, 2);
    expect(loaded.map((e) => e.version), [1, 2]);
    expect(loaded.last.toJson(), events().last.toJson());
  });
  test('future versions fail explicitly', () {
    opportunity(BehaviorAxis.NEGOCIATION);
    final old = journal.single;
    final future = StoredEvent(
      sessionId: 's',
      eventId: 'f',
      sequence: 2,
      type: old.type,
      payload: {...old.payload, 'event_version': 999},
      createdAt: old.createdAt,
    );
    expect(() => GameEvent.fromStored(future), throwsUnsupportedError);
  });
  test('sink failure does not advance sequence', () {
    final t = SessionTelemetry(
      sessionId: 's',
      clock: () => DateTime.utc(2026),
      sink: (_) => throw StateError('disk'),
    );
    expect(() => t.record(GameEventType.ROUND_STARTED, {}), throwsStateError);
    expect(t.lastSequence, 0);
  });
  test('wire roundtrip preserves analytics', () {
    final op = opportunity(BehaviorAxis.DEPENSE_PA);
    telemetry.decision(
      op,
      GameEventType.PA_SPENT,
      {},
      attempted: true,
      amount: 4,
    );
    expect(
      jsonDecode(jsonEncode(events().last.toJson())),
      events().last.toJson(),
    );
  });
}
