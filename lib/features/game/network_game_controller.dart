import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../domain/domain.dart';
import '../../engines/engines.dart';
import '../../sync/sync.dart';
import '../lobby/lobby_models.dart';
import 'network_duel_controller.dart' show NetworkDuelCard;
import 'network_duel_secret_store.dart';
import 'network_profile_learning.dart';

enum NetworkGameViewState {
  loading,
  choosing,
  committing,
  waitingForPartner,
  revealing,
  negotiationProposal,
  negotiationResponse,
  negotiationAdaptation,
  negotiationValidation,
  counterDecision,
  finalDefenseDecision,
  tieDecision,
  finalResult,
  corruptionDecision,
  corruptionResponse,
  corruptionExecution,
  recovery,
  recoveryResponse,
  recoveryExecution,
  waitingNext,
  error,
}

final class NetworkGameController extends ChangeNotifier {
  NetworkGameController({
    required this.session,
    required this.playerId,
    required this.repository,
    required this.privateStore,
    required Catalog catalog,
    this.contract = const CommitRevealContract(),
    this.duelEngine = const DuelEngine(),
    this.auctionEngine = const AuctionEngine(),
    this.negotiationEngine = const NegotiationEngineV3(),
    this.lifecycleEngine = const LifecycleEngine(),
    this.drawEngine = const DrawEngine(),
    this.corruptionEngine = const CorruptionEngine(),
    this.recoveryEngine = const RecoveryEngine(),
    NetworkProfileLearningStore? learningStore,
    PostGameProfileChoiceStore? profileChoiceStore,
    DateTime Function()? clock,
    String Function()? nonceFactory,
  }) : _catalog = catalog,
       clock = clock ?? DateTime.now,
       nonceFactory = nonceFactory ?? _secureNonce {
    final ids = session.players.map((player) => player.userId).toList()..sort();
    if (!session.ready || !ids.contains(playerId)) {
      throw ArgumentError('A ready lobby membership is required');
    }
    playerIds = List.unmodifiable(ids);
    _definitions = {for (final card in catalog.cards) card.stableId: card};
    _engineCards = {
      for (final card in catalog.cards)
        card.stableId: const CatalogEngineAdapter.v3().card(card),
    };
    _hierarchy = ProfileHierarchy({
      for (final element in catalog.profileElements)
        element.stableId: element.parentId,
    });
    _context = EngineSessionContext(
      mode: SessionMode.face_to_face,
      proximity: ProximityState.TOGETHER,
      chiliActive: 2,
      chiliUnlocked: 2,
      physicalStateByPlayer: {for (final id in playerIds) id: 'available'},
      clothesByPlayer: {for (final id in playerIds) id: 5},
    );
    learning = NetworkProfileLearningCoordinator(
      playerId: playerId,
      store:
          learningStore ?? const SharedPreferencesNetworkProfileLearningStore(),
    );
    _profileChoiceStore =
        profileChoiceStore ??
        (learningStore is MemoryNetworkProfileLearningStore
            ? MemoryPostGameProfileChoiceStore()
            : const SharedPreferencesPostGameProfileChoiceStore());
  }

  final LobbySession session;
  final String playerId;
  final NetworkGameRepository repository;
  final NetworkDuelSecretStore privateStore;
  final CommitRevealContract contract;
  final DuelEngine duelEngine;
  final AuctionEngine auctionEngine;
  final NegotiationEngineV3 negotiationEngine;
  final LifecycleEngine lifecycleEngine;
  final DrawEngine drawEngine;
  final CorruptionEngine corruptionEngine;
  final RecoveryEngine recoveryEngine;
  final DateTime Function() clock;
  final String Function() nonceFactory;
  late final NetworkProfileLearningCoordinator learning;
  late final PostGameProfileChoiceStore _profileChoiceStore;
  final Catalog _catalog;
  late final List<String> playerIds;
  late final Map<String, CardDefinition> _definitions;
  late final Map<String, EngineCard> _engineCards;
  late final ProfileHierarchy _hierarchy;
  late EngineSessionContext _context;

  NetworkGameViewState viewState = NetworkGameViewState.loading;
  NetworkGameRoundStateDto? round;
  NetworkDuelCard? selectedCard;
  String? errorMessage;
  int resolutionCount = 0;

  List<CardRuntimeState> _runtime = const [];
  Map<String, CardHistoryState> _history = {};
  Set<int> _learningRecordedRounds = {};
  List<DeckCandidateV3> _faceToFaceDeck = [];
  List<DeckCandidateV3> _distanceDeck = [];
  int _deckCycle = 1;
  bool _infiniteMode = false;
  ChoiceRevealDto? _activeReveal;
  bool _nextRoundPrepared = false;
  StreamSubscription<NetworkGameRoundStateDto>? _subscription;
  bool _committing = false;
  bool _revealing = false;
  bool _resolving = false;
  bool _transitioning = false;
  bool _disposed = false;
  PostGameProfileChoice? postGameProfileChoice;

  String get opponentId => playerIds.firstWhere((id) => id != playerId);
  int get roundNumber => round?.roundNumber ?? 1;
  Map<String, int> get actionPoints => round?.actionPoints ?? const {};
  NetworkInitialResolutionDto? get initialResolution =>
      round?.initialResolution;
  NetworkFinalResolutionDto? get finalResolution => round?.finalResolution;
  NetworkNegotiationDto? get negotiation => round?.negotiation;
  NetworkCorruptionDto? get corruption => round?.corruption;
  NetworkRecoveryDto? get pendingRecovery => round?.recoveryByPlayer.values
      .where((item) => !round!.recoveryDonePlayerIds.contains(item.playerId))
      .firstOrNull;
  bool get isInitialLoser => initialResolution?.loserPlayerId == playerId;
  bool get isInitialWinner => initialResolution?.winnerPlayerId == playerId;
  bool get inversionAllowed => initialResolution?.inversionAllowed ?? false;
  bool get hasSubmittedTieDecision =>
      round?.tieDecisions.containsKey(playerId) ?? false;
  int get minimumDefense => (round?.counterBid?.amount ?? 0) + 1;
  bool get usesV3Negotiation => repository is NetworkNegotiationRepository;
  String? get lockedCardId => _runtime
      .where((card) => card.zone == CardZone.HAND && card.locked)
      .map((card) => card.cardId)
      .firstOrNull;
  List<CardRuntimeState> get runtime => List.unmodifiable(_runtime);
  Map<String, CardHistoryState> get history => Map.unmodifiable(_history);
  HybridDeckOrientation get orientation =>
      round?.hybridOrientation ?? HybridDeckOrientation.faceToFace;
  bool get deckExhausted => _faceToFaceDeck.isEmpty && _distanceDeck.isEmpty;
  int get faceToFaceDeckRemaining => _faceToFaceDeck.length;
  int get distanceDeckRemaining => _distanceDeck.length;

  List<NetworkDuelCard> get hand => [
    for (final item in _runtime.where((card) => card.zone == CardZone.HAND))
      ?_networkCard(item.cardId),
  ];

  List<NetworkDuelCard> get auctionCards => [
    for (final item in _runtime)
      if ((item.zone == CardZone.HAND || item.zone == CardZone.DISCARD) &&
          item.cardId != _activeReveal?.choice.cardId)
        ?_networkCard(item.cardId),
  ];

  String? get corruptionActorId {
    final retained = finalResolution?.retainedPlayerId;
    if (retained == null) return null;
    return playerIds.firstWhere((id) => id != retained);
  }

  bool get isCorruptionActor => corruptionActorId == playerId;
  List<NetworkDuelCard> get corruptionCards => [
    for (final item in _runtime)
      if (lifecycleEngine.canUseForCorruption(item)) ?_networkCard(item.cardId),
  ];

  bool get recoveryAvailable => recoveryEngine.available(
    currentPa: actionPoints[playerId] ?? const BalanceConfig().initialPa,
    gate: RecoveryGate(
      betweenRounds: round?.phase == NetworkGamePhase.recovery,
      usedSinceLastNormalDuel:
          round?.recoveryDonePlayerIds.contains(playerId) ?? false,
    ),
  );

  List<NetworkDuelCard> get recoveryCards => [
    for (final item in _runtime)
      if (item.zone != CardZone.EXHAUSTED) ?_networkRecoveryCard(item.cardId),
  ];

  Future<void> start() async {
    if (_subscription != null) return;
    try {
      postGameProfileChoice = await _profileChoiceStore.load(playerId);
      final current = await repository.openCurrentRound(
        command: _command('OPEN', roundId: null, roundNumber: 0),
      );
      await _restoreOrCreatePrivateState(current);
      await _switchRound(current);
    } catch (error) {
      _fail(error);
    }
  }

  Future<void> choosePostGameProfile(PostGameProfileChoice choice) async {
    postGameProfileChoice = choice;
    await _profileChoiceStore.save(playerId, choice);
    notifyListeners();
  }

  Future<void> switchOrientation(HybridDeckOrientation value) async {
    if (repository is! NetworkSessionFlowRepository || value == orientation) {
      return;
    }
    await _networkAction(
      (repository as NetworkSessionFlowRepository).setHybridOrientation(
        command: _command('SET_ORIENTATION'),
        orientation: value,
      ),
    );
  }

  Future<void> continueDeck(DeckExhaustionChoice choice) async {
    if (repository is! NetworkSessionFlowRepository) return;
    if (choice != DeckExhaustionChoice.newCustomizedGame &&
        choice != DeckExhaustionChoice.finish) {
      final cycle = DeckCycleState(
        style: PlayerStyle.EPICE,
        infinite: _infiniteMode,
      ).next(choice);
      _deckCycle++;
      _infiniteMode = cycle.infinite;
      _buildDeckCycle();
      _refill(roundNumber + 1);
      await _persist();
    }
    await _networkAction(
      (repository as NetworkSessionFlowRepository).continueDeckCycle(
        command: _command('CONTINUE_CYCLE'),
        choice: choice,
      ),
    );
  }

  void toggleLock(String cardId) {
    if (viewState != NetworkGameViewState.choosing ||
        round?.ownCommitRecorded == true) {
      return;
    }
    final target = _runtime
        .where((card) => card.cardId == cardId && card.zone == CardZone.HAND)
        .firstOrNull;
    if (target == null) return;
    if (target.locked) {
      _runtime = [
        for (final card in _runtime)
          card.cardId == cardId ? card.copyWith(locked: false) : card,
      ];
    } else {
      _runtime = lifecycleEngine.lock(_runtime, cardId);
    }
    unawaited(_persist());
    notifyListeners();
  }

  void selectCard(String cardId) {
    if (viewState != NetworkGameViewState.choosing) return;
    selectedCard = hand.where((card) => card.id == cardId).firstOrNull;
    notifyListeners();
  }

  Future<void> confirmSelection() async {
    final current = round;
    final card = selectedCard;
    if (current == null ||
        card == null ||
        _committing ||
        viewState != NetworkGameViewState.choosing) {
      return;
    }
    _committing = true;
    viewState = NetworkGameViewState.committing;
    notifyListeners();
    try {
      final choice = ChoicePayload(
        cardId: card.id,
        variantId: card.variant.id,
        parameters: {
          'role': card.role.name,
          'personal_value': card.personalValue,
          'committed_at': clock().toUtc().toIso8601String(),
        },
      );
      final reveal = ChoiceRevealDto(
        sessionRound: current.sessionRound,
        playerId: playerId,
        choice: choice,
        nonce: nonceFactory(),
      );
      _activeReveal = reveal;
      _runtime = lifecycleEngine.engage(_runtime, card.id);
      await _persist();
      await _apply(
        await repository.submitCommit(
          command: _command('COMMIT'),
          commitment: contract.commit(
            sessionRound: current.sessionRound,
            playerId: playerId,
            choice: choice,
            nonce: reveal.nonce,
          ),
        ),
      );
    } catch (error) {
      _fail(error);
    } finally {
      _committing = false;
    }
  }

  Future<void> proposeNegotiation({
    required bool inversion,
    required int directPa,
    Set<String> cardIds = const {},
  }) async {
    if (viewState != NetworkGameViewState.negotiationProposal ||
        !isInitialLoser) {
      return;
    }
    final offer = _negotiationOffer(
      inversion: inversion,
      directPa: directPa,
      cardIds: cardIds,
    );
    _validateNegotiationOffer(offer, NegotiationPhase.proposal);
    await _networkAction(
      (repository as NetworkNegotiationRepository).submitNegotiationProposal(
        command: _command('NEGOTIATION_PROPOSAL'),
        offer: offer,
      ),
    );
  }

  Future<void> respondNegotiation({
    required bool acceptInversion,
    required bool acceptAuction,
  }) async {
    if (viewState != NetworkGameViewState.negotiationResponse ||
        !isInitialWinner) {
      return;
    }
    final response = NetworkNegotiationResponseDto(
      acceptInversion: acceptInversion,
      acceptAuction: acceptAuction,
    );
    final state = _negotiationState(NegotiationPhase.response);
    negotiationEngine.respond(
      state,
      NegotiationResponse(
        acceptInversion: acceptInversion,
        acceptAuction: acceptAuction,
      ),
    );
    await _networkAction(
      (repository as NetworkNegotiationRepository).respondNegotiation(
        command: _command('NEGOTIATION_RESPONSE'),
        response: response,
      ),
    );
  }

  Future<void> adaptNegotiation({
    required bool inversion,
    required int directPa,
    Set<String> cardIds = const {},
  }) async {
    if (viewState != NetworkGameViewState.negotiationAdaptation ||
        !isInitialLoser) {
      return;
    }
    final offer = _negotiationOffer(
      inversion: inversion,
      directPa: directPa,
      cardIds: cardIds,
    );
    _validateNegotiationOffer(offer, NegotiationPhase.adaptation);
    await _networkAction(
      (repository as NetworkNegotiationRepository).adaptNegotiation(
        command: _command('NEGOTIATION_ADAPTATION'),
        offer: offer,
      ),
    );
  }

  Future<void> validateNegotiation({required bool accepted}) async {
    if (viewState != NetworkGameViewState.negotiationValidation ||
        !isInitialWinner) {
      return;
    }
    negotiationEngine.validate(
      _negotiationState(NegotiationPhase.validation),
      accepted: accepted,
    );
    await _networkAction(
      (repository as NetworkNegotiationRepository).validateNegotiation(
        command: _command('NEGOTIATION_VALIDATION'),
        accepted: accepted,
      ),
    );
  }

  Future<void> acceptInitialResult() async {
    if (!_canCounter) return;
    await _networkAction(
      repository.submitCounterDecision(
        command: _command('COUNTER_DECISION'),
        decision: CounterDecision.accept,
      ),
    );
  }

  Future<void> submitCounterBid(int amount, AuctionTarget target) async {
    final initial = initialResolution;
    if (!_canCounter || initial == null) return;
    final auction = auctionEngine.start(
      initialWinnerId: initial.winnerPlayerId!,
      initialLoserId: initial.loserPlayerId!,
      actionPoints: actionPoints,
    );
    auctionEngine.counter(
      auction,
      amount: amount,
      target: target,
      inversionAllowed: initial.inversionAllowed,
    );
    await _networkAction(
      repository.submitCounterDecision(
        command: _command('COUNTER_DECISION'),
        decision: CounterDecision.bid,
        amount: amount,
        target: target,
      ),
    );
  }

  Future<void> yieldFinalDefense() async {
    if (!_canDefend) return;
    await _networkAction(
      repository.submitFinalDefense(
        command: _command('FINAL_DEFENSE'),
        decision: FinalDefenseDecision.renounce,
      ),
    );
  }

  Future<void> submitFinalDefense(int amount) async {
    final initial = initialResolution;
    final counter = round?.counterBid;
    if (!_canDefend || initial == null || counter == null) return;
    final beforeCounter = Map<String, int>.from(actionPoints)
      ..[initial.loserPlayerId!] =
          (actionPoints[initial.loserPlayerId!] ?? 0) + counter.amount;
    var auction = auctionEngine.start(
      initialWinnerId: initial.winnerPlayerId!,
      initialLoserId: initial.loserPlayerId!,
      actionPoints: beforeCounter,
    );
    auction = auctionEngine.counter(
      auction,
      amount: counter.amount,
      target: counter.target,
      inversionAllowed: initial.inversionAllowed,
    );
    auctionEngine.defend(auction, amount: amount);
    await _networkAction(
      repository.submitFinalDefense(
        command: _command('FINAL_DEFENSE'),
        decision: FinalDefenseDecision.defend,
        amount: amount,
      ),
    );
  }

  Future<void> concedeTie() async {
    if (viewState != NetworkGameViewState.tieDecision ||
        hasSubmittedTieDecision) {
      return;
    }
    await _networkAction(
      repository.submitTieDecision(
        command: _command('TIE_DECISION'),
        decision: TieDecision.concede,
      ),
    );
  }

  Future<void> abandonTie() async {
    if (viewState != NetworkGameViewState.tieDecision ||
        hasSubmittedTieDecision) {
      return;
    }
    await _networkAction(
      repository.submitTieDecision(
        command: _command('TIE_DECISION'),
        decision: TieDecision.abandon,
      ),
    );
  }

  Future<void> proposeCorruption(
    String cardId,
    CorruptionObjective objective,
  ) async {
    if (viewState != NetworkGameViewState.corruptionDecision ||
        !isCorruptionActor ||
        !corruptionCards.any((card) => card.id == cardId)) {
      return;
    }
    await _networkAction(
      repository.submitCorruptionOffer(
        command: _command('CORRUPTION_OFFER'),
        objective: objective,
        cardIds: [cardId],
      ),
    );
  }

  Future<void> skipCorruption() async {
    if (viewState != NetworkGameViewState.corruptionDecision ||
        !isCorruptionActor) {
      return;
    }
    await _networkAction(
      repository.skipCorruption(command: _command('CORRUPTION_SKIP')),
    );
  }

  Future<void> respondToCorruption({required bool accepted}) async {
    if (viewState != NetworkGameViewState.corruptionResponse ||
        corruption?.offeredBy == playerId) {
      return;
    }
    await _networkAction(
      repository.respondCorruption(
        command: _command('CORRUPTION_RESPONSE'),
        accepted: accepted,
      ),
    );
  }

  Future<void> completeCorruption({required bool completed}) async {
    final offer = corruption;
    if (viewState != NetworkGameViewState.corruptionExecution ||
        offer == null ||
        offer.offeredBy != playerId) {
      return;
    }
    final actions = [
      for (final action in offer.actions)
        action.copyWith(
          status: completed
              ? ActionExecutionStatus.COMPLETED
              : ActionExecutionStatus.SKIPPED,
        ),
    ];
    final resolution = corruptionEngine.resolve(
      offer: CorruptionOffer(
        offeredBy: offer.offeredBy,
        objective: offer.objective,
        actions: actions,
      ),
      accepted: true,
      cards: _runtime,
    );
    await _networkAction(
      repository.resolveCorruption(
        command: _command('CORRUPTION_RESOLVE'),
        actions: actions,
      ),
    );
    _runtime = resolution.cards;
    await _persist();
    notifyListeners();
  }

  Future<void> recoverWith(String cardId) async {
    if (viewState != NetworkGameViewState.recovery || !recoveryAvailable) {
      return;
    }
    final card = recoveryCards.where((item) => item.id == cardId).firstOrNull;
    final runtime = _runtime.where((item) => item.cardId == cardId).firstOrNull;
    if (card == null || runtime == null) return;
    final source = switch (runtime.zone) {
      CardZone.HAND => RecoverySource.HAND,
      CardZone.DISCARD => RecoverySource.DISCARD,
      _ => RecoverySource.CATALOG,
    };
    final recovery = NetworkRecoveryDto(
      playerId: playerId,
      cardId: card.id,
      variantId: card.variant.id,
      source: source,
      completed: false,
      gain: 0,
      occurrenceId: '$playerId:${round!.roundId}:recovery:$cardId',
    );
    await _networkAction(
      repository.submitRecovery(
        command: _command('RECOVERY_${round!.recoveryHistory.length}_$cardId'),
        recovery: recovery,
      ),
    );
  }

  Future<void> respondToRecovery(RecoveryResponse response) async {
    final proposal = pendingRecovery;
    if (viewState != NetworkGameViewState.recoveryResponse ||
        proposal == null ||
        proposal.playerId == playerId) {
      return;
    }
    await _networkAction(
      repository.respondRecovery(
        command: _command(
          'RECOVERY_RESPONSE_${round!.recoveryHistory.length}_${proposal.occurrenceId}',
        ),
        response: response,
      ),
    );
  }

  Future<void> completeRecovery({required bool completed}) async {
    final proposal = pendingRecovery;
    if (viewState != NetworkGameViewState.recoveryExecution ||
        proposal == null ||
        proposal.playerId != playerId) {
      return;
    }
    final resolved = NetworkRecoveryDto(
      playerId: proposal.playerId,
      cardId: proposal.cardId,
      variantId: proposal.variantId,
      source: proposal.source,
      completed: completed,
      gain: completed ? _recoveryGain(proposal.cardId) : 0,
      response: proposal.response,
      occurrenceId: proposal.occurrenceId,
    );
    await _networkAction(
      repository.resolveRecovery(
        command: _command(
          'RECOVERY_RESOLVE_${round!.recoveryHistory.length}_${proposal.occurrenceId}',
        ),
        recovery: resolved,
      ),
    );
    _runtime = recoveryEngine.applyLifecycle(
      cards: _runtime,
      cardId: proposal.cardId,
      source: proposal.source,
      completed: completed,
    );
    await _persist();
    notifyListeners();
  }

  Future<void> skipRecovery() async {
    if (viewState != NetworkGameViewState.recovery ||
        round?.recoveryDonePlayerIds.contains(playerId) == true) {
      return;
    }
    await _networkAction(
      repository.skipRecovery(command: _command('RECOVERY_SKIP')),
    );
  }

  Future<void> readyForNextRound() async {
    final current = round;
    if (current == null ||
        (viewState != NetworkGameViewState.finalResult &&
            viewState != NetworkGameViewState.waitingNext)) {
      return;
    }
    try {
      await _recordLearningForRound();
      await _prepareNextRound();
      await _apply(
        await repository.readyNextRound(command: _command('READY_NEXT')),
      );
    } catch (error) {
      _fail(error);
    }
  }

  bool get _canCounter =>
      viewState == NetworkGameViewState.counterDecision && isInitialLoser;
  bool get _canDefend =>
      viewState == NetworkGameViewState.finalDefenseDecision && isInitialWinner;

  Future<void> _networkAction(
    Future<NetworkGameRoundStateDto> operation,
  ) async {
    if (_transitioning) return;
    _transitioning = true;
    try {
      await _apply(await operation);
    } catch (error) {
      _fail(error);
    } finally {
      _transitioning = false;
    }
  }

  Future<void> _switchRound(NetworkGameRoundStateDto value) async {
    final changed = round?.roundId != value.roundId;
    round = value;
    if (changed) {
      await _subscription?.cancel();
      _subscription = repository
          .watchRound(sessionId: session.id, roundId: value.roundId)
          .listen(
            (update) => unawaited(_apply(update)),
            onError: (Object error) => _fail(error),
          );
    }
    await _apply(value);
  }

  Future<void> _apply(NetworkGameRoundStateDto value) async {
    if (_disposed) return;
    if (value.sessionId != session.id) {
      _fail(const NetworkRoundException('ROUND_NOT_FOUND'));
      return;
    }
    if (round?.roundId != value.roundId) {
      await _activatePreparedRound(value);
      await _switchRound(value);
      return;
    }
    round = value;
    await _closeNormalRoundForRecovery(value);
    await _reconcilePublicLifecycle(value);
    if (_disposed) return;
    switch (value.phase) {
      case NetworkGamePhase.commit:
        if (value.ownCommitRecorded) {
          if (_activeReveal == null) {
            _fail(const NetworkRoundException('ROUND_LOCAL_SECRET_MISSING'));
          } else {
            viewState = NetworkGameViewState.waitingForPartner;
          }
        } else {
          viewState = NetworkGameViewState.choosing;
        }
        break;
      case NetworkGamePhase.reveal:
        viewState = NetworkGameViewState.revealing;
        notifyListeners();
        if (!value.ownRevealRecorded) await _revealOnce(value);
        return;
      case NetworkGamePhase.ready:
        viewState = NetworkGameViewState.revealing;
        notifyListeners();
        await _resolveOnce(value);
        return;
      case NetworkGamePhase.negotiationProposal:
        viewState = NetworkGameViewState.negotiationProposal;
        break;
      case NetworkGamePhase.negotiationResponse:
        viewState = NetworkGameViewState.negotiationResponse;
        break;
      case NetworkGamePhase.negotiationAdaptation:
        viewState = NetworkGameViewState.negotiationAdaptation;
        break;
      case NetworkGamePhase.negotiationValidation:
        viewState = NetworkGameViewState.negotiationValidation;
        break;
      case NetworkGamePhase.counterDecision:
        viewState = NetworkGameViewState.counterDecision;
        break;
      case NetworkGamePhase.finalDefenseDecision:
        viewState = NetworkGameViewState.finalDefenseDecision;
        break;
      case NetworkGamePhase.tieDecision:
        viewState = NetworkGameViewState.tieDecision;
        break;
      case NetworkGamePhase.finalResolved:
        viewState = NetworkGameViewState.finalResult;
        break;
      case NetworkGamePhase.corruptionDecision:
        viewState = NetworkGameViewState.corruptionDecision;
        break;
      case NetworkGamePhase.corruptionResponse:
        viewState = NetworkGameViewState.corruptionResponse;
        break;
      case NetworkGamePhase.corruptionExecution:
        viewState = NetworkGameViewState.corruptionExecution;
        break;
      case NetworkGamePhase.recovery:
        viewState = NetworkGameViewState.recovery;
        break;
      case NetworkGamePhase.recoveryResponse:
        viewState = NetworkGameViewState.recoveryResponse;
        break;
      case NetworkGamePhase.recoveryExecution:
        viewState = NetworkGameViewState.recoveryExecution;
        break;
      case NetworkGamePhase.waitingNext:
        viewState = value.readyNextPlayerIds.contains(playerId)
            ? NetworkGameViewState.waitingNext
            : NetworkGameViewState.finalResult;
        break;
      case NetworkGamePhase.closed:
        viewState = NetworkGameViewState.waitingNext;
        notifyListeners();
        await _switchRound(
          await repository.getCurrentRound(sessionId: session.id),
        );
        return;
    }
    notifyListeners();
  }

  Future<void> _closeNormalRoundForRecovery(
    NetworkGameRoundStateDto value,
  ) async {
    if (value.phase != NetworkGamePhase.recovery &&
        value.phase != NetworkGamePhase.recoveryResponse &&
        value.phase != NetworkGamePhase.recoveryExecution) {
      return;
    }
    final played = _runtime
        .where((card) => card.zone == CardZone.ENGAGED)
        .map((card) => card.cardId)
        .toList();
    if (played.isEmpty) return;
    _runtime = lifecycleEngine.closeRound(_runtime);
    for (final id in played) {
      _history[id] = CardHistoryState.playedOrDiscarded;
    }
    await _persist();
  }

  Future<void> _reconcilePublicLifecycle(NetworkGameRoundStateDto value) async {
    var changed = false;
    final publicResult = value.finalResolution;
    if (publicResult != null) {
      final auctionOccurrences = publicResult.compromise
          .where(
            (card) =>
                card.ownerPlayerId == playerId &&
                card.origin == NetworkCompromiseOrigin.AUCTION,
          )
          .map((card) => card.cardId)
          .toSet();
      if (auctionOccurrences.isNotEmpty) {
        final reconciled = [
          for (final card in _runtime)
            if (auctionOccurrences.contains(card.cardId) &&
                card.zone != CardZone.EXHAUSTED)
              card.copyWith(zone: CardZone.ENGAGED, locked: false)
            else
              card,
        ];
        changed = changed || !_sameRuntime(_runtime, reconciled);
        _runtime = reconciled;
      }
    }
    final publicCorruption = value.corruption;
    if (publicCorruption != null &&
        publicCorruption.offeredBy == playerId &&
        publicCorruption.accepted == true &&
        publicCorruption.actions.every(
          (action) =>
              action.status != ActionExecutionStatus.PROPOSED &&
              action.status != ActionExecutionStatus.ACCEPTED,
        )) {
      final reconciled = corruptionEngine
          .resolve(
            offer: CorruptionOffer(
              offeredBy: publicCorruption.offeredBy,
              objective: publicCorruption.objective,
              actions: publicCorruption.actions,
            ),
            accepted: true,
            cards: _runtime,
          )
          .cards;
      changed = !_sameRuntime(_runtime, reconciled);
      _runtime = reconciled;
    }
    final publicRecovery = value.recoveryHistory
        .where((item) => item.playerId == playerId && item.completed)
        .lastOrNull;
    if (publicRecovery != null) {
      final reconciled = recoveryEngine.applyLifecycle(
        cards: _runtime,
        cardId: publicRecovery.cardId,
        source: publicRecovery.source,
        completed: publicRecovery.completed,
      );
      changed = changed || !_sameRuntime(_runtime, reconciled);
      _runtime = reconciled;
    }
    if (changed) await _persist();
  }

  bool _sameRuntime(
    List<CardRuntimeState> first,
    List<CardRuntimeState> second,
  ) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      final a = first[index];
      final b = second[index];
      if (a.cardId != b.cardId || a.zone != b.zone || a.locked != b.locked) {
        return false;
      }
    }
    return true;
  }

  Future<void> _revealOnce(NetworkGameRoundStateDto value) async {
    final reveal = _activeReveal;
    if (_revealing || reveal == null) {
      if (reveal == null) {
        _fail(const NetworkRoundException('ROUND_LOCAL_SECRET_MISSING'));
      }
      return;
    }
    _revealing = true;
    try {
      await _apply(
        await repository.submitReveal(
          command: _command('REVEAL'),
          reveal: reveal,
        ),
      );
    } catch (error) {
      _fail(error);
    } finally {
      _revealing = false;
    }
  }

  Future<void> _resolveOnce(NetworkGameRoundStateDto value) async {
    if (_resolving) return;
    final own = value.ownReveal;
    final other = value.opponentReveal;
    if (own == null || other == null) {
      _fail(const NetworkRoundException('ROUND_READY_INCOMPLETE'));
      return;
    }
    _resolving = true;
    try {
      final reveals = {own.playerId: own, other.playerId: other};
      final commitments = {
        for (final id in playerIds) id: _commitment(reveals[id]!),
      };
      final resolved = duelEngine.resolve(
        first: commitments[playerIds[0]]!,
        second: commitments[playerIds[1]]!,
        actionPoints: value.actionPoints,
      );
      resolutionCount++;
      final winner = resolved.winnerPlayerId;
      final loser = winner == null
          ? null
          : playerIds.firstWhere((id) => id != winner);
      final initial = NetworkInitialResolutionDto(
        tied: resolved.tied,
        winnerPlayerId: winner,
        loserPlayerId: loser,
        gap: resolved.gap,
        gapCost: resolved.gapCost,
        highValue: [
          commitments[playerIds[0]]!.snapshot.personalValue,
          commitments[playerIds[1]]!.snapshot.personalValue,
        ].reduce(max),
        // ABA owns the only final debit. Publishing the DuelEngine result here
        // would charge the initial gap before B has negotiated.
        actionPoints: usesV3Negotiation
            ? value.actionPoints
            : resolved.actionPoints,
        inversionAllowed: winner == null
            ? false
            : commitments[winner]!.cardInvertible,
      );
      await _apply(
        await repository.submitInitialResolution(
          command: _command('INITIAL_RESOLVE'),
          resolution: initial,
        ),
      );
    } catch (error) {
      _fail(error);
    } finally {
      _resolving = false;
    }
  }

  DuelCommitment _commitment(ChoiceRevealDto reveal) {
    final card = _definitions[reveal.choice.cardId];
    final variant = card?.variants
        .where((item) => item.stableId == reveal.choice.variantId)
        .firstOrNull;
    if (card == null || variant == null) throw StateError('Unknown reveal');
    final role = ProfileRole.values.byName(
      reveal.choice.parameters['role']! as String,
    );
    final value = reveal.choice.parameters['personal_value']! as int;
    if (role != _roleFor(card, variant) || value < 1 || value > 20) {
      throw StateError('Invalid revealed snapshot');
    }
    return duelEngine.commit(
      playerId: reveal.playerId,
      cardId: card.stableId,
      variantId: variant.stableId,
      voluntaryRole: role,
      preference: _preference('network.snapshot', role, value),
      committedAt: DateTime.parse(
        reveal.choice.parameters['committed_at']! as String,
      ),
      cardInvertible:
          (variant.inversionOverride ?? card.inversionPolicy) !=
          InversionPolicy.NONE,
    );
  }

  Future<void> _restoreOrCreatePrivateState(
    NetworkGameRoundStateDto current,
  ) async {
    final saved = await privateStore.loadGame(
      sessionId: session.id,
      playerId: playerId,
    );
    if (saved != null &&
        (saved.roundNumber == current.roundNumber ||
            saved.roundNumber == current.roundNumber + 1)) {
      _runtime = List.of(saved.cards);
      _history = Map.of(saved.history);
      _activeReveal = saved.activeReveal;
      _nextRoundPrepared = saved.nextRoundPrepared;
      _learningRecordedRounds = Set.of(saved.learningRecordedRounds);
      _faceToFaceDeck = List.of(saved.faceToFaceDeck);
      _distanceDeck = List.of(saved.distanceDeck);
      _deckCycle = saved.deckCycle;
      _infiniteMode = saved.infiniteMode;
      if (_faceToFaceDeck.isEmpty && _distanceDeck.isEmpty) {
        _buildDeckCycle();
      }
      if (_nextRoundPrepared && saved.roundNumber == current.roundNumber) {
        _nextRoundPrepared = false;
        await _persist(roundNumber: current.roundNumber);
      }
      return;
    }
    _runtime = [
      for (final card in _engineCards.values)
        CardRuntimeState(cardId: card.id, zone: CardZone.POOL),
    ];
    _history = {};
    _learningRecordedRounds = {};
    _buildDeckCycle();
    _refill(current.roundNumber);
    await _persist(roundNumber: current.roundNumber);
  }

  Future<void> _prepareNextRound() async {
    if (_nextRoundPrepared) return;
    final played = _runtime
        .where((card) => card.zone == CardZone.ENGAGED)
        .map((card) => card.cardId)
        .toList();
    _runtime = lifecycleEngine.closeRound(_runtime);
    for (final id in played) {
      _history[id] = CardHistoryState.playedOrDiscarded;
    }
    _refill(roundNumber + 1);
    _activeReveal = null;
    selectedCard = null;
    _nextRoundPrepared = true;
    await _persist(roundNumber: roundNumber + 1);
  }

  Future<void> _recordLearningForRound() async {
    final result = finalResolution;
    if (result == null || _learningRecordedRounds.contains(roundNumber)) return;
    final visibleHand = <LearningCardDescriptor>[];
    for (final runtimeCard in _runtime.where(
      (card) => card.zone == CardZone.HAND || card.zone == CardZone.ENGAGED,
    )) {
      final definition = _definitions[runtimeCard.cardId];
      final network = _networkCard(runtimeCard.cardId);
      if (definition == null || network == null) continue;
      final variant = definition.variants.singleWhere(
        (item) => item.stableId == network.variant.id,
      );
      visibleHand.add(v3LearningDescriptor(definition, variant));
    }
    final reveal = _activeReveal;
    await learning.recordHand(
      cards: visibleHand,
      played: {
        if (reveal != null)
          '${reveal.choice.cardId}|${reveal.choice.variantId}',
        for (final card in result.compromise)
          if (card.ownerPlayerId == playerId &&
              card.origin == NetworkCompromiseOrigin.AUCTION)
            '${card.cardId}|${card.variantId}',
      },
      locked: {
        for (final card in _runtime.where((card) => card.locked))
          for (final descriptor in visibleHand)
            if (descriptor.cardId == card.cardId) descriptor.identity,
      },
    );
    if (!result.mutualAbandon) {
      final accepted = <ResolvedLearningCard>[];
      final compromise = result.compromise.isNotEmpty
          ? result.compromise
          : <NetworkCompromiseCardDto>[
              if (result.cardId != null &&
                  result.variantId != null &&
                  result.retainedPlayerId != null)
                NetworkCompromiseCardDto(
                  occurrenceId: 'legacy:${result.cardId}',
                  cardId: result.cardId!,
                  variantId: result.variantId!,
                  ownerPlayerId: result.retainedPlayerId!,
                  nativeDirection: NetworkCardDirection.GENERAL,
                  effectiveDirection: NetworkCardDirection.GENERAL,
                  origin: NetworkCompromiseOrigin.INITIAL_DUEL,
                  snapshotValue: 0,
                ),
            ];
      for (final item in compromise) {
        final definition = _definitions[item.cardId];
        final variant = definition?.variants
            .where((candidate) => candidate.stableId == item.variantId)
            .firstOrNull;
        if (definition == null || variant == null) continue;
        accepted.add(
          _resolvedLearningCard(
            v3LearningDescriptor(definition, variant),
            ownerId: item.ownerPlayerId,
            inverted:
                item.origin == NetworkCompromiseOrigin.INITIAL_DUEL &&
                item.nativeDirection != item.effectiveDirection,
          ),
        );
      }
      if (accepted.isNotEmpty) await learning.recordAccepted(accepted);
      final recoveryAccepted = <ResolvedLearningCard>[];
      for (final recovery
          in round?.recoveryHistory ?? const <NetworkRecoveryDto>[]) {
        if (!recovery.completed) continue;
        final definition = _definitions[recovery.cardId];
        final variant = definition?.variants
            .where((item) => item.stableId == recovery.variantId)
            .firstOrNull;
        if (definition == null || variant == null) continue;
        recoveryAccepted.add(
          _resolvedLearningCard(
            v3LearningDescriptor(definition, variant),
            ownerId: recovery.playerId,
            inverted: false,
          ),
        );
      }
      if (recoveryAccepted.isNotEmpty) {
        await learning.recordAccepted(recoveryAccepted);
      }
      await _recordNegotiationResistance(result);
    }
    _learningRecordedRounds.add(roundNumber);
    await _persist();
  }

  Future<void> _recordNegotiationResistance(
    NetworkFinalResolutionDto result,
  ) async {
    final negotiation = round?.negotiation;
    final proposal = negotiation?.proposal;
    final response = negotiation?.response;
    if (proposal == null || response == null) return;

    if (isInitialWinner && !response.acceptAuction) {
      for (final item in proposal.cards) {
        final definition = _definitions[item.cardId];
        final variant = definition?.variants
            .where((candidate) => candidate.stableId == item.variantId)
            .firstOrNull;
        if (definition == null || variant == null) continue;
        await learning.recordResistance(
          ResistanceLearningEvent(
            playerId: playerId,
            card: v3LearningDescriptor(definition, variant),
            resistedRole: _learningRoleFor(item, playerId),
            signal: ResistanceSignal.resultModification,
          ),
        );
      }
    }

    if (isInitialLoser && proposal.inversionRequested) {
      final initial = result.compromise
          .where((item) => item.origin == NetworkCompromiseOrigin.INITIAL_DUEL)
          .firstOrNull;
      if (initial == null) return;
      final definition = _definitions[initial.cardId];
      final variant = definition?.variants
          .where((candidate) => candidate.stableId == initial.variantId)
          .firstOrNull;
      if (definition == null || variant == null) return;
      await learning.recordResistance(
        ResistanceLearningEvent(
          playerId: playerId,
          card: v3LearningDescriptor(definition, variant),
          resistedRole: _learningRoleFor(initial, playerId),
          signal: ResistanceSignal.inversionSought,
        ),
      );
    }
  }

  static LearningRole _learningRoleFor(
    NetworkCompromiseCardDto card,
    String participantId,
  ) {
    final owner = card.ownerPlayerId == participantId;
    return switch (card.nativeDirection) {
      NetworkCardDirection.FAIRE =>
        owner ? LearningRole.faire : LearningRole.recevoir,
      NetworkCardDirection.RECEVOIR =>
        owner ? LearningRole.recevoir : LearningRole.faire,
      NetworkCardDirection.MUTUEL => LearningRole.mutuel,
      NetworkCardDirection.SOLO => LearningRole.solo,
      NetworkCardDirection.SIMULTANE => LearningRole.simultane,
      NetworkCardDirection.GENERAL => LearningRole.general,
    };
  }

  ResolvedLearningCard _resolvedLearningCard(
    LearningCardDescriptor card, {
    required String ownerId,
    required bool inverted,
  }) {
    if (card.tags.contains('v3.direction.mutuel')) {
      return ResolvedLearningCard(
        card: card,
        participation: ResolvedParticipation.mutual,
        participantPlayerIds: playerIds,
      );
    }
    if (card.tags.contains('v3.direction.simultane')) {
      return ResolvedLearningCard(
        card: card,
        participation: ResolvedParticipation.simultaneous,
        participantPlayerIds: playerIds,
      );
    }
    if (card.tags.contains('v3.direction.solo')) {
      return ResolvedLearningCard(
        card: card,
        participation: ResolvedParticipation.solo,
        soloPlayerId: ownerId,
      );
    }
    final other = playerIds.firstWhere((id) => id != ownerId);
    final ownerReceives = card.tags.contains('v3.direction.recevoir');
    final ownerPerforms = inverted ? ownerReceives : !ownerReceives;
    return ResolvedLearningCard(
      card: card,
      participation: ResolvedParticipation.directed,
      performerPlayerId: ownerPerforms ? ownerId : other,
      receiverPlayerId: ownerPerforms ? other : ownerId,
    );
  }

  Future<void> _activatePreparedRound(NetworkGameRoundStateDto next) async {
    if (_nextRoundPrepared && next.roundNumber == roundNumber + 1) {
      _nextRoundPrepared = false;
      _activeReveal = null;
      selectedCard = null;
      await _persist(roundNumber: next.roundNumber);
    }
  }

  void _refill(int targetRound) {
    var needed =
        const BalanceConfig().handSize -
        _runtime.where((card) => card.zone == CardZone.HAND).length;
    if (needed <= 0) return;
    if (deckExhausted && _infiniteMode) _buildDeckCycle();
    final deck = SessionDeckRuntime(
      faceToFace: _faceToFaceDeck,
      distance: _distanceDeck,
      random: Random(_stableHash('$playerId/$targetRound/$_deckCycle')),
    );
    while (needed > 0) {
      final drawn = deck.draw(orientation);
      if (drawn == null) break;
      final alreadyActive = _runtime.any(
        (card) =>
            card.cardId == drawn.cardId &&
            (card.zone == CardZone.HAND || card.zone == CardZone.ENGAGED),
      );
      if (alreadyActive) continue;
      _runtime = [
        for (final card in _runtime)
          card.cardId == drawn.cardId
              ? card.copyWith(zone: CardZone.HAND, locked: false)
              : card,
      ];
      _history[drawn.cardId] = CardHistoryState.seenUnplayed;
      needed--;
    }
    _faceToFaceDeck = List.of(deck.faceToFace);
    _distanceDeck = List.of(deck.distance);
  }

  void _buildDeckCycle() {
    final source = <DeckCandidateV3>[];
    for (final definition in _definitions.values) {
      final card = _networkCard(definition.stableId);
      if (card == null) continue;
      source.add(
        DeckCandidateV3(
          cardId: card.id,
          variantId: card.variant.id,
          spiceLevel: card.chiliLevel,
          distanceExcluded: card.variant.tags.contains(
            'v3.technique.distance_exclue',
          ),
        ),
      );
    }
    final decks = HybridSessionDecks(source: source);
    _faceToFaceDeck = List.of(decks.faceToFace);
    _distanceDeck = List.of(decks.distance);
  }

  NetworkDuelCard? _networkCard(String cardId) {
    final definition = _definitions[cardId];
    final engine = _engineCards[cardId];
    if (definition == null || engine == null) return null;
    final eligible = const EligibilityEngine()
        .evaluate(
          card: engine,
          context: _context,
          actor: _profile(playerId),
          partner: _profile(opponentId),
          hierarchy: _hierarchy,
          requirePersonalValue: true,
        )
        .eligibleVariants
        .firstOrNull;
    if (eligible == null) return null;
    final variant = definition.variants.firstWhere(
      (item) => item.stableId == eligible.id,
    );
    final role = _roleFor(definition, variant);
    final elementId =
        eligible.tags
            .where((tag) => tag.startsWith('v3.preference.'))
            .firstOrNull ??
        _legacyElementId(definition, variant, role);
    return NetworkDuelCard(
      definition: definition,
      engine: engine,
      variant: eligible,
      role: role,
      preference: _preference(
        elementId,
        role,
        _fixtureValue(playerId, elementId, role),
      ),
    );
  }

  NetworkDuelCard? _networkRecoveryCard(String cardId) {
    final definition = _definitions[cardId];
    final engine = _engineCards[cardId];
    if (definition == null || engine == null) return null;
    final recoveryContext = _context.copyWith(
      exhaustedCardIds: {
        ..._context.exhaustedCardIds,
        for (final card in _runtime)
          if (card.zone == CardZone.EXHAUSTED) card.cardId,
      },
    );
    final eligible = recoveryEngine
        .actionEligibility(
          card: engine,
          context: recoveryContext,
          actor: _profile(playerId),
          partner: _profile(opponentId),
          hierarchy: _hierarchy,
        )
        .eligibleVariants
        .firstOrNull;
    if (eligible == null) return null;
    final variant = definition.variants.firstWhere(
      (item) => item.stableId == eligible.id,
    );
    final role = _roleFor(definition, variant);
    final elementId =
        eligible.tags
            .where((tag) => tag.startsWith('v3.preference.'))
            .firstOrNull ??
        _legacyElementId(definition, variant, role);
    return NetworkDuelCard(
      definition: definition,
      engine: engine,
      variant: eligible,
      role: role,
      preference: _preference(
        elementId,
        role,
        _fixtureValue(playerId, elementId, role),
      ),
    );
  }

  int _recoveryGain(String cardId) {
    final card = _networkRecoveryCard(cardId);
    if (card == null) return 0;
    return recoveryEngine
        .resolve(
          currentPa: actionPoints[playerId]!,
          response: RecoveryResponse.ACCEPT,
          performedRoles: [
            (
              PreferenceValue(
                status: PreferenceStatus.ACCEPTED,
                general: card.role == ProfileRole.GENERAL
                    ? card.personalValue
                    : null,
                faire: card.role == ProfileRole.FAIRE
                    ? card.personalValue
                    : null,
                recevoir: card.role == ProfileRole.RECEVOIR
                    ? card.personalValue
                    : null,
              ),
              card.role,
              true,
            ),
          ],
        )
        .gain;
  }

  NetworkNegotiationOfferDto _negotiationOffer({
    required bool inversion,
    required int directPa,
    required Set<String> cardIds,
  }) {
    final cards = <NetworkCompromiseCardDto>[];
    for (final id in cardIds) {
      final card = auctionCards.where((item) => item.id == id).firstOrNull;
      if (card == null) throw ArgumentError('Carte d’enchère indisponible');
      final direction = _networkDirection(card);
      cards.add(
        NetworkCompromiseCardDto(
          occurrenceId: '$playerId:${round!.roundId}:auction:$id',
          cardId: id,
          variantId: card.variant.id,
          ownerPlayerId: playerId,
          nativeDirection: direction,
          effectiveDirection: direction,
          origin: NetworkCompromiseOrigin.AUCTION,
          snapshotValue: card.personalValue,
          logicalOrder: cards.length + 1,
        ),
      );
    }
    return NetworkNegotiationOfferDto(
      inversionRequested: inversion,
      directPa: directPa,
      cards: cards,
    );
  }

  void _validateNegotiationOffer(
    NetworkNegotiationOfferDto offer,
    NegotiationPhase phase,
  ) {
    final engineOffer = NegotiationOffer(
      inversionRequested: offer.inversionRequested,
      personalPa: offer.directPa,
      cardIds: [for (final card in offer.cards) card.occurrenceId],
      cardValues: {
        for (final card in offer.cards) card.occurrenceId: card.snapshotValue,
      },
    );
    final state = _negotiationState(phase);
    if (phase == NegotiationPhase.proposal) {
      negotiationEngine.propose(state, engineOffer);
    } else {
      negotiationEngine.adapt(state, engineOffer);
    }
  }

  NegotiationState _negotiationState(NegotiationPhase phase) {
    final initial = initialResolution!;
    final dto = negotiation;
    NegotiationOffer? engineOffer(NetworkNegotiationOfferDto? value) =>
        value == null
        ? null
        : NegotiationOffer(
            inversionRequested: value.inversionRequested,
            personalPa: value.directPa,
            cardIds: [for (final card in value.cards) card.occurrenceId],
            cardValues: {
              for (final card in value.cards)
                card.occurrenceId: card.snapshotValue,
            },
          );
    final response = dto?.response;
    return NegotiationState(
      initialWinnerId: initial.winnerPlayerId!,
      initialLoserId: initial.loserPlayerId!,
      initialHighValue: initial.highValue,
      initialGapCost: initial.gapCost,
      actionPoints: actionPoints,
      phase: phase,
      proposal: engineOffer(dto?.proposal),
      response: response == null
          ? null
          : NegotiationResponse(
              acceptInversion: response.acceptInversion,
              acceptAuction: response.acceptAuction,
            ),
      finalOffer: engineOffer(dto?.finalOffer),
    );
  }

  static NetworkCardDirection _networkDirection(NetworkDuelCard card) {
    final tags = card.variant.tags;
    if (tags.contains('v3.direction.mutuel')) {
      return NetworkCardDirection.MUTUEL;
    }
    if (tags.contains('v3.direction.simultane')) {
      return NetworkCardDirection.SIMULTANE;
    }
    if (tags.contains('v3.direction.solo')) return NetworkCardDirection.SOLO;
    return switch (card.role) {
      ProfileRole.FAIRE => NetworkCardDirection.FAIRE,
      ProfileRole.RECEVOIR => NetworkCardDirection.RECEVOIR,
      _ => NetworkCardDirection.GENERAL,
    };
  }

  PlayerGameProfile _profile(String id) => PlayerGameProfile(
    playerId: id,
    preferences: {
      for (final element in _catalog.profileElements)
        element.stableId: PreferenceValue(
          status: PreferenceStatus.ACCEPTED,
          general: _fixtureValue(id, element.stableId, ProfileRole.GENERAL),
          faire: _fixtureValue(id, element.stableId, ProfileRole.FAIRE),
          recevoir: _fixtureValue(id, element.stableId, ProfileRole.RECEVOIR),
        ),
      for (final tag
          in _engineCards.values
              .expand((card) => card.variants)
              .expand((variant) => variant.tags)
              .where((tag) => tag.startsWith('v3.preference.'))
              .toSet())
        tag: PreferenceValue(
          status: PreferenceStatus.ACCEPTED,
          general: _fixtureValue(id, tag, ProfileRole.GENERAL),
          faire: _fixtureValue(id, tag, ProfileRole.FAIRE),
          recevoir: _fixtureValue(id, tag, ProfileRole.RECEVOIR),
        ),
    },
  );

  String _legacyElementId(
    CardDefinition definition,
    CardVariantDefinition variant,
    ProfileRole role,
  ) {
    final requirements = [
      ...definition.profileRequirements,
      ...variant.profileRequirements,
    ];
    return requirements
            .where((item) => item.role == role)
            .map((item) => item.elementId)
            .firstOrNull ??
        requirements.map((item) => item.elementId).firstOrNull ??
        'network.prototype';
  }

  Future<void> _persist({int? roundNumber}) => privateStore.saveGame(
    sessionId: session.id,
    playerId: playerId,
    state: NetworkPrivateGameState(
      roundNumber: roundNumber ?? this.roundNumber,
      cards: _runtime,
      history: _history,
      activeReveal: _activeReveal,
      nextRoundPrepared: _nextRoundPrepared,
      learningRecordedRounds: _learningRecordedRounds,
      faceToFaceDeck: _faceToFaceDeck,
      distanceDeck: _distanceDeck,
      deckCycle: _deckCycle,
      infiniteMode: _infiniteMode,
    ),
  );

  NetworkCommandDto _command(String type, {String? roundId, int? roundNumber}) {
    final number = roundNumber ?? this.roundNumber;
    final id = roundId ?? round?.roundId;
    return NetworkCommandDto(
      commandId:
          'game:${session.id}:round-$number:$playerId:${type.toLowerCase()}',
      sessionId: session.id,
      playerId: playerId,
      type: type,
      payload: {'round_id': ?id},
    );
  }

  void _fail(Object error) {
    if (_disposed) return;
    viewState = NetworkGameViewState.error;
    errorMessage = error is NetworkRoundException
        ? error.code
        : 'Le jeu réseau est momentanément indisponible.';
    notifyListeners();
  }

  static ProfileRole _roleFor(
    CardDefinition card,
    CardVariantDefinition variant,
  ) {
    final v3Tags = variant.v3?.tags ?? card.v3?.tags ?? const <String>[];
    if (v3Tags.contains('v3.direction.faire')) return ProfileRole.FAIRE;
    if (v3Tags.contains('v3.direction.recevoir')) return ProfileRole.RECEVOIR;
    final requirements = [
      ...card.profileRequirements,
      ...variant.profileRequirements,
    ];
    final directed = requirements
        .map((item) => item.role)
        .where((role) => role != ProfileRole.GENERAL)
        .firstOrNull;
    if (directed != null) return directed;
    return switch (card.directionality) {
      CardDirectionality.FAIRE => ProfileRole.FAIRE,
      CardDirectionality.RECEVOIR => ProfileRole.RECEVOIR,
      _ => ProfileRole.GENERAL,
    };
  }

  static UserPreference _preference(
    String elementId,
    ProfileRole role,
    int value,
  ) => UserPreference.fromJson({
    'profile_element_id': elementId,
    'status': PreferenceStatus.ACCEPTED.name,
    'general_value': role == ProfileRole.GENERAL ? value : null,
    'faire_value': role == ProfileRole.FAIRE ? value : null,
    'recevoir_value': role == ProfileRole.RECEVOIR ? value : null,
    'updated_at': DateTime.utc(2026, 1, 1).toIso8601String(),
    'source': PreferenceSource.ONBOARDING.name,
  });

  int _fixtureValue(String id, String element, ProfileRole role) =>
      8 + (_stableHash('$id/$element/${role.name}') % 11);

  static int _stableHash(String value) {
    var hash = 17;
    for (final unit in value.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return hash;
  }

  static String _secureNonce() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    super.dispose();
  }
}
