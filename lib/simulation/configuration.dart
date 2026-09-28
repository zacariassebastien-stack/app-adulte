import '../domain/domain.dart';
import '../engines/engines.dart';

// Synthetic experiment labels, never user diagnoses.
// ignore_for_file: constant_identifier_names
enum ConsentPool {
  CONSERVATIVE_POOL,
  BROAD_POOL,
  HIGH_AUDACITY_POOL,
  MIXED_POOL,
}

enum Strategy {
  BALANCED,
  PA_SAVER,
  PA_SPENDER,
  BOLD,
  CAUTIOUS,
  VARIETY_SEEKER,
  SPECIALIST,
  AUCTION_AGGRESSIVE,
  AUCTION_PASSIVE,
  CHILI_CLIMBER,
  CHILI_STABLE,
  RECOVERY_RISK,
}

final class SimulationLimits {
  const SimulationLimits({
    this.maxRounds = 50,
    this.maxActions = 5000,
    this.maxRecoveryCycles = 100,
  });
  final int maxRounds, maxActions, maxRecoveryCycles;
  void validate() {
    if (maxRounds < 1 || maxActions < 1 || maxRecoveryCycles < 0) {
      throw ArgumentError('Invalid simulation limits');
    }
  }

  Map<String, Object> toJson() => {
    'maxRounds': maxRounds,
    'maxActions': maxActions,
    'maxRecoveryCycles': maxRecoveryCycles,
  };
}

final class DecisionPolicy {
  const DecisionPolicy({
    this.counter = .3,
    this.defend = .4,
    this.climb = .12,
    this.agreeClimb = .7,
    this.lower = .02,
    this.recover = .5,
    this.refuseRecovery = .08,
    this.condition = .2,
    this.stop = .005,
    this.refuseAction = .01,
    this.lock = .15,
    this.playLock = .25,
    this.corrupt = .08,
    this.acceptCorruption = .5,
    this.extension = .01,
    this.agreeExtension = .5,
    this.renounce = .01,
    this.changeStyle = .01,
    this.bidFraction = .08,
    this.invert = .2,
  });
  final double counter,
      defend,
      climb,
      agreeClimb,
      lower,
      recover,
      refuseRecovery,
      condition,
      stop,
      refuseAction,
      lock,
      playLock,
      corrupt,
      acceptCorruption,
      extension,
      agreeExtension,
      renounce,
      changeStyle,
      bidFraction,
      invert;
  Map<String, double> toJson() => {
    'counter': counter,
    'defend': defend,
    'climb': climb,
    'agreeClimb': agreeClimb,
    'lower': lower,
    'recover': recover,
    'refuseRecovery': refuseRecovery,
    'condition': condition,
    'stop': stop,
    'refuseAction': refuseAction,
    'lock': lock,
    'playLock': playLock,
    'corrupt': corrupt,
    'acceptCorruption': acceptCorruption,
    'extension': extension,
    'agreeExtension': agreeExtension,
    'renounce': renounce,
    'changeStyle': changeStyle,
    'bidFraction': bidFraction,
    'invert': invert,
  };
  void validate() {
    if (toJson().values.any((p) => !p.isFinite || p < 0 || p > 1)) {
      throw ArgumentError('Probabilities/fractions must be within [0,1]');
    }
  }
}

final class SimulationPlayer {
  SimulationPlayer({
    required this.profile,
    required this.strategies,
    required this.style,
    this.policy = const DecisionPolicy(),
  });
  final PlayerGameProfile profile;
  final Set<Strategy> strategies;
  PlayerStyle style;
  final DecisionPolicy policy;
  bool has(Strategy s) => strategies.contains(s);
  double probability(String decision) {
    final base = policy.toJson()[decision]!;
    final factor = switch (decision) {
      'counter' || 'defend' =>
        has(Strategy.AUCTION_PASSIVE) || has(Strategy.PA_SAVER)
            ? .15
            : has(Strategy.AUCTION_AGGRESSIVE)
            ? 2.5
            : has(Strategy.PA_SPENDER)
            ? 2
            : 1,
      'climb' =>
        has(Strategy.CHILI_STABLE)
            ? .1
            : has(Strategy.CHILI_CLIMBER)
            ? 4
            : has(Strategy.PA_SPENDER)
            ? 2
            : has(Strategy.PA_SAVER)
            ? .25
            : 1,
      'agreeClimb' => has(Strategy.CHILI_STABLE) ? .3 : 1,
      'recover' => has(Strategy.RECOVERY_RISK) ? 2 : 1,
      _ => 1,
    };
    return (base * factor).clamp(0, 1).toDouble();
  }

  bool decide(String decision, RandomSource rng) =>
      rng.nextDouble() < probability(decision);
}

final class SimulationScenario {
  const SimulationScenario({
    required this.id,
    required this.first,
    required this.second,
    this.poolA = ConsentPool.BROAD_POOL,
    this.poolB = ConsentPool.BROAD_POOL,
    this.similar = false,
    this.mode = SessionMode.face_to_face,
    this.style = PlayerStyle.EPICE,
    this.initialChili = 1,
  });
  final String id;
  final Set<Strategy> first, second;
  final ConsentPool poolA, poolB;
  final bool similar;
  final SessionMode mode;
  final PlayerStyle style;
  final int initialChili;
  Map<String, Object> toJson() => {
    'id': id,
    'first': first.map((s) => s.name).toList(),
    'second': second.map((s) => s.name).toList(),
    'poolA': poolA.name,
    'poolB': poolB.name,
    'similar': similar,
    'mode': mode.name,
    'style': style.name,
    'initialChili': initialChili,
  };
}

List<SimulationScenario> representativeScenarios() {
  const pairs = [
    (Strategy.BALANCED, Strategy.BALANCED),
    (Strategy.PA_SAVER, Strategy.PA_SAVER),
    (Strategy.PA_SPENDER, Strategy.PA_SPENDER),
    (Strategy.PA_SAVER, Strategy.PA_SPENDER),
    (Strategy.BOLD, Strategy.CAUTIOUS),
    (Strategy.BOLD, Strategy.BOLD),
    (Strategy.VARIETY_SEEKER, Strategy.SPECIALIST),
    (Strategy.AUCTION_AGGRESSIVE, Strategy.AUCTION_AGGRESSIVE),
    (Strategy.AUCTION_AGGRESSIVE, Strategy.AUCTION_PASSIVE),
    (Strategy.CHILI_CLIMBER, Strategy.CHILI_STABLE),
    (Strategy.RECOVERY_RISK, Strategy.BALANCED),
  ];
  return [
    for (var i = 0; i < pairs.length; i++) ...[
      SimulationScenario(
        id: '${pairs[i].$1.name}_vs_${pairs[i].$2.name}_broad',
        first: {pairs[i].$1},
        second: {pairs[i].$2},
      ),
      SimulationScenario(
        id: '${pairs[i].$1.name}_vs_${pairs[i].$2.name}_asymmetric',
        first: {pairs[i].$1},
        second: {pairs[i].$2},
        poolA: ConsentPool.values[i % 4],
        poolB: ConsentPool.values[(i + 1) % 4],
        mode: SessionMode.values[i % 3],
      ),
    ],
    for (final style in PlayerStyle.values)
      SimulationScenario(
        id: 'style_${style.name}',
        first: {Strategy.BALANCED},
        second: {Strategy.BALANCED},
        poolA: ConsentPool.HIGH_AUDACITY_POOL,
        poolB: ConsentPool.HIGH_AUDACITY_POOL,
        style: style,
        initialChili: 5,
      ),
    const SimulationScenario(
      id: 'similar_tastes',
      first: {Strategy.BALANCED},
      second: {Strategy.BALANCED},
      similar: true,
    ),
    const SimulationScenario(
      id: 'bold_saver_composed',
      first: {Strategy.BOLD, Strategy.PA_SAVER},
      second: {Strategy.CAUTIOUS, Strategy.PA_SPENDER},
      poolA: ConsentPool.HIGH_AUDACITY_POOL,
      poolB: ConsentPool.CONSERVATIVE_POOL,
    ),
  ];
}

final class SyntheticProfileSpec {
  const SyntheticProfileSpec(
    this.acceptance,
    this.minimum,
    this.maximum, {
    this.excludedShare = 1 / 3,
    this.discoverShare = 1 / 3,
  });
  final double acceptance, excludedShare, discoverShare;
  final int minimum, maximum;
  Map<String, Object> toJson() => {
    'acceptance': acceptance,
    'minimum': minimum,
    'maximum': maximum,
    'excludedShareAmongNonaccepted': excludedShare,
    'discoverShareAmongNonaccepted': discoverShare,
  };
  void validate() {
    if ([
          acceptance,
          excludedShare,
          discoverShare,
        ].any((p) => !p.isFinite || p < 0 || p > 1) ||
        excludedShare + discoverShare > 1 ||
        minimum < 1 ||
        maximum > 20 ||
        minimum > maximum) {
      throw ArgumentError('Invalid synthetic profile specification');
    }
  }
}

const defaultProfileSpecs = {
  ConsentPool.CONSERVATIVE_POOL: SyntheticProfileSpec(.4, 1, 10),
  ConsentPool.BROAD_POOL: SyntheticProfileSpec(.9, 1, 20),
  ConsentPool.HIGH_AUDACITY_POOL: SyntheticProfileSpec(.95, 10, 20),
  ConsentPool.MIXED_POOL: SyntheticProfileSpec(.65, 1, 20),
};

PlayerGameProfile syntheticProfile(
  Catalog catalog,
  String id,
  ConsentPool pool,
  RandomSource rng, {
  SyntheticProfileSpec? spec,
}) {
  final settings = spec ?? defaultProfileSpecs[pool]!;
  settings.validate();
  int value() =>
      settings.minimum +
      (rng.nextDouble() * (settings.maximum - settings.minimum + 1)).floor();
  PreferenceStatus status() {
    if (rng.nextDouble() < settings.acceptance) {
      return PreferenceStatus.ACCEPTED;
    }
    final p = rng.nextDouble();
    if (p < settings.excludedShare) return PreferenceStatus.EXCLUDED;
    if (p < settings.excludedShare + settings.discoverShare) {
      return PreferenceStatus.DISCOVER;
    }
    return PreferenceStatus.UNSET;
  }

  return PlayerGameProfile(
    playerId: id,
    preferences: {
      for (final e in catalog.profileElements)
        e.stableId: PreferenceValue(
          status: status(),
          general: value(),
          faire: value(),
          recevoir: value(),
        ),
    },
  );
}

Map<String, Object> balanceJson(BalanceConfig c) => {
  'initialPA': c.initialPa,
  'handSize': c.handSize,
  'recoveryThreshold': c.recoveryThreshold,
  'gapCosts': [for (var i = 0; i < 20; i++) c.gapCost(i)],
  'rawGapCosts': [for (var i = 0; i < 20; i++) c.gapCostCurve.costForGap(i)],
  'capRatio': c.gapCostCapRatio,
  'chiliCosts': {
    for (final e in c.chiliUnlockCosts.entries) e.key.toString(): e.value,
  },
  'antiRepeatDecay': c.antiRepeatDecay,
  'styleDistributions': {
    for (final e in c.styleDistributions.entries)
      e.key.name: {for (final v in e.value.entries) v.key.toString(): v.value},
  },
  'drawWeights': {
    'unseen': c.drawWeights.unseen,
    'seenUnplayed': c.drawWeights.seenUnplayed,
    'played': c.drawWeights.played,
    'style': c.drawWeights.style,
    'chili': c.drawWeights.chili,
    'tagDiversity': c.drawWeights.tagDiversity,
    'precisionDiversity': c.drawWeights.precisionDiversity,
    'frequency': c.drawWeights.frequency,
  },
};
