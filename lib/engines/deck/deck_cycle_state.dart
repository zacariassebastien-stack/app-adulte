import '../../domain/game/game_models.dart';

enum HybridDeckOrientation { faceToFace, distance }

enum DeckExhaustionChoice {
  continueSpicier,
  continueIntenable,
  infinite,
  newCustomizedGame,
  finish,
}

final class DeckCycleState {
  const DeckCycleState({required this.style, this.infinite = false});
  final PlayerStyle style;
  final bool infinite;

  DeckCycleState next(DeckExhaustionChoice choice) => switch (choice) {
    DeckExhaustionChoice.continueSpicier => DeckCycleState(
      style: style == PlayerStyle.SOFT
          ? PlayerStyle.EPICE
          : PlayerStyle.INTENABLE,
    ),
    DeckExhaustionChoice.continueIntenable => DeckCycleState(
      style: PlayerStyle.INTENABLE,
    ),
    DeckExhaustionChoice.infinite => DeckCycleState(
      style: style,
      infinite: true,
    ),
    DeckExhaustionChoice.newCustomizedGame ||
    DeckExhaustionChoice.finish => this,
  };
}
