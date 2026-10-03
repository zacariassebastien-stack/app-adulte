import '../../domain/game/game_models.dart';

final class CardDirectionSelection {
  const CardDirectionSelection({
    required this.nativeDirection,
    required this.effectiveDirection,
  });

  final CardOccurrenceDirection nativeDirection;
  final CardOccurrenceDirection effectiveDirection;
}

/// Selects the direction exactly once when an occurrence enters the runtime.
/// Persistence belongs to [CardRuntimeState], not to this stateless engine.
final class CardDirectionEngine {
  const CardDirectionEngine();

  CardDirectionSelection select({
    required bool reversible,
    required CardOccurrenceDirection fixedDirection,
    required bool faireAllowed,
    required bool recevoirAllowed,
    required bool chooseFaire,
  }) {
    final direction = reversible
        ? _reversible(
            faireAllowed: faireAllowed,
            recevoirAllowed: recevoirAllowed,
            chooseFaire: chooseFaire,
          )
        : fixedDirection;
    return CardDirectionSelection(
      nativeDirection: direction,
      effectiveDirection: direction,
    );
  }

  CardOccurrenceDirection _reversible({
    required bool faireAllowed,
    required bool recevoirAllowed,
    required bool chooseFaire,
  }) {
    if (!faireAllowed && !recevoirAllowed) {
      throw StateError('Aucune direction autorisée pour cette carte');
    }
    if (!faireAllowed) return CardOccurrenceDirection.RECEVOIR;
    if (!recevoirAllowed) return CardOccurrenceDirection.FAIRE;
    return chooseFaire
        ? CardOccurrenceDirection.FAIRE
        : CardOccurrenceDirection.RECEVOIR;
  }

  CardOccurrenceDirection invert(CardOccurrenceDirection direction) =>
      switch (direction) {
        CardOccurrenceDirection.FAIRE => CardOccurrenceDirection.RECEVOIR,
        CardOccurrenceDirection.RECEVOIR => CardOccurrenceDirection.FAIRE,
        _ => direction,
      };
}
