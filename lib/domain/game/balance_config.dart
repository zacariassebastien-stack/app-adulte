import 'game_models.dart';

abstract interface class GapCostCurve {
  const GapCostCurve();
  int costForGap(int gap);
}

final class LinearGapCostCurve implements GapCostCurve {
  const LinearGapCostCurve();
  @override
  int costForGap(int gap) => gap.clamp(0, 20);
}

final class AcceleratingGapCostCurve implements GapCostCurve {
  const AcceleratingGapCostCurve();
  @override
  int costForGap(int gap) {
    if (gap <= 0) return 0;
    if (gap <= 2) return gap;
    return 2 + ((gap - 1) * (gap - 1) ~/ 2);
  }
}

final class DrawWeights {
  const DrawWeights({
    this.unseen = 8,
    this.seenUnplayed = 3,
    this.played = 1,
    this.style = 2,
    this.chili = 1,
    this.tagDiversity = 2,
    this.precisionDiversity = 1,
    this.frequency = 1,
  });
  final double unseen;
  final double seenUnplayed;
  final double played;
  final double style;
  final double chili;
  final double tagDiversity;
  final double precisionDiversity;
  final double frequency;
}

final class BalanceConfig {
  const BalanceConfig({
    this.initialPa = 100,
    this.handSize = 4,
    this.recoveryThreshold = 0.10,
    this.gapCostCurve = const LinearGapCostCurve(),
    this.gapCostCapRatio = 1.0,
    this.chiliUnlockCosts = const {2: 3, 3: 5, 4: 8, 5: 13},
    this.drawWeights = const DrawWeights(),
    this.antiRepeatDecay = 0.5,
    this.styleDistributions = const {
      PlayerStyle.SOFT: {1: 1.0, 2: 0.8, 3: 0.4, 4: 0.2, 5: 0.1},
      PlayerStyle.EPICE: {1: 0.4, 2: 0.8, 3: 1.0, 4: 0.8, 5: 0.4},
      PlayerStyle.INTENABLE: {1: 0.1, 2: 0.2, 3: 0.5, 4: 0.9, 5: 1.0},
    },
  });
  final int initialPa;
  final int handSize;
  final double recoveryThreshold;
  final GapCostCurve gapCostCurve;
  final double gapCostCapRatio;
  final Map<int, int> chiliUnlockCosts;
  final DrawWeights drawWeights;
  final double antiRepeatDecay;
  final Map<PlayerStyle, Map<int, double>> styleDistributions;

  int gapCost(int gap) {
    final raw = gapCostCurve.costForGap(gap);
    final cap = (initialPa * gapCostCapRatio).floor();
    return raw.clamp(0, cap);
  }

  int get recoveryThresholdPa => (initialPa * recoveryThreshold).floor();
}
