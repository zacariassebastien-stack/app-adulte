import 'concept_deck_engine.dart';

/// V4 fraction comparison over two projections of the same conceptual stock.
/// No persistent stock or stage counter is introduced. Eligibility/classification
/// is recomputed at N and virtually N+1; only the caller publishes a new ceiling.
final class ConceptSpiceProgression {
  const ConceptSpiceProgression();
  int unlockedLevel({
    required int currentLevel,
    required ConceptDeckStock stock,
    required Iterable<ConceptDeckCandidate> Function(int ceiling) project,
  }) {
    RangeError.checkValueInInterval(currentLevel, 1, 4, 'currentLevel');
    var level = currentLevel;
    while (level < 4) {
      final current = _units(level, project(level), stock);
      final next = _units(level + 1, project(level + 1), stock);
      if (next.initial == 0) break;
      if (current.initial != 0 &&
          current.remaining * next.initial >= next.remaining * current.initial)
        break;
      level++;
    }
    return level;
  }

  ({int initial, int remaining}) _units(
    int level,
    Iterable<ConceptDeckCandidate> projection,
    ConceptDeckStock stock,
  ) {
    final ids = {
      for (final c in projection)
        if (c.drawClass == level) c.concept.id,
    };
    return (
      initial: ids.fold(0, (sum, id) => sum + stock.capacity[id]!),
      remaining: ids.fold(0, (sum, id) => sum + stock.remainingFor(id)),
    );
  }
}
