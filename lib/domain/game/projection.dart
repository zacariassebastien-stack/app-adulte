final class CompleteGameState {
  CompleteGameState({
    required this.sessionId,
    required this.roundNumber,
    required Map<String, int> actionPoints,
    required Map<String, List<String>> hands,
    required Map<String, String?> committedCards,
    Map<String, String>? publiclyRevealedCards,
    this.revealed = false,
  }) : actionPoints = Map.unmodifiable(actionPoints),
       hands = Map.unmodifiable({
         for (final entry in hands.entries)
           entry.key: List<String>.unmodifiable(entry.value),
       }),
       committedCards = Map.unmodifiable(committedCards),
       publiclyRevealedCards = Map.unmodifiable(
         publiclyRevealedCards ?? const {},
       );
  final String sessionId;
  final int roundNumber;
  final Map<String, int> actionPoints;
  final Map<String, List<String>> hands;
  final Map<String, String?> committedCards;
  final Map<String, String> publiclyRevealedCards;
  final bool revealed;
}

final class PublicState {
  const PublicState({
    required this.sessionId,
    required this.roundNumber,
    required this.playerIds,
    required this.selectionMade,
    required this.revealed,
    this.revealedCards = const {},
    this.visibleActionPoints = const {},
  });
  final String sessionId;
  final int roundNumber;
  final List<String> playerIds;
  final Map<String, bool> selectionMade;
  final bool revealed;
  final Map<String, String> revealedCards;
  final Map<String, int> visibleActionPoints;
}

final class PrivatePlayerProjection {
  const PrivatePlayerProjection({
    required this.playerId,
    required this.actionPoints,
    required this.hand,
    this.committedCardId,
  });
  final String playerId;
  final int actionPoints;
  final List<String> hand;
  final String? committedCardId;
}

final class VisibilityProjection {
  const VisibilityProjection();

  PublicState publicState(
    CompleteGameState state, {
    bool revealActionPoints = false,
  }) => PublicState(
    sessionId: state.sessionId,
    roundNumber: state.roundNumber,
    playerIds: List.unmodifiable(state.hands.keys),
    selectionMade: Map.unmodifiable({
      for (final player in state.hands.keys)
        player: state.committedCards[player] != null,
    }),
    revealed: state.revealed,
    revealedCards: state.revealed
        ? Map.unmodifiable(state.publiclyRevealedCards)
        : const {},
    visibleActionPoints: revealActionPoints ? state.actionPoints : const {},
  );

  PrivatePlayerProjection privateState(
    CompleteGameState state,
    String playerId,
  ) {
    if (!state.hands.containsKey(playerId)) throw StateError('Unknown player');
    return PrivatePlayerProjection(
      playerId: playerId,
      actionPoints: state.actionPoints[playerId]!,
      hand: List.unmodifiable(state.hands[playerId]!),
      committedCardId: state.committedCards[playerId],
    );
  }
}
