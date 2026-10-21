import 'dart:async';
import 'dart:convert';
import 'dart:math';
import '../../core/json.dart';
import '../../sync/projection/usage_learning_projection.dart';

import 'package:flutter/foundation.dart';

import '../../domain/domain.dart';
import '../../engines/engines.dart';
import '../../sync/sync.dart';
import '../lobby/lobby_models.dart';
import 'network_duel_controller.dart' show NetworkDuelCard;
import 'network_duel_secret_store.dart';
import 'network_profile_learning.dart';
import '../../engines/eligibility/concept_runtime_catalog.dart';
import '../../engines/eligibility/concept_action_options.dart';

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
    this.negotiationEngine = const NegotiationEngineV3(),
    this.lifecycleEngine = const LifecycleEngine(),
    this.recoveryEngine = const RecoveryEngine(),
    NetworkProfileLearningStore? learningStore,
    V4CardLearningStore? cardLearningStore,
    PostGameProfileChoiceStore? profileChoiceStore,
    PlayerGameProfile? privateProfile,
    EngineSessionContext? initialContext,
    V4Profile? v4Profile,
    V4ScoringCatalog? scoringCatalog,
    Set<String> availableAccessories = const {},
    V4SessionMode sessionMode = V4SessionMode.presentiel,
    Map<String, int> initialClothingCounts = const {},
    Iterable<V4Accessory> profileAccessories = const [],
    Iterable<String> disabledAccessoryIds = const [],
    Iterable<V4Accessory> temporaryAccessories = const [],
    this.reconciliationInterval = const Duration(seconds: 8),
    this.watchRetryDelay = const Duration(seconds: 2),
    DateTime Function()? clock,
    String Function()? nonceFactory,
  }) : _catalog = catalog,
       _privateProfile = privateProfile,
       _v4Profile = v4Profile,
       clock = clock ?? DateTime.now,
       nonceFactory = nonceFactory ?? _secureNonce {
    final ids = session.players.map((player) => player.userId).toList()..sort();
    if (!session.ready || !ids.contains(playerId)) {
      throw ArgumentError('A ready lobby membership is required');
    }
    playerIds = List.unmodifiable(ids);
    if (catalog.concepts == null || catalog.conceptRules == null) {
      throw ArgumentError(
        'Concept catalogue and validated runtime bindings are required',
      );
    }
    _conceptCatalog = ConceptRuntimeCatalog(
      concepts: catalog.concepts!,
      source: catalog,
      rules: catalog.conceptRules!,
    );
    _definitions = _conceptCatalog.definitions;
    _engineCards = {
      for (final card in _definitions.values)
        card.stableId: const CatalogEngineAdapter.v3().card(card),
    };
    _hierarchy = ProfileHierarchy({
      for (final element in catalog.profileElements)
        element.stableId: element.parentId,
    });
    _sessionMode = sessionMode;
    _presence = sessionMode == V4SessionMode.distance
        ? V4SessionPresence.distance
        : V4SessionPresence.presentiel;
    _accessoryPool = V4SessionAccessoryPool(
      profileAccessories: profileAccessories,
      disabledIds: disabledAccessoryIds,
      temporaryAccessories: temporaryAccessories,
    );
    _context =
        initialContext ??
        EngineSessionContext(
          mode: switch (sessionMode) {
            V4SessionMode.presentiel => SessionMode.face_to_face,
            V4SessionMode.distance => SessionMode.distance,
            V4SessionMode.hybrid => SessionMode.hybrid,
          },
          proximity: _presence == V4SessionPresence.distance
              ? ProximityState.SEPARATED
              : ProximityState.TOGETHER,
          chiliActive: 1,
          chiliUnlocked: 1,
          accessories: availableAccessories,
          physicalStateByPlayer: {for (final id in playerIds) id: 'available'},
          clothesByPlayer: {
            for (final id in playerIds) id: initialClothingCounts[id] ?? 0,
          },
        );
    _initialClothing = _context.clothesByPlayer[playerId] ?? 0;
    _buildDeckCycle();
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
    _cardLearningStore =
        cardLearningStore ??
        (learningStore is MemoryNetworkProfileLearningStore
            ? MemoryV4CardLearningStore()
            : const SharedPreferencesV4CardLearningStore());
  }

  final LobbySession session;
  final String playerId;
  final NetworkGameRepository repository;
  final NetworkDuelSecretStore privateStore;
  final CommitRevealContract contract;
  final DuelEngine duelEngine;
  final NegotiationEngineV3 negotiationEngine;
  final LifecycleEngine lifecycleEngine;
  final RecoveryEngine recoveryEngine;
  final DateTime Function() clock;
  final String Function() nonceFactory;
  late final NetworkProfileLearningCoordinator learning;
  late final PostGameProfileChoiceStore _profileChoiceStore;
  late final V4CardLearningStore _cardLearningStore;
  CardSpecificLearningStore _cardRatings = CardSpecificLearningStore();
  Future<void> reloadPrivateCardRatings() async {
    _cardRatings = await _cardLearningStore.load(playerId);
    if (_disposed) return;
    if (_activeReveal == null &&
        selectedCard != null &&
        _selectedOption != null) {
      final current = choicesFor(
        selectedCard!.id,
      ).where((o) => o.key == _selectedOption!.key).firstOrNull;
      if (current == null) {
        await cancelPendingSelection();
      } else {
        chooseAction(current);
      }
    }
    notifyListeners();
  }

  final Catalog _catalog;
  final Duration reconciliationInterval;
  final Duration watchRetryDelay;
  Timer? _reconciliationTimer;
  Timer? _watchRetryTimer;
  bool _refreshingCanonical = false;
  int _watchGeneration = 0;
  Object? lastSynchronizationError;

  void _ensureReconciliation() {
    _reconciliationTimer ??= Timer.periodic(reconciliationInterval, (_) {
      final phase = round?.phase;
      if (phase == NetworkGamePhase.commit ||
          phase == NetworkGamePhase.reveal ||
          phase == NetworkGamePhase.ready) {
        unawaited(_refreshCanonical());
      }
    });
  }

  Future<void> _refreshCanonical() async {
    if (_disposed || _localSessionCleared || _refreshingCanonical) return;
    _refreshingCanonical = true;
    try {
      final value = await repository.getCurrentRound(sessionId: session.id);
      if (!_disposed) await _apply(value);
    } catch (error, stack) {
      lastSynchronizationError = error;
      debugPrint('Canonical round reconciliation failed: $error');
      debugPrint(stack.toString());
    } finally {
      _refreshingCanonical = false;
    }
  }

  void _watchRound(NetworkGameRoundStateDto value) {
    if (_disposed || _localSessionCleared) return;
    final generation = ++_watchGeneration;
    _watchRetryTimer?.cancel();
    final previous = _subscription;
    _subscription = null;
    if (previous != null) unawaited(previous.cancel());
    void restart([Object? error, StackTrace? stack]) {
      if (_disposed || generation != _watchGeneration) return;
      if (error != null) {
        lastSynchronizationError = error;
        debugPrint('Round surveillance interrupted: $error');
        if (stack != null) debugPrint(stack.toString());
      }
      final ended = _subscription;
      _subscription = null;
      if (ended != null) unawaited(ended.cancel());
      if (_watchRetryTimer?.isActive == true) return;
      _watchRetryTimer = Timer(watchRetryDelay, () {
        if (_disposed || generation != _watchGeneration) return;
        _watchRound(round ?? value);
        unawaited(_refreshCanonical());
      });
    }

    _subscription = repository
        .watchRound(sessionId: session.id, roundId: value.roundId)
        .listen(
          (update) => unawaited(
            _apply(update).catchError((Object error, StackTrace stack) {
              lastSynchronizationError = error;
              debugPrint('Round snapshot application failed: $error');
              debugPrint(stack.toString());
              _fail(error);
            }),
          ),
          onError: (Object error, StackTrace stack) => restart(error, stack),
          onDone: restart,
        );
  }

  late final ConceptRuntimeCatalog _conceptCatalog;
  late ConceptUsageCheckpoint _usageCheckpoint;
  bool _cycleInitialized = false;
  bool _privateStateReady = false;
  List<ConceptUsageCheckpoint> _priorCheckpoints = [];
  Map<String, int> _clothingObservations = {};
  Map<String, ConceptUsageSnapshot> _reservedChoices = {};
  JsonMap? _pendingSecondaryCommand;
  JsonMap? _pendingLearning;
  bool _flushingLearning = false;
  bool _sendingSecondary = false;
  bool _stagingSecondary = false;
  ConceptActionOption? _selectedOption;
  String get _intentId => '${round?.roundId ?? 'opening'}:v$_choiceVersion';
  final PlayerGameProfile? _privateProfile;
  V4Profile? _v4Profile;
  V4Profile? get editableProfile => _v4Profile;
  List<CardConcept> get stagedConcepts => _conceptCatalog.concepts.concepts
      .where((c) => c.stages.isNotEmpty)
      .toList();
  bool stageExcluded(String conceptId, String actionId, String direction) =>
      _v4Profile?.excludesStage(conceptId, actionId, direction) ?? false;
  bool cardExcluded(String conceptId) =>
      _v4Profile?.stageVetoes.any(
        (v) => v.conceptId == conceptId && v.actionId == '*',
      ) ??
      false;

  bool _fullyExcluded(String conceptId) {
    if (cardExcluded(conceptId)) return true;
    final variants = _definitions[conceptId]?.variants;
    if (variants == null || variants.isEmpty) return false;
    return variants.every((variant) {
      final directions =
          variant.v3?.tags
              .where((t) => t.startsWith('v3.direction.'))
              .toList() ??
          <String>[];
      return directions.isNotEmpty &&
          directions.every(
            (tag) => stageExcluded(
              conceptId,
              variant.stableId,
              tag.split('.').last.toUpperCase(),
            ),
          );
    });
  }

  Future<void> applyStageVetoProfile(V4Profile profile) async {
    _v4Profile = profile;
    _runtime = [
      for (final card in _runtime)
        _fullyExcluded(card.cardId) ? card.copyWith(locked: false) : card,
    ];
    if (_activeReveal == null &&
        selectedCard != null &&
        _selectedOption != null) {
      if (stageExcluded(
        selectedCard!.id,
        _selectedOption!.choice.actionId,
        selectedCard!.nativeDirection.name,
      )) {
        await cancelPendingSelection();
      } else {
        // Refresh the uncommitted inverse too; committed snapshots stay frozen.
        chooseAction(_selectedOption!);
      }
    }
    notifyListeners();
  }

  AdaptiveProfileState? _learnedState;
  V4Profile? get _ratingProfile {
    final base = _v4Profile;
    return base == null ? null : mergeV4ProfileLearning(base, _learnedState);
  }

  late final V4SessionMode _sessionMode;
  V4SessionMode get sessionMode => _sessionMode;
  late V4SessionPresence _presence;
  late V4SessionAccessoryPool _accessoryPool;
  List<V4PersistentEffect> _persistentEffects = [];
  bool _publishingAction = false;
  bool _startingNextRound = false;
  bool _reportingHybridAvailability = false;
  String? _preparedHybridAvailabilityKey;
  final Map<String, int> _latestRoundRevisions = {};
  Future<void> _snapshotApplication = Future.value();
  DeckExhaustionChoice? _sessionClosureIntent;
  bool _localSessionCleared = false;
  late final List<String> playerIds;
  late final Map<String, CardDefinition> _definitions;
  late final Map<String, EngineCard> _engineCards;
  late final ProfileHierarchy _hierarchy;
  late EngineSessionContext _context;
  late int _initialClothing;

  NetworkGameViewState viewState = NetworkGameViewState.loading;
  NetworkGameRoundStateDto? round;
  NetworkDuelCard? selectedCard;
  String? errorMessage;
  int resolutionCount = 0;

  List<CardRuntimeState> _runtime = const [];
  Set<int> _learningRecordedRounds = {};
  int _deckCycle = 1;
  int _choiceVersion = 0;
  bool _infiniteMode = false;
  PlayerStyle _deckStyle = PlayerStyle.SOFT;
  List<NetworkPlayedCardRecord> _publicDiscards = [];
  ChoiceRevealDto? _activeReveal;
  bool _nextRoundPrepared = false;
  StreamSubscription<NetworkGameRoundStateDto>? _subscription;
  bool _committing = false;
  bool _cancelling = false;
  bool _cancelCommitRequested = false;
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
  bool get usesV3Negotiation => repository is NetworkNegotiationRepository;
  String? get lockedCardId => _runtime
      .where((card) => card.zone == CardZone.HAND && card.locked)
      .map((card) => card.occurrenceId)
      .firstOrNull;
  List<CardRuntimeState> get runtime => List.unmodifiable(_runtime);
  HybridDeckOrientation get orientation =>
      round?.hybridOrientation ?? HybridDeckOrientation.faceToFace;
  int get activeSpice => _context.chiliActive;
  String titleFor(String conceptId) =>
      _definitions[conceptId]?.title ?? conceptId;
  ConceptUsageCheckpoint get usageCheckpoint => _usageCheckpoint;
  int get currentClothingCount => _context.clothesByPlayer[playerId] ?? 0;
  String? get pendingClothingObservationUsageId {
    for (final card
        in finalResolution?.compromise ?? <NetworkCompromiseCardDto>[]) {
      if (card.cardId == '013' &&
          (card.usage.resolvedAction['actor_player_ids']! as List).contains(
            playerId,
          ) &&
          !_clothingObservations.containsKey(card.usage.usageId)) {
        return card.usage.usageId;
      }
    }
    return null;
  }

  Future<void> recordClothingCount(String usageId, int count) async {
    RangeError.checkNotNegative(count, 'count');
    if (_clothingObservations.containsKey(usageId)) {
      if (_clothingObservations[usageId] != count) {
        throw StateError('Clothing outcome already recorded');
      }
      return;
    }
    if (usageId != pendingClothingObservationUsageId) {
      throw StateError('No clothing outcome expected');
    }
    _clothingObservations = {..._clothingObservations, usageId: count};
    _context = _context.copyWith(
      clothesByPlayer: {..._context.clothesByPlayer, playerId: count},
    );
    // Outcome is separate from the immutable engaged action and frozen capacities.
    await _persist();
    notifyListeners();
  }

  /// Accepts already resolved session settings; does not replace agreement/PA rules.
  Future<void> applyResolvedContext(EngineSessionContext context) async {
    RangeError.checkValueInInterval(context.chiliActive, 1, 4, 'chiliActive');
    _context = context;
    _followOrientation(orientation);
    if (selectedCard != null && _activeReveal == null) {
      final current = choicesFor(
        selectedCard!.id,
      ).where((o) => o.key == _selectedOption?.key).firstOrNull;
      _selectedOption = current;
      if (current == null) {
        await cancelPendingSelection();
      } else {
        chooseAction(current);
      }
    }
    await _persist();
    notifyListeners();
  }

  Future<void> retryCurrentAction() async {
    if (_stagingSecondary || _sendingSecondary) return;
    if (!_privateStateReady) {
      await start();
      return;
    }
    try {
      await _persist();
      if (_pendingSecondaryCommand != null) await _replaySecondaryCommand();
      if (_subscription == null && round != null) _watchRound(round!);
      await _refreshCanonical();
    } catch (error) {
      _fail(error);
    }
  }

  bool get decksEmpty => _conceptPool(excludeHeld: true).isEmpty;
  bool get deckExhausted => round?.cycleExhausted ?? false;
  PlayerStyle get deckStyle => _deckStyle;
  bool get infiniteMode => _infiniteMode;
  bool get isCycleController => round?.cycleExhausted ?? false;
  bool get canCancelSelection =>
      !_cancelling &&
      !_cancelCommitRequested &&
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

  NetworkDuelCard? get personalDuelCard {
    final reveal = round?.ownReveal ?? _activeReveal;
    if (reveal == null) return null;
    final saved = _usageCheckpoint.usagesByIntent.values
        .where((u) => u.usageId == reveal.choice.usageId)
        .firstOrNull;
    return _cardFromUsage(
      saved == null
          ? reveal.choice.usage!
          : NetworkUsageProjection.fromSnapshot(
              saved,
              sharedParameterKeys: saved.action.parameters.keys.toSet(),
              sharedEffectIds: saved.action.effects
                  .map((e) => e.effectId)
                  .toSet(),
              includePersonalValue: true,
            ),
      forDisplay: true,
    );
  }

  String? zoneForCard(NetworkDuelCard card) {
    if (card.identity != card.id) {
      final own = round?.ownReveal?.choice.usage;
      if (own?.usageId == card.identity) {
        return own!.resolvedAction['zone_id'] as String?;
      }
      for (final checkpoint in [_usageCheckpoint, ..._priorCheckpoints]) {
        final usage = checkpoint.usagesByIntent.values
            .where((u) => u.usageId == card.identity)
            .firstOrNull;
        if (usage != null) return usage.action.zoneId;
      }
    }
    return conceptFor(
      card.id,
    ).variants.where((v) => v.id == card.variant.id).firstOrNull?.zoneId;
  }

  List<CardConcept> get heldConcepts => [
    for (final state in _runtime.where((c) => c.zone == CardZone.HAND))
      _conceptCatalog.concepts.concepts.singleWhere(
        (c) => c.id == state.cardId,
      ),
  ];

  List<NetworkUsageProjection> get visibleDiscardUsages => [
    for (final record in _publicDiscards.reversed)
      _withPrivateValues(record.usage),
  ];

  NetworkUsageProjection _withPrivateValues(NetworkUsageProjection projection) {
    if (projection.snapshotValue != null ||
        projection.ownerPlayerId != playerId) {
      return projection;
    }
    for (final checkpoint in [_usageCheckpoint, ..._priorCheckpoints]) {
      for (final saved in checkpoint.usagesByIntent.values) {
        if (saved.usageId != projection.usageId) continue;
        final inverse =
            saved.action.direction.name !=
            projection.resolvedAction['direction'];
        final action = saved.reconstruct(inverted: inverse);
        final json = Map<String, Object?>.from(projection.toJson());
        json['snapshot_value'] = action.personalValues
            .singleWhere((v) => v.playerId == playerId)
            .value;
        if (json['inverted_resolution'] != null &&
            saved.invertedAction != null) {
          json['inverted_resolution'] = <String, Object?>{
            ...Map<String, Object?>.from(json['inverted_resolution']! as Map),
            'snapshot_value': saved.invertedAction!.personalValues
                .singleWhere((v) => v.playerId == playerId)
                .value,
          };
        }
        return NetworkUsageProjection.fromJson(json);
      }
    }
    return projection;
  }

  List<NetworkDuelCard> get auctionCards => [
    for (final card in _replayableDiscards())
      if (!heldConcepts.any((concept) => concept.id == card.id)) card,
  ];

  String? get corruptionActorId {
    return finalLoserId;
  }

  bool get isCorruptionActor => corruptionActorId == playerId;
  bool get canAttemptNegotiation => negotiation?.response == null;
  bool get canAttemptCorruption => corruption?.accepted == null;
  List<NetworkDuelCard> get corruptionCards =>
      _replayableDiscards(corruptionReplay: true);

  List<NetworkDuelCard> _replayableDiscards({
    bool recovery = false,
    bool corruptionReplay = false,
  }) {
    final currentCycleUsageIds = {
      for (final usage in _usageCheckpoint.usagesByIntent.values)
        if (usage.cycle == _deckCycle) usage.usageId,
    };
    final spentReplayIds = {
      for (final checkpoint in [_usageCheckpoint, ..._priorCheckpoints])
        for (final usage in checkpoint.usagesByIntent.values)
          if (usage.intentId.contains(':corruption:')) ...[
            usage.usageId,
            ?usage.sourceUsageId,
          ],
    };
    final seen = <String>{};
    return [
      for (final record in _publicDiscards)
        if (record.roundNumber < roundNumber &&
            record.usage.ownerPlayerId == playerId &&
            (recovery || currentCycleUsageIds.contains(record.usageId)) &&
            (!corruptionReplay || !spentReplayIds.contains(record.usageId)) &&
            (corruptionReplay ||
                _usageCheckpoint.availableFor(record.cardId) > 0 ||
                _reservedChoices.values.any(
                  (draft) =>
                      draft.sourceUsageId == record.usage.usageId &&
                      draft.intentId.startsWith(
                        '${round!.roundId}:negotiation:',
                      ),
                )) &&
            seen.add(record.usage.usageId) &&
            _replayConsentAllowed(record.usage, recovery: recovery) &&
            (_currentOptions(
                      recovery: recovery,
                      includeConsumedStages: corruptionReplay,
                    )[record.cardId] ??
                    const [])
                .any((o) => _matchesUsage(o, record.usage)))
          _cardFromUsage(_withPrivateValues(record.usage)),
    ];
  }

  bool _replayConsentAllowed(
    NetworkUsageProjection usage, {
    bool recovery = false,
  }) {
    if (!_definitions.containsKey(usage.conceptId)) return false;
    if (_v4Profile?.excludesStage(
          usage.conceptId,
          (usage.resolvedAction['stage_id'] ??
                  usage.resolvedAction['variant_id'])!
              as String,
          usage.resolvedAction['direction']! as String,
        ) ??
        false) {
      return false;
    }
    if (!recovery &&
        (usage.resolvedAction['effective_chili']! as int) >
            _context.chiliActive) {
      return false;
    }
    if (_ratingProfile case final profile?) {
      final tags = _conceptCatalog.vetoTags(usage.conceptId);
      return !profile.preferences.values.any(
        (p) => p.excluded && tags.contains(p.key.tagId),
      );
    }
    final role = _profileRole(
      CardOccurrenceDirection.values.byName(
        usage.resolvedAction['direction']! as String,
      ),
      fallback: ProfileRole.GENERAL,
    );
    return (usage.resolvedAction['tags']! as List)
        .cast<String>()
        .where((t) => t.startsWith('v3.preference.'))
        .every((id) {
          final preference = _profile(playerId).preference(id);
          return preference.status == PreferenceStatus.ACCEPTED &&
              preference.valueFor(role) != null;
        });
  }

  bool _matchesUsage(
    ConceptActionOption option,
    NetworkUsageProjection usage,
  ) =>
      option.choice.actionId ==
          (usage.resolvedAction['stage_id'] ??
              usage.resolvedAction['variant_id']) &&
      option.choice.zoneId == usage.resolvedAction['zone_id'] &&
      option.parameters['technique'] ==
          (usage.resolvedAction['parameters'] as Map)['technique'] &&
      option.parameters['practice_action_id'] ==
          (usage.resolvedAction['parameters'] as Map)['practice_action_id'] &&
      option.parameters['practice_zone_id'] ==
          (usage.resolvedAction['parameters'] as Map)['practice_zone_id'];

  bool get recoveryAvailable => recoveryEngine.available(
    currentPa: actionPoints[playerId] ?? const BalanceConfig().initialPa,
    gate: RecoveryGate(
      betweenRounds: round?.phase == NetworkGamePhase.recovery,
      usedSinceLastNormalDuel:
          round?.recoveryDonePlayerIds.contains(playerId) ?? false,
    ),
  );

  List<NetworkDuelCard> get recoveryCards => [
    for (final id in _currentOptions(recovery: true).keys)
      if (!heldConcepts.any((c) => c.id == id) &&
          _usageCheckpoint.availableFor(id) > 0)
        if (_networkCard(id, recovery: true) case final card?) card,
    for (final item in _runtime.where((c) => c.zone == CardZone.HAND))
      if (_usageCheckpoint.availableFor(item.cardId) > 0)
        ?_networkCard(
          item.cardId,
          option: _currentOptions(recovery: true)[item.cardId]?.firstOrNull,
          recovery: true,
        ),
    ..._replayableDiscards(recovery: true),
  ];

  Future<void> start() async {
    if (_subscription != null) return;
    try {
      postGameProfileChoice = await _profileChoiceStore.load(playerId);
      _learnedState = await learning.state();
      _cardRatings = await _cardLearningStore.load(playerId);
      final current = await repository.openCurrentRound(
        command: _command('OPEN', roundId: null, roundNumber: 0),
      );
      if (current.usageContractVersion != 1) {
        throw const NetworkRoundException('USAGE_CONTRACT_NOT_DEPLOYED');
      }
      _context = _context.copyWith(
        chiliActive: current.v4UnlockedSpice,
        chiliUnlocked: current.v4UnlockedSpice,
      );
      _followOrientation(current.hybridOrientation);
      await _restoreOrCreatePrivateState(current);
      _privateStateReady = true;
      _ensureReconciliation();
      await _switchRound(current);
      if (_pendingSecondaryCommand != null) await _replaySecondaryCommand();
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
    final pa = category.personalPa;
    await learning.manuallyCustomize(
      key: key,
      pa: pa,
      excluded: category == DetailedPreferenceCategory.excluded,
    );
    _learnedState = await learning.state();
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
    if (repository is! NetworkSessionFlowRepository || !isCycleController) {
      return;
    }
    if (viewState != NetworkGameViewState.actionInProgress &&
        viewState != NetworkGameViewState.waitingNext) {
      return;
    }
    if (choice == DeckExhaustionChoice.finish ||
        choice == DeckExhaustionChoice.newCustomizedGame) {
      _sessionClosureIntent = choice;
      await closeSession();
      return;
    }
    await _stageLearningForRound();
    await _sendSecondary('CONTINUE_CYCLE', {
      'choice': choice.name,
      'expected_cycle': _deckCycle,
      'style_revision': round?.cycleStyleRevision ?? 0,
    });
  }

  void toggleLock(String conceptId) {
    if (viewState != NetworkGameViewState.choosing ||
        round?.ownCommitRecorded == true) {
      return;
    }
    final target = _runtime
        .where(
          (card) =>
              card.occurrenceId == conceptId && card.zone == CardZone.HAND,
        )
        .firstOrNull;
    if (target == null) return;
    if (target.locked) {
      _runtime = [
        for (final card in _runtime)
          card.occurrenceId == conceptId ? card.copyWith(locked: false) : card,
      ];
    } else {
      _runtime = lifecycleEngine.lock(_runtime, conceptId);
    }
    unawaited(_persist());
    notifyListeners();
  }

  void selectCard(String conceptId) {
    if (viewState != NetworkGameViewState.choosing) return;
    selectedCard = hand.where((card) => card.identity == conceptId).firstOrNull;
    _selectedOption = selectedCard == null
        ? null
        : materializedAction(selectedCard!.id);
    notifyListeners();
  }

  List<ConceptActionOption> recoveryChoicesFor(String conceptId) =>
      _currentOptions(recovery: true)[conceptId] ?? const [];

  List<ConceptActionOption> choicesFor(String conceptId) =>
      _currentOptions()[conceptId] ?? const [];

  Future<void> reserveSelection() async {
    final card = selectedCard;
    if (card == null) return;
    _usageCheckpoint = _usageCheckpoint
        .releaseReservation(_intentId)
        .reserve(
          intentId: _intentId,
          conceptId: card.id,
          stageId: conceptFor(card.id).stages.isEmpty
              ? null
              : _selectedOption?.choice.actionId,
        );
    await _persist();
  }

  Future<void> cancelPendingSelection() async {
    if (_usageCheckpoint.usageForIntent(_intentId) != null) return;
    _usageCheckpoint = _usageCheckpoint.releaseReservation(_intentId);
    _selectedOption = null;
    selectedCard = null;
    await _persist();
    notifyListeners();
  }

  void chooseAction(ConceptActionOption option) {
    final card = selectedCard;
    if (card == null) return;
    final current = choicesFor(
      card.id,
    ).where((v) => v.key == option.key).firstOrNull;
    if (current == null) throw StateError('Choice is no longer eligible');
    _selectedOption = current;
    selectedCard = _networkCard(
      card.id,
      occurrenceId: card.id,
      option: current,
    );
    notifyListeners();
  }

  Map<String, List<ConceptActionOption>> _currentOptions({
    bool recovery = false,
    bool includeConsumedStages = false,
  }) {
    final options = const ConceptActionOptions().evaluate(
      catalog: _conceptCatalog,
      profile: _ratingProfile,
      cardRatings: _cardRatings,
      context: _context,
      actor: _profile(playerId),
      partner: _profile(opponentId),
      hierarchy: _hierarchy,
      mediaSendRequired: _context.flags['mediaSendRequired'] == true,
      recovery: recovery,
    );
    if (includeConsumedStages) return options;
    return {
      for (final entry in options.entries)
        if (entry.value.any((o) => _stageAvailable(entry.key, o)))
          entry.key: entry.value
              .where((o) => _stageAvailable(entry.key, o))
              .toList(),
    };
  }

  bool _stageAvailable(String id, ConceptActionOption option) {
    final concept = _conceptCatalog.concepts.concepts.singleWhere(
      (c) => c.id == id,
    );
    return _usageCheckpoint.stageAvailable(
      id,
      concept.stages.isEmpty ? null : option.choice.actionId,
      intentId: _intentId,
    );
  }

  CardConcept conceptFor(String id) =>
      _conceptCatalog.concepts.concepts.singleWhere((c) => c.id == id);

  bool stageConsumed(String id, String stageId) =>
      _usageCheckpoint.stageConsumed(id, stageId);

  ConceptActionOption? defaultAction(
    String id, [
    List<ConceptActionOption>? options,
  ]) {
    final choices = options ?? choicesFor(id);
    final concept = conceptFor(id);
    if (concept.stages.isNotEmpty) {
      for (final stage in concept.stages.reversed) {
        final found = choices
            .where((o) => o.choice.actionId == stage.id)
            .firstOrNull;
        if (found != null) return found;
      }
    }
    // The generic zone card is presented as LIBRE. Its complete free action
    // must be played directly; fixed-zone definitions remain available when
    // an explicitly structured action is requested by another flow.
    return choices
            .where(
              (o) => concept.variants.any(
                (v) => v.id == o.choice.actionId && v.freeZone,
              ),
            )
            .firstOrNull ??
        choices.firstOrNull;
  }

  ConceptActionOption? materializedAction(
    String id, [
    List<ConceptActionOption>? options,
  ]) {
    final choices = options ?? choicesFor(id);
    final variantId = _runtime
        .where((card) => card.cardId == id && card.zone == CardZone.HAND)
        .firstOrNull
        ?.variantId;
    return choices
            .where((option) => option.choice.actionId == variantId)
            .firstOrNull ??
        defaultAction(id, choices);
  }

  NetworkDuelCard? previewAction(String id, ConceptActionOption option) =>
      _networkCard(id, option: option);

  ConceptDeckPool _conceptPool({
    bool excludeHeld = false,
    Set<String> excluded = const {},
  }) {
    final options = _currentOptions();
    return const ConceptDeckEngine().prepare(
      catalog: _conceptCatalog.concepts,
      stock: _usageCheckpoint.stock,
      globalChili: _context.chiliActive,
      style: _deckStyle,
      unavailableConceptIds: {
        ...excluded,
        for (final concept in _conceptCatalog.concepts.concepts)
          if (_fullyExcluded(concept.id)) concept.id,
        for (final entry in _usageCheckpoint.stock.remaining.entries)
          if (_usageCheckpoint.availableFor(entry.key) == 0) entry.key,
        if (excludeHeld)
          ..._runtime
              .where(
                (c) => c.zone == CardZone.HAND || c.zone == CardZone.ENGAGED,
              )
              .map((c) => c.cardId),
      },
      eligibility: ConceptDeckEligibility(
        actionIdsByConcept: {
          for (final entry in options.entries)
            entry.key: entry.value.map((o) => o.choice.actionId).toSet(),
        },
        zoneIdsByConcept: {
          for (final entry in options.entries)
            entry.key: {
              ...entry.value.map((o) => o.choice.zoneId).nonNulls,
              // An eligible unspecified zone has no anatomical choice to carry
              // into the second (draw-only) eligibility projection.
              if (entry.value.any((o) => o.choice.zoneId == null))
                ..._conceptCatalog.concepts.zones.map((z) => z.id),
            },
        },
      ),
    );
  }

  void _followOrientation(HybridDeckOrientation value) {
    _context = _context.copyWith(
      mode: value == HybridDeckOrientation.distance
          ? SessionMode.distance
          : SessionMode.face_to_face,
      proximity: value == HybridDeckOrientation.distance
          ? ProximityState.SEPARATED
          : ProximityState.TOGETHER,
    );
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
      await reserveSelection();
      if (round?.roundId != current.roundId) return;
      final option = choicesFor(
        card.id,
      ).where((o) => o.key == _selectedOption?.key).firstOrNull;
      if (option == null) {
        throw StateError('Selected action is no longer eligible');
      }
      if (stageExcluded(
        card.id,
        option.choice.actionId,
        card.nativeDirection.name,
      )) {
        throw StateError('Selected stage is excluded');
      }
      final engagedAt = clock().toUtc();
      final engagedCheckpoint = _usageCheckpoint.engage(
        intentId: _intentId,
        conceptId: card.id,
        resolveAction: () => _freezeAction(card, option, engagedAt),
        resolveInvertedAction: card.oppositePersonalValue == null
            ? null
            : () => _freezeAction(card, option, engagedAt, inverted: true),
        clock: () => engagedAt,
      );
      final usage = engagedCheckpoint.usageForIntent(_intentId)!;
      final choice = ChoicePayload.fromUsage(
        NetworkUsageProjection.fromSnapshot(
          usage,
          sharedParameterKeys: const {
            'committed_at',
            'learning_role',
            'clothing_behavior',
            'duration_actions',
            'persistent_instruction',
            'technique',
            'practice_concept_id',
            'practice_action_id',
            'practice_chili',
            'practice_zone_id',
            'media_capture_player_id',
            'media_send',
          },
          sharedEffectIds: usage.action.effects.map((e) => e.effectId).toSet(),
          includePersonalValue: true,
        ),
      );
      final reveal =
          _activeReveal ??
          ChoiceRevealDto(
            sessionRound: current.sessionRound,
            playerId: playerId,
            choice: choice,
            nonce: '${nonceFactory()}:v$_choiceVersion',
          );
      _usageCheckpoint = engagedCheckpoint;
      _activeReveal = reveal;
      _runtime = [
        for (final item in _runtime)
          if (item.cardId == card.id && item.zone == CardZone.HAND)
            CardRuntimeState(
              cardId: card.id,
              occurrenceId: usage.usageId,
              variantId: usage.action.stageId ?? usage.action.variantId,
              zone: CardZone.ENGAGED,
              nativeDirection: usage.action.direction,
            )
          else
            item,
      ];
      await _persist();
      await _apply(
        await repository.submitCommit(
          command: _command(
            'COMMIT',
            roundId: current.roundId,
            roundNumber: current.roundNumber,
            choiceVersion: _choiceVersion,
          ),
          commitment: contract.commit(
            sessionRound: current.sessionRound,
            playerId: playerId,
            choice: reveal.choice,
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
    if ((!canCancelSelection && !_cancelCommitRequested) ||
        round == null ||
        cancellable is! NetworkCommitCancellationRepository) {
      return false;
    }
    if (_cancelling) return false;
    _cancelling = true;
    try {
      _cancelCommitRequested = true;
      await _persist();
      final updated = await (cancellable as NetworkCommitCancellationRepository)
          .cancelCommit(
            command: _command('CANCEL_COMMIT', choiceVersion: _choiceVersion),
          );
      _restoreCancelledChoice();
      _choiceVersion++;
      _cancelCommitRequested = false;
      await privateStore.clear(sessionId: session.id, playerId: playerId);
      await _persist();
      await _apply(updated);
      return true;
    } on NetworkRoundException catch (error) {
      if (error.code != 'ROUND_CANCEL_CLOSED' &&
          error.code != 'ROUND_COMMIT_CLOSED') {
        _fail(error);
        return false;
      }
      _cancelCommitRequested = false;
      await _persist();
      await _apply(await repository.getCurrentRound(sessionId: session.id));
      return false;
    } catch (error) {
      _fail(error);
      return false;
    } finally {
      _cancelling = false;
    }
  }

  ResolvedConceptAction _freezeAction(
    NetworkDuelCard card,
    ConceptActionOption option,
    DateTime at, {
    bool inverted = false,
  }) {
    final direction = inverted
        ? const CardDirectionEngine().invert(card.nativeDirection)
        : card.nativeDirection;
    final role = _profileRole(direction, fallback: ProfileRole.GENERAL);
    final actor = direction == CardOccurrenceDirection.RECEVOIR
        ? opponentId
        : playerId;
    final mutual =
        direction == CardOccurrenceDirection.MUTUEL ||
        direction == CardOccurrenceDirection.SIMULTANE;
    final concept = _conceptCatalog.concepts.concepts.singleWhere(
      (c) => c.id == card.id,
    );
    final conceptVariant = concept.variants
        .where((variant) => variant.id == option.choice.actionId)
        .firstOrNull;
    final editorialRenderer = ConceptEditorialRenderer(
      _conceptCatalog.concepts,
    );
    final editorial =
        editorialRenderer.appliesTo(
          concept: concept,
          actionId: option.choice.actionId,
        )
        ? editorialRenderer.render(
            concept: concept,
            actionId: option.choice.actionId,
            direction: direction,
          )
        : null;
    return ResolvedConceptAction.fromJson({
      'concept_id': card.id,
      'catalog_version':
          _conceptCatalog.concepts.reader.json['catalog_version'],
      'locale': _conceptCatalog.concepts.reader.json['locale'],
      if (concept.stages.isNotEmpty)
        'stage_id': option.choice.actionId
      else
        'variant_id': option.choice.actionId,
      if (option.choice.zoneId != null) 'zone_id': option.choice.zoneId,
      'effective_chili': option.choice.chili,
      'direction': direction.name,
      'actor_player_ids': mutual ? playerIds : [actor],
      'target_player_ids': const V4ActionTargetResolver().resolve(
        ownerPlayerId: playerId,
        playerIds: playerIds,
        direction: direction,
      ),
      'parameters': {
        ...option.parameters,
        if (card.id == '013') 'learning_role': 'soi',
        'committed_at': at.toIso8601String(),
        'display_title': card.title,
        'display_details':
            editorial?.detailsText ??
            card.definition.variants
                .singleWhere((v) => v.stableId == option.choice.actionId)
                .detailsText ??
            card.definition.detailsText,
        'display_illustration': card.definition.illustrationKey,
        'clothing_behavior': _definitions[card.id]?.v4?.clothingBehavior.name,
        'duration_actions': _definitions[card.id]?.v4?.durationActions,
        'persistent_instruction': editorial?.detailsText ?? concept.detailsText,
        'clothes_at_engagement': _context.clothesByPlayer,
      },
      'accessories': <Object?>[],
      'tags': [
        for (final tag in option.variant.tags)
          if (!tag.startsWith('v3.preference.') ||
              _ratedPreferenceIds(card.id, option).contains(tag))
            tag
          else
            'v3.semantic.${tag.split('.').last}',
        ..._ratedPreferenceIds(
          card.id,
          option,
        ).where((t) => !option.variant.tags.contains(t)),
      ],
      'primary_preference_ids': _primaryPreferenceIds(card.id, option),
      'personal_values': [
        {
          'player_id': playerId,
          'role': role.name,
          'value': inverted ? card.oppositePersonalValue! : card.personalValue,
        },
      ],
      'effects': [
        if (_definitions[card.id]?.v4?.durationActions case final duration?)
          for (final target
              in const {'033', '061'}.contains(card.id)
                  ? [actor]
                  : const V4ActionTargetResolver().resolve(
                      ownerPlayerId: playerId,
                      playerIds: playerIds,
                      direction: direction,
                    ))
            {
              'effect_id': 'duration:${card.id}:$target',
              'parameters': {
                'card_id': card.id,
                'target_player_id': target,
                'remaining_actions': duration,
                'stage_id': ?(concept.stages.isNotEmpty
                    ? option.choice.actionId
                    : null),
                'actor_player_ids': mutual ? playerIds : [actor],
                'action_text': editorial?.actionText ?? concept.actionText,
                'instruction': ?(editorial?.detailsText ?? concept.detailsText),
              },
            },
        for (var i = 0; i < option.variant.effects.length; i++)
          {
            'effect_id': '${card.id}:$i',
            'parameters': option.variant.effects[i].toJson(),
          },
      ],
      'action_text':
          editorial?.actionText ??
          (card.id == '024'
              ? concept.actionText
              : conceptVariant?.freeZone == true
              ? option.title
              : concept.kind == ConceptKind.zones && conceptVariant != null
              ? '${concept.actionText} · ${conceptVariant.title}'
              : '${concept.actionText} · ${option.title}'),
    });
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
    final usageId = _activeReveal?.choice.usageId;
    _runtime = _runtime.where((card) => card.occurrenceId != usageId).toList();
    _activeReveal = null;
    selectedCard = null;
    _selectedOption = null;
    // Engagement is definitive, including when a server commit is cancelled.
    // Refill may draw the concept again only if its remaining quota allows it.
    _refill(roundNumber);
  }

  NetworkUsageProjection _sharedUsage(ConceptUsageSnapshot usage) =>
      NetworkUsageProjection.fromSnapshot(
        usage,
        sharedParameterKeys: const {
          'committed_at',
          'learning_role',
          'clothing_behavior',
          'duration_actions',
          'persistent_instruction',
          'technique',
          'practice_concept_id',
          'practice_action_id',
          'practice_chili',
          'practice_zone_id',
          'media_capture_player_id',
          'media_send',
        },
        sharedEffectIds: usage.action.effects.map((e) => e.effectId).toSet(),
        includePersonalValue: true,
      );

  ConceptUsageSnapshot _savedUsage(String usageId) {
    for (final checkpoint in [_usageCheckpoint, ..._priorCheckpoints]) {
      for (final usage in checkpoint.usagesByIntent.values) {
        if (usage.usageId == usageId) return usage;
      }
    }
    throw StateError('Historical private usage is missing');
  }

  NetworkUsageProjection _reserveSecondary(
    NetworkDuelCard card,
    String intent, {
    ConceptActionOption? option,
    NetworkUsageProjection? source,
    bool recovery = false,
  }) {
    if (source != null) source = _withPrivateValues(source);
    final engaged = _usageCheckpoint.usageForIntent(intent);
    if (engaged != null) return _sharedUsage(engaged);
    final previous = _reservedChoices[intent];
    if (previous != null &&
        (option == null ||
            (option.choice.actionId ==
                    (previous.action.stageId ?? previous.action.variantId) &&
                option.choice.zoneId == previous.action.zoneId &&
                option.parameters['technique'] ==
                    previous.action.parameters['technique']))) {
      if (!_usageCheckpoint.stageAvailable(
        card.id,
        previous.action.stageId,
        intentId: intent,
      )) {
        throw const NetworkRoundException('ROUND_STAGE_ALREADY_CONSUMED');
      }
      return _sharedUsage(previous);
    }
    if (source != null && !_replayConsentAllowed(source, recovery: recovery)) {
      throw StateError('Historical replay is no longer eligible');
    }
    final choices = _currentOptions(recovery: recovery)[card.id] ?? const [];
    final resolvedOption =
        option ??
        (source == null
            ? defaultAction(card.id, choices)
            : choices.where((o) => _matchesUsage(o, source!)).firstOrNull);
    if (resolvedOption == null ||
        !choices.any((o) => o.key == resolvedOption.key)) {
      throw StateError('Secondary action is not eligible');
    }
    final currentCard = _networkCard(
      card.id,
      option: resolvedOption,
      recovery: recovery,
    );
    if (currentCard == null) {
      throw StateError('Secondary direction unavailable');
    }
    final at = clock().toUtc();
    final original = source == null ? null : _savedUsage(source.usageId);
    if (source != null && original == null) {
      throw StateError(
        'Historical replay requires its immutable private usage',
      );
    }
    final wasInverted =
        original != null &&
        original.action.direction.name != source!.resolvedAction['direction'];
    final action = original == null
        ? _freezeAction(currentCard, resolvedOption, at)
        : original.reconstruct(inverted: wasInverted);
    final inverse = original == null
        ? (currentCard.oppositePersonalValue == null
              ? null
              : _freezeAction(currentCard, resolvedOption, at, inverted: true))
        : (wasInverted ? original.action : original.invertedAction);
    final draft = ConceptUsageSnapshot.create(
      sessionId: session.id,
      ownerPlayerId: playerId,
      cycle: _deckCycle,
      intentId: intent,
      engagedAt: at,
      action: action,
      invertedAction: _eligibleStageInverse(inverse),
      sourceUsageId: source?.usageId,
    );
    _usageCheckpoint = _usageCheckpoint
        .releaseReservation(intent)
        .reserve(intentId: intent, conceptId: card.id, stageId: action.stageId);
    _reservedChoices = {..._reservedChoices, intent: draft};
    return _sharedUsage(draft);
  }

  NetworkUsageProjection _reserveCorruptionReplay(
    NetworkUsageProjection source,
  ) {
    final intent = '${round!.roundId}:corruption:${source.usageId}';
    final previous =
        _usageCheckpoint.usageForIntent(intent) ?? _reservedChoices[intent];
    if (previous != null) return _sharedUsage(previous);
    if (!_replayConsentAllowed(source) ||
        !(_currentOptions(includeConsumedStages: true)[source.conceptId] ??
                const [])
            .any((option) => _matchesUsage(option, source))) {
      throw StateError('Historical replay is no longer eligible');
    }
    final original = _savedUsage(source.usageId);
    final inverted =
        original.action.direction.name != source.resolvedAction['direction'];
    final draft = ConceptUsageSnapshot.create(
      sessionId: session.id,
      ownerPlayerId: playerId,
      cycle: _deckCycle,
      intentId: intent,
      engagedAt: clock().toUtc(),
      action: original.reconstruct(inverted: inverted),
      invertedAction: _eligibleStageInverse(
        inverted ? original.action : original.invertedAction,
      ),
      sourceUsageId: source.usageId,
    );
    _reservedChoices = {..._reservedChoices, intent: draft};
    return _sharedUsage(draft);
  }

  void _releaseSecondary(String intent) {
    _usageCheckpoint = _usageCheckpoint.releaseReservation(intent);
    _reservedChoices = {..._reservedChoices}..remove(intent);
  }

  ResolvedConceptAction? _eligibleStageInverse(ResolvedConceptAction? action) {
    if (action == null) return null;
    return stageExcluded(
          action.conceptId,
          action.stageId ?? action.variantId!,
          action.direction.name,
        )
        ? null
        : action;
  }

  void _acceptSecondary(NetworkUsageProjection projection) {
    if (projection.ownerPlayerId != playerId) return;
    if ([_usageCheckpoint, ..._priorCheckpoints].any(
      (c) =>
          c.usagesByIntent.values.any((u) => u.usageId == projection.usageId),
    )) {
      return;
    }
    final draft = _reservedChoices.values
        .where((u) => u.usageId == projection.usageId)
        .firstOrNull;
    if (draft == null) {
      throw StateError('Accepted usage has no persisted reservation');
    }
    final corruptionReplay = draft.intentId.contains(':corruption:');
    _usageCheckpoint = corruptionReplay
        ? _usageCheckpoint.engageReplay(draft)
        : _usageCheckpoint.engage(
            intentId: draft.intentId,
            conceptId: draft.conceptId,
            resolveAction: () => draft.action,
            resolveInvertedAction: draft.invertedAction == null
                ? null
                : () => draft.invertedAction!,
            sourceUsageId: draft.sourceUsageId,
            clock: clock,
          );
    _reservedChoices = {..._reservedChoices}..remove(draft.intentId);
    _runtime = [
      for (final card in _runtime)
        if (corruptionReplay ||
            !(card.cardId == draft.conceptId && card.zone == CardZone.HAND))
          card,
      CardRuntimeState(
        cardId: draft.conceptId,
        occurrenceId: draft.usageId,
        variantId: draft.action.stageId ?? draft.action.variantId,
        zone: CardZone.ENGAGED,
        nativeDirection: draft.action.direction,
      ),
    ];
  }

  Future<void> _reconcileSecondaryChoices(
    NetworkGameRoundStateDto value,
  ) async {
    final before = _usageCheckpoint;
    final beforeChoices = _reservedChoices;
    final finalResult = value.finalResolution;
    if (finalResult != null) {
      final accepted = finalResult.compromise.where(
        (c) =>
            c.ownerPlayerId == playerId &&
            c.origin == NetworkCompromiseOrigin.AUCTION,
      );
      for (final card in accepted) {
        _acceptSecondary(card.usage);
      }
      if (value.negotiation?.response?.accepted != null) {
        for (final intent in _reservedChoices.keys.toList()) {
          if (intent.startsWith('${value.roundId}:negotiation:')) {
            _releaseSecondary(intent);
          }
        }
      }
    }
    final corruption = value.corruption;
    if (corruption != null &&
        corruption.offeredBy == playerId &&
        corruption.accepted != null) {
      for (final action in corruption.actions) {
        if (corruption.accepted == true) _acceptSecondary(action.usage);
      }
      if (corruption.accepted == false) {
        for (final intent in _reservedChoices.keys.toList()) {
          if (intent.startsWith('${value.roundId}:corruption:')) {
            _releaseSecondary(intent);
          }
        }
      }
    }
    for (final recovery in [
      ...value.recoveryByPlayer.values,
      ...value.recoveryHistory,
    ]) {
      if (recovery.playerId != playerId || recovery.response == null) continue;
      if (recovery.response == RecoveryResponse.ACCEPT || recovery.completed) {
        _acceptSecondary(recovery.usage);
      } else if (recovery.response == RecoveryResponse.REFUSE) {
        final id = recovery.usage.usageId;
        for (final entry in _reservedChoices.entries.toList()) {
          if (entry.value.usageId == id) _releaseSecondary(entry.key);
        }
      }
    }
    if (!identical(before, _usageCheckpoint) ||
        !identical(beforeChoices, _reservedChoices)) {
      await _persist();
    }
  }

  Future<void> _sendSecondary(String kind, JsonMap payload) async {
    if (_sendingSecondary || _stagingSecondary) return;
    _stagingSecondary = true;
    try {
      if (_pendingSecondaryCommand == null) {
        final suffix = kind == 'CONTINUE_CYCLE'
            ? ':cycle-${payload['expected_cycle']}:${payload['choice']}:r${payload['style_revision'] ?? 0}'
            : kind.startsWith('RECOVERY')
            ? ':${payload['usage_id'] ?? round!.recoveryHistory.length}'
            : '';
        _pendingSecondaryCommand =
            freezeJson({
                  'kind': kind,
                  'command': _command('$kind$suffix').toJson(),
                  'payload': payload,
                })
                as JsonMap;
      }
      // No concurrent click may dispatch the command before this write finishes.
      await _persist();
      await _replaySecondaryCommand();
    } catch (error) {
      _fail(error);
    } finally {
      _stagingSecondary = false;
    }
  }

  Future<void> _replaySecondaryCommand() async {
    final pending = _pendingSecondaryCommand;
    if (pending == null || _sendingSecondary) return;
    _sendingSecondary = true;
    try {
      final proposesNewUsage = const {
        'NEGOTIATION_PROPOSAL',
        'NEGOTIATION_ADAPTATION',
        'CORRUPTION_OFFER',
        'RECOVERY',
      }.contains(pending['kind']);
      for (final draft in _reservedChoices.values) {
        if (proposesNewUsage &&
            !draft.intentId.contains(':corruption:') &&
            _usageCheckpoint.usageForIntent(draft.intentId) == null &&
            !_usageCheckpoint.stageAvailable(
              draft.conceptId,
              draft.action.stageId,
              intentId: draft.intentId,
            )) {
          // A pending v1 replay may target an already played stage. Preserve
          // its data, but do not dispatch a new engagement under the old rule.
          throw const NetworkRoundException('ROUND_STAGE_ALREADY_CONSUMED');
        }
      }
      final command = NetworkCommandDto.fromJson(
        pending['command']! as JsonMap,
      );
      final payload = pending['payload']! as JsonMap;
      final updated = await switch (pending['kind']! as String) {
        'NEGOTIATION_PROPOSAL' =>
          (repository as NetworkNegotiationRepository)
              .submitNegotiationProposal(
                command: command,
                offer: NetworkNegotiationOfferDto.fromJson(payload),
              ),
        'NEGOTIATION_ADAPTATION' =>
          (repository as NetworkNegotiationRepository).adaptNegotiation(
            command: command,
            offer: NetworkNegotiationOfferDto.fromJson(payload),
          ),
        'NEGOTIATION_RESPONSE' =>
          (repository as NetworkNegotiationRepository).respondNegotiation(
            command: command,
            response: NetworkNegotiationResponseDto.fromJson(payload),
          ),
        'NEGOTIATION_VALIDATION' =>
          (repository as NetworkNegotiationRepository).validateNegotiation(
            command: command,
            accepted: payload['accepted']! as bool,
          ),
        'CORRUPTION_OFFER' => repository.submitCorruptionOffer(
          command: command,
          objective: CorruptionObjective.values.byName(
            payload['objective']! as String,
          ),
          actions: [
            for (final raw in payload['actions']! as List)
              NetworkCorruptionActionDto.fromJson(raw as JsonMap),
          ],
        ),
        'CORRUPTION_RESPONSE' => repository.respondCorruption(
          command: command,
          accepted: payload['accepted']! as bool,
        ),
        'CORRUPTION_RESOLVE' => repository.resolveCorruption(
          command: command,
          actions: [
            for (final raw in payload['actions']! as List)
              NetworkCorruptionActionDto.fromJson(raw as JsonMap),
          ],
        ),
        'RECOVERY' => repository.submitRecovery(
          command: command,
          recovery: NetworkRecoveryDto.fromJson(payload),
        ),
        'RECOVERY_RESPONSE' => repository.respondRecovery(
          command: command,
          response: RecoveryResponse.values.byName(
            payload['response']! as String,
          ),
        ),
        'CONTINUE_CYCLE' =>
          (repository as NetworkSessionFlowRepository).continueDeckCycle(
            command: command,
            choice: DeckExhaustionChoice.values.byName(
              payload['choice']! as String,
            ),
            expectedCycle: payload['expected_cycle']! as int,
            expectedStyleRevision: (payload['style_revision'] as int?) ?? 0,
          ),
        'READY_NEXT' => repository.readyNextRound(command: command),
        'RECOVERY_RESOLVE' => repository.resolveRecovery(
          command: command,
          recovery: NetworkRecoveryDto.fromJson(payload),
        ),
        _ => throw StateError('Unknown secondary command'),
      };
      _pendingSecondaryCommand = null;
      await _persist();
      await _apply(updated);
    } on NetworkRoundException {
      final current = await repository.getCurrentRound(sessionId: session.id);
      if (current.phase != NetworkGamePhase.sessionClosed) rethrow;
      // The partner may close the session before this proposal is accepted.
      // Only pending reservations are released; engaged quota is untouched.
      _pendingSecondaryCommand = null;
      for (final intent in _reservedChoices.keys.toList()) {
        _releaseSecondary(intent);
      }
      await _persist();
      await _apply(current);
    } finally {
      _sendingSecondary = false;
    }
  }

  Future<void> proposeNegotiation({
    required bool inversion,
    required int directPa,
    Set<String> cardIds = const {},
    Map<String, ConceptActionOption> actionChoices = const {},
  }) async {
    if ((viewState != NetworkGameViewState.negotiationProposal &&
            viewState != NetworkGameViewState.corruptionDecision) ||
        !isNegotiationProposer ||
        !canAttemptNegotiation) {
      return;
    }
    if (directPa == 0 && !inversion && cardIds.isEmpty) {
      throw ArgumentError('Une proposition de compromis ne peut pas être vide');
    }
    final before = _usageCheckpoint;
    final beforeChoices = Map<String, ConceptUsageSnapshot>.of(
      _reservedChoices,
    );
    late NetworkNegotiationOfferDto offer;
    try {
      offer = _negotiationOffer(
        inversion: inversion,
        directPa: directPa,
        cardIds: cardIds,
        actionChoices: actionChoices,
      );
      if (offer.directPa > (actionPoints[playerId] ?? 0) || offer.directPa < 0)
        throw ArgumentError('PA indisponibles');
      if (offer.inversionRequested && !inversionAllowed)
        throw ArgumentError('Inversion indisponible');
    } catch (_) {
      _usageCheckpoint = before;
      _reservedChoices = beforeChoices;
      rethrow;
    }
    await _sendSecondary(
      'NEGOTIATION_PROPOSAL',
      offer.toJson(includePrivateSnapshots: true),
    );
  }

  Future<void> respondNegotiation({
    bool? accepted,
    bool acceptInversion = false,
    bool acceptAuction = false,
  }) async {
    if (viewState != NetworkGameViewState.negotiationResponse ||
        !isNegotiationResponder)
      return;
    await _sendSecondary(
      'NEGOTIATION_RESPONSE',
      NetworkNegotiationResponseDto(
        accepted: accepted ?? (acceptInversion || acceptAuction),
      ).toCommandJson(),
    );
  }

  Future<void> adaptNegotiation({
    required bool inversion,
    required int directPa,
    Set<String> cardIds = const {},
    Map<String, ConceptActionOption> actionChoices = const {},
  }) async {
    if (viewState != NetworkGameViewState.negotiationAdaptation ||
        !isInitialLoser) {
      return;
    }
    final before = _usageCheckpoint;
    final beforeChoices = Map<String, ConceptUsageSnapshot>.of(
      _reservedChoices,
    );
    late NetworkNegotiationOfferDto offer;
    try {
      offer = _negotiationOffer(
        inversion: inversion,
        directPa: directPa,
        cardIds: cardIds,
        actionChoices: actionChoices,
      );
      _validateNegotiationOffer(offer, NegotiationPhase.adaptation);
    } catch (_) {
      _usageCheckpoint = before;
      _reservedChoices = beforeChoices;
      rethrow;
    }
    await _sendSecondary(
      'NEGOTIATION_ADAPTATION',
      offer.toJson(includePrivateSnapshots: true),
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
    await _sendSecondary('NEGOTIATION_VALIDATION', {'accepted': accepted});
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
    Set<String> usageIds,
    CorruptionObjective objective,
  ) async {
    final cards = corruptionCards
        .where((c) => usageIds.contains(c.identity))
        .toList();
    if (viewState != NetworkGameViewState.corruptionDecision ||
        !isCorruptionActor ||
        !canAttemptCorruption ||
        cards.isEmpty ||
        cards.length != usageIds.length)
      return;
    final before = _usageCheckpoint;
    final beforeChoices = Map<String, ConceptUsageSnapshot>.of(
      _reservedChoices,
    );
    try {
      final actions = <NetworkCorruptionActionDto>[];
      for (final card in cards) {
        final source = _publicDiscards
            .singleWhere((r) => r.usageId == card.identity)
            .usage;
        final projection = _reserveCorruptionReplay(source);
        actions.add(NetworkCorruptionActionDto.fromUsage(projection));
      }
      await _sendSecondary('CORRUPTION_OFFER', {
        'objective': objective.name,
        'actions': actions.map((a) => a.toJson()).toList(),
      });
    } catch (_) {
      _usageCheckpoint = before;
      _reservedChoices = beforeChoices;
      rethrow;
    }
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
    await _sendSecondary('CORRUPTION_RESPONSE', {'accepted': accepted});
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
    await _sendSecondary('CORRUPTION_RESOLVE', {
      'actions': [for (final action in actions) action.toJson()],
    });
  }

  Future<void> recoverWith(
    String identity, {
    ConceptActionOption? option,
  }) async {
    if (viewState != NetworkGameViewState.recovery || !recoveryAvailable) {
      return;
    }
    final card = recoveryCards.where((c) => c.identity == identity).firstOrNull;
    if (card == null) return;
    final sourceUsage = _publicDiscards
        .where((r) => r.usage.usageId == identity)
        .firstOrNull
        ?.usage;
    final source = sourceUsage != null
        ? RecoverySource.DISCARD
        : heldConcepts.any((c) => c.id == card.id)
        ? RecoverySource.HAND
        : RecoverySource.CATALOG;
    final projection = _reserveSecondary(
      card,
      '${round!.roundId}:recovery:${round!.recoveryHistory.length}:$identity',
      option: option,
      source: sourceUsage,
      recovery: true,
    );
    final proposal = NetworkRecoveryDto.fromUsage(projection, source: source);
    await _sendSecondary('RECOVERY', proposal.toJson());
  }

  Future<void> respondToRecovery(RecoveryResponse response) async {
    final proposal = pendingRecovery;
    if (viewState != NetworkGameViewState.recoveryResponse ||
        proposal == null ||
        proposal.playerId == playerId) {
      return;
    }
    await _sendSecondary('RECOVERY_RESPONSE', {'response': response.name});
  }

  Future<void> completeRecovery({required bool completed}) async {
    final proposal = pendingRecovery;
    if (viewState != NetworkGameViewState.recoveryExecution ||
        proposal == null ||
        proposal.playerId != playerId) {
      return;
    }
    final resolved = NetworkRecoveryDto.fromUsage(
      proposal.usage,
      source: proposal.source,
      completed: completed,
      gain: completed ? _recoveryGain(proposal) : 0,
      response: proposal.response,
    );
    await _sendSecondary('RECOVERY_RESOLVE', resolved.toJson());
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
      if (atBoundary && !canStartNextRound) return;
      if (atBoundary) {
        await _startNextRoundAutomatically();
        return;
      }
      await _stageLearningForRound();
      await _apply(
        await repository.readyNextRound(
          command: _command(
            atBoundary ? 'START_NEXT_ROUND' : 'ACTION_COMPLETE',
            roundId: current.roundId,
            roundNumber: current.roundNumber,
          ),
          noPlayableOccurrences:
              !atBoundary && _availablePlayableConcepts(_presence) == 0,
          hasPlayableAlternateOrientation:
              !atBoundary &&
              sessionMode == V4SessionMode.hybrid &&
              _availablePlayableConcepts(
                    _presence == V4SessionPresence.presentiel
                        ? V4SessionPresence.distance
                        : V4SessionPresence.presentiel,
                  ) >
                  0,
          clothingCount: !atBoundary && ownClothingResyncRequired
              ? _context.clothesByPlayer[playerId]
              : null,
        ),
      );
    } on NetworkRoundException catch (error) {
      if (error.code == 'ROUND_INVALID_PHASE') {
        try {
          await _apply(await repository.getCurrentRound(sessionId: session.id));
          return;
        } catch (refreshError) {
          _fail(refreshError);
          return;
        }
      }
      _fail(error);
    } catch (error) {
      _fail(error);
    }
  }

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

  Future<void> _switchRound(
    NetworkGameRoundStateDto value, {
    bool applyImmediately = false,
  }) async {
    final changed = round?.roundId != value.roundId;
    if (changed || _subscription == null) _watchRound(value);
    if (applyImmediately) {
      await _applyNow(value, roundBound: true);
    } else {
      await _apply(value, roundBound: true);
    }
  }

  Future<void> _apply(
    NetworkGameRoundStateDto value, {
    bool roundBound = false,
  }) {
    final operation = _snapshotApplication.then(
      (_) => _applyNow(value, roundBound: roundBound),
    );
    _snapshotApplication = operation.then<void>((_) {}, onError: (_, _) {});
    return operation;
  }

  Future<void> _closeNormalRoundForRecovery(
    NetworkGameRoundStateDto value,
  ) async {
    if (value.phase != NetworkGamePhase.recovery &&
        value.phase != NetworkGamePhase.recoveryResponse &&
        value.phase != NetworkGamePhase.recoveryExecution) {
      return;
    }
    if (!_runtime.any((c) => c.zone == CardZone.ENGAGED)) return;
    _runtime = _runtime.where((c) => c.zone != CardZone.ENGAGED).toList();
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
          .map((card) => card.usageId)
          .toSet();
      if (auctionOccurrences.isNotEmpty) {
        final reconciled = [
          for (final card in _runtime)
            if (auctionOccurrences.contains(card.occurrenceId) &&
                card.zone != CardZone.EXHAUSTED)
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
            card.occurrenceId == initial.usageId
                ? card.copyWith(effectiveDirection: direction)
                : card,
        ];
        changed = changed || !_sameRuntime(_runtime, reconciled);
        _runtime = reconciled;
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
      await _applyNow(
        await repository.submitReveal(
          command: _command(
            'REVEAL',
            roundId: value.roundId,
            roundNumber: value.roundNumber,
            choiceVersion: _choiceVersion,
          ),
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
    if (repository is NetworkPrivateInitialResolutionRepository) {
      final privateResolver =
          repository as NetworkPrivateInitialResolutionRepository;
      _resolving = true;
      try {
        await _applyNow(
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
      await _applyNow(
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
    final projection = reveal.choice.usage;
    if (projection == null) throw StateError('Native usage reveal required');
    final role = ProfileRole.values.byName(
      reveal.choice.parameters['role']! as String,
    );
    return duelEngine.commit(
      playerId: reveal.playerId,
      cardId: projection.conceptId,
      variantId: reveal.choice.variantId,
      voluntaryRole: role,
      preference: _preference(
        'network.snapshot',
        role,
        projection.snapshotValue!,
      ),
      committedAt: DateTime.parse(
        reveal.choice.parameters['committed_at']! as String,
      ),
      cardInvertible: projection.toJson()['inverted_resolution'] != null,
    );
  }

  Future<void> _restoreOrCreatePrivateState(
    NetworkGameRoundStateDto current,
  ) async {
    final saved = await privateStore.loadGame(
      sessionId: session.id,
      playerId: playerId,
    );
    if (saved != null && saved.conceptCheckpoint == null) {
      throw const NetworkRoundException(
        'LEGACY_DEVELOPMENT_SESSION_REQUIRES_NEW_SESSION',
      );
    }
    if (saved != null &&
        (saved.roundNumber == current.roundNumber ||
            saved.roundNumber == current.roundNumber + 1 ||
            saved.roundNumber == current.roundNumber - 1)) {
      _runtime = List.of(saved.cards);
      _activeReveal = saved.activeReveal;
      _nextRoundPrepared = saved.nextRoundPrepared;
      _learningRecordedRounds = Set.of(saved.learningRecordedRounds);
      _deckCycle = saved.deckCycle;
      _infiniteMode = saved.infiniteMode;
      _deckStyle = saved.deckStyle;
      _publicDiscards = List.of(saved.publicDiscards);
      _choiceVersion = saved.choiceVersion;
      _cancelCommitRequested = saved.cancelCommitRequested;
      _usageCheckpoint = saved.conceptCheckpoint!;
      _reservedChoices = Map.of(saved.reservedChoices);
      _pendingSecondaryCommand = saved.pendingSecondaryCommand;
      _pendingLearning = saved.pendingLearning;
      _initialClothing = saved.initialClothing;
      _priorCheckpoints = List.of(saved.priorCheckpoints);
      _clothingObservations = Map.of(saved.clothingObservations);
      _presence = switch (sessionMode) {
        V4SessionMode.presentiel => V4SessionPresence.presentiel,
        V4SessionMode.distance => V4SessionPresence.distance,
        V4SessionMode.hybrid => saved.presence,
      };
      _accessoryPool = saved.accessoryPool;
      _persistentEffects = List.of(saved.persistentEffects);
      if (_usageCheckpoint.sessionId != session.id ||
          _usageCheckpoint.ownerPlayerId != playerId ||
          _usageCheckpoint.cycle != _deckCycle) {
        throw const NetworkRoundException('PRIVATE_CHECKPOINT_SCOPE_MISMATCH');
      }
      _context = _context.copyWith(
        mode: switch (sessionMode) {
          V4SessionMode.presentiel => SessionMode.face_to_face,
          V4SessionMode.distance => SessionMode.distance,
          V4SessionMode.hybrid => _context.mode,
        },
        proximity: sessionMode == V4SessionMode.hybrid
            ? _context.proximity
            : _presence == V4SessionPresence.distance
            ? ProximityState.SEPARATED
            : ProximityState.TOGETHER,
        chiliActive: saved.activeChili,
        chiliUnlocked: saved.activeChili,
        clothesByPlayer: saved.clothesByPlayer.isEmpty
            ? null
            : saved.clothesByPlayer,
      );
      final restoredUsage = _activeReveal?.choice.usage;
      selectedCard = restoredUsage == null
          ? null
          : _cardFromUsage(restoredUsage);
      if (saved.roundNumber == current.roundNumber - 1) {
        await _prepareNextRound(targetRound: current.roundNumber);
        _nextRoundPrepared = false;
        await _persist(roundNumber: current.roundNumber);
      }
      if (_nextRoundPrepared && saved.roundNumber == current.roundNumber) {
        _nextRoundPrepared = false;
        await _persist(roundNumber: current.roundNumber);
      }
      return;
    }
    _runtime = [];
    _publicDiscards = [];
    _choiceVersion = 0;
    _learningRecordedRounds = {};
    _deckCycle = current.deckCycle;
    _deckStyle = current.deckStyle;
    _infiniteMode = current.infiniteMode;
    _buildDeckCycle();
    _refill(current.roundNumber);
    await _persist(roundNumber: current.roundNumber);
  }

  Future<void> _prepareNextRound({int? targetRound}) async {
    if (_nextRoundPrepared) return;
    _runtime = _runtime
        .where(
          (c) =>
              c.zone != CardZone.ENGAGED &&
              !(c.zone == CardZone.HAND && _fullyExcluded(c.cardId)),
        )
        .toList();
    final nextNumber = targetRound ?? roundNumber + 1;
    _refill(nextNumber);
    _activeReveal = null;
    selectedCard = null;
    _selectedOption = null;
    _cancelCommitRequested = false;
    _nextRoundPrepared = true;
    await _persist(roundNumber: nextNumber);
  }

  JsonMap _descriptorJson(LearningCardDescriptor card) => {
    'concept_id': card.cardId,
    'action_id': card.variantId,
    'identity': card.identity,
    'is_usage': card.usageId != null,
    'tags': card.tags,
    'spice': card.spiceLevel,
    'primary_preferences': card.primaryPreferenceIds,
  };

  LearningCardDescriptor _descriptorFromJson(JsonMap json) =>
      LearningCardDescriptor(
        cardId: json['concept_id']! as String,
        variantId: json['action_id']! as String,
        usageId: json['is_usage'] == true ? json['identity']! as String : null,
        conceptIdentity: json['is_usage'] == true
            ? null
            : json['identity']! as String,
        tags: (json['tags']! as List).cast<String>(),
        spiceLevel: json['spice']! as int,
        primaryPreferenceIds: (json['primary_preferences']! as List)
            .cast<String>(),
      );

  Future<void> _stageLearningForRound() async {
    if (_pendingLearning != null ||
        _learningRecordedRounds.contains(roundNumber)) {
      return;
    }
    final result = finalResolution;
    if (result == null) return;
    final displayed = <String, LearningCardDescriptor>{};
    for (final card in hand) {
      final descriptor = LearningCardDescriptor(
        cardId: card.id,
        variantId: card.variant.id,
        conceptIdentity: card.id,
        tags: card.variant.tags.toList(),
        spiceLevel: card.chiliLevel,
        primaryPreferenceIds: [
          for (final tag
              in _conceptCatalog
                  .ratingFor(card.id, card.variant.id)
                  .primaryPreferenceTags)
            'v3.preference.$tag',
        ],
      );
      displayed[descriptor.identity] = descriptor;
    }
    final own = _activeReveal?.choice.usage;
    if (own != null) displayed[own.usageId] = usageLearningDescriptor(own);
    final accepted = <String, NetworkUsageProjection>{};
    if (!result.mutualAbandon) {
      for (final card in result.compromise) {
        accepted[card.usage.usageId] = card.usage;
      }
    }
    for (final action
        in corruption?.actions ?? <NetworkCorruptionActionDto>[]) {
      if (action.status == ActionExecutionStatus.COMPLETED) {
        accepted[action.usage.usageId] = action.usage;
      }
    }
    for (final action in round!.recoveryHistory) {
      if (action.completed) accepted[action.usage.usageId] = action.usage;
    }
    final played = <String>{if (own != null) own.usageId};
    for (final card in result.compromise.where(
      (c) =>
          c.ownerPlayerId == playerId &&
          c.origin == NetworkCompromiseOrigin.AUCTION,
    )) {
      played.add(card.usage.usageId);
      displayed.remove(card.cardId);
      displayed[card.usage.usageId] = usageLearningDescriptor(card.usage);
    }
    final resistances = <JsonMap>[];
    final proposal = negotiation?.proposal;
    final response = negotiation?.response;
    if (!result.mutualAbandon && proposal != null && response != null) {
      if (isInitialWinner && !response.acceptAuction) {
        for (final item in proposal.cards) {
          resistances.add({
            'usage': item.usage.toJson(),
            'role': _learningRoleFor(item, playerId).name,
            'signal': ResistanceSignal.resultModification.name,
          });
        }
      }
      if (isInitialLoser && proposal.inversionRequested) {
        final initial = result.compromise
            .where((c) => c.origin == NetworkCompromiseOrigin.INITIAL_DUEL)
            .firstOrNull;
        if (initial != null) {
          resistances.add({
            'usage': initial.usage.toJson(),
            'role': _learningRoleFor(initial, playerId).name,
            'signal': ResistanceSignal.inversionSought.name,
          });
        }
      }
    }
    _pendingLearning =
        freezeJson({
              'round_id': round!.roundId,
              'round_number': roundNumber,
              'event_id': '${session.id}/${round!.roundId}/$playerId',
              'hand': displayed.values.map(_descriptorJson).toList(),
              'played': played.toList(),
              'locked': [if (lockedCardId != null) lockedCardId],
              'accepted': accepted.values.map((u) => u.toJson()).toList(),
              'resistance': resistances,
            })
            as JsonMap;
    await _persist();
  }

  Future<void> _flushLearning(NetworkGameRoundStateDto current) async {
    final pending = _pendingLearning;
    if (pending == null || _flushingLearning) return;
    final oldNumber = pending['round_number']! as int;
    if (current.roundNumber < oldNumber ||
        (current.roundNumber == oldNumber &&
            !current.readyNextPlayerIds.containsAll(playerIds))) {
      return;
    }
    _flushingLearning = true;
    try {
      final canonical = current.roundId == pending['round_id']
          ? current
          : await repository.getRound(
              sessionId: session.id,
              roundId: pending['round_id']! as String,
            );
      if (!canonical.readyNextPlayerIds.containsAll(playerIds) ||
          (canonical.phase != NetworkGamePhase.waitingNext &&
              canonical.phase != NetworkGamePhase.closed))
        return;
      final completedUsages = <String, NetworkUsageProjection>{
        for (final raw in pending['accepted']! as List)
          if (NetworkUsageProjection.fromJson(raw as JsonMap) case final usage)
            usage.usageId: usage,
        for (final recovery in canonical.recoveryHistory)
          if (recovery.completed) recovery.usageId: recovery.usage,
        for (final action
            in canonical.corruption?.actions ?? <NetworkCorruptionActionDto>[])
          if (action.status == ActionExecutionStatus.COMPLETED)
            action.identity: action.usage,
      };
      await learning.recordCompletedRound(
        eventId: pending['event_id']! as String,
        expectedPlayers: playerIds.toSet(),
        completedPlayers: canonical.readyNextPlayerIds,
        hand: HandLearningEvent(
          playerId: playerId,
          availableCards: [
            for (final raw in pending['hand']! as List)
              _descriptorFromJson(raw as JsonMap),
          ],
          playedCardIdentities: (pending['played']! as List)
              .cast<String>()
              .toSet(),
          lockedCardIdentities: (pending['locked']! as List)
              .cast<String>()
              .toSet(),
        ),
        accepted: [
          for (final usage in completedUsages.values)
            usageLearningOutcome(usage),
        ],
        resistance: [
          for (final raw in pending['resistance']! as List)
            ResistanceLearningEvent(
              playerId: playerId,
              card: usageLearningDescriptor(
                NetworkUsageProjection.fromJson(
                  (raw as JsonMap)['usage']! as JsonMap,
                ),
              ),
              resistedRole: LearningRole.values.byName(raw['role']! as String),
              signal: ResistanceSignal.values.byName(raw['signal']! as String),
            ),
        ],
      );
      _learnedState = await learning.state();
      _learningRecordedRounds.add(oldNumber);
      _pendingLearning = null;
      await _persist(roundNumber: current.roundNumber);
    } finally {
      _flushingLearning = false;
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

  Future<void> _activatePreparedRound(NetworkGameRoundStateDto next) async {
    if (round != null && next.roundNumber > roundNumber) {
      // Realtime/RPC refreshes can skip WAITING_NEXT entirely. Preparing the
      // local hand and clearing the old secret cannot depend on observing it.
      await _prepareNextRound(targetRound: next.roundNumber);
      _nextRoundPrepared = false;
      _activeReveal = null;
      selectedCard = null;
      await _persist(roundNumber: next.roundNumber);
    }
  }

  void _refill(int targetRound, {Set<String> excluded = const {}}) {
    var needed =
        const BalanceConfig().handSize -
        _runtime.where((c) => c.zone == CardZone.HAND).length;
    if (needed <= 0) return;
    final random = Random(_stableHash('$playerId/$targetRound/$_deckCycle'));
    while (needed > 0) {
      final concept = _conceptPool(
        excludeHeld: true,
        excluded: excluded,
      ).draw(random);
      if (concept == null) break;
      final materialized = concept.concept.kind == ConceptKind.zones
          ? concept.materialize(random)
          : null;
      _runtime = [
        ..._runtime,
        CardRuntimeState(
          cardId: concept.concept.id,
          variantId: materialized?.actionId,
          zone: CardZone.HAND,
        ),
      ];
      needed--;
    }
  }

  void _buildDeckCycle() {
    if (_cycleInitialized) {
      if (_usageCheckpoint.cycle == _deckCycle) return;
      _priorCheckpoints = [..._priorCheckpoints, _usageCheckpoint];
    }
    _usageCheckpoint = ConceptUsageCheckpoint.startCycle(
      sessionId: session.id,
      ownerPlayerId: playerId,
      cycle: _deckCycle,
      catalog: _conceptCatalog.concepts,
      initialClothing: _initialClothing,
    );
    _cycleInitialized = true;
  }

  NetworkDuelCard? _networkCard(
    String cardId, {
    String? occurrenceId,
    String? variantId,
    ConceptActionOption? option,
    bool recovery = false,
  }) {
    for (final checkpoint in [_usageCheckpoint, ..._priorCheckpoints]) {
      for (final usage in checkpoint.usagesByIntent.values) {
        if (usage.usageId == occurrenceId) {
          return _cardFromUsage(
            NetworkUsageProjection.fromSnapshot(
              usage,
              sharedParameterKeys: const {},
              sharedEffectIds: const {},
              includePersonalValue: true,
            ),
          );
        }
      }
    }
    final definition = _definitions[cardId];
    if (definition == null) return null;
    final options = recovery
        ? (_currentOptions(recovery: true)[cardId] ?? const [])
        : choicesFor(cardId);
    final selected =
        option ??
        (variantId == null
            ? defaultAction(cardId, options)
            : options.where((o) => o.choice.actionId == variantId).firstOrNull);
    if (selected == null) return null;
    final eligible = selected.variant;
    final variant = definition.variants.firstWhere(
      (v) => v.stableId == eligible.id,
    );
    final preferenceIds = eligible.tags
        .where((t) => t.startsWith('v3.preference.'))
        .toList();
    if (preferenceIds.isEmpty) return null;
    bool allows(ProfileRole role) {
      if (_v4Profile != null) {
        return _conceptPersonalValue(
              cardId,
              selected,
              role == ProfileRole.FAIRE
                  ? CardOccurrenceDirection.FAIRE
                  : role == ProfileRole.RECEVOIR
                  ? CardOccurrenceDirection.RECEVOIR
                  : CardOccurrenceDirection.GENERAL,
            ) !=
            null;
      }
      return preferenceIds.every((id) {
        final value = _profile(playerId).preference(id);
        return value.status == PreferenceStatus.ACCEPTED &&
            value.valueFor(role) != null;
      });
    }

    final reversible =
        eligible.invertible &&
        eligible.tags.contains('v3.direction.faire') &&
        eligible.tags.contains('v3.direction.recevoir');
    final fixed = eligible.tags.contains('v3.direction.mutuel')
        ? CardOccurrenceDirection.MUTUEL
        : eligible.tags.contains('v3.direction.solo')
        ? CardOccurrenceDirection.SOLO
        : _fixedDirection(definition, variant);
    CardDirectionSelection direction;
    try {
      direction = const CardDirectionEngine().select(
        reversible: reversible,
        fixedDirection: fixed,
        faireAllowed: allows(ProfileRole.FAIRE),
        recevoirAllowed: allows(ProfileRole.RECEVOIR),
        chooseFaire: Random(
          _stableHash('${session.id}/$playerId/$_deckCycle/$cardId/direction'),
        ).nextBool(),
      );
    } on StateError {
      return null;
    }
    final role = _profileRole(
      direction.effectiveDirection,
      fallback: ProfileRole.GENERAL,
    );
    if (_v4Profile == null && !allows(role)) return null;
    final elementId = preferenceIds.first;
    final value = _conceptPersonalValue(
      cardId,
      selected,
      direction.effectiveDirection,
    );
    if (value == null) return null;
    return NetworkDuelCard(
      definition: definition,
      engine: EngineCard(id: cardId, variants: [eligible]),
      variant: eligible,
      role: role,
      preference: _preference(
        elementId,
        role,
        value,
        faire: allows(ProfileRole.FAIRE)
            ? _conceptPersonalValue(
                cardId,
                selected,
                CardOccurrenceDirection.FAIRE,
              )
            : null,
        recevoir: allows(ProfileRole.RECEVOIR)
            ? _conceptPersonalValue(
                cardId,
                selected,
                CardOccurrenceDirection.RECEVOIR,
              )
            : null,
      ),
      occurrenceId: occurrenceId ?? cardId,
      nativeDirection: direction.nativeDirection,
      effectiveDirection: direction.effectiveDirection,
    );
  }

  NetworkDuelCard _cardFromUsage(
    NetworkUsageProjection usage, {
    bool forDisplay = false,
  }) {
    final action = usage.resolvedAction;
    final inverse = usage.toJson()['inverted_resolution'] as JsonMap?;
    final oppositeValue = inverse?['snapshot_value'] as int?;
    final actionId = (action['stage_id'] ?? action['variant_id'])! as String;
    final template = _definitions[usage.conceptId] ?? _definitions.values.first;
    final variant = CardVariantDefinition.fromJson({
      ...template.variants.first.reader.json,
      'stable_id': actionId,
      'card_id': usage.conceptId,
      'action_text': action['action_text'],
      'details_text':
          (action['parameters'] as Map).containsKey('display_details')
          ? (action['parameters'] as Map)['display_details']
          : template.detailsText,
      'chili_level': action['effective_chili'],
    });
    final definition = CardDefinition.fromJson({
      ...template.reader.json,
      'stable_id': usage.conceptId,
      'title':
          (action['parameters'] as Map)['display_title'] ??
          _definitions[usage.conceptId]?.title ??
          usage.conceptId,
      'action_text': action['action_text'],
      'details_text':
          (action['parameters'] as Map).containsKey('display_details')
          ? (action['parameters'] as Map)['display_details']
          : template.detailsText,
      if ((action['parameters'] as Map).containsKey('display_illustration'))
        'illustration_key':
            (action['parameters'] as Map)['display_illustration'],
      'variants': [variant.toJson()],
    });
    final direction = CardOccurrenceDirection.values.byName(
      action['direction']! as String,
    );
    final role = _profileRole(direction, fallback: ProfileRole.GENERAL);
    final engine = EngineVariant(
      id: actionId,
      chiliLevel: action['effective_chili']! as int,
      tags: (action['tags']! as List).cast<String>().toSet(),
    );
    return NetworkDuelCard(
      definition: definition,
      engine: EngineCard(id: usage.conceptId, variants: [engine]),
      variant: engine,
      role: role,
      preference: _preference(
        'historical.snapshot',
        role,
        usage.snapshotValue!,
        faire: forDisplay && role == ProfileRole.RECEVOIR
            ? oppositeValue
            : null,
        recevoir: forDisplay && role == ProfileRole.FAIRE
            ? oppositeValue
            : null,
      ),
      occurrenceId: usage.usageId,
      nativeDirection: CardOccurrenceDirection.values.byName(
        usage.toJson()['native_direction']! as String,
      ),
      effectiveDirection: direction,
    );
  }

  int _recoveryGain(NetworkRecoveryDto proposal) {
    final projection = _withPrivateValues(proposal.usage);
    final card = _cardFromUsage(projection);
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
    Map<String, ConceptActionOption> actionChoices = const {},
  }) {
    final cards = <NetworkCompromiseCardDto>[];
    for (final id in cardIds) {
      final card = auctionCards
          .where((item) => item.identity == id)
          .firstOrNull;
      if (card == null) throw ArgumentError('Carte d’enchère indisponible');
      final projection = _reserveSecondary(
        card,
        '${round!.roundId}:negotiation:$id',
        option: actionChoices[id],
        source: _publicDiscards
            .where((r) => r.usageId == id)
            .firstOrNull
            ?.usage,
      );
      cards.add(
        NetworkCompromiseCardDto.fromUsage(
          projection,
          origin: NetworkCompromiseOrigin.AUCTION,
          logicalOrder: cards.length + 1,
        ),
      );
    }
    final retained = cards.map((c) => c.usage.usageId).toSet();
    for (final entry in _reservedChoices.entries.toList()) {
      if (entry.key.startsWith('${round!.roundId}:negotiation:') &&
          !retained.contains(entry.value.usageId)) {
        _releaseSecondary(entry.key);
      }
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
      cardIds: [for (final card in offer.cards) card.usageId],
      cardValues: {
        for (final card in offer.cards) card.usageId: card.snapshotValue,
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
            cardIds: [for (final card in value.cards) card.usageId],
            cardValues: {
              for (final card in value.cards) card.usageId: card.snapshotValue,
            },
          );
    final response = dto?.response;
    return NegotiationState(
      initialWinnerId: finalWinnerId ?? initial.winnerPlayerId!,
      initialLoserId: finalLoserId ?? initial.loserPlayerId!,
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

  PlayerGameProfile _profile(String id) {
    if (id == playerId && _v4Profile != null) {
      return playerGameProfileFromLearningState(
        adaptiveProfileFromV4Profile(_v4Profile!),
      );
    }
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

  Future<void> _persist({int? roundNumber}) {
    if (_localSessionCleared) return Future.value();
    return privateStore.saveGame(
      sessionId: session.id,
      playerId: playerId,
      state: NetworkPrivateGameState(
        roundNumber: roundNumber ?? this.roundNumber,
        cards: _runtime,
        activeReveal: _activeReveal,
        nextRoundPrepared: _nextRoundPrepared,
        learningRecordedRounds: _learningRecordedRounds,
        deckCycle: _deckCycle,
        infiniteMode: _infiniteMode,
        deckStyle: _deckStyle,
        publicDiscards: _publicDiscards,
        choiceVersion: _choiceVersion,
        cancelCommitRequested: _cancelCommitRequested,
        conceptCheckpoint: _usageCheckpoint,
        reservedChoices: _reservedChoices,
        pendingSecondaryCommand: _pendingSecondaryCommand,
        pendingLearning: _pendingLearning,
        priorCheckpoints: _priorCheckpoints,
        activeChili: _context.chiliActive,
        sessionMode: sessionMode,
        presence: _presence,
        persistentEffects: _persistentEffects,
        accessoryPool: _accessoryPool,
        initialClothing: _initialClothing,
        clothesByPlayer: _context.clothesByPlayer,
        clothingObservations: _clothingObservations,
      ),
    );
  }

  void _capturePublicDiscards(NetworkGameRoundStateDto value) {
    if (value.finalResolution == null) return;
    void add(NetworkUsageProjection usage, {bool finalAction = false}) {
      final index = _publicDiscards.indexWhere(
        (r) => r.usageId == usage.usageId,
      );
      if (index >= 0) {
        // A final resolution may select the already frozen inverted action.
        if (finalAction) {
          final next = List<NetworkPlayedCardRecord>.of(_publicDiscards);
          next[index] = NetworkPlayedCardRecord(
            usage: usage,
            roundNumber: value.roundNumber,
          );
          _publicDiscards = next;
        }
        return;
      }
      _publicDiscards = [
        ..._publicDiscards,
        NetworkPlayedCardRecord(usage: usage, roundNumber: value.roundNumber),
      ];
    }

    for (final card in value.finalResolution!.compromise) {
      add(card.usage, finalAction: true);
    }
    for (final action
        in value.corruption?.actions ?? <NetworkCorruptionActionDto>[]) {
      if (value.corruption!.accepted == true) add(action.usage);
    }
    for (final action in value.recoveryHistory) {
      if (action.response == RecoveryResponse.ACCEPT) add(action.usage);
    }
    for (final reveal in [value.ownReveal, value.opponentReveal]) {
      if (reveal != null) add(reveal.choice.usage!);
    }
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

  int _fixtureValue(String id, String element, ProfileRole role) =>
      8 + (_stableHash('$id/$element/${role.name}') % 11);

  int? _privateValue(String elementId, ProfileRole role) {
    final v4 = _v4Profile;
    if (v4 != null) {
      final tag = elementId.replaceFirst('v3.preference.', '');
      final effective = ProfilePreferenceRole.values.byName(
        role.name.toLowerCase(),
      );
      final preference =
          v4.preference(ProfilePreferenceKey(tagId: tag, role: effective)) ??
          v4.preference(
            ProfilePreferenceKey(
              tagId: tag,
              role: ProfilePreferenceRole.general,
            ),
          );
      return preference == null || preference.excluded
          ? null
          : preference.pa?.round();
    }
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

  static String _secureNonce() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  String? get finalWinnerId =>
      initialResolution?.winnerPlayerId ??
      finalResolution?.finalWinnerPlayerId ??
      finalResolution?.retainedPlayerId;
  String? get finalLoserId {
    final winner = finalWinnerId;
    if (winner == null) return null;
    return playerIds.where((id) => id != winner).firstOrNull;
  }

  bool get isFinalLoser => finalLoserId == playerId;
  bool get isFinalWinner => finalWinnerId == playerId;
  bool get isNegotiationProposer =>
      finalResolution == null ? isInitialLoser : isFinalLoser;
  bool get isNegotiationResponder =>
      finalResolution == null ? isInitialWinner : isFinalWinner;
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

  bool get ownClothingChangeIsDeterministic {
    final cards = actionProjection?.cards.where(
      (card) => card.targetPlayerIds.contains(playerId),
    );
    if (cards == null || cards.isEmpty) return false;
    var found = false;
    for (final card in cards) {
      final behavior = V4ClothingBehavior.values.byName(
        (card.parameters['clothing_behavior'] as String?) ?? 'none',
      );
      if (behavior == V4ClothingBehavior.removeOne ||
          behavior == V4ClothingBehavior.removeTwo) {
        found = true;
      } else if (behavior != V4ClothingBehavior.none) {
        return false;
      }
    }
    return found;
  }

  int suggestedOwnClothingCount() {
    final canonicalCount =
        round?.clothingCounts[playerId] ??
        _context.clothesByPlayer[playerId] ??
        0;
    final cards = actionProjection?.cards
        .where((card) => card.targetPlayerIds.contains(playerId))
        .toList(growable: false);
    if (cards == null || cards.isEmpty) return canonicalCount;
    final behaviors = <V4ClothingBehavior>[];
    for (final card in cards) {
      final behavior = V4ClothingBehavior.values.byName(
        (card.parameters['clothing_behavior'] as String?) ?? 'none',
      );
      if (behavior == V4ClothingBehavior.removeOne ||
          behavior == V4ClothingBehavior.removeTwo) {
        behaviors.add(behavior);
      } else if (behavior != V4ClothingBehavior.none) {
        // Outfit choices and resets require the player's real resulting count.
        return canonicalCount;
      }
    }
    var snapshot = V4ClothingSnapshot(
      state: canonicalCount == 0 ? V4ClothingState.nu : V4ClothingState.habille,
      removableClothing: canonicalCount,
    );
    for (final behavior in behaviors) {
      snapshot = const V4ClothingEngine().apply(
        current: snapshot,
        behavior: behavior,
        fullOutfitCount: canonicalCount,
      );
    }
    return snapshot.removableClothing;
  }

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
  bool get mustSwitchHybridContext {
    if (sessionMode != V4SessionMode.hybrid) return false;
    final alternate = _presence == V4SessionPresence.presentiel
        ? V4SessionPresence.distance
        : V4SessionPresence.presentiel;
    final alternateAvailability = _availablePlayableConcepts(alternate);
    final barrierOrientation = round?.hybridAvailabilityOrientation;
    if (barrierOrientation == orientation &&
        round!.hybridAvailabilityByPlayer.values.any(
          (report) =>
              report.orientation == orientation &&
              !report.hasPlayableCurrentOrientation &&
              report.hasPlayableAlternateOrientation,
        )) {
      return true;
    }
    if (round?.cycleExhausted == true && alternateAvailability > 0) {
      return true;
    }
    return const V4CycleGuard().evaluate(
          mode: sessionMode,
          activeOccurrencesByPlayer: {
            playerId: _availablePlayableConcepts(_presence),
          },
          alternateContextOccurrencesByPlayer: {
            playerId: alternateAvailability,
          },
        ) ==
        V4CycleAvailability.switchHybridContext;
  }

  bool get canStartNextRound =>
      !deckExhausted &&
      !mustSwitchHybridContext &&
      _hybridAvailabilityBarrierSatisfied;

  bool get _hybridAvailabilityBarrierSatisfied {
    final current = round;
    if (sessionMode != V4SessionMode.hybrid ||
        current?.hybridAvailabilityOrientation == null) {
      return true;
    }
    if (current!.hybridAvailabilityOrientation != orientation) return false;
    return playerIds.every((id) {
      final report = current.hybridAvailabilityByPlayer[id];
      return report?.orientation == orientation &&
          report!.hasPlayableCurrentOrientation;
    });
  }

  DeckExhaustionChoice? get sessionClosureIntent => _sessionClosureIntent;
  Future<void> clearLocalSessionState() async {
    _localSessionCleared = true;
    _watchGeneration++;
    _watchRetryTimer?.cancel();
    _reconciliationTimer?.cancel();
    _reconciliationTimer = null;
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }
    await privateStore.clear(sessionId: session.id, playerId: playerId);
    await privateStore.clearGame(sessionId: session.id, playerId: playerId);
  }

  bool _isSuperseded(NetworkGameRoundStateDto value) {
    final revision = value.roundRevision;
    if (revision == null) return false;
    return (_latestRoundRevisions[value.roundId] ?? revision) > revision;
  }

  bool _hybridAvailabilityReportRequired(NetworkGameRoundStateDto value) {
    if (sessionMode != V4SessionMode.hybrid ||
        value.hybridAvailabilityOrientation != orientation) {
      return false;
    }
    final report = value.hybridAvailabilityByPlayer[playerId];
    return report?.orientation != orientation;
  }

  Future<void> _reportHybridAvailability(NetworkGameRoundStateDto value) async {
    if (_reportingHybridAvailability ||
        repository is! NetworkSessionFlowRepository ||
        value.phase != NetworkGamePhase.waitingNext ||
        value.hybridAvailabilityOrientation != orientation) {
      return;
    }
    final alternate = _presence == V4SessionPresence.presentiel
        ? V4SessionPresence.distance
        : V4SessionPresence.presentiel;
    final availability = NetworkHybridAvailabilityDto(
      orientation: orientation,
      hasPlayableCurrentOrientation: _availablePlayableConcepts(_presence) > 0,
      hasPlayableAlternateOrientation:
          _availablePlayableConcepts(alternate) > 0,
    );
    _reportingHybridAvailability = true;
    try {
      await _applyNow(
        await (repository as NetworkSessionFlowRepository)
            .reportHybridAvailability(
              command: _command(
                'REPORT_HYBRID_AVAILABILITY_'
                '${value.hybridAvailabilityGeneration}_'
                '${orientation.name}',
              ),
              availability: availability,
              generation: value.hybridAvailabilityGeneration,
            ),
      );
    } catch (error) {
      _fail(error);
    } finally {
      _reportingHybridAvailability = false;
    }
  }

  Future<void> _startNextRoundAutomatically({
    bool applyImmediately = false,
  }) async {
    if (_startingNextRound ||
        viewState != NetworkGameViewState.waitingNext ||
        !canStartNextRound) {
      return;
    }
    _startingNextRound = true;
    try {
      final boundaryRoundId = round!.roundId;
      final boundaryRoundNumber = roundNumber;
      await _prepareNextRound();
      if (round?.roundId != boundaryRoundId) {
        return;
      }
      final updated = await repository.readyNextRound(
        command: _command(
          'START_NEXT_ROUND',
          roundId: boundaryRoundId,
          roundNumber: boundaryRoundNumber,
        ),
      );
      if (applyImmediately) {
        await _applyNow(updated);
      } else {
        await _apply(updated);
      }
    } catch (error) {
      _fail(error);
    } finally {
      _startingNextRound = false;
    }
  }

  Future<void> _applyNow(
    NetworkGameRoundStateDto value, {
    bool roundBound = false,
  }) async {
    if (_disposed) return;
    if (value.sessionId != session.id) {
      _fail(const NetworkRoundException('ROUND_NOT_FOUND'));
      return;
    }
    if (value.roundNumber < roundNumber) return;
    final revision = value.roundRevision;
    final latest = _latestRoundRevisions[value.roundId];
    if (revision == null) {
      if (latest != null) return;
    } else {
      if (latest != null && revision < latest) return;
      _latestRoundRevisions[value.roundId] = revision;
    }
    if (value.usageContractVersion != 1) {
      _fail(const NetworkRoundException('USAGE_CONTRACT_NOT_DEPLOYED'));
      return;
    }
    if (value.deckCycle < _deckCycle) return;
    await _flushLearning(value);
    _context = _context.copyWith(
      chiliActive: value.v4UnlockedSpice,
      chiliUnlocked: value.v4UnlockedSpice,
    );
    if (value.hasCanonicalPersistentEffects) {
      _persistentEffects = List.of(value.v4PersistentEffects);
    }
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
        mode: SessionMode.hybrid,
        proximity: _presence == V4SessionPresence.presentiel
            ? ProximityState.TOGETHER
            : ProximityState.SEPARATED,
      );
      if (previousPresence != _presence &&
          value.phase != NetworkGamePhase.waitingNext) {
        _rebuildHandForPresence(value.roundNumber);
        await _persist(roundNumber: value.roundNumber);
        if (_isSuperseded(value)) return;
      }
    }
    _deckStyle = value.deckStyle;
    _infiniteMode = value.infiniteMode;
    if (publicCycleAdvanced) {
      await _reconcileSecondaryChoices(value);
      await _transitionToCanonicalDeckCycle(
        deckCycle: value.deckCycle,
        targetRound: value.roundNumber + 1,
      );
      if (_isSuperseded(value)) return;
    }
    if (round?.roundId != value.roundId && !roundBound) {
      await _activatePreparedRound(value);
      if (_isSuperseded(value)) return;
      if (value.roundNumber < roundNumber) return;
      await _switchRound(value, applyImmediately: true);
      return;
    }
    round = value;
    if (value.phase == NetworkGamePhase.commit ||
        value.phase == NetworkGamePhase.reveal ||
        value.phase == NetworkGamePhase.ready) {
      _ensureReconciliation();
    } else {
      _reconciliationTimer?.cancel();
      _reconciliationTimer = null;
    }
    await _reconcileSecondaryChoices(value);
    _capturePublicDiscards(value);
    await _closeNormalRoundForRecovery(value);
    await _reconcilePublicLifecycle(value);
    if (_disposed ||
        _isSuperseded(value) ||
        round?.roundId != value.roundId ||
        value.roundNumber < roundNumber) {
      return;
    }
    switch (value.phase) {
      case NetworkGamePhase.commit:
        if (_cancelCommitRequested) {
          if (!_cancelling) unawaited(cancelSelection());
          return;
        }
        if (value.ownCommitRecorded) {
          if (_activeReveal == null) {
            _fail(const NetworkRoundException('ROUND_LOCAL_SECRET_MISSING'));
          } else {
            viewState = NetworkGameViewState.waitingForPartner;
          }
        } else {
          // Missing remote commit is not evidence of cancellation. Replay the
          // persisted projection and nonce; never engage or consume again.
          if (_activeReveal != null) {
            if (!_committing) {
              _committing = true;
              try {
                await _persist();
                final reveal = _activeReveal!;
                final updated = await repository.submitCommit(
                  command: _command(
                    'COMMIT',
                    roundId: value.roundId,
                    roundNumber: value.roundNumber,
                    choiceVersion: _choiceVersion,
                  ),
                  commitment: contract.commit(
                    sessionRound: reveal.sessionRound,
                    playerId: playerId,
                    choice: reveal.choice,
                    nonce: reveal.nonce,
                  ),
                );
                await _applyNow(updated);
              } catch (error) {
                _fail(error);
              } finally {
                _committing = false;
              }
            }
            return;
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
      case NetworkGamePhase.finalDefenseDecision:
        _fail(const NetworkRoundException('ROUND_MECHANIC_REMOVED'));
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
        viewState = NetworkGameViewState.actionInProgress;
        break;
      case NetworkGamePhase.corruptionDecision:
        viewState = NetworkGameViewState.corruptionDecision;
        break;
      case NetworkGamePhase.corruptionResponse:
        viewState = NetworkGameViewState.corruptionResponse;
        break;
      case NetworkGamePhase.corruptionExecution:
        // Compatibility only: the pending SQL migration converts persisted
        // legacy rows to the normal FINAL_RESOLVED action flow.
        viewState = NetworkGameViewState.actionInProgress;
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
        await _flushLearning(value);
        viewState = NetworkGameViewState.waitingNext;
        notifyListeners();
        if (_hybridAvailabilityReportRequired(value)) {
          final preparationKey =
              '${value.roundId}:${value.hybridAvailabilityGeneration}:'
              '${orientation.name}';
          if (_preparedHybridAvailabilityKey != preparationKey) {
            _rebuildHandForPresence(value.roundNumber + 1);
            _preparedHybridAvailabilityKey = preparationKey;
            await _persist(roundNumber: value.roundNumber);
          }
          await _reportHybridAvailability(value);
          return;
        }
        if (canStartNextRound) {
          await _startNextRoundAutomatically(applyImmediately: true);
        }
        return;
      case NetworkGamePhase.closed:
        viewState = NetworkGameViewState.waitingNext;
        notifyListeners();
        await _switchRound(
          await repository.getCurrentRound(sessionId: session.id),
          applyImmediately: true,
        );
        return;
      case NetworkGamePhase.sessionClosed:
        viewState = NetworkGameViewState.sessionEnded;
        break;
    }
    notifyListeners();
  }

  Future<void> _transitionToCanonicalDeckCycle({
    required int deckCycle,
    required int targetRound,
  }) async {
    if (deckCycle <= _deckCycle) return;
    if (round != null) {
      await _reconcileSecondaryChoices(round!);
      _capturePublicDiscards(round!);
      await _stageLearningForRound();
    }
    for (final intent in _reservedChoices.keys.toList()) {
      _releaseSecondary(intent);
    }
    _deckCycle = deckCycle;
    _runtime = [];
    _nextRoundPrepared = false;
    _buildDeckCycle();
    _refill(targetRound);
    await _persist(roundNumber: roundNumber);
  }

  int _availablePlayableConcepts(V4SessionPresence presence) {
    final context = _context.copyWith(
      proximity: presence == V4SessionPresence.presentiel
          ? ProximityState.TOGETHER
          : ProximityState.SEPARATED,
    );
    final options = const ConceptActionOptions().evaluate(
      catalog: _conceptCatalog,
      context: context,
      actor: _profile(playerId),
      partner: _profile(opponentId),
      hierarchy: _hierarchy,
    );
    return options.keys
        .where(
          (id) =>
              _usageCheckpoint.availableFor(id) > 0 &&
              options[id]!.any((o) => _stageAvailable(id, o)),
        )
        .length;
  }

  void _rebuildHandForPresence(int targetRound) {
    final available = _currentOptions();
    _runtime = _runtime
        .where(
          (card) =>
              card.zone != CardZone.HAND || available.containsKey(card.cardId),
        )
        .toList();
    _refill(targetRound);
  }

  Future<void> _publishActionProjection(NetworkGameRoundStateDto value) async {
    if (repository is! NetworkV4ActionRepository ||
        value.finalResolution == null ||
        _publishingAction)
      return;
    _publishingAction = true;
    try {
      final result = value.finalResolution!;
      final cards = result.mutualAbandon
          ? <NetworkResolvedActionCardDto>[]
          : [
              for (final card in result.compromise)
                NetworkResolvedActionCardDto.fromUsage(card.usage),
            ];
      final required = <String>{
        for (final card in cards)
          if (card.parameters['clothing_behavior'] != null &&
              card.parameters['clothing_behavior'] != 'none')
            ...card.targetPlayerIds,
      };
      await _applyNow(
        await (repository as NetworkV4ActionRepository)
            .publishV4ActionProjection(
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

  int? _conceptPersonalValue(
    String conceptId,
    ConceptActionOption option,
    CardOccurrenceDirection direction,
  ) {
    if (_v4Profile?.excludesStage(
          conceptId,
          option.choice.actionId,
          direction.name,
        ) ??
        false) {
      return null;
    }
    final rating = _conceptCatalog.optionalRatingFor(
      option.parameters['practice_concept_id'] as String? ?? conceptId,
      option.parameters['practice_action_id'] as String? ??
          option.choice.actionId,
    );
    if (rating == null) return null;
    if (_ratingProfile case final profile?) {
      final result = const V4CardRatingEngine().initializeForDirection(
        profile: profile,
        variant: rating,
        conceptId:
            option.parameters['practice_concept_id'] as String? ?? conceptId,
        direction: direction.name,
        vetoTags: _conceptCatalog.vetoTags(conceptId),
      );
      if (result.kind == V4RatingResultKind.excluded ||
          result.kind == V4RatingResultKind.unavailable) {
        return null;
      }
      final explicit = _cardRatings.explicitEstimate(
        CardRatingKey(
          profileId: profile.profileId,
          cardId: conceptId,
          variantId: option.choice.actionId,
          role: ProfilePreferenceRole.parse(direction.name),
        ),
      );
      return explicit?.round().clamp(1, 20) ?? result.rawScore?.toInt();
    }
    // Existing private-profile test/local flow, using the same classified weights.
    final role = _profileRole(direction, fallback: ProfileRole.GENERAL);
    var sum = 0.0;
    var total = 0.0;
    for (final entry in [
      for (final tag in rating.primaryPreferenceTags) (tag, 1.0),
      for (final tag in rating.secondaryPreferenceTags) (tag, .5),
    ]) {
      final value = _privateValue('v3.preference.${entry.$1}', role);
      if (value == null) return null;
      sum += value * entry.$2;
      total += entry.$2;
    }
    return total == 0 ? null : (sum / total).round();
  }

  List<String> _ratedPreferenceIds(
    String conceptId,
    ConceptActionOption option,
  ) {
    final rating = _conceptCatalog.optionalRatingFor(
      option.parameters['practice_concept_id'] as String? ?? conceptId,
      option.parameters['practice_action_id'] as String? ??
          option.choice.actionId,
    );
    return [
      for (final tag in [
        ...?rating?.primaryPreferenceTags,
        ...?rating?.secondaryPreferenceTags,
      ])
        'v3.preference.$tag',
    ];
  }

  List<String> _primaryPreferenceIds(
    String conceptId,
    ConceptActionOption option,
  ) {
    final rating = _conceptCatalog.optionalRatingFor(
      option.parameters['practice_concept_id'] as String? ?? conceptId,
      option.parameters['practice_action_id'] as String? ??
          option.choice.actionId,
    );
    return [
      for (final tag in rating?.primaryPreferenceTags ?? <String>[])
        'v3.preference.$tag',
    ];
  }

  bool isCardPlayable(NetworkDuelCard card) =>
      !stageExcluded(card.id, card.variant.id, card.nativeDirection.name) &&
      choicesFor(card.id).any((o) => o.choice.actionId == card.variant.id) &&
      _usageCheckpoint.availableFor(card.id) > 0;

  Future<void> replaceExcludedCard(String conceptId) async {
    if (viewState != NetworkGameViewState.choosing ||
        _activeReveal != null ||
        _committing) {
      return;
    }
    final held = _runtime
        .where((c) => c.cardId == conceptId && c.zone == CardZone.HAND)
        .firstOrNull;
    if (held == null ||
        !(_v4Profile?.stageVetoes.any((v) => v.conceptId == conceptId) ??
            false)) {
      return;
    }
    await cancelPendingSelection();
    _runtime = _runtime.where((c) => c != held).toList();
    // Refill through the regular private pool, excluding the voluntarily released card.
    _refill(roundNumber, excluded: {conceptId});
    await _persist();
    notifyListeners();
  }

  bool isAuctionCardPlayable(NetworkDuelCard card) =>
      auctionCards.any((c) => c.identity == card.identity);
  bool isCorruptionCardPlayable(NetworkDuelCard card) =>
      corruptionCards.any((c) => c.identity == card.identity);

  @override
  void dispose() {
    _disposed = true;
    _watchGeneration++;
    _watchRetryTimer?.cancel();
    _reconciliationTimer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }
}
