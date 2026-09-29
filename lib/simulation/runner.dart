import '../domain/domain.dart';
import '../engines/engines.dart';
import 'configuration.dart';
import 'metrics.dart';

final class _Limit implements Exception {}

typedef _Choice = ({
  EngineCard card,
  EngineVariant variant,
  ConsentRule rule,
  PreferenceValue preference,
});

final class SimulationRunner {
  SimulationRunner(
    this.catalog, {
    this.config = const BalanceConfig(),
    this.limits = const SimulationLimits(),
    this.policy = const DecisionPolicy(),
    this.failOnInvariant = true,
    this.profileSpecs = defaultProfileSpecs,
    this.onEvent,
  }) : cards = catalog.cards.map(const CatalogEngineAdapter().card).toList(),
       hierarchy = ProfileHierarchy({
         for (final e in catalog.profileElements) e.stableId: e.parentId,
       }) {
    limits.validate();
    policy.validate();
    for (final pool in ConsentPool.values) {
      profileSpecs[pool]!.validate();
    }
    if (config.handSize != 4) {
      throw ArgumentError('Phase 4 preserves the target hand of four');
    }
  }
  final Catalog catalog;
  final List<EngineCard> cards;
  final ProfileHierarchy hierarchy;
  final BalanceConfig config;
  final SimulationLimits limits;
  final DecisionPolicy policy;
  final bool failOnInvariant;
  final Map<ConsentPool, SyntheticProfileSpec> profileSpecs;
  final void Function(StoredEvent)? onEvent;
  SimulationMetrics run({
    required int seed,
    required SimulationScenario scenario,
  }) => _Session(this, seed, scenario).run();
}

final class _Session {
  _Session(this.runner, this.seed, this.scenario)
    : random = SeededRandomSource(seed),
      draw = DrawEngine(config: runner.config),
      duel = DuelEngine(config: runner.config),
      lifecycle = LifecycleEngine(config: runner.config),
      recovery = RecoveryEngine(config: runner.config),
      intensity = IntensityEngine(config: runner.config) {
    telemetry = runner.onEvent == null
        ? null
        : SessionTelemetry(
            sessionId: 'simulation.$seed',
            clock: () => DateTime.utc(2026).add(Duration(seconds: round)),
            sink: runner.onEvent!,
          );
    final a = syntheticProfile(
      runner.catalog,
      'a',
      scenario.poolA,
      SeededRandomSource(seed * 2 + 1),
      spec: runner.profileSpecs[scenario.poolA],
    );
    final b = scenario.similar
        ? PlayerGameProfile(playerId: 'b', preferences: a.preferences)
        : syntheticProfile(
            runner.catalog,
            'b',
            scenario.poolB,
            SeededRandomSource(seed * 2 + 2),
            spec: runner.profileSpecs[scenario.poolB],
          );
    players = [
      SimulationPlayer(
        profile: a,
        strategies: scenario.first,
        style: scenario.style,
        policy: runner.policy,
      ),
      SimulationPlayer(
        profile: b,
        strategies: scenario.second,
        style: scenario.style,
        policy: runner.policy,
      ),
    ];
    pa = {'a': runner.config.initialPa, 'b': runner.config.initialPa};
    context = EngineSessionContext(
      mode: scenario.mode,
      proximity: scenario.mode == SessionMode.distance
          ? ProximityState.SEPARATED
          : ProximityState.TOGETHER,
      chiliActive: scenario.initialChili,
      chiliUnlocked: scenario.initialChili,
      clothesByPlayer: const {'a': 5, 'b': 5},
      physicalStateByPlayer: const {'a': 'TOGETHER', 'b': 'TOGETHER'},
      mediaCapabilitiesByPlayer: {
        'a': MediaCapability.values.toSet(),
        'b': MediaCapability.values.toSet(),
      },
    );
    // Catalog physical-state strings describe proximity, independently of mode.
    context = context.copyWith(
      physicalStateByPlayer: {
        'a': context.proximity.name,
        'b': context.proximity.name,
      },
    );
    zones = [<CardRuntimeState>[], <CardRuntimeState>[]];
    for (final p in players) {
      metrics.sample(
        'pa.${p.profile.playerId}.initial',
        pa[p.profile.playerId]!,
      );
    }
    metrics.sample('chili.initial', scenario.initialChili);
    firstChili.add(scenario.initialChili);
    metrics.sample('chili.firstAt${scenario.initialChili}', 0);
  }
  final SimulationRunner runner;
  final int seed;
  final SimulationScenario scenario;
  final RandomSource random;
  final DrawEngine draw;
  final DuelEngine duel;
  final LifecycleEngine lifecycle;
  final RecoveryEngine recovery;
  final IntensityEngine intensity;
  final eligibility = const EligibilityEngine();
  final auction = const AuctionEngine();
  final corruption = const CorruptionEngine();
  final metrics = SimulationMetrics();
  late final List<SimulationPlayer> players;
  late Map<String, int> pa;
  late EngineSessionContext context;
  late List<List<CardRuntimeState>> zones;
  final histories = [
    <String, CardHistoryState>{},
    <String, CardHistoryState>{},
  ];
  final recentTags = [<String>{}, <String>{}];
  final recentPrecisions = [<Precision>{}, <Precision>{}];
  final seen = [<String, int>{}, <String, int>{}];
  final selectedTags = [<String, int>{}, <String, int>{}];
  final gates = [
    const RecoveryGate(betweenRounds: true, usedSinceLastNormalDuel: false),
    const RecoveryGate(betweenRounds: true, usedSinceLastNormalDuel: false),
  ];
  final firstThresholds = <String>{};
  final firstChili = <int>{};
  final lockSince = [<String, int>{}, <String, int>{}];
  int round = 0, actions = 0, recoveries = 0, drawIndex = 0;
  bool firstRecovery = false;
  _Choice? invertedAction;
  bool sequenceStopped = false;
  late final SessionTelemetry? telemetry;
  ActionSource resultSource = ActionSource.NORMAL_DUEL;
  String? invertedVoluntaryPlayer;

  void spendEvidence(String playerId, String source, int before, int after) {
    if (before == after) return;
    final op = telemetry?.opportunity(playerId, 'PA_$source', [
      BehaviorAxis.DEPENSE_PA,
      BehaviorAxis.ECONOMIE_PA,
    ], availableAmount: before);
    if (op != null) {
      telemetry!.decision(
        op,
        GameEventType.PA_SPENT,
        {'source': source, 'pa_before': before, 'pa_after': after},
        attempted: true,
        completed: true,
        amount: before - after,
      );
    }
  }

  void executionEvidence(
    _Choice c,
    int i,
    ActionSource source,
    ActionExecutionStatus status, {
    DecisionOpportunity? promise,
    NonPerformanceReason reason = NonPerformanceReason.NONE,
  }) {
    final id = players[i].profile.playerId;
    final op =
        promise ??
        telemetry?.opportunity(id, 'ACTION_${source.name}', [
          BehaviorAxis.REALISATION,
          if (c.rule.role == ProfileRole.FAIRE) BehaviorAxis.INITIATIVE,
          if (c.rule.role == ProfileRole.RECEVOIR) BehaviorAxis.RECEPTIVITE,
        ]);
    if (op == null) return;
    final roles = {
      id: c.rule.role,
      players[1 - i].profile.playerId: switch (c.rule.role) {
        ProfileRole.FAIRE => ProfileRole.RECEVOIR,
        ProfileRole.RECEVOIR => ProfileRole.FAIRE,
        _ => ProfileRole.GENERAL,
      },
    };
    telemetry!.executed(
      op,
      actionId: op.id,
      cardId: c.card.id,
      variantId: c.variant.id,
      source: source,
      voluntaryPlayerId: source == ActionSource.AUCTION_RESULT
          ? (invertedVoluntaryPlayer ?? id)
          : id,
      plannedRoles: roles,
      actualRoles: status == ActionExecutionStatus.COMPLETED ? roles : const {},
      status: status.name,
      reason: reason,
    );
    final partner = players[1 - i].profile.playerId;
    final partnerRole = roles[partner]!;
    if (partnerRole != ProfileRole.GENERAL) {
      final partnerOp = telemetry!.opportunity(partner, 'EXECUTED_ROLE', [
        partnerRole == ProfileRole.FAIRE
            ? BehaviorAxis.INITIATIVE
            : BehaviorAxis.RECEPTIVITE,
      ]);
      telemetry!.executed(
        partnerOp,
        actionId: op.id,
        cardId: c.card.id,
        variantId: c.variant.id,
        source: source,
        voluntaryPlayerId: source == ActionSource.AUCTION_RESULT
            ? (invertedVoluntaryPlayer ?? id)
            : id,
        plannedRoles: roles,
        actualRoles: status == ActionExecutionStatus.COMPLETED
            ? roles
            : const {},
        status: status.name,
        reason: reason,
      );
    }
  }

  void tick() {
    if (actions >= runner.limits.maxActions) throw _Limit();
    actions++;
  }

  void check(bool ok, String code) {
    if (ok) return;
    metrics.increment('invariantViolations');
    if (metrics.anomalies.length < 100) {
      metrics.anomalies.add({
        'seed': seed,
        'round': round,
        'code': code,
        'scenario': scenario.id,
      });
    }
    if (runner.failOnInvariant) {
      throw StateError('Invariant $code seed=$seed round=$round');
    }
  }

  void events(Iterable<GameEvent> events) {
    for (final e in events) {
      metrics.frequency('events', e.type.name);
      if (e.type == GameEventType.ROUND_STARTED ||
          e.type == GameEventType.ROUND_CLOSED) {
        telemetry?.record(e.type, e.payload, visibility: DataVisibility.PUBLIC);
      }
    }
  }

  CardEligibility evaluate(EngineCard c, int i, {bool recovering = false}) =>
      eligibility.evaluate(
        card: c,
        context: context,
        actor: players[i].profile,
        partner: players[1 - i].profile,
        hierarchy: runner.hierarchy,
        recovery: recovering,
      );
  _Choice? choice(EngineCard card, int i, {bool recovering = false}) {
    final variants = evaluate(card, i, recovering: recovering).eligibleVariants;
    for (final v in variants.reversed) {
      // Explicit synthetic selection policy: first accepted own requirement with
      // a rated voluntary role. Never invent consent or a fallback combat value.
      for (final r in v.consentRules) {
        final p = players[i].profile.preference(r.elementId);
        if (r.subject != RequirementSubject.PARTNER &&
            p.status == PreferenceStatus.ACCEPTED &&
            p.valueFor(r.role) != null &&
            !runner.hierarchy
                .ancestorsOf(r.elementId)
                .any(
                  (id) =>
                      players[i].profile.preference(id).status ==
                      PreferenceStatus.EXCLUDED,
                )) {
          return (card: card, variant: v, rule: r, preference: p);
        }
      }
    }
    return null;
  }

  int value(_Choice c) => c.preference.valueFor(c.rule.role)!;
  void syncExhausted() {
    context = context.copyWith(
      exhaustedCardIds: {
        for (final z in zones)
          for (final c in z)
            if (c.zone == CardZone.EXHAUSTED) c.cardId,
      },
    );
  }

  void verify() {
    check(pa.values.every((v) => v >= 0), 'negative_pa');
    for (final id in ['a', 'b']) {
      int counter(String suffix) => metrics.counters['pa.$id.$suffix'] ?? 0;
      check(
        pa[id] ==
            runner.config.initialPa -
                counter('duelSpent') -
                counter('auctionSpent') -
                counter('chiliSpent') +
                counter('recoveryGain') +
                counter('extensionGain'),
        'pa_ledger',
      );
    }
    final state = CompleteGameState(
      sessionId: 'synthetic',
      roundNumber: round,
      actionPoints: pa,
      hands: {
        for (var i = 0; i < 2; i++)
          players[i].profile.playerId: zones[i]
              .where((c) => c.zone == CardZone.HAND)
              .map((c) => c.cardId)
              .toList(),
      },
      committedCards: const {'a': null, 'b': null},
    );
    final public = const VisibilityProjection().publicState(state);
    check(
      public.visibleActionPoints.isEmpty && public.revealedCards.isEmpty,
      'private_projection',
    );
    for (final z in zones) {
      check(
        z.map((c) => c.cardId).toSet().length == z.length,
        'multiple_zones',
      );
      check(z.where((c) => c.locked).length <= 1, 'multiple_locks');
      check(
        z.where((c) => c.locked).every((c) => c.zone == CardZone.HAND),
        'lock_outside_hand',
      );
      check(
        z.where((c) => c.zone == CardZone.HAND).length <= 4,
        'hand_overflow',
      );
    }
    check(
      !lifecycle.shouldEndSession(
        explicitHumanDecision: false,
        technicalClosure: false,
        actionPoints: 0,
        indicativeDurationReached: true,
      ),
      'automatic_end',
    );
  }

  SimulationMetrics run() {
    metrics.increment('sessions');
    try {
      for (round = 1; round <= runner.limits.maxRounds; round++) {
        telemetry?.roundId = 'sim.$round';
        resultSource = ActionSource.NORMAL_DUEL;
        tick();
        events([lifecycle.startRound('sim.$round')]);
        for (var i = 0; i < 2; i++) {
          tryRecovery(i);
        }
        changeIntensity();
        observeThresholds();
        final extensionOps = [
          for (final p in players)
            telemetry?.opportunity(p.profile.playerId, 'MUTUAL_EXTENSION', [
              BehaviorAxis.PROLONGATION,
            ]),
        ];
        if (players[0].decide('extension', random) &&
            players[1].decide('agreeExtension', random)) {
          tick();
          final extension = recovery.mutualExtension(
            actionPoints: pa,
            amount: 10,
            mutualAgreement: true,
          );
          final beforeExtension = pa;
          pa = extension.actionPoints;
          for (final op in extensionOps) {
            if (op != null) {
              telemetry!.extension(
                op,
                amount: 10,
                before: beforeExtension,
                after: pa,
              );
            }
          }
          events([extension.event]);
          metrics.increment('extensions');
          for (final id in ['a', 'b']) {
            metrics.increment('pa.$id.extensionGain', 10);
          }
        }
        final pools = <Set<String>>[];
        for (var i = 0; i < 2; i++) {
          final eligible = <String>{};
          for (final c in runner.cards) {
            final e = evaluate(c, i);
            if (e.eligible) {
              metrics.frequency('eligible.card', c.id);
              for (final v in e.eligibleVariants) {
                metrics.frequency('eligible.variant', v.id);
              }
              eligible.add(c.id);
              metrics.eligibleCards.add(c.id);
              metrics.eligibleVariants.addAll(
                e.eligibleVariants.map((v) => v.id),
              );
            }
            for (final v in e.variants) {
              for (final r in v.reasons) {
                metrics.frequency('ineligibility', r.code.name);
              }
            }
          }
          pools.add(eligible);
          metrics.sample('pool.player${i + 1}', eligible.length);
          if (eligible.length < 4) metrics.increment('pool.small');
          if (eligible.isEmpty) metrics.increment('pool.empty');
          refill(i);
        }
        metrics.sample('pool.common', pools[0].intersection(pools[1]).length);
        final selected = [select(0), select(1)];
        if (selected.any((c) => c == null)) {
          metrics.increment('round.unresolvable');
          metrics.frequency('termination', 'no_playable_hand');
          break;
        }
        final renunciationOps = {
          for (final p in players)
            p.profile.playerId: telemetry?.opportunity(
              p.profile.playerId,
              'RENUNCIATION',
              [BehaviorAxis.RENONCEMENT_STRATEGIQUE],
            ),
        };
        final renouncing = players
            .where((p) => p.decide('renounce', random))
            .toList();
        if (renouncing.isNotEmpty) {
          for (final p in renouncing) {
            final op = renunciationOps[p.profile.playerId];
            if (op != null) {
              telemetry!.decision(
                op,
                GameEventType.STRATEGIC_RENUNCIATION,
                {
                  'round_id': 'sim.$round',
                  'duel_context': 'PRE_COMMIT',
                  'selected_card_id': selected[players.indexOf(p)]!.card.id,
                },
                attempted: true,
                completed: true,
              );
            }
            events([duel.strategicRenunciation(p.profile.playerId)]);
          }
          metrics.increment('strategicRenunciations');
          metrics.increment('round.renounced');
          events([GameEvent(GameEventType.ROUND_CLOSED)]);
          recordRound();
          continue;
        }
        final commits = <DuelCommitment>[];
        for (var i = 0; i < 2; i++) {
          tick();
          final c = selected[i]!;
          final selectable = runner.cards
              .where(
                (card) =>
                    zones[i].any(
                      (z) => z.cardId == card.id && z.zone == CardZone.HAND,
                    ) &&
                    choice(card, i) != null,
              )
              .toList();
          final selectionOp = telemetry?.opportunity(
            players[i].profile.playerId,
            'VOLUNTARY_COMMIT',
            [
              BehaviorAxis.AUDACE,
              BehaviorAxis.PRUDENCE,
              BehaviorAxis.VARIETE,
              BehaviorAxis.SPECIALISATION,
            ],
            cards: selectable.map((c) => c.id),
            tags: selectable.expand((c) => c.tags),
          );
          check(
            evaluate(
              c.card,
              i,
            ).eligibleVariants.any((v) => v.id == c.variant.id),
            'consent_or_context',
          );
          check(
            !context.exhaustedCardIds.contains(c.card.id),
            'exhausted_selected',
          );
          if (zones[i].any((z) => z.cardId == c.card.id && z.locked)) {
            telemetry?.lockChanged(
              players[i].profile.playerId,
              c.card.id,
              false,
            );
          }
          zones[i] = lifecycle.engage(zones[i], c.card.id);
          final since = lockSince[i].remove(c.card.id);
          if (since != null) {
            metrics.sample('lock.retentionRounds', round - since);
          }
          final p = c.preference;
          final commit = duel.commit(
            playerId: players[i].profile.playerId,
            cardId: c.card.id,
            variantId: c.variant.id,
            voluntaryRole: c.rule.role,
            preference: UserPreference.fromJson({
              'profile_element_id': c.rule.elementId,
              'status': p.status.name,
              'general_value': p.general,
              'faire_value': p.faire,
              'recevoir_value': p.recevoir,
              'updated_at': '2026-01-01T00:00:00Z',
              'source': 'ONBOARDING',
            }),
            committedAt: DateTime.utc(2026).add(Duration(seconds: round)),
            cardInvertible: c.variant.invertible,
          );
          commits.add(commit);
          if (selectionOp != null) {
            telemetry!.committed(selectionOp, commit.snapshot, c.variant.tags);
          }
          events(commit.events);
          metrics.sample(
            'selection.value.${players[i].profile.playerId}',
            value(c),
          );
          metrics.frequency('selection.role', c.rule.role.name);
          for (final tag in c.variant.tags) {
            selectedTags[i].update(tag, (n) => n + 1, ifAbsent: () => 1);
          }
        }
        tick();
        final result = duel.resolve(
          first: commits[0],
          second: commits[1],
          actionPoints: pa,
        );
        final before = pa;
        pa = result.actionPoints;
        events(result.events);
        metrics.increment('duels');
        final gap =
            (commits[0].snapshot.personalValue -
                    commits[1].snapshot.personalValue)
                .abs();
        metrics.sample('duel.gap', gap);
        metrics.sample('duel.cost', result.gapCost);
        if (runner.config.gapCostCurve.costForGap(gap) >
            runner.config.gapCost(gap)) {
          metrics.increment('duel.cap');
        }
        for (final id in ['a', 'b']) {
          spendEvidence(id, 'NORMAL_DUEL', before[id]!, pa[id]!);
          metrics.increment('pa.$id.duelSpent', before[id]! - pa[id]!);
          if (before[id] != pa[id]) metrics.increment('pa.$id.duelPayments');
        }
        observeThresholds();
        int? winner = result.winnerPlayerId == null
            ? null
            : result.winnerPlayerId == 'a'
            ? 0
            : 1;
        if (winner == null) {
          metrics.increment('duel.ties');
        } else {
          if (pa[result.winnerPlayerId] == 0) {
            metrics.increment('duel.winnerAtZero');
          }
          invertedAction = null;
          invertedVoluntaryPlayer = null;
          sequenceStopped = false;
          winner = runAuction(winner, selected);
          winner = runCorruption(winner, selected);
          if (!sequenceStopped) {
            execute(invertedAction ?? selected[winner]!, winner);
          }
        }
        for (var i = 0; i < 2; i++) {
          final c = selected[i]!;
          histories[i][c.card.id] = CardHistoryState.playedOrDiscarded;
          recentTags[i] = c.variant.tags;
          recentPrecisions[i] = {c.card.precision};
          final closed = lifecycle.closeRoundWithEvents(zones[i]);
          zones[i] = closed.cards;
          events(
            closed.events.where((e) => e.type != GameEventType.ROUND_CLOSED),
          );
          gates[i] = recovery.afterNormalDuel();
        }
        metrics.increment('roundsCompleted');
        events([GameEvent(GameEventType.ROUND_CLOSED)]);
        recordRound();
        verify();
      }
      if (round > runner.limits.maxRounds) {
        metrics.frequency('termination', 'maxRounds');
      }
    } on _Limit {
      metrics.frequency('termination', 'maxActions');
    }
    metrics.sample('session.actions', actions);
    metrics.sample('session.rounds', metrics.counters['roundsCompleted'] ?? 0);
    metrics.sample('recovery.perSession', recoveries);
    final recoveryGain =
        (metrics.counters['pa.a.recoveryGain'] ?? 0) +
        (metrics.counters['pa.b.recoveryGain'] ?? 0);
    final spent =
        (metrics.counters['pa.a.duelSpent'] ?? 0) +
        (metrics.counters['pa.b.duelSpent'] ?? 0) +
        (metrics.counters['pa.a.auctionSpent'] ?? 0) +
        (metrics.counters['pa.b.auctionSpent'] ?? 0) +
        (metrics.counters['pa.a.chiliSpent'] ?? 0) +
        (metrics.counters['pa.b.chiliSpent'] ?? 0);
    if (recoveries >= 10 && recoveryGain >= spent) {
      metrics.increment('signal.recoveryOffsetsAllSpending');
    }
    for (var i = 0; i < 2; i++) {
      final id = players[i].profile.playerId;
      metrics.sample('pa.$id.final', pa[id]!);
      final total = seen[i].values.fold(0, (a, b) => a + b);
      metrics.sample('draw.uniquePerPlayerSession', seen[i].length);
      metrics.sample('draw.totalPerPlayerSession', total);
      if (total > 0) {
        metrics.sample(
          'draw.uniqueRatioBasisPoints',
          (seen[i].length / total * 10000).round(),
        );
      }
      for (final start in lockSince[i].values) {
        metrics.sample(
          'lock.censoredRetentionRounds',
          (round - start).clamp(0, runner.limits.maxRounds),
        );
      }
    }
    verify();
    return metrics;
  }

  final lastDraw = [<String, int>{}, <String, int>{}];
  void refill(int i) {
    tick();
    final previous = zones[i]
        .where((c) => c.zone == CardZone.HAND)
        .map((c) => c.cardId)
        .toSet();
    final hand = draw.refill(
      currentHand: runner.cards.where((c) => previous.contains(c.id)).toList(),
      cards: runner.cards,
      context: context,
      actor: players[i].profile,
      partner: players[1 - i].profile,
      hierarchy: runner.hierarchy,
      style: players[i].style,
      history: DrawHistory(
        cards: histories[i],
        recentTags: recentTags[i],
        recentPrecisions: recentPrecisions[i],
      ),
      random: random,
    );
    var newCards = 0;
    for (final c in hand.where((c) => !previous.contains(c.id))) {
      newCards++;
      drawIndex++;
      check(!context.exhaustedCardIds.contains(c.id), 'exhausted_draw');
      check(evaluate(c, i).eligible, 'ineligible_draw');
      telemetry?.drawn(
        players[i].profile.playerId,
        c,
        evaluate(c, i).eligibleVariants,
      );
      final state = zones[i].where((s) => s.cardId == c.id).firstOrNull;
      check(
        state == null || state.zone == CardZone.DISCARD,
        'illegal_draw_zone',
      );
      if (state?.zone == CardZone.DISCARD) {
        zones[i] = lifecycle.redrawDiscard(zones[i], c.id);
      } else {
        zones[i] = [
          ...zones[i],
          CardRuntimeState(cardId: c.id, zone: CardZone.HAND),
        ];
      }
      histories[i][c.id] = CardHistoryState.seenUnplayed;
      metrics.frequency('draw.card', c.id);
      metrics.frequency('draw.style', players[i].style.name);
      metrics.frequency('draw.precision', c.precision.name);
      metrics.frequency('draw.frequency', c.frequency.name);
      final v = choice(c, i)?.variant ?? evaluate(c, i).eligibleVariants.first;
      metrics.frequency('draw.chili', v.chiliLevel.toString());
      for (final tag in v.tags) {
        metrics.frequency('draw.tag', tag);
      }
      final prior = lastDraw[i][c.id];
      if (prior != null) {
        metrics.increment('draw.repetitions');
        metrics.sample('draw.repeatDelayDraws', drawIndex - prior);
      }
      lastDraw[i][c.id] = drawIndex;
      seen[i].update(c.id, (n) => n + 1, ifAbsent: () => 1);
    }
    metrics.sample('hand.size', hand.length);
    metrics.sample(
      'hand.playableSize',
      hand.where((c) => choice(c, i) != null).length,
    );
    metrics.sample('hand.newCards', newCards);
    final locked = zones[i].any((c) => c.locked);
    metrics.sample(
      locked ? 'hand.newCardsLocked' : 'hand.newCardsUnlocked',
      newCards,
    );
    if (hand.length < 4) metrics.increment('hand.incomplete');
    final tagList = [for (final c in hand) ...c.tags];
    metrics.sample('hand.uniqueTags', tagList.toSet().length);
    metrics.sample(
      'hand.repeatedTags',
      tagList.length - tagList.toSet().length,
    );
    metrics.sample(
      'hand.uniquePrecisions',
      hand.map((c) => c.precision).toSet().length,
    );
    final levels = <int>{};
    for (final c in hand) {
      final selected = choice(c, i);
      if (selected != null) {
        metrics.sample('hand.personalValues', value(selected));
        metrics.frequency('hand.chili', selected.variant.chiliLevel.toString());
        levels.add(selected.variant.chiliLevel);
      }
    }
    metrics.sample('hand.uniqueChili', levels.length);
    if (!locked && hand.isNotEmpty && players[i].decide('lock', random)) {
      final c = hand[(random.nextDouble() * hand.length).floor()];
      zones[i] = lifecycle.lock(zones[i], c.id);
      telemetry?.lockChanged(players[i].profile.playerId, c.id, true);
      lockSince[i][c.id] = round;
      metrics.increment('lock.used');
    }
    final styleOp = telemetry?.opportunity(
      players[i].profile.playerId,
      'STYLE',
      [BehaviorAxis.CHANGEMENT_STYLE],
    );
    if (players[i].decide('changeStyle', random)) {
      final previous = players[i].style;
      players[i].style = PlayerStyle.values[(players[i].style.index + 1) % 3];
      if (styleOp != null) {
        telemetry!.styleChanged(styleOp, previous, players[i].style);
      }
      metrics.increment('style.changed');
    }
  }

  _Choice? select(int i) {
    final held = zones[i]
        .where((z) => z.zone == CardZone.HAND)
        .map((z) => z.cardId)
        .toSet();
    var options = runner.cards
        .where((c) => held.contains(c.id))
        .map((c) => choice(c, i))
        .whereType<_Choice>()
        .toList();
    final locked = zones[i].where((z) => z.locked).firstOrNull;
    if (locked != null && !players[i].decide('playLock', random)) {
      final alternatives = options
          .where((c) => c.card.id != locked.cardId)
          .toList();
      if (alternatives.isNotEmpty) options = alternatives;
    }
    if (options.isEmpty) {
      if (locked != null) metrics.increment('lock.blocked');
      return null;
    }
    double score(_Choice c) {
      var score = random.nextDouble() * 5;
      final p = players[i];
      if (p.has(Strategy.BOLD)) score += value(c);
      if (p.has(Strategy.CAUTIOUS)) score -= value(c);
      if (p.has(Strategy.VARIETY_SEEKER)) {
        score -= 5 * (seen[i][c.card.id] ?? 0);
        for (final tag in c.variant.tags) {
          score -= selectedTags[i][tag] ?? 0;
        }
      }
      if (p.has(Strategy.SPECIALIST) &&
          c.card.tags.contains(runner.cards.first.tags.firstOrNull)) {
        score += 20;
      }
      return score;
    }

    final scored = [for (final c in options) (c, score(c))]
      ..sort((a, b) => b.$2.compareTo(a.$2));
    return scored.first.$1;
  }

  int runAuction(int winner, List<_Choice?> selected) {
    final loser = 1 - winner;
    final wid = players[winner].profile.playerId,
        lid = players[loser].profile.playerId;
    final counterOp = pa[lid]! >= 1
        ? telemetry?.opportunity(lid, 'COUNTER', [
            BehaviorAxis.NEGOCIATION,
          ], availableAmount: pa[lid])
        : null;
    if (pa[lid]! < 1 || !players[loser].decide('counter', random)) {
      if (counterOp != null) {
        telemetry!.decision(counterOp, GameEventType.DECISION_PASSED, {
          'kind': 'COUNTER',
        });
      }
      return winner;
    }
    tick();
    metrics.increment('auction.counter');
    var a = auction.start(
      initialWinnerId: wid,
      initialLoserId: lid,
      actionPoints: pa,
    );
    final amount =
        (1 + pa[lid]! * players[loser].policy.bidFraction * random.nextDouble())
            .floor()
            .clamp(1, pa[lid]!);
    final winningAction = selected[winner]!;
    final canInvert =
        winningAction.variant.invertible &&
        evaluate(
          winningAction.card,
          loser,
        ).eligibleVariants.any((v) => v.id == winningAction.variant.id);
    final target = canInvert && players[loser].decide('invert', random)
        ? AuctionTarget.INVERT_WINNING_ACTION
        : AuctionTarget.OWN_INITIAL_ACTION;
    final targetName = target == AuctionTarget.OWN_INITIAL_ACTION
        ? 'OWN_CARD'
        : 'INVERT_WINNER_CARD';
    final inversionOp = canInvert
        ? telemetry?.opportunity(lid, 'INVERSION', [BehaviorAxis.INVERSION])
        : null;
    final rolesBefore = {
      wid: winningAction.rule.role.name,
      lid: switch (winningAction.rule.role) {
        ProfileRole.FAIRE => 'RECEVOIR',
        ProfileRole.RECEVOIR => 'FAIRE',
        _ => 'GENERAL',
      },
    };
    final rolesAfter = {wid: rolesBefore[lid], lid: rolesBefore[wid]};
    if (inversionOp != null && target == AuctionTarget.INVERT_WINNING_ACTION) {
      telemetry!.decision(inversionOp, GameEventType.INVERSION_ATTEMPTED, {
        'roles_before': rolesBefore,
        'roles_after': rolesAfter,
        'variant_id': winningAction.variant.id,
      }, attempted: true);
    }
    a = auction.counter(
      a,
      amount: amount,
      target: target,
      inversionAllowed: canInvert,
    );
    metrics.sample('auction.bid', amount);
    metrics.increment('pa.$lid.auctionSpent', amount);
    resultSource = ActionSource.AUCTION_RESULT;
    if (counterOp != null) {
      telemetry!.decision(
        counterOp,
        GameEventType.AUCTION_COMMITTED,
        {
          'kind': 'COUNTER',
          'amount': amount,
          'target': targetName,
          'initial_winner_id': wid,
        },
        attempted: true,
        amount: amount,
      );
    }
    final defenseOp = a.actionPoints[wid]! > amount
        ? telemetry?.opportunity(wid, 'FINAL_DEFENSE', [
            BehaviorAxis.NEGOCIATION,
          ], availableAmount: a.actionPoints[wid])
        : null;
    var spend = amount;
    if (a.actionPoints[wid]! > amount &&
        players[winner].decide('defend', random)) {
      a = auction.defend(a, amount: amount + 1);
      if (defenseOp != null) {
        telemetry!.decision(
          defenseOp,
          GameEventType.AUCTION_COMMITTED,
          {
            'kind': 'FINAL_DEFENSE',
            'amount': amount + 1,
            'target': targetName,
            'success': true,
          },
          attempted: true,
          completed: true,
          amount: amount + 1,
        );
      }
      metrics.increment('auction.defense');
      metrics.increment('auction.initiatorFailed');
      metrics.sample('auction.bid', amount + 1);
      metrics.increment('pa.$wid.auctionSpent', amount + 1);
      spend += amount + 1;
    } else {
      metrics.increment('auction.reversal');
      if (target == AuctionTarget.INVERT_WINNING_ACTION) {
        invertedAction = winningAction;
        invertedVoluntaryPlayer = wid;
        if (inversionOp != null) {
          telemetry!.decision(inversionOp, GameEventType.INVERSION_RETAINED, {
            'roles_before': rolesBefore,
            'roles_after': rolesAfter,
            'variant_id': winningAction.variant.id,
          }, completed: true);
        }
        metrics.increment('auction.inversion');
      }
    }
    events(a.events);
    if (counterOp != null) {
      telemetry!.decision(counterOp, GameEventType.AUCTION_RESOLVED, {
        'kind': 'COUNTER',
        'target': targetName,
        'winner_player_id': a.winnerId,
        'success': a.winnerId == lid,
      }, completed: a.winnerId == lid);
    }
    if (defenseOp != null && a.defenseBid == null) {
      telemetry!.decision(defenseOp, GameEventType.DECISION_PASSED, {
        'kind': 'FINAL_DEFENSE',
      });
    }
    for (final id in [wid, lid]) {
      spendEvidence(id, 'AUCTION', pa[id]!, a.actionPoints[id]!);
    }
    metrics.sample('auction.totalSpent', spend);
    pa = a.actionPoints;
    observeThresholds();
    return a.winnerId == wid ? winner : loser;
  }

  int runCorruption(int winner, List<_Choice?> selected) {
    final loser = 1 - winner;
    final discards = zones[loser]
        .where((c) => c.zone == CardZone.DISCARD)
        .map((c) => c.cardId)
        .toSet();
    final options = runner.cards
        .where((c) => discards.contains(c.id))
        .map((c) => choice(c, loser))
        .whereType<_Choice>()
        .toList();
    final negotiationOp = options.isNotEmpty
        ? telemetry?.opportunity(
            players[loser].profile.playerId,
            'CORRUPTION',
            [BehaviorAxis.TENTATION],
            cards: options.map((c) => c.card.id),
          )
        : null;
    if (!players[loser].decide('corrupt', random)) return winner;
    if (options.isEmpty) return winner;
    tick();
    final c = options[(random.nextDouble() * options.length).floor()];
    final accepted = players[winner].decide('acceptCorruption', random);
    final status = accepted
        ? actionStatus(loser)
        : ActionExecutionStatus.PROPOSED;
    final offer = CorruptionOffer(
      offeredBy: players[loser].profile.playerId,
      objective: CorruptionObjective.OWN_INITIAL_ACTION,
      actions: [
        ActionPromise(
          cardId: c.card.id,
          source: CardZone.DISCARD,
          status: status,
        ),
      ],
    );
    final promise = telemetry?.opportunity(
      players[loser].profile.playerId,
      'PROMISE',
      [BehaviorAxis.PROMESSE, BehaviorAxis.REALISATION],
      correlationId: '${negotiationOp!.id}.action.0',
    );
    if (negotiationOp != null) {
      telemetry!.corruptionProposed(
        negotiationOp,
        offer,
        players[winner].profile.playerId,
        variantByCard: {c.card.id: c.variant.id},
      );
    }
    if (promise != null) {
      telemetry!.decision(
        promise,
        GameEventType.CORRUPTION_RESOLVED,
        {
          'offered_by': players[loser].profile.playerId,
          'recipient_id': players[winner].profile.playerId,
          'accepted': accepted,
          'action_id': promise.id,
        },
        attempted: accepted,
        accepted: accepted,
        neutralReason: accepted
            ? NonPerformanceReason.NONE
            : NonPerformanceReason.PRACTICE_REFUSAL,
      );
    }
    check(corruption.power(offer) == 0, 'promise_has_power');
    final result = corruption.resolve(
      offer: offer,
      accepted: accepted,
      cards: zones[loser],
    );
    zones[loser] = result.cards;
    sequenceStopped = result.stoppedByConsent;
    events(result.events);
    metrics.increment('corruption.proposed');
    if (accepted) {
      metrics.increment('corruption.accepted');
      applyAction(c, loser, status);
      executionEvidence(
        c,
        loser,
        ActionSource.CORRUPTION,
        status,
        promise: promise,
        reason: status == ActionExecutionStatus.SKIPPED
            ? NonPerformanceReason.PRACTICE_REFUSAL
            : NonPerformanceReason.NONE,
      );
    }
    syncExhausted();
    if (accepted && status == ActionExecutionStatus.COMPLETED) {
      invertedAction = null;
      invertedVoluntaryPlayer = null;
      resultSource = ActionSource.CORRUPTION;
      return loser;
    }
    return winner;
  }

  ActionExecutionStatus actionStatus(int i) {
    if (players[i].decide('stop', random)) return ActionExecutionStatus.STOPPED;
    if (players[i].decide('refuseAction', random)) {
      return ActionExecutionStatus.SKIPPED;
    }
    return ActionExecutionStatus.COMPLETED;
  }

  void execute(_Choice c, int i) {
    tick();
    if (!evaluate(
      c.card,
      i,
    ).eligibleVariants.any((v) => v.id == c.variant.id)) {
      metrics.increment('execution.contextChanged');
      events([lifecycle.actionEvent(ActionExecutionStatus.SKIPPED, c.card.id)]);
      executionEvidence(
        c,
        i,
        resultSource,
        ActionExecutionStatus.SKIPPED,
        reason: NonPerformanceReason.CONTEXTUAL,
      );
      return;
    }
    final status = actionStatus(i);
    events([lifecycle.actionEvent(status, c.card.id)]);
    applyAction(c, i, status);
    executionEvidence(
      c,
      i,
      resultSource,
      status,
      reason: status == ActionExecutionStatus.SKIPPED
          ? NonPerformanceReason.PRACTICE_REFUSAL
          : NonPerformanceReason.NONE,
    );
  }

  void applyAction(_Choice c, int i, ActionExecutionStatus status) {
    final before = context;
    final beforePa = Map<String, int>.from(pa);
    context = lifecycle.applyEffects(
      beforeAction: before,
      current: context,
      effects: c.variant.effects,
      actorId: players[i].profile.playerId,
      partnerId: players[1 - i].profile.playerId,
      status: status,
    );
    if (status != ActionExecutionStatus.COMPLETED) {
      check(identical(before, context), 'effect_without_completion');
      check(
        pa.entries.every((e) => beforePa[e.key] == e.value),
        'stop_refusal_pa',
      );
      metrics.increment('technicalNeutralTransitions');
    } else {
      metrics.increment('actions.completed');
    }
    if (status == ActionExecutionStatus.STOPPED) {
      final stopped = lifecycle.consentStop(context, c.variant.id);
      context = stopped.$1;
      metrics.increment('technicalStop');
    }
  }

  void tryRecovery(int i) {
    final id = players[i].profile.playerId;
    final available = recovery.available(currentPa: pa[id]!, gate: gates[i]);
    final options = available
        ? runner.cards
              .map((c) => choice(c, i, recovering: true))
              .whereType<_Choice>()
              .toList()
        : <_Choice>[];
    final recoveryOp =
        available &&
            options.isNotEmpty &&
            recoveries < runner.limits.maxRecoveryCycles
        ? telemetry?.opportunity(id, 'RECOVERY', [
            BehaviorAxis.RECOVERY_RISK,
          ], cards: options.map((c) => c.card.id))
        : null;
    if (!available || !players[i].decide('recover', random)) {
      if (recoveryOp != null) {
        telemetry!.decision(recoveryOp, GameEventType.DECISION_PASSED, {
          'kind': 'RECOVERY',
        });
      }
      return;
    }
    if (recoveries >= runner.limits.maxRecoveryCycles) {
      metrics.increment('recovery.limitReached');
      return;
    }
    if (options.isEmpty) {
      metrics.increment('recovery.noEligibleAction');
      return;
    }
    tick();
    check(
      recovery.available(currentPa: pa[id]!, gate: gates[i]),
      'illegal_recovery',
    );
    final c = options[(random.nextDouble() * options.length).floor()];
    if (recoveryOp != null) {
      telemetry!.decision(recoveryOp, GameEventType.RECOVERY_PROPOSED, {
        'card_id': c.card.id,
        'variant_id': c.variant.id,
        'recipient_id': players[1 - i].profile.playerId,
      }, attempted: true);
    }
    check(
      recovery
          .actionEligibility(
            card: c.card,
            context: context,
            actor: players[i].profile,
            partner: players[1 - i].profile,
            hierarchy: runner.hierarchy,
          )
          .eligibleVariants
          .any((v) => v.id == c.variant.id),
      'recovery_consent',
    );
    var response = players[1 - i].decide('refuseRecovery', random)
        ? RecoveryResponse.REFUSE
        : RecoveryResponse.ACCEPT;
    final discardIds = zones[i]
        .where((z) => z.zone == CardZone.DISCARD && z.cardId != c.card.id)
        .map((z) => z.cardId)
        .toSet();
    final conditions = runner.cards
        .where((card) => discardIds.contains(card.id))
        .map((card) => choice(card, i, recovering: true))
        .whereType<_Choice>()
        .toList();
    _Choice? condition;
    if (response == RecoveryResponse.ACCEPT &&
        conditions.isNotEmpty &&
        players[1 - i].decide('condition', random)) {
      response = RecoveryResponse.ACCEPT_WITH_ONE_DISCARD_CONDITION;
      condition = conditions.first;
      metrics.increment('recovery.conditions');
    }
    if (response == RecoveryResponse.REFUSE) {
      metrics.increment('recovery.refused');
    }
    final status = response == RecoveryResponse.REFUSE
        ? ActionExecutionStatus.SKIPPED
        : actionStatus(i);
    final roles = <(PreferenceValue, ProfileRole, bool)>[
      (c.preference, c.rule.role, status == ActionExecutionStatus.COMPLETED),
    ];
    applyAction(c, i, status);
    // Recheck after effects/STOP: a condition must still be possible when run.
    final conditionStatus = condition == null
        ? null
        : status == ActionExecutionStatus.STOPPED ||
              !evaluate(
                condition.card,
                i,
                recovering: true,
              ).eligibleVariants.any((v) => v.id == condition!.variant.id)
        ? ActionExecutionStatus.SKIPPED
        : actionStatus(i);
    if (condition != null) applyAction(condition, i, conditionStatus!);
    if (condition != null) {
      roles.add((
        condition.preference,
        condition.rule.role,
        conditionStatus == ActionExecutionStatus.COMPLETED,
      ));
    }
    final before = pa[id]!;
    final resolved = recovery.resolve(
      currentPa: before,
      response: response,
      performedRoles: roles,
      conditionCount: condition == null ? 0 : 1,
    );
    events(resolved.events);
    events([lifecycle.actionEvent(status, c.card.id)]);
    if (condition != null) {
      events([lifecycle.actionEvent(conditionStatus!, condition.card.id)]);
    }
    pa = {...pa, id: resolved.actionPoints};
    recoveries++;
    if (!firstRecovery) {
      firstRecovery = true;
      metrics.sample('recovery.firstRound', round);
    }
    metrics.sample('recovery.before', before);
    metrics.sample('recovery.gain', resolved.gain);
    metrics.sample('recovery.after', resolved.actionPoints);
    metrics.increment('pa.$id.recoveryGain', resolved.gain);
    if (resolved.actionPoints > runner.config.initialPa) {
      metrics.increment('recovery.aboveInitial');
    }
    if (c.variant.chiliLevel > context.chiliActive) {
      metrics.increment('recovery.higherChiliProposed');
    }
    if (status == ActionExecutionStatus.COMPLETED &&
        c.variant.chiliLevel > context.chiliActive) {
      metrics.increment('recovery.higherChiliCompleted');
    }
    final zone = zones[i].where((z) => z.cardId == c.card.id).firstOrNull?.zone;
    final source = switch (zone) {
      CardZone.HAND => RecoverySource.HAND,
      CardZone.DISCARD => RecoverySource.DISCARD,
      _ => RecoverySource.CATALOG,
    };
    if (recoveryOp != null) {
      telemetry!.decision(
        recoveryOp,
        GameEventType.RECOVERY_RESOLVED,
        {
          'response': response.name,
          'card_id': c.card.id,
          'variant_id': c.variant.id,
          'card_source': source.name,
          'condition_card_id': condition?.card.id,
          'condition_variant_id': condition?.variant.id,
          'chili_active': context.chiliActive,
          'chili_variant': c.variant.chiliLevel,
          'chili_exception': c.variant.chiliLevel > context.chiliActive,
          'pa_before': before,
          'gain': resolved.gain,
          'pa_after': resolved.actionPoints,
          'status': status.name,
        },
        accepted: response != RecoveryResponse.REFUSE,
        completed: status == ActionExecutionStatus.COMPLETED,
        neutralReason: response == RecoveryResponse.REFUSE
            ? NonPerformanceReason.PRACTICE_REFUSAL
            : status == ActionExecutionStatus.STOPPED
            ? NonPerformanceReason.CONSENT_STOP
            : status == ActionExecutionStatus.SKIPPED
            ? NonPerformanceReason.PRACTICE_REFUSAL
            : NonPerformanceReason.NONE,
      );
    }
    executionEvidence(
      c,
      i,
      ActionSource.RECOVERY,
      status,
      reason: status == ActionExecutionStatus.SKIPPED
          ? NonPerformanceReason.PRACTICE_REFUSAL
          : NonPerformanceReason.NONE,
    );
    if (condition != null) {
      executionEvidence(
        condition,
        i,
        ActionSource.RECOVERY_CONDITION,
        conditionStatus!,
        reason: conditionStatus == ActionExecutionStatus.SKIPPED
            ? NonPerformanceReason.CONTEXTUAL
            : NonPerformanceReason.NONE,
      );
    }
    if (source == RecoverySource.HAND &&
        status == ActionExecutionStatus.COMPLETED &&
        zones[i].any((z) => z.cardId == c.card.id && z.locked)) {
      telemetry?.lockChanged(id, c.card.id, false);
    }
    zones[i] = recovery.applyLifecycle(
      cards: zones[i],
      cardId: c.card.id,
      source: source,
      completed: status == ActionExecutionStatus.COMPLETED,
    );
    if (status == ActionExecutionStatus.COMPLETED) {
      histories[i][c.card.id] = CardHistoryState.playedOrDiscarded;
      final since = lockSince[i].remove(c.card.id);
      if (since != null) metrics.sample('lock.retentionRounds', round - since);
    }
    if (source == RecoverySource.DISCARD &&
        status == ActionExecutionStatus.COMPLETED) {
      metrics.increment('recovery.exhausted');
    }
    if (condition != null) {
      zones[i] = recovery.applyLifecycle(
        cards: zones[i],
        cardId: condition.card.id,
        source: RecoverySource.DISCARD,
        completed: conditionStatus == ActionExecutionStatus.COMPLETED,
      );
      if (conditionStatus == ActionExecutionStatus.COMPLETED) {
        metrics.increment('recovery.exhausted');
      }
    }
    gates[i] = recovery.afterRecovery(gates[i]);
    syncExhausted();
  }

  void changeIntensity() {
    final proposer = (random.nextDouble() * 2).floor(), other = 1 - proposer;
    final p = players[proposer];
    var target = context.chiliActive;
    final increaseOp = target < 5
        ? telemetry?.opportunity(p.profile.playerId, 'CHILI_INCREASE', [
            BehaviorAxis.ESCALADE,
          ])
        : null;
    final decreaseOp = target > 1
        ? telemetry?.opportunity(p.profile.playerId, 'CHILI_DECREASE', [
            BehaviorAxis.MODERATION,
          ])
        : null;
    if (p.decide('climb', random) && target < 5) {
      target++;
      metrics.increment('chili.proposals');
      if (increaseOp != null) {
        telemetry!.decision(increaseOp, GameEventType.CHILI_INCREASE_PROPOSED, {
          'previous_level': context.chiliActive,
          'target_level': target,
          'recipient_id': players[other].profile.playerId,
        }, attempted: true);
      }
      if (!players[other].decide('agreeClimb', random)) {
        metrics.increment('chili.refused');
        if (increaseOp != null) {
          telemetry!
              .decision(increaseOp, GameEventType.CHILI_INCREASE_DECLINED, {
                'target_level': target,
                'recipient_id': players[other].profile.playerId,
                'decision_kind': 'INTENSITY_ONLY',
              });
        }
        return;
      }
    } else if (p.decide('lower', random) && target > 1) {
      target--;
      if (decreaseOp != null) {
        telemetry!.decision(decreaseOp, GameEventType.CHILI_DECREASE_PROPOSED, {
          'previous_level': context.chiliActive,
          'target_level': target,
          'recipient_id': players[other].profile.playerId,
        }, attempted: true);
      }
    } else {
      return;
    }
    tick();
    final state = IntensityState(
      active: context.chiliActive,
      unlocked: context.chiliUnlocked,
      maximum: 5,
    );
    final cost = intensity.unlockCost(state, target);
    final pid = p.profile.playerId, oid = players[other].profile.playerId;
    // Experiment policy: proposer pays the odd unit; no implicit debt or rule change.
    final payment = {pid: (cost + 1) ~/ 2, oid: cost ~/ 2};
    if (payment.entries.any((e) => e.value > pa[e.key]!)) {
      metrics.increment('chili.unaffordable');
      return;
    }
    final result = intensity.change(
      state: state,
      target: target,
      mutualAgreement: true,
      actionPoints: pa,
      payments: payment,
    );
    final intensityOp = target < context.chiliActive ? decreaseOp : increaseOp;
    if (intensityOp != null) {
      telemetry!.decision(
        intensityOp,
        target < context.chiliActive
            ? GameEventType.CHILI_DECREASE_ACCEPTED
            : GameEventType.CHILI_INCREASE_ACCEPTED,
        {
          'target_level': target,
          'recipient_id': players[other].profile.playerId,
          'payments': payment,
        },
        accepted: true,
        completed: true,
      );
    }
    telemetry?.record(GameEventType.CHILI_LEVEL_CHANGED, {
      'previous_level': context.chiliActive,
      'new_level': target,
    }, visibility: DataVisibility.PUBLIC);
    for (final id in pa.keys) {
      spendEvidence(id, 'CHILI', pa[id]!, result.actionPoints[id]!);
    }
    for (final e in payment.entries) {
      metrics.increment('pa.${e.key}.chiliSpent', e.value);
    }
    if (target < context.chiliActive) {
      metrics.increment('chili.lowered');
    } else {
      metrics.increment('chili.accepted');
      if (cost == 0) metrics.increment('chili.freeReturn');
    }
    metrics.increment('chili.spent', cost);
    pa = result.actionPoints;
    context = context.copyWith(
      chiliActive: result.state.active,
      chiliUnlocked: result.state.unlocked,
    );
  }

  void recordRound() {
    for (final id in ['a', 'b']) {
      metrics.sample('pa.$id.afterRound.$round', pa[id]!);
      metrics.sample('pa.$id.allRounds', pa[id]!);
    }
    observeThresholds();
    metrics.sample('chili.afterRound.$round', context.chiliActive);
    if (firstChili.add(context.chiliActive)) {
      metrics.sample('chili.firstAt${context.chiliActive}', round);
    }
  }

  void observeThresholds() {
    for (final id in ['a', 'b']) {
      for (final threshold in [50, 20, 0]) {
        final key = '$id.$threshold';
        if (pa[id]! <= runner.config.initialPa * threshold / 100 &&
            firstThresholds.add(key)) {
          metrics.sample('pa.$id.firstAt$threshold', round);
          metrics.sample(
            'pa.$id.duelsTo$threshold',
            metrics.counters['duels'] ?? 0,
          );
        }
      }
    }
  }
}
