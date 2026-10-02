import '../../domain/domain.dart';
import '../protocol/network_dtos.dart';

/// Complete in-memory truth used only as projection input. It is never a
/// public wire DTO.
final class CompleteNetworkGameState {
  CompleteNetworkGameState({
    required this.sessionId,
    required this.roundId,
    required this.roundNumber,
    required this.phase,
    required this.proximity,
    required this.chiliActive,
    required this.chiliUnlocked,
    required List<String> playerIds,
    required Map<String, int> actionPoints,
    required Map<String, List<PrivateCardDto>> cardsByPlayer,
    required Map<String, PublicChoiceDto?> committedChoices,
    required Map<String, String?> commitNonces,
    required Map<String, Map<String, int>> personalValues,
    required Map<String, Map<String, PreferenceValue>> preferences,
    required Map<String, PlayerStyle> drawStyles,
    required Map<String, PrivateRecoveryDto> recoveryByPlayer,
    Map<String, PublicChoiceDto> revealedChoices = const {},
    this.revealAllowed = false,
    this.resolution,
    this.auction,
    this.execution,
  }) : playerIds = List.unmodifiable(playerIds),
       actionPoints = Map.unmodifiable(actionPoints),
       cardsByPlayer = _freezeLists(cardsByPlayer),
       committedChoices = Map.unmodifiable(committedChoices),
       commitNonces = Map.unmodifiable(commitNonces),
       personalValues = _freezeMaps(personalValues),
       preferences = _freezeMaps(preferences),
       drawStyles = Map.unmodifiable(drawStyles),
       recoveryByPlayer = Map.unmodifiable(recoveryByPlayer),
       revealedChoices = Map.unmodifiable(revealedChoices);

  final String sessionId;
  final String roundId;
  final int roundNumber;
  final PublicRoundPhase phase;
  final ProximityState proximity;
  final int chiliActive;
  final int chiliUnlocked;
  final List<String> playerIds;
  final Map<String, int> actionPoints;
  final Map<String, List<PrivateCardDto>> cardsByPlayer;
  final Map<String, PublicChoiceDto?> committedChoices;
  final Map<String, String?> commitNonces;
  final Map<String, Map<String, int>> personalValues;
  final Map<String, Map<String, PreferenceValue>> preferences;
  final Map<String, PlayerStyle> drawStyles;
  final Map<String, PrivateRecoveryDto> recoveryByPlayer;
  final Map<String, PublicChoiceDto> revealedChoices;
  final bool revealAllowed;
  final PublicResolutionDto? resolution;
  final PublicAuctionDto? auction;
  final PublicExecutionDto? execution;
}

final class NetworkVisibilityConfiguration {
  const NetworkVisibilityConfiguration({
    this.actionPoints = ActionPointVisibility.discreet,
  });

  final ActionPointVisibility actionPoints;
}

final class PlayerNetworkProjection {
  const PlayerNetworkProjection({
    required this.publicState,
    required this.privateState,
  });

  final PublicGameStateDto publicState;
  final PrivatePlayerStateDto privateState;
}

/// Pure privacy boundary. It reads complete state and produces one public DTO
/// plus the requesting player's owner-only DTO.
final class NetworkVisibilityProjection {
  const NetworkVisibilityProjection();

  PlayerNetworkProjection project({
    required CompleteNetworkGameState state,
    required String playerId,
    required NetworkVisibilityConfiguration configuration,
  }) {
    if (!state.playerIds.contains(playerId)) {
      throw StateError('Unknown projection player');
    }
    final showPoints =
        configuration.actionPoints == ActionPointVisibility.visible;
    final ownCards = state.cardsByPlayer[playerId] ?? const [];
    final ownPreferences = state.preferences[playerId] ?? const {};
    return PlayerNetworkProjection(
      publicState: PublicGameStateDto(
        sessionId: state.sessionId,
        roundId: state.roundId,
        roundNumber: state.roundNumber,
        phase: state.phase,
        proximity: state.proximity.name,
        chiliActive: state.chiliActive,
        chiliUnlocked: state.chiliUnlocked,
        playerIds: state.playerIds,
        selectionMade: {
          for (final id in state.playerIds)
            id: state.committedChoices[id] != null,
        },
        revealedChoices: state.revealAllowed ? state.revealedChoices : const {},
        visibleActionPoints: showPoints ? state.actionPoints : const {},
        resolution: state.revealAllowed ? state.resolution : null,
        auction: state.auction,
        execution: state.execution,
      ),
      privateState: PrivatePlayerStateDto(
        sessionId: state.sessionId,
        roundId: state.roundId,
        playerId: playerId,
        hand: [
          for (final card in ownCards)
            if (card.zone == 'HAND') card,
        ],
        lockedCardId:
            ownCards
                .where((card) => card.zone == 'HAND' && card.locked)
                .firstOrNull
                ?.occurrenceId ??
            ownCards
                .where((card) => card.zone == 'HAND' && card.locked)
                .firstOrNull
                ?.cardId,
        committedChoice: state.committedChoices[playerId],
        commitNonce: state.commitNonces[playerId],
        personalValues: state.personalValues[playerId] ?? const {},
        preferences: {
          for (final entry in ownPreferences.entries)
            entry.key: PrivatePreferenceDto(
              status: entry.value.status.name,
              general: entry.value.general,
              faire: entry.value.faire,
              recevoir: entry.value.recevoir,
            ),
        },
        drawStyle: state.drawStyles[playerId]!.name,
        recovery: state.recoveryByPlayer[playerId],
        actionPoints: showPoints ? null : state.actionPoints[playerId],
      ),
    );
  }
}

Map<String, List<T>> _freezeLists<T>(Map<String, List<T>> source) =>
    Map.unmodifiable({
      for (final entry in source.entries)
        entry.key: List<T>.unmodifiable(entry.value),
    });

Map<String, Map<String, T>> _freezeMaps<T>(
  Map<String, Map<String, T>> source,
) => Map.unmodifiable({
  for (final entry in source.entries)
    entry.key: Map<String, T>.unmodifiable(entry.value),
});
