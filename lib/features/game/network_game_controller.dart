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

typedef NetworkOccurrenceParameterResolver =
    FutureOr<V4ResolvedParameters> Function(
      NetworkDuelCard card,
      V4ResolvedParameters current,
    );

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
  actionInProgress,
  corruptionDecision,
  corruptionResponse,
  corruptionExecution,
  recovery,
  recoveryResponse,
  recoveryExecution,
  waitingNext,
  sessionEnded,
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
    PlayerGameProfile? privateProfile,
    V4Profile? v4Profile,
    V4ScoringCatalog? scoringCatalog,
    Set<String> availableAccessories = const {},
    V4SessionMode sessionMode = V4SessionMode.presentiel,
    Map<String, int> initialClothingCounts = const {},
    Iterable<V4Accessory> profileAccessories = const [],
    Iterable<String> disabledAccessoryIds = const [],
    Iterable<V4Accessory> temporaryAccessories = const [],
    DateTime Function()? clock,
    String Function()? nonceFactory,
    NetworkOccurrenceParameterResolver? occurrenceParameterResolver,
  }) : _catalog = catalog,
       _privateProfile = privateProfile,
       _v4Profile = v4Profile,
       _scoringCatalog = scoringCatalog,
       _occurrenceParameterResolver =
           occurrenceParameterResolver ?? _keepOccurrenceParameters,
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
        card.stableId: const CatalogEngineAdapter.v4().card(card),
    };
    _hierarchy = ProfileHierarchy({
      for (final element in catalog.profileElements)
        element.stableId: element.parentId,
    });
    _presence = sessionMode == V4SessionMode.distance
        ? V4SessionPresence.distance
        : V4SessionPresence.presentiel;
    _sessionMode = sessionMode;
    _accessoryPool = V4SessionAccessoryPool(
      profileAccessories: profileAccessories,
      disabledIds: disabledAccessoryIds,
      temporaryAccessories: temporaryAccessories,
    );
    final sessionAccessoryCapabilities = <String>{
      ...availableAccessories,
      if (_accessoryPool.available.isNotEmpty) 'SEXTOY',
      if (_accessoryPool.available.any(
        (item) => item.tags.contains(V4AccessoryTag.vibrant),
      ))
        'VIBRATING_TOY',
      if (_accessoryPool.available.any((item) => item.remoteControllable))
        'REMOTE_CONTROL_TOY',
    };
    _context = EngineSessionContext(
      mode: switch (sessionMode) {
        V4SessionMode.presentiel => SessionMode.face_to_face,
        V4SessionMode.distance => SessionMode.distance,
        V4SessionMode.hybrid => SessionMode.hybrid,
      },
      proximity: _presence == V4SessionPresence.presentiel
          ? ProximityState.TOGETHER
          : ProximityState.SEPARATED,
      chiliActive: 1,
      chiliUnlocked: 1,
      physicalStateByPlayer: {for (final id in playerIds) id: 'available'},
      clothesByPlayer: {
        for (final id in playerIds) id: initialClothingCounts[id] ?? 0,
      },
      accessories: sessionAccessoryCapabilities,
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
  late V4SessionMode _sessionMode;
  V4SessionMode get sessionMode => _sessionMode;
  final DateTime Function() clock;
  final String Function() nonceFactory;
  final NetworkOccurrenceParameterResolver _occurrenceParameterResolver;
  late final NetworkProfileLearningCoordinator learning;
  late final PostGameProfileChoiceStore _profileChoiceStore;
  final Catalog _catalog;
  final PlayerGameProfile? _privateProfile;
  final V4Profile? _v4Profile;
  final V4ScoringCatalog? _scoringCatalog;
  late final List<String> playerIds;
  late final Map<String, CardDefinition> _definitions;
  late final Map<String, EngineCard> _engineCards;
  late final ProfileHierarchy _hierarchy;
  late EngineSessionContext _context;
  late V4SessionPresence _presence;
  late V4SessionAccessoryPool _accessoryPool;
  Map<String, V4ResolvedParameters> _resolvedParameters = {};
  List<V4PersistentEffect> _persistentEffects = [];

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
  List<DeckCandidateV3> _allDeckCandidates = [];
  V4SpiceProgression _spiceProgression = V4SpiceProgression(
    initialUnitsBySpice: const {},
  );
  int _deckCycle = 1;
  int _choiceVersion = 0;
  bool _infiniteMode = false;
  PlayerStyle _deckStyle = PlayerStyle.SOFT;
  List<DeckShortage> _deckShortages = [];
  List<String> _recentCardIds = [];
  List<NetworkPlayedCardRecord> _publicDiscards = [];
  ChoiceRevealDto? _activeReveal;
  bool _nextRoundPrepared = false;
  StreamSubscription<NetworkGameRoundStateDto>? _subscription;
  bool _committing = false;
  bool _revealing = false;
  bool _resolving = false;
  bool _transitioning = false;
  bool _publishingAction = false;
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
      .map((card) => card.occurrenceId)
      .firstOrNull;
  List<CardRuntimeState> get runtime => List.unmodifiable(_runtime);
  Map<String, CardHistoryState> get history => Map.unmodifiable(_history);
  HybridDeckOrientation get orientation =>
      round?.hybridOrientation ?? HybridDeckOrientation.faceToFace;
  int get activeSpice => _context.chiliActive;
  V4SpiceProgression get spiceProgression => _spiceProgression;
  V4SessionPresence get presence => _presence;
  List<V4PersistentEffect> get persistentEffects =>
      List.unmodifiable(_persistentEffects);
  Map<String, int> get clothingCounts =>
      Map.unmodifiable(_context.clothesByPlayer);
  List<V4Accessory> get sessionAccessories => _accessoryPool.available;
  String? accessoryName(String? id) => id == null
      ? null
      : _accessoryPool.available
            .where((item) => item.id == id)
            .map((item) => item.name)
            .firstOrNull;
  NetworkResolvedActionProjectionDto? get actionProjection =>
      round?.actionProjection;
  Set<String> get requiredClothingPlayerIds =>
      actionProjection?.requiredClothingPlayerIds ?? const {};
  bool get ownClothingResyncRequired =>
      const NetworkActionCompletionGate().requiresPlayer(
        projection: actionProjection,
        resyncedPlayerIds: round?.clothingResyncedPlayerIds ?? const {},
        playerId: playerId,
      );
  bool get actionCompletionSubmitted =>
      round?.readyNextPlayerIds.contains(playerId) ?? false;
  bool get waitingForClothingResync =>
      actionProjection != null &&
      !const NetworkActionCompletionGate().canClose(
        projection: actionProjection,
        resyncedPlayerIds: round?.clothingResyncedPlayerIds ?? const {},
      );

  Future<void> updateOwnClothingCount(int actualCount) async {
    if (actualCount < 0) {
      throw ArgumentError.value(actualCount, 'actualCount');
    }
    final clothing = V4ClothingCounter(_context.clothesByPlayer)
      ..resynchronize(playerId, actualCount);
    _context = _context.copyWith(clothesByPlayer: clothing.counts);
    await _persist();
    notifyListeners();
  }

  Future<bool> resolveOccurrenceParameters(
    String occurrenceId, {
    V4ZoneSelectionSource? zoneSelectionSource,
    bool? sexualOrIntimateZone,
    String? zoneId,
    Set<V4AccessoryTag> requiredAccessoryTags = const {},
  }) async {
    final occurrence = _runtime
        .where(
          (item) =>
              item.occurrenceId == occurrenceId && item.zone == CardZone.HAND,
        )
        .firstOrNull;
    if (occurrence == null) return false;
    final current =
        _resolvedParameters[occurrenceId] ?? const V4ResolvedParameters();
    V4Accessory? accessory;
    if (requiredAccessoryTags.isNotEmpty) {
      final compatible = _accessoryPool.available
          .where((item) => item.supports(requiredAccessoryTags))
          .where(
            (item) => _accessoryAllowedForDirection(
              item,
              occurrence.effectiveDirection,
            ),
          )
          .toList();
      if (compatible.isNotEmpty) {
        final random = Random(
          _stableHash('$session.id/$occurrenceId/accessory'),
        );
        accessory = compatible[random.nextInt(compatible.length)];
      }
      if (accessory == null) return false;
    }
    _resolvedParameters[occurrenceId] = V4ResolvedParameters(
      zoneSelectionSource: zoneSelectionSource ?? current.zoneSelectionSource,
      sexualOrIntimateZone:
          sexualOrIntimateZone ?? current.sexualOrIntimateZone,
      zoneId: zoneId ?? current.zoneId,
      accessoryId: accessory?.id ?? current.accessoryId,
    );
    _ensurePlayableHand(roundNumber);
    await _persist();
    notifyListeners();
    return true;
  }

  bool get decksEmpty => _faceToFaceDeck.isEmpty && _distanceDeck.isEmpty;
  bool get mustSwitchHybridContext {
    if (sessionMode != V4SessionMode.hybrid) return false;
    final alternate = _presence == V4SessionPresence.presentiel
        ? V4SessionPresence.distance
        : V4SessionPresence.presentiel;
    final alternateAvailability = _availablePlayableOccurrences(alternate);
    if (round?.cycleExhausted == true && alternateAvailability > 0) {
      return true;
    }
    return const V4CycleGuard().evaluate(
          mode: sessionMode,
          activeOccurrencesByPlayer: {
            playerId: _availablePlayableOccurrences(_presence),
          },
          alternateContextOccurrencesByPlayer: {
            playerId: alternateAvailability,
          },
        ) ==
        V4CycleAvailability.switchHybridContext;
  }

  bool get canStartNextRound => !deckExhausted && !mustSwitchHybridContext;

  bool get deckExhausted {
    if (round?.cycleExhausted == true) {
      if (sessionMode != V4SessionMode.hybrid) return true;
      final alternate = _presence == V4SessionPresence.presentiel
          ? V4SessionPresence.distance
          : V4SessionPresence.presentiel;
      if (_availablePlayableOccurrences(alternate) == 0) return true;
    }
    if (_availablePlayableOccurrences(_presence) > 0) return false;
    if (sessionMode == V4SessionMode.hybrid) {
      final alternate = _presence == V4SessionPresence.presentiel
          ? V4SessionPresence.distance
          : V4SessionPresence.presentiel;
      if (_availablePlayableOccurrences(alternate) > 0) return false;
    }
    return true;
  }

  PlayerStyle get deckStyle => _deckStyle;
  bool get infiniteMode => _infiniteMode;
  bool get isCycleController => session.players.any(
    (player) =>
        player.userId == playerId && player.role == LobbyPlayerRole.player1,
  );
  List<DeckShortage> get deckShortages => List.unmodifiable(_deckShortages);
  int get faceToFaceDeckRemaining => _faceToFaceDeck.length;
  int get distanceDeckRemaining => _distanceDeck.length;
  bool get canCancelSelection =>
      repository is NetworkCommitCancellationRepository &&
      viewState == NetworkGameViewState.waitingForPartner &&
      round?.phase == NetworkGamePhase.commit &&
      round?.ownCommitRecorded == true &&
      (round?.commits.length ?? 0) < 2;

  List<NetworkDuelCard> get hand => [
    for (final item in _runtime.where((card) => card.zone == CardZone.HAND))
      ?_networkCard(
        item.cardId,
        occurrenceId: item.occurrenceId,
        variantId: item.variantId,
      ),
  ];

  List<NetworkDuelCard> get visibleDiscardCards {
    final cards = <NetworkDuelCard>[];
    final seen = <String>{};
    for (final item in _publicDiscards.reversed) {
      final card = _networkCard(
        item.cardId,
        occurrenceId: item.occurrenceId,
        variantId: item.variantId,
      );
      if (card != null && seen.add(card.identity)) cards.add(card);
    }
    for (final item in _runtime.where(
      (card) =>
          card.zone == CardZone.DISCARD || card.zone == CardZone.EXHAUSTED,
    )) {
      final card = _networkCard(
        item.cardId,
        occurrenceId: item.occurrenceId,
        variantId: item.variantId,
      );
      if (card != null && seen.add(card.identity)) cards.add(card);
    }
    return List.unmodifiable(cards);
  }

  List<NetworkDuelCard> get auctionCards => [
    for (final item in _runtime)
      if ((item.zone == CardZone.HAND || item.zone == CardZone.DISCARD) &&
          item.occurrenceId !=
              _activeReveal?.choice.parameters['occurrence_id'])
        ?_networkCard(
          item.cardId,
          occurrenceId: item.occurrenceId,
          variantId: item.variantId,
        ),
  ];

  String? get corruptionActorId {
    final retained = finalResolution?.retainedPlayerId;
    if (retained == null) return null;
    return playerIds.firstWhere((id) => id != retained);
  }

  bool get isCorruptionActor => corruptionActorId == playerId;
  List<NetworkDuelCard> get corruptionCards => [
    for (final item in _runtime)
      if (lifecycleEngine.canUseForCorruption(item))
        ?_networkCard(
          item.cardId,
          occurrenceId: item.occurrenceId,
          variantId: item.variantId,
        ),
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
      if (item.zone != CardZone.EXHAUSTED)
        ?_networkRecoveryCard(
          item.cardId,
          occurrenceId: item.occurrenceId,
          variantId: item.variantId,
        ),
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

  Future<AdaptiveProfileState> profileState() => learning.state();

  Future<void> customizePreference(
    PreferenceLearningKey key,
    DetailedPreferenceCategory category,
  ) async {
    final pa = switch (category) {
      DetailedPreferenceCategory.essential => 1.5,
      DetailedPreferenceCategory.love => 3.5,
      DetailedPreferenceCategory.likeALot => 5.5,
      DetailedPreferenceCategory.like => 7.5,
      DetailedPreferenceCategory.tempted => 10.0,
      DetailedPreferenceCategory.depends => 13.0,
      DetailedPreferenceCategory.occasional => 15.5,
      DetailedPreferenceCategory.atMyLimit => 18.0,
      DetailedPreferenceCategory.unsure => 20.0,
      DetailedPreferenceCategory.excluded => null,
    };
    await learning.manuallyCustomize(
      key: key,
      pa: pa,
      excluded: category == DetailedPreferenceCategory.excluded,
    );
    notifyListeners();
  }

  Future<void> switchOrientation(HybridDeckOrientation value) async {
    if (sessionMode != V4SessionMode.hybrid ||
        repository is! NetworkSessionFlowRepository ||
        value == orientation ||
        viewState != NetworkGameViewState.waitingNext) {
      return;
    }
    await _networkAction(
      (repository as NetworkSessionFlowRepository).setHybridOrientation(
        command: _command('SET_ORIENTATION_${value.name}'),
        orientation: value,
      ),
    );
  }

  Future<void> continueDeck(DeckExhaustionChoice choice) async {
    if (repository is! NetworkSessionFlowRepository || !isCycleController) {
      return;
    }
    if (choice != DeckExhaustionChoice.newCustomizedGame &&
        choice != DeckExhaustionChoice.finish) {
      final cycle = DeckCycleState(
        style: _deckStyle,
        infinite: _infiniteMode,
        recentOccurrenceKeys: _recentCardIds,
      ).next(choice);
      _deckCycle++;
      _infiniteMode = cycle.infinite;
      _deckStyle = cycle.style;
      _buildDeckCycle();
      _refill(roundNumber + 1);
      await _persist();
    }
    await _networkAction(
      (repository as NetworkSessionFlowRepository).continueDeckCycle(
        command: _command('CONTINUE_CYCLE'),
        choice: choice,
        deckAdjustment: {
          for (final shortage in _deckShortages)
            shortage.requestedSpice: shortage.missingCount,
        },
      ),
    );
    if (choice != DeckExhaustionChoice.newCustomizedGame &&
        choice != DeckExhaustionChoice.finish &&
        viewState == NetworkGameViewState.waitingNext &&
        !deckExhausted) {
      await completeAction();
    }
  }

  void toggleLock(String occurrenceId) {
    if (viewState != NetworkGameViewState.choosing ||
        round?.ownCommitRecorded == true) {
      return;
    }
    final target = _runtime
        .where(
          (card) =>
              card.occurrenceId == occurrenceId && card.zone == CardZone.HAND,
        )
        .firstOrNull;
    if (target == null) return;
    if (target.locked) {
      _runtime = [
        for (final card in _runtime)
          card.occurrenceId == occurrenceId
              ? card.copyWith(locked: false)
              : card,
      ];
    } else {
      _runtime = lifecycleEngine.lock(_runtime, occurrenceId);
    }
    unawaited(_persist());
    notifyListeners();
  }

  void selectCard(String occurrenceId) {
    if (viewState != NetworkGameViewState.choosing) return;
    final candidate = hand
        .where((card) => card.identity == occurrenceId)
        .firstOrNull;
    if (candidate == null || !isCardPlayable(candidate)) return;
    selectedCard = candidate;
    notifyListeners();
  }

  bool isCardPlayable(NetworkDuelCard card) {
    final runtimeCard = _runtime
        .where(
          (item) => item.cardId == card.id && item.variantId == card.variant.id,
        )
        .firstOrNull;
    final candidate = _allDeckCandidates
        .where(
          (item) => runtimeCard == null
              ? item.variantId == card.variant.id
              : item.occurrenceId == runtimeCard.occurrenceId,
        )
        .firstOrNull;
    final parameters =
        _resolvedParameters[card.identity] ?? const V4ResolvedParameters();
    final effectiveSpice = parameters.effectiveSpice(
      candidate?.spiceLevel ?? card.variant.chiliLevel,
    );
    return _spiceProgression.isPlayable(effectiveSpice) &&
        (candidate == null ||
            const V4ContextualPool().isContextuallyEligible(
              candidate,
              _poolContext(),
            ));
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
    final runtimeCard = _runtime
        .where((item) => item.occurrenceId == card.identity)
        .firstOrNull;
    if (runtimeCard == null ||
        runtimeCard.zone != CardZone.HAND ||
        !isCardPlayable(card)) {
      selectedCard = null;
      notifyListeners();
      return;
    }
    _committing = true;
    viewState = NetworkGameViewState.committing;
    notifyListeners();
    try {
      final currentParameters =
          _resolvedParameters[card.identity] ?? const V4ResolvedParameters();
      final resolvedParameters = await _occurrenceParameterResolver(
        card,
        currentParameters,
      );
      final resolved = await resolveOccurrenceParameters(
        card.identity,
        zoneSelectionSource: resolvedParameters.zoneSelectionSource,
        sexualOrIntimateZone: resolvedParameters.sexualOrIntimateZone,
        zoneId: resolvedParameters.zoneId,
      );
      final occurrenceId = card.identity;
      final resolvedCard = hand
          .where((item) => item.identity == occurrenceId)
          .firstOrNull;
      if (!resolved || resolvedCard == null || !isCardPlayable(resolvedCard)) {
        selectedCard = null;
        viewState = NetworkGameViewState.choosing;
        notifyListeners();
        return;
      }
      final committedCard = resolvedCard;
      final choice = ChoicePayload(
        cardId: committedCard.id,
        variantId: committedCard.variant.id,
        parameters: {
          'role': committedCard.role.name,
          'personal_value': committedCard.personalValue,
          'opposite_personal_value': committedCard.oppositePersonalValue,
          'native_direction': committedCard.nativeDirection.name,
          'effective_direction': committedCard.effectiveDirection.name,
          'occurrence_id': committedCard.identity,
          'effective_spice': committedCard.chiliLevel,
          'resolved_parameters':
              (_resolvedParameters[committedCard.identity] ??
                      const V4ResolvedParameters())
                  .toJson(),
          'committed_at': clock().toUtc().toIso8601String(),
        },
      );
      final reveal = ChoiceRevealDto(
        sessionRound: current.sessionRound,
        playerId: playerId,
        choice: choice,
        nonce: '${nonceFactory()}:v$_choiceVersion',
      );
      _activeReveal = reveal;
      _runtime = lifecycleEngine.reserve(_runtime, committedCard.identity);
      await _persist();
      await _apply(
        await repository.submitCommit(
          command: _command('COMMIT', choiceVersion: _choiceVersion),
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

  Future<bool> cancelSelection() async {
    final cancellable = repository;
    if (!canCancelSelection ||
        round == null ||
        cancellable is! NetworkCommitCancellationRepository) {
      return false;
    }
    try {
      final updated = await (cancellable as NetworkCommitCancellationRepository)
          .cancelCommit(
            command: _command('CANCEL_COMMIT', choiceVersion: _choiceVersion),
          );
      _restoreCancelledChoice();
      _choiceVersion++;
      await privateStore.clear(sessionId: session.id, playerId: playerId);
      await _persist();
      await _apply(updated);
      return true;
    } on NetworkRoundException catch (error) {
      if (error.code != 'ROUND_CANCEL_CLOSED' &&
          error.code != 'ROUND_COMMIT_CLOSED') {
        rethrow;
      }
      await _apply(await repository.getCurrentRound(sessionId: session.id));
      return false;
    }
  }

  Future<void> closeSession() async {
    final closable = repository;
    if (closable is! NetworkSessionClosureRepository || round == null) {
      throw const NetworkRoundException('ROUND_CLOSE_UNAVAILABLE');
    }
    await _apply(
      await (closable as NetworkSessionClosureRepository).closeSession(
        command: _command('CLOSE_SESSION'),
      ),
    );
  }

  void _restoreCancelledChoice() {
    final occurrence =
        _activeReveal?.choice.parameters['occurrence_id'] as String?;
    if (occurrence != null) {
      _runtime = [
        for (final card in _runtime)
          if (card.occurrenceId == occurrence && card.zone == CardZone.RESERVED)
            card.copyWith(zone: CardZone.HAND, locked: false)
          else
            card,
      ];
    }
    _activeReveal = null;
    selectedCard = null;
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

  Future<void> respondNegotiation({required bool accepted}) async {
    if (viewState != NetworkGameViewState.negotiationResponse ||
        !isInitialWinner) {
      return;
    }
    final proposal = negotiation?.proposal;
    if (proposal == null) throw StateError('No proposal to answer');
    negotiationEngine.decide(
      _negotiationState(NegotiationPhase.response),
      accepted: accepted,
    );
    await _networkAction(
      (repository as NetworkNegotiationRepository).respondNegotiation(
        command: _command('NEGOTIATION_RESPONSE'),
        response: NetworkNegotiationResponseDto(accepted: accepted),
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
    if (negotiation?.finalOffer == null) {
      throw StateError('There is no final compromise to validate');
    }
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
    String occurrenceId,
    CorruptionObjective objective,
  ) async {
    final card = corruptionCards
        .where((item) => item.identity == occurrenceId)
        .firstOrNull;
    if (viewState != NetworkGameViewState.corruptionDecision ||
        !isCorruptionActor ||
        card == null) {
      return;
    }
    await _networkAction(
      repository.submitCorruptionOffer(
        command: _command('CORRUPTION_OFFER'),
        objective: objective,
        actions: [
          ActionPromise(
            cardId: card.id,
            occurrenceId: card.identity,
            source: CardZone.DISCARD,
          ),
        ],
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

  Future<void> recoverWith(String occurrenceId) async {
    if (viewState != NetworkGameViewState.recovery || !recoveryAvailable) {
      return;
    }
    final card = recoveryCards
        .where((item) => item.identity == occurrenceId)
        .firstOrNull;
    final runtime = _runtime
        .where((item) => item.occurrenceId == occurrenceId)
        .firstOrNull;
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
      occurrenceId: occurrenceId,
    );
    await _networkAction(
      repository.submitRecovery(
        command: _command(
          'RECOVERY_${round!.recoveryHistory.length}_$occurrenceId',
        ),
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
      gain: completed ? _recoveryGain(proposal) : 0,
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
      cardId: proposal.occurrenceId ?? proposal.cardId,
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

  Future<void> completeAction() async {
    final current = round;
    if (current == null ||
        (viewState != NetworkGameViewState.actionInProgress &&
            viewState != NetworkGameViewState.waitingNext)) {
      return;
    }
    if (viewState == NetworkGameViewState.actionInProgress &&
        actionCompletionSubmitted) {
      return;
    }
    try {
      final atBoundary = viewState == NetworkGameViewState.waitingNext;
      if (atBoundary && !isCycleController) return;
      if (atBoundary && !canStartNextRound) return;
      if (atBoundary) await _prepareNextRound();
      await _apply(
        await repository.readyNextRound(
          command: _command(
            atBoundary ? 'START_NEXT_ROUND' : 'ACTION_COMPLETE',
          ),
          noPlayableOccurrences:
              !atBoundary && _availablePlayableOccurrences(_presence) == 0,
          clothingCount: !atBoundary && ownClothingResyncRequired
              ? _context.clothesByPlayer[playerId]
              : null,
        ),
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
      // Publish the new round's immediately usable state before awaiting the
      // old realtime subscription cancellation. Otherwise the new round
      // number can briefly coexist with the previous WAITING_NEXT UI.
      if (value.phase == NetworkGamePhase.commit) {
        viewState = NetworkGameViewState.choosing;
        notifyListeners();
      }
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
    if (value.roundNumber < roundNumber) return;
    if (value.clothingCounts.isNotEmpty) {
      _context = _context.copyWith(clothesByPlayer: value.clothingCounts);
    }
    final publicCycleAdvanced = value.deckCycle > _deckCycle;
    final previousPresence = _presence;
    if (sessionMode == V4SessionMode.hybrid) {
      _presence = value.hybridOrientation == HybridDeckOrientation.faceToFace
          ? V4SessionPresence.presentiel
          : V4SessionPresence.distance;
      _context = _context.copyWith(
        proximity: _presence == V4SessionPresence.presentiel
            ? ProximityState.TOGETHER
            : ProximityState.SEPARATED,
      );
      if (previousPresence != _presence &&
          value.phase == NetworkGamePhase.waitingNext) {
        _rebuildHandForPresence(value.roundNumber + 1);
        await _persist(roundNumber: value.roundNumber);
      }
    }
    _deckStyle = value.deckStyle;
    _deckCycle = value.deckCycle;
    _infiniteMode = value.infiniteMode;
    if (publicCycleAdvanced && decksEmpty && deckExhausted) {
      _buildDeckCycle();
      _refill(value.roundNumber + 1);
      await _persist(roundNumber: value.roundNumber);
    }
    if (round?.roundId != value.roundId) {
      await _activatePreparedRound(value);
      if (value.roundNumber < roundNumber) return;
      await _switchRound(value);
      return;
    }
    round = value;
    _capturePublicDiscards(value);
    await _closeNormalRoundForRecovery(value);
    await _reconcilePublicLifecycle(value);
    if (_disposed ||
        round?.roundId != value.roundId ||
        value.roundNumber < roundNumber) {
      return;
    }
    switch (value.phase) {
      case NetworkGamePhase.commit:
        if (value.ownCommitRecorded) {
          if (_activeReveal == null) {
            _fail(const NetworkRoundException('ROUND_LOCAL_SECRET_MISSING'));
          } else {
            viewState = NetworkGameViewState.waitingForPartner;
          }
        } else {
          // The round stream can emit its pre-command snapshot while the local
          // commit RPC is still in flight. Only reconcile a missing server
          // commit once that operation has completed.
          if (_activeReveal != null && !_committing) {
            _restoreCancelledChoice();
            await _persist();
          }
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
        if (value.actionProjection == null &&
            repository is NetworkV4ActionRepository &&
            !_publishingAction) {
          await _publishActionProjection(value);
          return;
        }
        await _recordLearningForRound();
        viewState = NetworkGameViewState.actionInProgress;
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
      case NetworkGamePhase.sessionClosed:
        viewState = NetworkGameViewState.sessionEnded;
        break;
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
    _consumeEngagedVariants();
    _runtime = lifecycleEngine.closeRound(_runtime);
    for (final id in played) {
      _history[id] = CardHistoryState.playedOrDiscarded;
    }
    _rememberRecent(played);
    await _persist();
  }

  Future<void> _reconcilePublicLifecycle(NetworkGameRoundStateDto value) async {
    var changed = false;
    final publicResult = value.finalResolution;
    if (publicResult != null) {
      final ownInitialOccurrence =
          _activeReveal?.choice.parameters['occurrence_id'] as String?;
      if (ownInitialOccurrence != null) {
        final reconciled = [
          for (final card in _runtime)
            if (card.occurrenceId == ownInitialOccurrence &&
                card.zone == CardZone.RESERVED)
              card.copyWith(zone: CardZone.ENGAGED, locked: false)
            else
              card,
        ];
        changed = changed || !_sameRuntime(_runtime, reconciled);
        _runtime = reconciled;
      }
      final auctionOccurrences = publicResult.compromise
          .where(
            (card) =>
                card.ownerPlayerId == playerId &&
                card.origin == NetworkCompromiseOrigin.AUCTION,
          )
          .map((card) => card.occurrenceId)
          .toSet();
      if (auctionOccurrences.isNotEmpty) {
        final reconciled = [
          for (final card in _runtime)
            if (auctionOccurrences.contains(card.occurrenceId) &&
                (card.zone == CardZone.HAND || card.zone == CardZone.RESERVED))
              card.copyWith(zone: CardZone.ENGAGED, locked: false)
            else
              card,
        ];
        changed = changed || !_sameRuntime(_runtime, reconciled);
        _runtime = reconciled;
      }
      final initialCards = publicResult.compromise.where(
        (card) =>
            card.ownerPlayerId == playerId &&
            card.origin == NetworkCompromiseOrigin.INITIAL_DUEL,
      );
      if (initialCards.firstOrNull case final initial?) {
        final direction = CardOccurrenceDirection.values.byName(
          initial.effectiveDirection.name,
        );
        final reconciled = [
          for (final card in _runtime)
            card.occurrenceId == initial.occurrenceId
                ? card.copyWith(
                    zone: card.zone == CardZone.RESERVED
                        ? CardZone.ENGAGED
                        : card.zone,
                    effectiveDirection: direction,
                  )
                : card,
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
        cardId: publicRecovery.occurrenceId ?? publicRecovery.cardId,
        source: publicRecovery.source,
        completed: publicRecovery.completed,
      );
      changed = changed || !_sameRuntime(_runtime, reconciled);
      _runtime = reconciled;
      if (!_spiceProgression.consumedOccurrenceIds.contains(
        publicRecovery.occurrenceId ?? publicRecovery.variantId,
      )) {
        _consumeOccurrence(
          publicRecovery.occurrenceId ?? publicRecovery.variantId,
        );
        changed = true;
      }
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
      if (a.cardId != b.cardId ||
          a.variantId != b.variantId ||
          a.occurrenceId != b.occurrenceId ||
          a.zone != b.zone ||
          a.locked != b.locked ||
          a.nativeDirection != b.nativeDirection ||
          a.effectiveDirection != b.effectiveDirection) {
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
          command: _command('REVEAL', choiceVersion: _choiceVersion),
          reveal: reveal,
        ),
      );
    } catch (error) {
      _fail(error);
    } finally {
      _revealing = false;
    }
  }

  Future<void> _publishActionProjection(NetworkGameRoundStateDto value) async {
    final repository = this.repository;
    var resolution = value.finalResolution;
    if (repository is! NetworkV4ActionRepository || resolution == null) return;
    final actionRepository = repository as NetworkV4ActionRepository;
    _publishingAction = true;
    try {
      if (!resolution.mutualAbandon &&
          resolution.compromise.any(
            (card) =>
                card.resolvedParameters == null || card.effectiveSpice == null,
          )) {
        final repaired = await actionRepository.repairV4ActionParameters(
          command: _command('REPAIR_V4_ACTION_PARAMETERS'),
        );
        resolution = repaired.finalResolution;
        if (resolution == null) {
          throw const NetworkRoundException('ROUND_ACTION_PARAMETERS_MISSING');
        }
      }
      final cards = resolution.mutualAbandon
          ? const <NetworkResolvedActionCardDto>[]
          : [
              for (final card in resolution.compromise)
                _resolvedActionCard(card),
            ];
      final required = <String>{
        for (final card in cards)
          if (_definitions[card.cardId]?.v4?.clothingBehavior != null &&
              _definitions[card.cardId]!.v4!.clothingBehavior !=
                  V4ClothingBehavior.none)
            ...card.targetPlayerIds,
      };
      await _apply(
        await actionRepository.publishV4ActionProjection(
          command: _command('PUBLISH_V4_ACTION'),
          projection: NetworkResolvedActionProjectionDto(
            cards: cards,
            requiredClothingPlayerIds: required,
          ),
        ),
      );
    } catch (error) {
      _fail(error);
    } finally {
      _publishingAction = false;
    }
  }

  NetworkResolvedActionCardDto _resolvedActionCard(
    NetworkCompromiseCardDto card,
  ) {
    final parameters = card.resolvedParameters;
    final effectiveSpice = card.effectiveSpice;
    if (parameters == null || effectiveSpice == null) {
      throw const NetworkRoundException('ROUND_ACTION_PARAMETERS_MISSING');
    }
    final definition = _definitions[card.cardId];
    final direction = card.effectiveDirection;
    final targets = const V4ActionTargetResolver().resolve(
      ownerPlayerId: card.ownerPlayerId,
      playerIds: playerIds,
      direction: CardOccurrenceDirection.values.byName(direction.name),
    );
    final duration = definition?.v4?.durationActions;
    final effects = duration == null
        ? const <V4PersistentEffect>[]
        : const V4PersistentEffectEngine().createForAction(
            cardId: card.cardId,
            targetPlayerIds: targets,
            durationActions: duration,
          );
    return NetworkResolvedActionCardDto(
      occurrenceId: card.occurrenceId,
      cardId: card.cardId,
      variantId: card.variantId,
      direction: direction,
      targetPlayerIds: targets,
      effectiveSpice: effectiveSpice,
      zoneId: parameters.zoneId,
      accessoryId: parameters.accessoryId,
      parameters: parameters.toJson(),
      effects: effects,
    );
  }

  Future<void> _resolveOnce(NetworkGameRoundStateDto value) async {
    if (_resolving) return;
    if (repository is NetworkPrivateInitialResolutionRepository) {
      final privateResolver =
          repository as NetworkPrivateInitialResolutionRepository;
      _resolving = true;
      try {
        await _apply(
          await privateResolver.resolveInitialPrivately(
            command: _command('INITIAL_RESOLVE'),
          ),
        );
        resolutionCount++;
      } catch (error) {
        _fail(error);
      } finally {
        _resolving = false;
      }
      return;
    }
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
    final nativeName = reveal.choice.parameters['native_direction'] as String?;
    final effectiveName =
        reveal.choice.parameters['effective_direction'] as String?;
    final native = nativeName == null
        ? _fixedDirection(card, variant)
        : CardOccurrenceDirection.values.byName(nativeName);
    final effective = effectiveName == null
        ? native
        : CardOccurrenceDirection.values.byName(effectiveName);
    final expectedRole = _profileRole(
      effective,
      fallback: _roleFor(card, variant),
    );
    final opposite = reveal.choice.parameters['opposite_personal_value'];
    final reversible = _isReversible(card, variant);
    if (role != expectedRole ||
        effective != native ||
        value < 1 ||
        value > 20 ||
        (opposite != null &&
            (opposite is! int || opposite < 1 || opposite > 20))) {
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
      cardInvertible: reversible && opposite is int,
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
      _deckCycle = saved.deckCycle;
      _infiniteMode = saved.infiniteMode;
      _deckStyle = saved.deckStyle;
      _deckShortages = List.of(saved.deckShortages);
      _recentCardIds = List.of(saved.recentCardIds);
      _publicDiscards = List.of(saved.publicDiscards);
      _choiceVersion = saved.choiceVersion;
      _presence = switch (sessionMode) {
        V4SessionMode.presentiel => V4SessionPresence.presentiel,
        V4SessionMode.distance => V4SessionPresence.distance,
        V4SessionMode.hybrid => saved.presence,
      };
      _resolvedParameters = Map.of(saved.resolvedParameters);
      _persistentEffects = List.of(saved.persistentEffects);
      _accessoryPool = saved.accessoryPool;
      _allDeckCandidates = _catalogCandidates();
      _runtime = _normalizeRuntimeOccurrences(_runtime);
      _context = _context.copyWith(
        accessories: saved.availableAccessories.isEmpty
            ? _context.accessories
            : saved.availableAccessories,
        clothesByPlayer: saved.clothesByPlayer.isEmpty
            ? _context.clothesByPlayer
            : saved.clothesByPlayer,
      );
      _spiceProgression =
          saved.spiceProgression.initialUnitsBySpice.values.every(
            (count) => count == 0,
          )
          ? _legacyProgression(saved)
          : _normalizeProgression(saved.spiceProgression);
      final activeOccurrences = _runtime
          .map((card) => card.occurrenceId)
          .toSet();
      _faceToFaceDeck = [
        for (final candidate in _allDeckCandidates)
          if (!_spiceProgression.consumedOccurrenceIds.contains(
                candidate.occurrenceId,
              ) &&
              !activeOccurrences.contains(candidate.occurrenceId))
            candidate,
      ];
      _distanceDeck = List.of(_faceToFaceDeck);
      _syncSpiceContext();
      if (_faceToFaceDeck.isEmpty &&
          _distanceDeck.isEmpty &&
          saved.cards.isEmpty) {
        _buildDeckCycle();
      }
      if (_nextRoundPrepared && saved.roundNumber == current.roundNumber) {
        _nextRoundPrepared = false;
        await _persist(roundNumber: current.roundNumber);
      }
      return;
    }
    _runtime = [];
    _history = {};
    _publicDiscards = [];
    _choiceVersion = 0;
    _learningRecordedRounds = {};
    _buildDeckCycle();
    _refill(current.roundNumber);
    await _persist(roundNumber: current.roundNumber);
  }

  Future<void> _prepareNextRound() async {
    if (_nextRoundPrepared) return;
    _closePersistentEffects();
    final played = _runtime
        .where((card) => card.zone == CardZone.ENGAGED)
        .map((card) => card.cardId)
        .toList();
    _consumeEngagedVariants();
    _runtime = lifecycleEngine.closeRound(_runtime);
    for (final id in played) {
      _history[id] = CardHistoryState.playedOrDiscarded;
    }
    _rememberRecent(played);
    _refill(roundNumber + 1);
    _activeReveal = null;
    selectedCard = null;
    _nextRoundPrepared = true;
    await _persist(roundNumber: roundNumber + 1);
  }

  Future<void> _recordLearningForRound() async {
    final currentRound = round;
    final result = currentRound?.finalResolution;
    final currentRoundNumber = currentRound?.roundNumber;
    if (result == null ||
        currentRound == null ||
        currentRoundNumber == null ||
        _learningRecordedRounds.contains(currentRoundNumber)) {
      return;
    }
    final visibleHand = <LearningCardDescriptor>[];
    for (final runtimeCard in _runtime.where(
      (card) => card.zone == CardZone.HAND || card.zone == CardZone.ENGAGED,
    )) {
      final definition = _definitions[runtimeCard.cardId];
      final network = _networkCard(
        runtimeCard.cardId,
        occurrenceId: runtimeCard.occurrenceId,
        variantId: runtimeCard.variantId,
      );
      if (definition == null || network == null) continue;
      final variant = definition.variants.singleWhere(
        (item) => item.stableId == network.variant.id,
      );
      visibleHand.add(
        v3LearningDescriptor(
          definition,
          variant,
          occurrenceId: runtimeCard.occurrenceId,
        ),
      );
    }
    final reveal = _activeReveal;
    final played = <String>{
      if (reveal != null)
        (reveal.choice.parameters['occurrence_id'] as String?) ??
            '${reveal.choice.cardId}|${reveal.choice.variantId}',
      for (final card in result.compromise)
        if (card.ownerPlayerId == playerId &&
            card.origin == NetworkCompromiseOrigin.AUCTION)
          card.occurrenceId,
    };
    final locked = <String>{
      for (final card in _runtime.where((card) => card.locked))
        for (final descriptor in visibleHand)
          if (descriptor.occurrenceId == card.occurrenceId) descriptor.identity,
    };
    final acceptedBatches = <List<ResolvedLearningCard>>[];
    final resistanceEvents = <ResistanceLearningEvent>[];
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
            v3LearningDescriptor(
              definition,
              variant,
              occurrenceId: item.occurrenceId,
            ),
            ownerId: item.ownerPlayerId,
            effectiveDirection: item.effectiveDirection,
          ),
        );
      }
      if (accepted.isNotEmpty) acceptedBatches.add(accepted);
      final recoveryAccepted = <ResolvedLearningCard>[];
      for (final recovery in currentRound.recoveryHistory) {
        if (!recovery.completed) continue;
        final definition = _definitions[recovery.cardId];
        final variant = definition?.variants
            .where((item) => item.stableId == recovery.variantId)
            .firstOrNull;
        if (definition == null || variant == null) continue;
        recoveryAccepted.add(
          _resolvedLearningCard(
            v3LearningDescriptor(
              definition,
              variant,
              occurrenceId: recovery.occurrenceId,
            ),
            ownerId: recovery.playerId,
            effectiveDirection: _runtime
                .where((item) => item.occurrenceId == recovery.occurrenceId)
                .map(
                  (item) => NetworkCardDirection.values.byName(
                    item.effectiveDirection.name,
                  ),
                )
                .firstOrNull,
          ),
        );
      }
      if (recoveryAccepted.isNotEmpty) {
        acceptedBatches.add(recoveryAccepted);
      }
      resistanceEvents.addAll(_negotiationResistance(result, currentRound));
    }
    await learning.recordResolvedRoundOnce(
      eventId: 'v4-learning:${currentRound.roundId}:$playerId:final-resolved',
      handCards: visibleHand,
      played: played,
      locked: locked,
      acceptedBatches: acceptedBatches,
      resistanceEvents: resistanceEvents,
    );
    _learningRecordedRounds.add(currentRoundNumber);
    await _persist();
  }

  List<ResistanceLearningEvent> _negotiationResistance(
    NetworkFinalResolutionDto result,
    NetworkGameRoundStateDto currentRound,
  ) {
    final events = <ResistanceLearningEvent>[];
    final negotiation = currentRound.negotiation;
    final proposal = negotiation?.proposal;
    final response = negotiation?.response;
    if (proposal == null || response == null) return events;

    if (isInitialWinner && !response.acceptAuction) {
      for (final item in proposal.cards) {
        final definition = _definitions[item.cardId];
        final variant = definition?.variants
            .where((candidate) => candidate.stableId == item.variantId)
            .firstOrNull;
        if (definition == null || variant == null) continue;
        events.add(
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
      if (initial == null) return events;
      final definition = _definitions[initial.cardId];
      final variant = definition?.variants
          .where((candidate) => candidate.stableId == initial.variantId)
          .firstOrNull;
      if (definition == null || variant == null) return events;
      events.add(
        ResistanceLearningEvent(
          playerId: playerId,
          card: v3LearningDescriptor(definition, variant),
          resistedRole: _learningRoleFor(initial, playerId),
          signal: ResistanceSignal.inversionSought,
        ),
      );
    }
    return events;
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
    NetworkCardDirection? effectiveDirection,
  }) {
    if (effectiveDirection == NetworkCardDirection.MUTUEL ||
        card.tags.contains('v3.direction.mutuel')) {
      return ResolvedLearningCard(
        card: card,
        participation: ResolvedParticipation.mutual,
        participantPlayerIds: playerIds,
      );
    }
    if (effectiveDirection == NetworkCardDirection.SIMULTANE ||
        card.tags.contains('v3.direction.simultane')) {
      return ResolvedLearningCard(
        card: card,
        participation: ResolvedParticipation.simultaneous,
        participantPlayerIds: playerIds,
      );
    }
    if (effectiveDirection == NetworkCardDirection.SOLO ||
        card.tags.contains('v3.direction.solo')) {
      return ResolvedLearningCard(
        card: card,
        participation: ResolvedParticipation.solo,
        soloPlayerId: ownerId,
      );
    }
    final other = playerIds.firstWhere((id) => id != ownerId);
    final ownerPerforms =
        effectiveDirection == NetworkCardDirection.FAIRE ||
        (effectiveDirection == null &&
            !card.tags.contains('v3.direction.recevoir'));
    return ResolvedLearningCard(
      card: card,
      participation: ResolvedParticipation.directed,
      performerPlayerId: ownerPerforms ? ownerId : other,
      receiverPlayerId: ownerPerforms ? other : ownerId,
    );
  }

  Future<void> _activatePreparedRound(NetworkGameRoundStateDto next) async {
    if (!_nextRoundPrepared && next.roundNumber == roundNumber + 1) {
      await _prepareNextRound();
    }
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
    if (decksEmpty && _infiniteMode) {
      _deckCycle++;
      _buildDeckCycle();
    }
    final currentHand = <DeckCandidateV3>[];
    for (final card in _runtime.where((card) => card.zone == CardZone.HAND)) {
      final candidate = _allDeckCandidates
          .where((candidate) => candidate.occurrenceId == card.occurrenceId)
          .firstOrNull;
      if (candidate != null) currentHand.add(candidate);
    }
    final accessoryEligibleCandidates = _allDeckCandidates
        .where(_candidateAccessoryCompatible)
        .toList(growable: false);
    final pool = const V4ContextualPool().project(
      allCandidates: accessoryEligibleCandidates,
      progression: _spiceProgression,
      context: _poolContext(),
      inHandOccurrenceIds: currentHand
          .map((candidate) => candidate.occurrenceId)
          .toSet(),
    );
    final generated = const V4HandGenerator().refill(
      currentHand: currentHand,
      pool: pool.drawable,
      allCandidates: accessoryEligibleCandidates,
      progression: _spiceProgression,
      style: _deckStyle,
      random: Random(_stableHash('$playerId/$targetRound/$_deckCycle')),
      orientation: _presence == V4SessionPresence.distance
          ? HybridDeckOrientation.distance
          : HybridDeckOrientation.faceToFace,
    );
    final acceptedDrawnIds = <String>{};
    for (final drawn in generated.drawn) {
      final alreadyActive = _runtime.any(
        (card) => card.occurrenceId == drawn.occurrenceId,
      );
      if (alreadyActive) continue;
      final selection = _directionFor(drawn);
      if (selection == null) continue;
      final parameters = _resolveDrawParameters(drawn, targetRound);
      if (parameters == null) continue;
      _runtime = [
        ..._runtime,
        CardRuntimeState(
          cardId: drawn.cardId,
          occurrenceId: drawn.occurrenceId,
          variantId: drawn.variantId,
          zone: CardZone.HAND,
          nativeDirection: selection.nativeDirection,
          effectiveDirection: selection.effectiveDirection,
        ),
      ];
      _resolvedParameters[drawn.occurrenceId] = parameters;
      acceptedDrawnIds.add(drawn.occurrenceId);
      _history[drawn.cardId] = CardHistoryState.seenUnplayed;
      needed--;
    }
    _faceToFaceDeck = [
      for (final card in _faceToFaceDeck)
        if (!acceptedDrawnIds.contains(card.occurrenceId)) card,
    ];
    _distanceDeck = [
      for (final card in _distanceDeck)
        if (!acceptedDrawnIds.contains(card.occurrenceId)) card,
    ];
    _ensurePlayableHand(targetRound);
    if (needed < const BalanceConfig().handSize) _recentCardIds = [];
  }

  void _rebuildHandForPresence(int targetRound) {
    final context = _poolContext();
    final returned = <DeckCandidateV3>[];
    final returnedIds = <String>{};
    for (final card in _runtime.where((item) => item.zone == CardZone.HAND)) {
      final candidate = _candidateForOccurrence(card.occurrenceId);
      if (candidate != null &&
          !const V4ContextualPool().isContextuallyEligible(
            candidate,
            context,
          )) {
        returned.add(candidate);
        returnedIds.add(card.occurrenceId);
      }
    }
    if (returnedIds.isNotEmpty) {
      _runtime = [
        for (final card in _runtime)
          if (!returnedIds.contains(card.occurrenceId)) card,
      ];
      if (selectedCard != null &&
          returnedIds.contains(selectedCard!.identity)) {
        selectedCard = null;
      }
      _returnCandidatesToPool(returned);
    }
    _refill(targetRound);
  }

  DeckCandidateV3? _candidateForOccurrence(String occurrenceId) =>
      _allDeckCandidates
          .where((item) => item.occurrenceId == occurrenceId)
          .firstOrNull;

  void _returnCandidatesToPool(Iterable<DeckCandidateV3> candidates) {
    for (final candidate in candidates) {
      if (_spiceProgression.consumedOccurrenceIds.contains(
        candidate.occurrenceId,
      )) {
        continue;
      }
      if (!_faceToFaceDeck.any(
        (item) => item.occurrenceId == candidate.occurrenceId,
      )) {
        _faceToFaceDeck.add(candidate);
      }
      if (!_distanceDeck.any(
        (item) => item.occurrenceId == candidate.occurrenceId,
      )) {
        _distanceDeck.add(candidate);
      }
    }
  }

  void _ensurePlayableHand(int targetRound) {
    final handOccurrences = <V4PlayableOccurrence>[];
    for (final card in _runtime.where((item) => item.zone == CardZone.HAND)) {
      final candidate = _candidateForOccurrence(card.occurrenceId);
      if (candidate == null) continue;
      final parameters =
          _resolvedParameters[card.occurrenceId] ??
          const V4ResolvedParameters();
      handOccurrences.add(
        V4PlayableOccurrence(
          candidate: candidate,
          parameters: parameters,
          playable: _isPlayableInPresence(candidate, parameters, _presence),
          locked: card.locked,
        ),
      );
    }
    final activeIds = _runtime.map((item) => item.occurrenceId).toSet();
    final pool = const V4ContextualPool().project(
      allCandidates: _allDeckCandidates.where(_candidateAccessoryCompatible),
      progression: _spiceProgression,
      context: _poolContext(),
      inHandOccurrenceIds: activeIds,
    );
    final available = <V4PlayableOccurrence>[];
    for (final candidate in pool.drawable) {
      final parameters =
          _resolvedParameters[candidate.occurrenceId] ??
          _resolveDrawParameters(candidate, targetRound);
      if (parameters == null) continue;
      available.add(
        V4PlayableOccurrence(
          candidate: candidate,
          parameters: parameters,
          playable: _isPlayableInPresence(candidate, parameters, _presence),
        ),
      );
    }
    final guarded = const V4PlayableHandGuard().ensurePlayable(
      hand: handOccurrences,
      availablePool: available,
      random: Random(_stableHash('$playerId/$targetRound/hand-guard')),
    );
    if (guarded.length == handOccurrences.length &&
        guarded.indexed.every(
          (entry) =>
              entry.$2.candidate.occurrenceId ==
              handOccurrences[entry.$1].candidate.occurrenceId,
        )) {
      return;
    }
    final guardedIds = guarded
        .map((item) => item.candidate.occurrenceId)
        .toSet();
    final returned = handOccurrences
        .where((item) => !guardedIds.contains(item.candidate.occurrenceId))
        .map((item) => item.candidate)
        .toList();
    final added = guarded
        .where(
          (item) => !handOccurrences.any(
            (old) => old.candidate.occurrenceId == item.candidate.occurrenceId,
          ),
        )
        .toList();
    final returnedIds = returned.map((item) => item.occurrenceId).toSet();
    _runtime = [
      for (final card in _runtime)
        if (!returnedIds.contains(card.occurrenceId)) card,
    ];
    _returnCandidatesToPool(returned);
    for (final item in added) {
      final selection = _directionFor(item.candidate);
      if (selection == null) continue;
      _runtime = [
        ..._runtime,
        CardRuntimeState(
          cardId: item.candidate.cardId,
          occurrenceId: item.candidate.occurrenceId,
          variantId: item.candidate.variantId,
          zone: CardZone.HAND,
          nativeDirection: selection.nativeDirection,
          effectiveDirection: selection.effectiveDirection,
        ),
      ];
      _resolvedParameters[item.candidate.occurrenceId] = item.parameters;
      _faceToFaceDeck.removeWhere(
        (candidate) => candidate.occurrenceId == item.candidate.occurrenceId,
      );
      _distanceDeck.removeWhere(
        (candidate) => candidate.occurrenceId == item.candidate.occurrenceId,
      );
    }
  }

  V4ResolvedParameters? _resolveDrawParameters(
    DeckCandidateV3 candidate,
    int targetRound,
  ) {
    if (candidate.requiredAccessoriesAnyOf.isEmpty) {
      return const V4ResolvedParameters();
    }
    final requirements = V4AccessoryRequirements.fromTokens(
      candidate.requiredAccessoriesAnyOf,
    );
    final direction = _directionFor(candidate)?.effectiveDirection;
    if (direction == null) return null;
    final compatible = _accessoryPool.available
        .where(requirements.accepts)
        .where((item) => _accessoryAllowedForDirection(item, direction))
        .toList();
    if (compatible.isEmpty) return null;
    final random = Random(
      _stableHash('$playerId/$targetRound/${candidate.occurrenceId}/accessory'),
    );
    final selected = compatible[random.nextInt(compatible.length)];
    return V4ResolvedParameters(accessoryId: selected.id);
  }

  bool _candidateAccessoryCompatible(DeckCandidateV3 candidate) {
    if (candidate.requiredAccessoriesAnyOf.isEmpty) return true;
    final requirements = V4AccessoryRequirements.fromTokens(
      candidate.requiredAccessoriesAnyOf,
    );
    final direction = _directionFor(candidate)?.effectiveDirection;
    return direction != null &&
        _accessoryPool.available.any(
          (item) =>
              requirements.accepts(item) &&
              _accessoryAllowedForDirection(item, direction),
        );
  }

  bool _accessoryAllowedForDirection(
    V4Accessory accessory,
    CardOccurrenceDirection direction,
  ) {
    final profile = _v4Profile;
    if (profile == null) return true;
    final preferences = profile.accessoryPreferencesForExactTags({
      for (final tag in accessory.tags) tag.name.toUpperCase(),
    });
    final roles = switch (direction) {
      CardOccurrenceDirection.FAIRE => const [ProfilePreferenceRole.faire],
      CardOccurrenceDirection.RECEVOIR => const [
        ProfilePreferenceRole.recevoir,
      ],
      CardOccurrenceDirection.SOLO => const [ProfilePreferenceRole.soi],
      CardOccurrenceDirection.MUTUEL => const [
        ProfilePreferenceRole.faire,
        ProfilePreferenceRole.recevoir,
      ],
      _ => const <ProfilePreferenceRole>[],
    };
    return roles.every((role) => preferences[role] != null);
  }

  void _buildDeckCycle() {
    final source = _catalogCandidates();
    _allDeckCandidates = List.of(source);
    _spiceProgression = V4SpiceProgression.fromCandidates(
      source,
      unlockedLevel: _spiceProgression.unlockedLevel,
    );
    _syncSpiceContext();
    _faceToFaceDeck = List.of(source);
    _distanceDeck = List.of(source);
    _deckShortages = [];
  }

  List<DeckCandidateV3> _catalogCandidates() {
    final source = <DeckCandidateV3>[];
    for (final definition in _definitions.values) {
      final engine = _engineCards[definition.stableId];
      if (engine == null) continue;
      final context = _context.copyWith(
        proximity: ProximityState.TOGETHER,
        chiliActive: 4,
        chiliUnlocked: 4,
        clothesByPlayer: {for (final id in playerIds) id: 999},
        accessories: const {
          'SEXTOY',
          'VIBRATING_TOY',
          'REMOTE_CONTROL_TOY',
          'CONSTRAINT_ACCESSORY',
          'OIL',
          'LUBRICANT',
          'PROTECTION',
          'FOOD',
          'DRINK',
        },
      );
      final eligible = const EligibilityEngine().evaluate(
        card: engine,
        context: context,
        actor: _profile(playerId),
        partner: _profile(opponentId),
        hierarchy: _hierarchy,
        requirePersonalValue: true,
      );
      for (final variant in eligible.eligibleVariants) {
        final editorialVariant = definition.variants
            .where((item) => item.stableId == variant.id)
            .firstOrNull;
        if (editorialVariant == null) continue;
        final distanceExcluded = variant.tags.contains(
          'v3.technique.distance_exclue',
        );
        final candidate = DeckCandidateV3(
          cardId: definition.stableId,
          variantId: variant.id,
          spiceLevel: variant.chiliLevel,
          distanceExcluded: distanceExcluded,
          stage: editorialVariant.v4Stage ?? 1,
          sequenceKey: _sequenceKey(
            editorialVariant.stableId,
            editorialVariant.v4Stage,
          ),
          presence:
              editorialVariant.v4Presence ??
              definition.v4?.presence ??
              (distanceExcluded
                  ? V4PresenceCompatibility.presentiel
                  : V4PresenceCompatibility.both),
          requiredAccessoriesAnyOf:
              editorialVariant.v4RequiredAccessoriesAnyOf ??
              definition.v4?.requiredAccessoriesAnyOf ??
              const [],
          poolMultiplicity:
              definition.v4?.poolMultiplicity ?? V4PoolMultiplicity.standard,
        );
        if (_directionFor(candidate) != null) source.add(candidate);
      }
    }
    return const V4PoolMaterializer().materialize(
      candidates: source,
      totalRemovableClothing: _context.clothesByPlayer.values.fold(
        0,
        (sum, value) => sum + value,
      ),
    );
  }

  V4SpiceProgression _legacyProgression(NetworkPrivateGameState saved) {
    var progression = V4SpiceProgression.fromCandidates(_allDeckCandidates);
    final consumed = <String>{
      for (final card in saved.cards)
        if ((card.zone == CardZone.DISCARD ||
                card.zone == CardZone.EXHAUSTED) &&
            card.occurrenceId.isNotEmpty)
          card.occurrenceId,
      for (final card in saved.publicDiscards)
        card.occurrenceId.isEmpty ? card.variantId : card.occurrenceId,
    };
    for (final occurrenceId in consumed) {
      progression = progression.consume(occurrenceId, _allDeckCandidates);
    }
    return progression;
  }

  List<CardRuntimeState> _normalizeRuntimeOccurrences(
    Iterable<CardRuntimeState> cards,
  ) {
    final used = <String>{};
    return [
      for (final card in cards)
        if (_allDeckCandidates
                .where(
                  (candidate) =>
                      candidate.occurrenceId == card.occurrenceId &&
                      used.add(candidate.occurrenceId),
                )
                .firstOrNull
            case final exact?)
          _runtimeWithOccurrence(card, exact.occurrenceId)
        else if (_allDeckCandidates
                .where(
                  (candidate) =>
                      candidate.variantId == card.variantId &&
                      !used.contains(candidate.occurrenceId),
                )
                .firstOrNull
            case final migrated?)
          _runtimeWithOccurrence(card, migrated.occurrenceId, onUse: used.add)
        else
          card,
    ];
  }

  CardRuntimeState _runtimeWithOccurrence(
    CardRuntimeState card,
    String occurrenceId, {
    bool Function(String)? onUse,
  }) {
    onUse?.call(occurrenceId);
    return CardRuntimeState(
      cardId: card.cardId,
      occurrenceId: occurrenceId,
      variantId: card.variantId,
      zone: card.zone,
      locked: card.locked,
      nativeDirection: card.nativeDirection,
      effectiveDirection: card.effectiveDirection,
    );
  }

  V4SpiceProgression _normalizeProgression(V4SpiceProgression saved) {
    var normalized = V4SpiceProgression.fromCandidates(
      _allDeckCandidates,
      unlockedLevel: saved.unlockedLevel,
    );
    for (final identity in saved.consumedOccurrenceIds) {
      normalized = normalized.consume(identity, _allDeckCandidates);
    }
    return normalized;
  }

  static String _sequenceKey(String variantId, int? stage) => stage == null
      ? variantId
      : variantId.replaceFirst(RegExp(r'\.s\d+$'), '');

  void _consumeEngagedVariants() {
    for (final card in _runtime.where(
      (card) => card.zone == CardZone.ENGAGED && card.variantId != null,
    )) {
      _consumeOccurrence(card.occurrenceId);
    }
  }

  void _consumeOccurrence(String occurrenceId) {
    _spiceProgression = _spiceProgression.consume(
      occurrenceId,
      _allDeckCandidates,
    );
    _faceToFaceDeck.removeWhere((card) => card.occurrenceId == occurrenceId);
    _distanceDeck.removeWhere((card) => card.occurrenceId == occurrenceId);
    _resolvedParameters.remove(occurrenceId);
    _syncSpiceContext();
  }

  V4PoolContext _poolContext() => V4PoolContext(
    presence: _presence,
    availableAccessories: _context.accessories,
  );

  int _availablePlayableOccurrences(V4SessionPresence presence) {
    final handPlayable = _runtime
        .where((card) => card.zone == CardZone.HAND)
        .where((card) {
          final candidate = _candidateForOccurrence(card.occurrenceId);
          if (candidate == null) return false;
          final parameters =
              _resolvedParameters[card.occurrenceId] ??
              const V4ResolvedParameters();
          return _isPlayableInPresence(candidate, parameters, presence);
        })
        .length;
    final activeIds = _runtime.map((card) => card.occurrenceId).toSet();
    final pool = const V4ContextualPool().project(
      allCandidates: _allDeckCandidates.where(_candidateAccessoryCompatible),
      progression: _spiceProgression,
      context: V4PoolContext(
        presence: presence,
        availableAccessories: _context.accessories,
      ),
      inHandOccurrenceIds: activeIds,
    );
    final drawablePlayable = pool.drawable.where((candidate) {
      final parameters =
          _resolvedParameters[candidate.occurrenceId] ??
          const V4ResolvedParameters();
      return _isPlayableInPresence(candidate, parameters, presence);
    }).length;
    return handPlayable + drawablePlayable;
  }

  bool _isPlayableInPresence(
    DeckCandidateV3 candidate,
    V4ResolvedParameters parameters,
    V4SessionPresence presence,
  ) =>
      _spiceProgression.isPlayable(
        parameters.effectiveSpice(candidate.spiceLevel),
      ) &&
      const V4ContextualPool().isContextuallyEligible(
        candidate,
        V4PoolContext(
          presence: presence,
          availableAccessories: _context.accessories,
        ),
      );

  void _syncSpiceContext() {
    _context = _context.copyWith(
      chiliActive: _spiceProgression.unlockedLevel,
      chiliUnlocked: _spiceProgression.unlockedLevel,
    );
  }

  NetworkDuelCard? _networkCard(
    String cardId, {
    String? occurrenceId,
    String? variantId,
    EngineSessionContext? context,
  }) {
    final definition = _definitions[cardId];
    final engine = _engineCards[cardId];
    if (definition == null || engine == null) return null;
    final eligible = variantId == null
        ? const EligibilityEngine()
              .evaluate(
                card: engine,
                context: context ?? _context,
                actor: _profile(playerId),
                partner: _profile(opponentId),
                hierarchy: _hierarchy,
                requirePersonalValue: true,
              )
              .eligibleVariants
              .firstOrNull
        : engine.variants.where((item) => item.id == variantId).firstOrNull;
    if (eligible == null) return null;
    final variant = definition.variants.firstWhere(
      (item) => item.stableId == eligible.id,
    );
    final occurrence = occurrenceId == null
        ? null
        : _runtime
              .where((item) => item.occurrenceId == occurrenceId)
              .firstOrNull;
    final role = _profileRole(
      occurrence?.effectiveDirection ?? _fixedDirection(definition, variant),
      fallback: _roleFor(definition, variant),
    );
    final v4Rating = _v4PersonalRating(
      definition.stableId,
      variant.stableId,
      occurrence?.effectiveDirection ?? _fixedDirection(definition, variant),
      occurrenceId: occurrenceId,
    );
    if (v4Rating?.excluded ?? false) return null;
    final elementId =
        eligible.tags
            .where((tag) => tag.startsWith('v3.preference.'))
            .firstOrNull ??
        _legacyElementId(definition, variant, role);
    final activeValue = v4Rating?.value ?? _privateValue(elementId, role);
    if (activeValue == null) return null;
    final faireValue = _v4PersonalRating(
      definition.stableId,
      variant.stableId,
      CardOccurrenceDirection.FAIRE,
      occurrenceId: occurrenceId,
    );
    final recevoirValue = _v4PersonalRating(
      definition.stableId,
      variant.stableId,
      CardOccurrenceDirection.RECEVOIR,
      occurrenceId: occurrenceId,
    );
    return NetworkDuelCard(
      definition: definition,
      engine: engine,
      variant: eligible,
      role: role,
      preference: _preference(
        elementId,
        role,
        activeValue,
        faire: faireValue == null
            ? _privateValue(elementId, ProfileRole.FAIRE)
            : faireValue.value,
        recevoir: recevoirValue == null
            ? _privateValue(elementId, ProfileRole.RECEVOIR)
            : recevoirValue.value,
      ),
      occurrenceId: occurrenceId,
      nativeDirection:
          occurrence?.nativeDirection ?? _fixedDirection(definition, variant),
      effectiveDirection:
          occurrence?.effectiveDirection ??
          _fixedDirection(definition, variant),
      resolvedChiliLevel: occurrenceId == null
          ? null
          : (_resolvedParameters[occurrenceId] ?? const V4ResolvedParameters())
                .effectiveSpice(variant.chiliLevel),
    );
  }

  ({int? value, bool excluded})? _v4PersonalRating(
    String cardId,
    String variantId,
    CardOccurrenceDirection direction, {
    String? occurrenceId,
  }) {
    final profile = _v4Profile;
    final scoring = _scoringCatalog;
    if (profile == null || scoring == null) return null;
    final card = scoring.cards
        .where((item) => item.cardId == cardId)
        .firstOrNull;
    final variant = card?.variants
        .where((item) => item.variantId == variantId)
        .firstOrNull;
    if (variant == null) return null;
    final roles = switch (direction) {
      CardOccurrenceDirection.FAIRE => const [ProfilePreferenceRole.faire],
      CardOccurrenceDirection.RECEVOIR => const [
        ProfilePreferenceRole.recevoir,
      ],
      CardOccurrenceDirection.MUTUEL => const [
        ProfilePreferenceRole.faire,
        ProfilePreferenceRole.recevoir,
      ],
      CardOccurrenceDirection.SOLO => const [
        ProfilePreferenceRole.soi,
        ProfilePreferenceRole.solo,
      ],
      CardOccurrenceDirection.SIMULTANE => const [
        ProfilePreferenceRole.simultane,
      ],
      _ => const [ProfilePreferenceRole.general],
    };
    final values = <double>[];
    for (final role in roles) {
      final result = const V4CardRatingEngine().initialize(
        profile: profile,
        variant: variant,
        effectiveRole: role,
      );
      if (result.kind == V4RatingResultKind.excluded) {
        return (value: null, excluded: true);
      }
      if (result.kind == V4RatingResultKind.rated) {
        values.add(result.rawScore!);
        if (direction == CardOccurrenceDirection.SOLO) break;
      }
    }
    final accessoryId = occurrenceId == null
        ? null
        : _resolvedParameters[occurrenceId]?.accessoryId;
    final accessory = accessoryId == null
        ? null
        : _accessoryPool.available
              .where((item) => item.id == accessoryId)
              .firstOrNull;
    if (accessory != null) {
      final preferences = profile.accessoryPreferencesForExactTags({
        for (final tag in accessory.tags) tag.name.toUpperCase(),
      });
      final accessoryRoles = switch (direction) {
        CardOccurrenceDirection.FAIRE => const [ProfilePreferenceRole.faire],
        CardOccurrenceDirection.RECEVOIR => const [
          ProfilePreferenceRole.recevoir,
        ],
        CardOccurrenceDirection.SOLO => const [ProfilePreferenceRole.soi],
        CardOccurrenceDirection.MUTUEL => const [
          ProfilePreferenceRole.faire,
          ProfilePreferenceRole.recevoir,
        ],
        _ => const <ProfilePreferenceRole>[],
      };
      for (final role in accessoryRoles) {
        final value = preferences[role];
        if (value == null) return (value: null, excluded: true);
        values.add(value);
      }
    }
    return (
      value: values.isEmpty ? null : const V4PaCalculator().combine(values),
      excluded: false,
    );
  }

  void _closePersistentEffects() {
    final produced = <V4PersistentEffect>[];
    final result = finalResolution;
    final resolvedCards = result == null || result.mutualAbandon
        ? const <NetworkCompromiseCardDto>[]
        : result.compromise.isNotEmpty
        ? result.compromise
        : result.cardId == null
        ? const <NetworkCompromiseCardDto>[]
        : [
            NetworkCompromiseCardDto(
              occurrenceId: result.cardId!,
              cardId: result.cardId!,
              variantId: result.variantId ?? '',
              ownerPlayerId:
                  result.retainedPlayerId ??
                  result.finalWinnerPlayerId ??
                  playerId,
              nativeDirection: NetworkCardDirection.GENERAL,
              effectiveDirection: NetworkCardDirection.GENERAL,
              origin: NetworkCompromiseOrigin.INITIAL_DUEL,
              snapshotValue: 0,
            ),
          ];
    for (final card in resolvedCards) {
      final definition = _definitions[card.cardId];
      final duration = definition?.v4?.durationActions;
      if (duration != null) {
        final projected = actionProjection?.cards
            .where((item) => item.occurrenceId == card.occurrenceId)
            .firstOrNull;
        final targets =
            projected?.targetPlayerIds ??
            const V4ActionTargetResolver().resolve(
              ownerPlayerId: card.ownerPlayerId,
              playerIds: playerIds,
              direction: CardOccurrenceDirection.values.byName(
                card.effectiveDirection.name,
              ),
            );
        produced.addAll(
          const V4PersistentEffectEngine().createForAction(
            cardId: card.cardId,
            targetPlayerIds: targets,
            durationActions: duration,
          ),
        );
      }
    }
    _persistentEffects = const V4PersistentEffectEngine().closeAction(
      activeBeforeAction: _persistentEffects,
      producedEffects: produced,
    );
  }

  NetworkDuelCard? _networkRecoveryCard(
    String cardId, {
    String? occurrenceId,
    String? variantId,
  }) {
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
    final eligible = variantId == null
        ? recoveryEngine
              .actionEligibility(
                card: engine,
                context: recoveryContext,
                actor: _profile(playerId),
                partner: _profile(opponentId),
                hierarchy: _hierarchy,
              )
              .eligibleVariants
              .firstOrNull
        : engine.variants.where((item) => item.id == variantId).firstOrNull;
    if (eligible == null) return null;
    final variant = definition.variants.firstWhere(
      (item) => item.stableId == eligible.id,
    );
    final occurrence = occurrenceId == null
        ? null
        : _runtime
              .where((item) => item.occurrenceId == occurrenceId)
              .firstOrNull;
    final role = _profileRole(
      occurrence?.effectiveDirection ?? _fixedDirection(definition, variant),
      fallback: _roleFor(definition, variant),
    );
    final elementId =
        eligible.tags
            .where((tag) => tag.startsWith('v3.preference.'))
            .firstOrNull ??
        _legacyElementId(definition, variant, role);
    final activeValue = _privateValue(elementId, role);
    if (activeValue == null) return null;
    return NetworkDuelCard(
      definition: definition,
      engine: engine,
      variant: eligible,
      role: role,
      preference: _preference(
        elementId,
        role,
        activeValue,
        faire: _privateValue(elementId, ProfileRole.FAIRE),
        recevoir: _privateValue(elementId, ProfileRole.RECEVOIR),
      ),
      occurrenceId: occurrenceId,
      nativeDirection:
          occurrence?.nativeDirection ?? _fixedDirection(definition, variant),
      effectiveDirection:
          occurrence?.effectiveDirection ??
          _fixedDirection(definition, variant),
    );
  }

  int _recoveryGain(NetworkRecoveryDto proposal) {
    final card = _networkRecoveryCard(
      proposal.cardId,
      occurrenceId: proposal.occurrenceId,
      variantId: proposal.variantId,
    );
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
      final card = auctionCards
          .where((item) => item.identity == id)
          .firstOrNull;
      if (card == null) throw ArgumentError('Carte d’enchère indisponible');
      final direction = _networkDirection(card);
      final parameters =
          _resolvedParameters[card.identity] ?? const V4ResolvedParameters();
      cards.add(
        NetworkCompromiseCardDto(
          occurrenceId: card.identity,
          cardId: card.id,
          variantId: card.variant.id,
          ownerPlayerId: playerId,
          nativeDirection: direction,
          effectiveDirection: direction,
          origin: NetworkCompromiseOrigin.AUCTION,
          snapshotValue: card.personalValue,
          logicalOrder: cards.length + 1,
          resolvedParameters: parameters,
          effectiveSpice: parameters.effectiveSpice(card.chiliLevel),
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

  PlayerGameProfile _profile(String id) {
    if (id == playerId && _privateProfile != null) return _privateProfile;
    return PlayerGameProfile(
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
  }

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
      deckStyle: _deckStyle,
      deckShortages: _deckShortages,
      recentCardIds: _recentCardIds,
      publicDiscards: _publicDiscards,
      choiceVersion: _choiceVersion,
      spiceProgression: _spiceProgression,
      availableAccessories: _context.accessories,
      clothesByPlayer: _context.clothesByPlayer,
      sessionMode: sessionMode,
      presence: _presence,
      resolvedParameters: _resolvedParameters,
      persistentEffects: _persistentEffects,
      accessoryPool: _accessoryPool,
    ),
  );

  void _capturePublicDiscards(NetworkGameRoundStateDto value) {
    if (value.finalResolution == null) return;
    final known = _publicDiscards.map((card) => card.occurrenceId).toSet();
    void add(String cardId, String variantId, String occurrenceId) {
      if (!known.add(occurrenceId)) return;
      _publicDiscards = [
        ..._publicDiscards,
        NetworkPlayedCardRecord(
          cardId: cardId,
          variantId: variantId,
          occurrenceId: occurrenceId,
          roundNumber: value.roundNumber,
        ),
      ];
    }

    for (final reveal in [value.ownReveal, value.opponentReveal]) {
      if (reveal == null) continue;
      add(
        reveal.choice.cardId,
        reveal.choice.variantId,
        (reveal.choice.parameters['occurrence_id'] as String?) ??
            '${value.roundId}:${reveal.playerId}',
      );
    }
    for (final card in value.finalResolution!.compromise) {
      add(card.cardId, card.variantId, card.occurrenceId);
    }
  }

  void _rememberRecent(Iterable<String> cardIds) {
    _recentCardIds = [
      ..._recentCardIds,
      ...cardIds,
    ].reversed.toSet().take(4).toList().reversed.toList();
  }

  NetworkCommandDto _command(
    String type, {
    String? roundId,
    int? roundNumber,
    int? choiceVersion,
  }) {
    final number = roundNumber ?? this.roundNumber;
    final id = roundId ?? round?.roundId;
    return NetworkCommandDto(
      commandId:
          'game:${session.id}:round-$number:$playerId:${type.toLowerCase()}${choiceVersion == null ? '' : ':v$choiceVersion'}',
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
    int value, {
    int? faire,
    int? recevoir,
  }) => UserPreference.fromJson({
    'profile_element_id': elementId,
    'status': PreferenceStatus.ACCEPTED.name,
    'general_value': role == ProfileRole.GENERAL ? value : null,
    'faire_value': faire ?? (role == ProfileRole.FAIRE ? value : null),
    'recevoir_value': recevoir ?? (role == ProfileRole.RECEVOIR ? value : null),
    'updated_at': DateTime.utc(2026, 1, 1).toIso8601String(),
    'source': PreferenceSource.ONBOARDING.name,
  });

  CardDirectionSelection? _directionFor(DeckCandidateV3 candidate) {
    final definition = _definitions[candidate.cardId];
    final variant = definition?.variants
        .where((item) => item.stableId == candidate.variantId)
        .firstOrNull;
    if (definition == null || variant == null) return null;
    final fixed = _fixedDirection(definition, variant);
    final reversible = _isReversible(definition, variant);
    final preferenceIds =
        (variant.v3?.tags ?? definition.v3?.tags ?? const <String>[])
            .where((tag) => tag.startsWith('v3.preference.'))
            .toList();
    if (preferenceIds.isEmpty) {
      preferenceIds.add(
        _legacyElementId(definition, variant, ProfileRole.GENERAL),
      );
    }
    final profile = _profile(playerId);
    final faireRating = _v4PersonalRating(
      candidate.cardId,
      candidate.variantId,
      CardOccurrenceDirection.FAIRE,
    );
    final recevoirRating = _v4PersonalRating(
      candidate.cardId,
      candidate.variantId,
      CardOccurrenceDirection.RECEVOIR,
    );
    final faireAllowed = faireRating == null
        ? preferenceIds.every((elementId) {
            final preference = profile.preference(elementId);
            return preference.status == PreferenceStatus.ACCEPTED &&
                preference.faire != null;
          })
        : !faireRating.excluded && faireRating.value != null;
    final recevoirAllowed = recevoirRating == null
        ? preferenceIds.every((elementId) {
            final preference = profile.preference(elementId);
            return preference.status == PreferenceStatus.ACCEPTED &&
                preference.recevoir != null;
          })
        : !recevoirRating.excluded && recevoirRating.value != null;
    if (!reversible && _v4Profile != null && _scoringCatalog != null) {
      final fixedRating = _v4PersonalRating(
        candidate.cardId,
        candidate.variantId,
        fixed,
      );
      if (fixedRating == null ||
          fixedRating.excluded ||
          fixedRating.value == null) {
        return null;
      }
    }
    try {
      return const CardDirectionEngine().select(
        reversible: reversible,
        fixedDirection: fixed,
        faireAllowed: faireAllowed,
        recevoirAllowed: recevoirAllowed,
        chooseFaire: Random(
          _stableHash(
            '${session.id}/$playerId/${candidate.occurrenceId}/direction',
          ),
        ).nextBool(),
      );
    } on StateError {
      return null;
    }
  }

  static ProfileRole _profileRole(
    CardOccurrenceDirection direction, {
    required ProfileRole fallback,
  }) => switch (direction) {
    CardOccurrenceDirection.FAIRE => ProfileRole.FAIRE,
    CardOccurrenceDirection.RECEVOIR => ProfileRole.RECEVOIR,
    _ => fallback,
  };

  static CardOccurrenceDirection _fixedDirection(
    CardDefinition card,
    CardVariantDefinition variant,
  ) {
    final tags = variant.v3?.tags ?? card.v3?.tags ?? const <String>[];
    if (tags.contains('v3.direction.mutuel')) {
      return CardOccurrenceDirection.MUTUEL;
    }
    if (tags.contains('v3.direction.simultane')) {
      return CardOccurrenceDirection.SIMULTANE;
    }
    if (tags.contains('v3.direction.solo')) return CardOccurrenceDirection.SOLO;
    if (tags.contains('v3.direction.recevoir')) {
      return CardOccurrenceDirection.RECEVOIR;
    }
    if (tags.contains('v3.direction.faire')) {
      return CardOccurrenceDirection.FAIRE;
    }
    return CardOccurrenceDirection.GENERAL;
  }

  static bool _isReversible(
    CardDefinition card,
    CardVariantDefinition variant,
  ) {
    final direction = _fixedDirection(card, variant);
    return (variant.inversionOverride ?? card.inversionPolicy) ==
            InversionPolicy.SWAP_ACTOR_TARGET &&
        (direction == CardOccurrenceDirection.FAIRE ||
            direction == CardOccurrenceDirection.RECEVOIR);
  }

  int _fixtureValue(String id, String element, ProfileRole role) =>
      8 + (_stableHash('$id/$element/${role.name}') % 11);

  int? _privateValue(String elementId, ProfileRole role) {
    final profile = _privateProfile;
    if (profile == null) return _fixtureValue(playerId, elementId, role);
    return profile.preference(elementId).valueFor(role);
  }

  static int _stableHash(String value) {
    var hash = 17;
    for (final unit in value.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return hash;
  }

  static V4ResolvedParameters _keepOccurrenceParameters(
    NetworkDuelCard _,
    V4ResolvedParameters current,
  ) => current;

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
