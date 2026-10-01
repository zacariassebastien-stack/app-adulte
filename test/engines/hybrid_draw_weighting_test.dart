import 'package:couple_cards/engines/engines.dart';
import 'package:test/test.dart';

void main() {
  const engine = HybridDrawWeighting();
  final cards = [
    const HybridDrawCandidate(id: 'remote.1', distanceExcluded: false),
    const HybridDrawCandidate(id: 'remote.2', distanceExcluded: false),
    const HybridDrawCandidate(id: 'remote.3', distanceExcluded: false),
    const HybridDrawCandidate(id: 'physical.1', distanceExcluded: true),
  ];

  test('distance orientation distributes 70/30 by eligible groups', () {
    final result = engine.weights(cards, HybridDrawOrientation.distance);
    final remote = result.where((item) => !item.candidate.distanceExcluded);
    final physical = result.where((item) => item.candidate.distanceExcluded);
    expect(
      remote.fold(0.0, (sum, item) => sum + item.weight),
      closeTo(.7, 1e-9),
    );
    expect(
      physical.fold(0.0, (sum, item) => sum + item.weight),
      closeTo(.3, 1e-9),
    );
    expect(
      remote.map((item) => item.weight).toSet().single,
      closeTo(.7 / 3, 1e-9),
    );
  });

  test('face-to-face orientation reverses group shares', () {
    final result = engine.weights(cards, HybridDrawOrientation.faceToFace);
    expect(
      result
          .where((item) => !item.candidate.distanceExcluded)
          .fold(0.0, (sum, item) => sum + item.weight),
      closeTo(.3, 1e-9),
    );
    expect(
      result
          .where((item) => item.candidate.distanceExcluded)
          .fold(0.0, (sum, item) => sum + item.weight),
      closeTo(.7, 1e-9),
    );
  });

  test('small group is compensated and DISTANCE_EXCLUE stays eligible', () {
    final result = engine.weights(cards, HybridDrawOrientation.distance);
    final physical = result.singleWhere(
      (item) => item.candidate.distanceExcluded,
    );
    expect(physical.weight, closeTo(.3, 1e-9));
    expect(
      result.fold(0.0, (sum, item) => sum + item.weight),
      closeTo(1, 1e-9),
    );
  });

  test('empty group falls back to a uniform eligible pool', () {
    final result = engine.weights(
      cards.where((card) => !card.distanceExcluded),
      HybridDrawOrientation.faceToFace,
    );
    expect(result, hasLength(3));
    expect(
      result.map((item) => item.weight),
      everyElement(closeTo(1 / 3, 1e-9)),
    );
    expect(engine.weights(const [], HybridDrawOrientation.distance), isEmpty);
  });
}
