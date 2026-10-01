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

/// Pure V3 bounded negotiation. The initial loser proposes, the initial winner
/// answers each component, the loser adapts once, and the winner validates.
enum NegotiationPhase { proposal, response, adaptation, validation, resolved }

final class NegotiationOffer {
  NegotiationOffer({
    this.inversionRequested = false,
    this.personalPa = 0,
    List<String> cardIds = const [],
    Map<String, int> cardValues = const {},
  }) : cardIds = List.unmodifiable(cardIds),
       cardValues = Map.unmodifiable(cardValues);

  final bool inversionRequested;
  final int personalPa;
  final List<String> cardIds;
  final Map<String, int> cardValues;

  int get cardPa => cardIds.fold(0, (sum, id) => sum + (cardValues[id] ?? 0));
  int get totalPa => personalPa + cardPa;
}

final class NegotiationResponse {
  const NegotiationResponse({
    required this.acceptInversion,
    required this.acceptAuction,
  });
  final bool acceptInversion;
  final bool acceptAuction;
}

final class NegotiationState {
  NegotiationState({
    required this.initialWinnerId,
    required this.initialLoserId,
    required this.initialHighValue,
    required this.initialGapCost,
    required Map<String, int> actionPoints,
    this.phase = NegotiationPhase.proposal,
    this.proposal,
    this.response,
    this.finalOffer,
    this.finalWinnerId,
    this.inversionApplied = false,
  }) : actionPoints = Map.unmodifiable(actionPoints);

  final String initialWinnerId;
  final String initialLoserId;
  final int initialHighValue;
  final int initialGapCost;
  final Map<String, int> actionPoints;
  final NegotiationPhase phase;
  final NegotiationOffer? proposal;
  final NegotiationResponse? response;
  final NegotiationOffer? finalOffer;
  final String? finalWinnerId;
  final bool inversionApplied;
}

final class NegotiationEngineV3 {
  const NegotiationEngineV3({this.recoveryThresholdPa = 10});
  final int recoveryThresholdPa;

  NegotiationState propose(NegotiationState state, NegotiationOffer offer) {
    if (state.phase != NegotiationPhase.proposal) {
      throw StateError('Proposal is no longer available');
    }
    _validateOffer(state, offer);
    return _copy(state, phase: NegotiationPhase.response, proposal: offer);
  }

  NegotiationState respond(
    NegotiationState state,
    NegotiationResponse response,
  ) {
    if (state.phase != NegotiationPhase.response || state.proposal == null) {
      throw StateError('No proposal to answer');
    }
    if (response.acceptInversion && !state.proposal!.inversionRequested) {
      throw ArgumentError('Cannot accept an inversion that was not proposed');
    }
    if (response.acceptAuction && state.proposal!.totalPa == 0) {
      throw ArgumentError('Cannot accept an empty auction');
    }
    return _copy(state, phase: NegotiationPhase.adaptation, response: response);
  }

  NegotiationState adapt(NegotiationState state, NegotiationOffer offer) {
    if (state.phase != NegotiationPhase.adaptation || state.response == null) {
      throw StateError('Adaptation is not available');
    }
    _validateOffer(state, offer);
    if (offer.inversionRequested && !state.response!.acceptInversion) {
      throw StateError('A refused inversion cannot be retained');
    }
    if (offer.totalPa > 0 && !state.response!.acceptAuction) {
      throw StateError('A refused auction cannot be retained');
    }
    return _copy(state, phase: NegotiationPhase.validation, finalOffer: offer);
  }

  NegotiationState validate(NegotiationState state, {required bool accepted}) {
    if (state.phase != NegotiationPhase.validation ||
        state.finalOffer == null) {
      throw StateError('There is no final compromise to validate');
    }
    if (!accepted) {
      return _resolve(state, state.initialWinnerId, false, spendLoser: 0);
    }
    final offer = state.finalOffer!;
    final loserWins = offer.inversionRequested || offer.totalPa > 0;
    return _resolve(
      state,
      loserWins ? state.initialLoserId : state.initialWinnerId,
      offer.inversionRequested,
      spendLoser:
          offer.personalPa +
          (offer.inversionRequested ? state.initialHighValue : 0),
    );
  }

  void _validateOffer(NegotiationState state, NegotiationOffer offer) {
    if (offer.personalPa < 0 ||
        offer.cardIds.toSet().length != offer.cardIds.length) {
      throw ArgumentError('Invalid auction resources');
    }
    final available = state.actionPoints[state.initialLoserId] ?? 0;
    if (offer.personalPa > available) {
      throw StateError('Bid would create PA debt');
    }
    if (available < recoveryThresholdPa && offer.personalPa > 0) {
      throw StateError(
        'Personal PA bidding is unavailable below recovery threshold',
      );
    }
  }

  NegotiationState _resolve(
    NegotiationState state,
    String winner,
    bool inverted, {
    required int spendLoser,
  }) {
    final points = Map<String, int>.from(state.actionPoints);
    if (winner == state.initialWinnerId) {
      final current = points[state.initialWinnerId] ?? 0;
      points[state.initialWinnerId] = (current - state.initialGapCost).clamp(
        0,
        current,
      );
    }
    if (spendLoser > 0) {
      final current = points[state.initialLoserId] ?? 0;
      if (spendLoser > current) throw StateError('Committed costs exceed PA');
      points[state.initialLoserId] = current - spendLoser;
    }
    return _copy(
      state,
      phase: NegotiationPhase.resolved,
      actionPoints: points,
      finalWinnerId: winner,
      inversionApplied: inverted,
    );
  }

  NegotiationState _copy(
    NegotiationState state, {
    NegotiationPhase? phase,
    NegotiationOffer? proposal,
    NegotiationResponse? response,
    NegotiationOffer? finalOffer,
    Map<String, int>? actionPoints,
    String? finalWinnerId,
    bool? inversionApplied,
  }) => NegotiationState(
    initialWinnerId: state.initialWinnerId,
    initialLoserId: state.initialLoserId,
    initialHighValue: state.initialHighValue,
    initialGapCost: state.initialGapCost,
    actionPoints: actionPoints ?? state.actionPoints,
    phase: phase ?? state.phase,
    proposal: proposal ?? state.proposal,
    response: response ?? state.response,
    finalOffer: finalOffer ?? state.finalOffer,
    finalWinnerId: finalWinnerId ?? state.finalWinnerId,
    inversionApplied: inversionApplied ?? state.inversionApplied,
  );
}
