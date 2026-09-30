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

enum NetworkGameViewState {
  loading,
  choosing,
  committing,
  waitingForPartner,
  revealing,
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
    this.lifecycleEngine = const LifecycleEngine(),
    this.drawEngine = const DrawEngine(),
    this.corruptionEngine = const CorruptionEngine(),
    this.recoveryEngine = const RecoveryEngine(),
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
        card.stableId: const CatalogEngineAdapter().card(card),
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
  }

  final LobbySession session;
  final String playerId;
  final NetworkGameRepository repository;
  final NetworkDuelSecretStore privateStore;
  final CommitRevealContract contract;
  final DuelEngine duelEngine;
  final AuctionEngine auctionEngine;
  final LifecycleEngine lifecycleEngine;
  final DrawEngine drawEngine;
  final CorruptionEngine corruptionEngine;
  final RecoveryEngine recoveryEngine;
  final DateTime Function() clock;
  final String Function() nonceFactory;
  final Catalog _catalog;
  late final List<String> playerIds;
  late final Map<String, CardDefinition> _definitions;
  late final Map<String, EngineCard> _engineCards;
  late final ProfileHierarchy _hierarchy;
  late final EngineSessionContext _context;

  NetworkGameViewState viewState = NetworkGameViewState.loading;
  NetworkGameRoundStateDto? round;
  NetworkDuelCard? selectedCard;
  String? errorMessage;
  int resolutionCount = 0;

  List<CardRuntimeState> _runtime = const [];
  Map<String, CardHistoryState> _history = {};
  ChoiceRevealDto? _activeReveal;
  bool _nextRoundPrepared = false;
  StreamSubscription<NetworkGameRoundStateDto>? _subscription;
  bool _committing = false;
  bool _revealing = false;
  bool _resolving = false;
  bool _transitioning = false;
  bool _disposed = false;

  String get opponentId => playerIds.firstWhere((id) => id != playerId);
  int get roundNumber => round?.roundNumber ?? 1;
  Map<String, int> get actionPoints => round?.actionPoints ?? const {};
  NetworkInitialResolutionDto? get initialResolution =>
      round?.initialResolution;
  NetworkFinalResolutionDto? get finalResolution => round?.finalResolution;
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
  String? get lockedCardId => _runtime
      .where((card) => card.zone == CardZone.HAND && card.locked)
      .map((card) => card.cardId)
      .firstOrNull;
  List<CardRuntimeState> get runtime => List.unmodifiable(_runtime);
  Map<String, CardHistoryState> get history => Map.unmodifiable(_history);

  List<NetworkDuelCard> get hand => [
    for (final item in _runtime.where((card) => card.zone == CardZone.HAND))
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
      final current = await repository.openCurrentRound(
        command: _command('OPEN', roundId: null, roundNumber: 0),
      );
      await _restoreOrCreatePrivateState(current);
      await _switchRound(current);
    } catch (error) {
      _fail(error);
    }
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

  Future<void> recoverWith(String cardId, {bool completed = true}) async {
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
    final result = recoveryEngine.resolve(
      currentPa: actionPoints[playerId]!,
      response: RecoveryResponse.ACCEPT,
      performedRoles: [
        (
          PreferenceValue(
            status: PreferenceStatus.ACCEPTED,
            general: card.role == ProfileRole.GENERAL
                ? card.personalValue
                : null,
            faire: card.role == ProfileRole.FAIRE ? card.personalValue : null,
            recevoir: card.role == ProfileRole.RECEVOIR
                ? card.personalValue
                : null,
          ),
          card.role,
          completed,
        ),
      ],
    );
    final recovery = NetworkRecoveryDto(
      playerId: playerId,
      cardId: card.id,
      variantId: card.variant.id,
      source: source,
      completed: completed,
      gain: result.gain,
    );
    await _networkAction(
      repository.submitRecovery(
        command: _command('RECOVERY'),
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
        command: _command('RECOVERY_RESPONSE'),
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
      gain: completed ? proposal.gain : 0,
      response: proposal.response,
    );
    await _networkAction(
      repository.resolveRecovery(
        command: _command('RECOVERY_RESOLVE'),
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
        viewState = NetworkGameViewState.waitingNext;
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

  Future<void> _reconcilePublicLifecycle(NetworkGameRoundStateDto value) async {
    var changed = false;
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
    final publicRecovery = value.recoveryByPlayer[playerId];
    if (publicRecovery != null &&
        value.recoveryDonePlayerIds.contains(playerId)) {
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
        actionPoints: resolved.actionPoints,
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

  Future<void> _activatePreparedRound(NetworkGameRoundStateDto next) async {
    if (_nextRoundPrepared && next.roundNumber == roundNumber + 1) {
      _nextRoundPrepared = false;
      _activeReveal = null;
      selectedCard = null;
      await _persist(roundNumber: next.roundNumber);
    }
  }

  void _refill(int targetRound) {
    final current = _runtime
        .where((card) => card.zone == CardZone.HAND)
        .map((card) => _engineCards[card.cardId]!)
        .toList();
    final drawn = drawEngine.refill(
      currentHand: current,
      cards: _engineCards.values.toList(),
      context: _context,
      actor: _profile(playerId),
      partner: _profile(opponentId),
      hierarchy: _hierarchy,
      style: PlayerStyle.EPICE,
      history: DrawHistory(cards: _history),
      random: SeededRandomSource(_stableHash('$playerId/$targetRound')),
    );
    final ids = drawn.map((card) => card.id).toSet();
    _runtime = [
      for (final card in _runtime)
        if (ids.contains(card.cardId))
          card.copyWith(zone: CardZone.HAND)
        else
          card,
    ];
    for (final id in ids) {
      _history[id] = CardHistoryState.seenUnplayed;
    }
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
    final requirements = [
      ...definition.profileRequirements,
      ...variant.profileRequirements,
    ];
    final elementId =
        requirements
            .where((item) => item.role == role)
            .map((item) => item.elementId)
            .firstOrNull ??
        requirements.map((item) => item.elementId).firstOrNull ??
        'network.prototype';
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
    final requirements = [
      ...definition.profileRequirements,
      ...variant.profileRequirements,
    ];
    final elementId =
        requirements
            .where((item) => item.role == role)
            .map((item) => item.elementId)
            .firstOrNull ??
        requirements.map((item) => item.elementId).firstOrNull ??
        'network.prototype';
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
    },
  );

  Future<void> _persist({int? roundNumber}) => privateStore.saveGame(
    sessionId: session.id,
    playerId: playerId,
    state: NetworkPrivateGameState(
      roundNumber: roundNumber ?? this.roundNumber,
      cards: _runtime,
      history: _history,
      activeReveal: _activeReveal,
      nextRoundPrepared: _nextRoundPrepared,
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
