import '../../domain/game/events.dart';

// ignore_for_file: constant_identifier_names
enum AuctionTarget { OWN_INITIAL_ACTION, INVERT_WINNING_ACTION }

final class AuctionBid {
  const AuctionBid({
    required this.playerId,
    required this.amount,
    required this.target,
  });
  final String playerId;
  final int amount;
  final AuctionTarget target;
}

final class AuctionState {
  AuctionState({
    required this.initialWinnerId,
    required this.initialLoserId,
    required Map<String, int> actionPoints,
    this.counterBid,
    this.defenseBid,
    List<GameEvent> events = const [],
  }) : actionPoints = Map.unmodifiable(actionPoints),
       events = List.unmodifiable(events);
  final String initialWinnerId;
  final String initialLoserId;
  final Map<String, int> actionPoints;
  final AuctionBid? counterBid;
  final AuctionBid? defenseBid;
  final List<GameEvent> events;
  String get winnerId => defenseBid != null
      ? initialWinnerId
      : counterBid != null
      ? initialLoserId
      : initialWinnerId;
}

final class AuctionEngine {
  const AuctionEngine();

  AuctionState start({
    required String initialWinnerId,
    required String initialLoserId,
    required Map<String, int> actionPoints,
  }) => AuctionState(
    initialWinnerId: initialWinnerId,
    initialLoserId: initialLoserId,
    actionPoints: actionPoints,
    events: [GameEvent(GameEventType.AUCTION_STARTED)],
  );

  AuctionState counter(
    AuctionState state, {
    required int amount,
    required AuctionTarget target,
    bool inversionAllowed = false,
  }) {
    if (state.counterBid != null) {
      throw StateError('Counter bid already used');
    }
    if (target == AuctionTarget.INVERT_WINNING_ACTION && !inversionAllowed) {
      throw StateError('Winning action is not invertible');
    }
    return _bid(
      state,
      AuctionBid(
        playerId: state.initialLoserId,
        amount: amount,
        target: target,
      ),
      0,
      counter: true,
    );
  }

  AuctionState defend(AuctionState state, {required int amount}) {
    final counter = state.counterBid;
    if (counter == null) {
      throw StateError('No counter bid to defend');
    }
    if (state.defenseBid != null) {
      throw StateError('Final defense already used');
    }
    return _bid(
      state,
      AuctionBid(
        playerId: state.initialWinnerId,
        amount: amount,
        target: counter.target,
      ),
      counter.amount,
      counter: false,
    );
  }

  AuctionState _bid(
    AuctionState state,
    AuctionBid bid,
    int previous, {
    required bool counter,
  }) {
    if (bid.amount <= previous) {
      throw ArgumentError('Bid must strictly exceed previous bid');
    }
    final current = state.actionPoints[bid.playerId] ?? 0;
    if (bid.amount > current) throw StateError('Bid would create PA debt');
    final points = Map<String, int>.from(state.actionPoints)
      ..[bid.playerId] = current - bid.amount;
    return AuctionState(
      initialWinnerId: state.initialWinnerId,
      initialLoserId: state.initialLoserId,
      actionPoints: points,
      counterBid: counter ? bid : state.counterBid,
      defenseBid: counter ? state.defenseBid : bid,
      events: [
        ...state.events,
        GameEvent(GameEventType.AUCTION_COMMITTED, {
          'player_id': bid.playerId,
          'amount': bid.amount,
        }),
        if (!counter)
          GameEvent(GameEventType.AUCTION_RESOLVED, {
            'winner_player_id': state.initialWinnerId,
          }),
      ],
    );
  }
}
