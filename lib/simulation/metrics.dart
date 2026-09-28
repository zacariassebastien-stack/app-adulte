import 'dart:math' as math;

final class Distribution {
  final Map<int, int> histogram = {};
  void add(int value, [int count = 1]) =>
      histogram.update(value, (n) => n + count, ifAbsent: () => count);
  void merge(Distribution other) {
    for (final e in other.histogram.entries) {
      add(e.key, e.value);
    }
  }

  int get count => histogram.values.fold(0, (a, b) => a + b);
  Map<String, Object?> toJson() {
    final keys = histogram.keys.toList()..sort();
    if (keys.isEmpty) {
      return {
        'count': 0,
        'mean': null,
        'median': null,
        'min': null,
        'max': null,
        'distribution': <String, int>{},
      };
    }
    int at(int position) {
      var seen = 0;
      for (final k in keys) {
        seen += histogram[k]!;
        if (seen > position) return k;
      }
      return keys.last;
    }

    return {
      'count': count,
      'mean': keys.fold<int>(0, (n, k) => n + k * histogram[k]!) / count,
      'median': (at((count - 1) ~/ 2) + at(count ~/ 2)) / 2,
      'min': keys.first,
      'max': keys.last,
      'distribution': {for (final k in keys) k.toString(): histogram[k]},
    };
  }
}

/// Bounded by distinct values/IDs, not by campaign length. No real user data.
final class SimulationMetrics {
  final Map<String, int> counters = {};
  final Map<String, Distribution> distributions = {};
  final Map<String, Map<String, int>> frequencies = {};
  final Set<String> eligibleCards = {}, eligibleVariants = {};
  final List<Map<String, Object>> anomalies = [];
  void increment(String name, [int by = 1]) =>
      counters.update(name, (n) => n + by, ifAbsent: () => by);
  void sample(String name, int value) =>
      distributions.putIfAbsent(name, Distribution.new).add(value);
  void frequency(String name, String id, [int by = 1]) => frequencies
      .putIfAbsent(name, () => {})
      .update(id, (n) => n + by, ifAbsent: () => by);
  void merge(SimulationMetrics other) {
    for (final e in other.counters.entries) {
      increment(e.key, e.value);
    }
    for (final e in other.distributions.entries) {
      distributions.putIfAbsent(e.key, Distribution.new).merge(e.value);
    }
    for (final f in other.frequencies.entries) {
      for (final e in f.value.entries) {
        frequency(f.key, e.key, e.value);
      }
    }
    eligibleCards.addAll(other.eligibleCards);
    eligibleVariants.addAll(other.eligibleVariants);
    // Keep a bounded diagnostic example list; counters retain exact totals.
    anomalies.addAll(other.anomalies.take(math.max(0, 100 - anomalies.length)));
  }

  Map<String, Object?> toJson() {
    final cards = frequencies['draw.card'] ?? {};
    final total = cards.values.fold(0, (a, b) => a + b);
    final sorted = cards.values.toList()..sort((a, b) => b.compareTo(a));
    return {
      'counters': counters,
      'distributions': {
        for (final e in distributions.entries) e.key: e.value.toJson(),
      },
      'frequencies': frequencies,
      'eligibleCards': eligibleCards.toList()..sort(),
      'eligibleVariants': eligibleVariants.toList()..sort(),
      'anomalies': anomalies,
      'diversity': {
        'uniqueCards': cards.length,
        'draws': total,
        'catalogUniqueOverDraws': total == 0 ? null : cards.length / total,
        'top10Share': total == 0
            ? null
            : sorted.take(10).fold(0, (a, b) => a + b) / total,
        'entropyBits': total == 0
            ? null
            : -cards.values.fold<double>(0, (s, n) {
                final p = n / total;
                return s + p * math.log(p) / math.ln2;
              }),
      },
    };
  }
}
