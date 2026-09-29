import '../../domain/domain.dart';
import '../../engines/engines.dart';

enum LocalPostDuelPhase {
  duelRevealed,
  counterAuction,
  finalDefense,
  corruption,
  actionExecution,
  roundComplete,
}

/// Orchestrates the existing post-duel engines without owning card zones.
final class LocalPostDuelController {
  LocalPostDuelController({
    required this.duel,
    required this.duelEngine,
    this.auctionEngine = const AuctionEngine(),
    this.corruptionEngine = const CorruptionEngine(),
  }) : _actionPoints = Map.of(duel.actionPoints);

  final DuelResolution duel;
  final DuelEngine duelEngine;
  final AuctionEngine auctionEngine;
  final CorruptionEngine corruptionEngine;

  LocalPostDuelPhase phase = LocalPostDuelPhase.duelRevealed;
  AuctionState? auction;
  CorruptionOffer? corruptionOffer;
  CorruptionResolution? corruptionResolution;
  List<ActionPromise> executionActions = const [];
  final List<GameEvent> _extraEvents = [];
  late Map<String, int> _actionPoints;

  Map<String, int> get actionPoints => Map.unmodifiable(_actionPoints);
  bool get tied => duel.tied;
  String? get initialWinnerId => duel.winnerPlayerId;
  String? get initialLoserId {
    final winner = initialWinnerId;
    if (winner == null) return null;
    return duel.first.snapshot.playerId == winner
        ? duel.second.snapshot.playerId
        : duel.first.snapshot.playerId;
  }

  DuelCommitment? get initialWinnerCommitment =>
      _commitmentFor(initialWinnerId);
  bool get inversionAllowed => initialWinnerCommitment?.cardInvertible ?? false;
  int get minimumBid => phase == LocalPostDuelPhase.finalDefense
      ? (auction?.counterBid?.amount ?? 0) + 1
      : 1;
  String? get activeBidderId => switch (phase) {
    LocalPostDuelPhase.counterAuction => initialLoserId,
    LocalPostDuelPhase.finalDefense => initialWinnerId,
    _ => null,
  };

  String? get finalWinnerId =>
      tied ? null : auction?.winnerId ?? initialWinnerId;

  bool get inversionRetained =>
      auction?.counterBid?.target == AuctionTarget.INVERT_WINNING_ACTION &&
      auction?.defenseBid == null;

  DuelCommitment? get finalActionCommitment {
    if (tied) return null;
    final counter = auction?.counterBid;
    if (counter == null || auction?.defenseBid != null) {
      return initialWinnerCommitment;
    }
    if (counter.target == AuctionTarget.OWN_INITIAL_ACTION) {
      return _commitmentFor(initialLoserId);
    }
    return duelEngine.inverted(initialWinnerCommitment!);
  }

  String? get corruptionActorId {
    final winner = finalWinnerId;
    if (winner == null) return null;
    return duel.first.snapshot.playerId == winner
        ? duel.second.snapshot.playerId
        : duel.first.snapshot.playerId;
  }

  ActionPromise? get currentAction => executionActions
      .where((action) => action.status == ActionExecutionStatus.ACCEPTED)
      .firstOrNull;

  List<GameEvent> get events => List.unmodifiable([
    ...duel.events,
    ...?auction?.events,
    ..._extraEvents,
    ...?corruptionResolution?.events,
  ]);

  void continueAfterDuel() {
    _require(LocalPostDuelPhase.duelRevealed);
    if (tied) {
      phase = LocalPostDuelPhase.roundComplete;
      return;
    }
    auction = auctionEngine.start(
      initialWinnerId: initialWinnerId!,
      initialLoserId: initialLoserId!,
      actionPoints: _actionPoints,
    );
    phase = LocalPostDuelPhase.counterAuction;
  }

  void counter({required int amount, required AuctionTarget target}) {
    _require(LocalPostDuelPhase.counterAuction);
    auction = auctionEngine.counter(
      auction!,
      amount: amount,
      target: target,
      inversionAllowed: inversionAllowed,
    );
    _actionPoints = Map.of(auction!.actionPoints);
    phase = LocalPostDuelPhase.finalDefense;
  }

  void renounceCounter() {
    _require(LocalPostDuelPhase.counterAuction);
    _extraEvents.add(duelEngine.strategicRenunciation(initialLoserId!));
    phase = LocalPostDuelPhase.corruption;
  }

  void defend(int amount) {
    _require(LocalPostDuelPhase.finalDefense);
    auction = auctionEngine.defend(auction!, amount: amount);
    _actionPoints = Map.of(auction!.actionPoints);
    phase = LocalPostDuelPhase.corruption;
  }

  void renounceDefense() {
    _require(LocalPostDuelPhase.finalDefense);
    _extraEvents.add(duelEngine.strategicRenunciation(initialWinnerId!));
    phase = LocalPostDuelPhase.corruption;
  }

  void proposeCorruption({
    required CorruptionObjective objective,
    required List<String> cardIds,
  }) {
    _require(LocalPostDuelPhase.corruption);
    if (corruptionOffer != null) throw StateError('Offer already proposed');
    if (cardIds.isEmpty) throw ArgumentError('Offer requires an action');
    corruptionOffer = CorruptionOffer(
      offeredBy: corruptionActorId!,
      objective: objective,
      actions: [
        for (final cardId in cardIds)
          ActionPromise(cardId: cardId, source: CardZone.DISCARD),
      ],
    );
  }

  CorruptionResolution refuseCorruption(List<CardRuntimeState> cards) {
    _requireOffer();
    final result = corruptionEngine.resolve(
      offer: corruptionOffer!,
      accepted: false,
      cards: cards,
    );
    corruptionResolution = result;
    phase = LocalPostDuelPhase.roundComplete;
    return result;
  }

  void acceptCorruption() {
    _requireOffer();
    executionActions = [
      for (final action in corruptionOffer!.actions)
        action.copyWith(status: ActionExecutionStatus.ACCEPTED),
    ];
    phase = LocalPostDuelPhase.actionExecution;
  }

  void recordCurrentAction(ActionExecutionStatus status) {
    _require(LocalPostDuelPhase.actionExecution);
    if (status != ActionExecutionStatus.COMPLETED &&
        status != ActionExecutionStatus.SKIPPED) {
      throw ArgumentError('Action must be completed or skipped');
    }
    final current = currentAction;
    if (current == null) throw StateError('No pending action');
    executionActions = [
      for (final action in executionActions)
        identical(action, current) ? action.copyWith(status: status) : action,
    ];
  }

  CorruptionResolution stop(List<CardRuntimeState> cards) {
    _require(LocalPostDuelPhase.actionExecution);
    final current = currentAction;
    if (current == null) throw StateError('No pending action');
    executionActions = [
      for (final action in executionActions)
        identical(action, current)
            ? action.copyWith(status: ActionExecutionStatus.STOPPED)
            : action,
    ];
    return _finishCorruption(cards);
  }

  CorruptionResolution finishActions(List<CardRuntimeState> cards) {
    _require(LocalPostDuelPhase.actionExecution);
    if (currentAction != null) throw StateError('Pending action remains');
    return _finishCorruption(cards);
  }

  void skipCorruption() {
    _require(LocalPostDuelPhase.corruption);
    if (corruptionOffer != null) throw StateError('Offer already proposed');
    phase = LocalPostDuelPhase.roundComplete;
  }

  CorruptionResolution _finishCorruption(List<CardRuntimeState> cards) {
    final resolvedOffer = CorruptionOffer(
      offeredBy: corruptionOffer!.offeredBy,
      objective: corruptionOffer!.objective,
      actions: executionActions,
    );
    final result = corruptionEngine.resolve(
      offer: resolvedOffer,
      accepted: true,
      cards: cards,
    );
    corruptionResolution = result;
    phase = LocalPostDuelPhase.roundComplete;
    return result;
  }

  DuelCommitment? _commitmentFor(String? playerId) {
    if (duel.first.snapshot.playerId == playerId) return duel.first;
    if (duel.second.snapshot.playerId == playerId) return duel.second;
    return null;
  }

  void _require(LocalPostDuelPhase expected) {
    if (phase != expected) {
      throw StateError('Expected $expected, found $phase');
    }
  }

  void _requireOffer() {
    _require(LocalPostDuelPhase.corruption);
    if (corruptionOffer == null) throw StateError('No corruption offer');
  }
}
