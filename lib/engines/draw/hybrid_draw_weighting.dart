enum HybridDrawOrientation { distance, faceToFace }

final class HybridDrawCandidate {
  const HybridDrawCandidate({required this.id, required this.distanceExcluded});

  final String id;
  final bool distanceExcluded;
}

final class HybridWeightedCandidate {
  const HybridWeightedCandidate({
    required this.candidate,
    required this.weight,
  });

  final HybridDrawCandidate candidate;
  final double weight;
}

/// Computes hybrid draw weights over the currently eligible pool only.
///
/// `distanceExcluded` cards remain eligible in hybrid sessions. The orientation
/// changes their target share; it never changes catalogue compatibility.
final class HybridDrawWeighting {
  const HybridDrawWeighting();

  List<HybridWeightedCandidate> weights(
    Iterable<HybridDrawCandidate> eligibleCards,
    HybridDrawOrientation orientation,
  ) {
    final compatible = <HybridDrawCandidate>[];
    final physical = <HybridDrawCandidate>[];
    for (final card in eligibleCards) {
      (card.distanceExcluded ? physical : compatible).add(card);
    }
    if (compatible.isEmpty && physical.isEmpty) return const [];
    if (compatible.isEmpty) return _uniform(physical);
    if (physical.isEmpty) return _uniform(compatible);

    final compatibleShare = orientation == HybridDrawOrientation.distance
        ? 0.70
        : 0.30;
    final physicalShare = 1 - compatibleShare;
    return List.unmodifiable([
      ..._group(compatible, compatibleShare),
      ..._group(physical, physicalShare),
    ]);
  }

  List<HybridWeightedCandidate> _uniform(List<HybridDrawCandidate> cards) =>
      _group(cards, 1);

  List<HybridWeightedCandidate> _group(
    List<HybridDrawCandidate> cards,
    double targetShare,
  ) {
    final weight = targetShare / cards.length;
    return [
      for (final card in cards)
        HybridWeightedCandidate(candidate: card, weight: weight),
    ];
  }
}
