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
    this.corruptionEngine = const CorruptionEngine(),
    this.recoveryEngine = const RecoveryEngine(),
    NetworkProfileLearningStore? learningStore,
    PostGameProfileChoiceStore? profileChoiceStore,
    PlayerGameProfile? privateProfile,
    EngineSessionContext? initialContext,
    DateTime Function()? clock,
    String Function()? nonceFactory,
  }) : _catalog = catalog,
       _privateProfile = privateProfile,
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
    _context =
        initialContext ??
        EngineSessionContext(
          mode: SessionMode.face_to_face,
          proximity: ProximityState.TOGETHER,
          chiliActive: 2,
          chiliUnlocked: 2,
          physicalStateByPlayer: {for (final id in playerIds) id: 'available'},
          clothesByPlayer: {for (final id in playerIds) id: 5},
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
  final CorruptionEngine corruptionEngine;
  final RecoveryEngine recoveryEngine;
  final DateTime Function() clock;
  final String Function() nonceFactory;
  late final NetworkProfileLearningCoordinator learning;
  late final PostGameProfileChoiceStore _profileChoiceStore;
  final Catalog _catalog;
  late final ConceptRuntimeCatalog _conceptCatalog;
  late ConceptUsageCheckpoint _usageCheckpoint;
  bool _cycleInitialized = false;
  bool _privateStateReady = false;
  List<ConceptUsageCheckpoint> _priorCheckpoints = [];
  Map<String, int> _clothingObservations = {};
  ConceptActionOption? _selectedOption;
  String get _intentId => '${round?.roundId ?? 'opening'}:v$_choiceVersion';
  final PlayerGameProfile? _privateProfile;
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
  Map<String, CardHistoryState> _history = {};
  Set<int> _learningRecordedRounds = {};
  int _deckCycle = 1;
  int _choiceVersion = 0;
  bool _infiniteMode = false;
  PlayerStyle _deckStyle = PlayerStyle.SOFT;
  List<DeckShortage> _deckShortages = [];
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
  String titleFor(String conceptId) =>
      _definitions[conceptId]?.title ?? conceptId;
  ConceptUsageCheckpoint get usageCheckpoint => _usageCheckpoint;
  int get currentClothingCount => _context.clothesByPlayer[playerId] ?? 0;
  String? get pendingClothingObservationUsageId {
    for (final card
        in finalResolution?.compromise ?? <NetworkCompromiseCardDto>[]) {
      if (card.cardId == '013' &&
          card.usage != null &&
          (card.usage!.resolvedAction['actor_player_ids']! as List).contains(
            playerId,
          ) &&
          !_clothingObservations.containsKey(card.usage!.usageId)) {
        return card.usage!.usageId;
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
      if (current == null) await cancelPendingSelection();
    }
    await _persist();
    notifyListeners();
  }

  Future<void> retryCurrentAction() async {
    if (!_privateStateReady) {
      await start();
      return;
    }
    try {
      await _persist();
      await _apply(await repository.getCurrentRound(sessionId: session.id));
    } catch (error) {
      _fail(error);
    }
  }

  bool get decksEmpty => _conceptPool(excludeHeld: true).isEmpty;
  bool get deckExhausted =>
      decksEmpty && !_runtime.any((card) => card.zone == CardZone.HAND);
  PlayerStyle get deckStyle => _deckStyle;
  bool get infiniteMode => _infiniteMode;
  bool get isCycleController => session.players.any(
    (player) =>
        player.userId == playerId && player.role == LobbyPlayerRole.player1,
  );
  List<DeckShortage> get deckShortages => List.unmodifiable(_deckShortages);
  int get faceToFaceDeckRemaining =>
      _conceptPool(excludeHeld: true).classes.values.expand((v) => v).length;
  int get distanceDeckRemaining => faceToFaceDeckRemaining;
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

  List<CardConcept> get heldConcepts => [
    for (final state in _runtime.where((c) => c.zone == CardZone.HAND))
      _conceptCatalog.concepts.concepts.singleWhere(
        (c) => c.id == state.cardId,
      ),
  ];

  List<NetworkDuelCard> get visibleDiscardCards {
    final cards = <NetworkDuelCard>[];
    final seen = <String>{};
    for (final item in _publicDiscards.reversed) {
      final card = item.usage != null
          ? _cardFromUsage(item.usage!)
          : _networkCard(
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
          item.occurrenceId != _activeReveal?.choice.usageId)
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
      if (current.usageContractVersion != 1) {
        throw const NetworkRoundException('USAGE_CONTRACT_NOT_DEPLOYED');
      }
      _followOrientation(current.hybridOrientation);
      await _restoreOrCreatePrivateState(current);
      _privateStateReady = true;
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
    if (choice != DeckExhaustionChoice.newCustomizedGame &&
        choice != DeckExhaustionChoice.finish) {
      final cycle = DeckCycleState(
        style: _deckStyle,
        infinite: _infiniteMode,
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
    selectedCard = hand
        .where((card) => card.identity == occurrenceId)
        .firstOrNull;
    _selectedOption = selectedCard == null
        ? null
        : choicesFor(selectedCard!.id).firstOrNull;
    notifyListeners();
  }

  List<ConceptActionOption> choicesFor(String conceptId) =>
      _currentOptions()[conceptId] ?? const [];

  Future<void> reserveSelection() async {
    final card = selectedCard;
    if (card == null) return;
    _usageCheckpoint = _usageCheckpoint
        .releaseReservation(_intentId)
        .reserve(intentId: _intentId, conceptId: card.id);
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

  Map<String, List<ConceptActionOption>> _currentOptions() =>
      const ConceptActionOptions().evaluate(
        catalog: _conceptCatalog,
        context: _context,
        actor: _profile(playerId),
        partner: _profile(opponentId),
        hierarchy: _hierarchy,
        mediaSendRequired: _context.flags['mediaSendRequired'] == true,
      );

  ConceptDeckPool _conceptPool({bool excludeHeld = false}) {
    final options = _currentOptions();
    return const ConceptDeckEngine().prepare(
      catalog: _conceptCatalog.concepts,
      stock: _usageCheckpoint.stock,
      globalChili: _context.chiliActive,
      style: _deckStyle,
      unavailableConceptIds: {
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
            entry.key: entry.value.map((o) => o.choice.zoneId).nonNulls.toSet(),
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
      final option = choicesFor(
        card.id,
      ).where((o) => o.key == _selectedOption?.key).firstOrNull;
      if (option == null) {
        throw StateError('Selected action is no longer eligible');
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
          command: _command('COMMIT', choiceVersion: _choiceVersion),
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
      'target_player_ids': mutual
          ? playerIds
          : direction == CardOccurrenceDirection.SOLO
          ? <String>[]
          : [actor == playerId ? opponentId : playerId],
      'parameters': {
        ...option.parameters,
        'committed_at': at.toIso8601String(),
        'clothes_at_engagement': _context.clothesByPlayer,
      },
      'accessories': <Object?>[],
      'tags': option.variant.tags.toList(),
      'primary_preference_ids': option.variant.tags
          .where((t) => t.startsWith('v3.preference.'))
          .toList(),
      'personal_values': [
        {
          'player_id': playerId,
          'role': role.name,
          'value': inverted ? card.oppositePersonalValue! : card.personalValue,
        },
      ],
      'effects': [
        for (var i = 0; i < option.variant.effects.length; i++)
          {
            'effect_id': '${card.id}:$i',
            'parameters': option.variant.effects[i].toJson(),
          },
      ],
      'action_text': '${concept.actionText} · ${option.title}',
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
    if (value.usageContractVersion != 1) {
      _fail(const NetworkRoundException('USAGE_CONTRACT_NOT_DEPLOYED'));
      return;
    }
    if (value.sessionId != session.id) {
      _fail(const NetworkRoundException('ROUND_NOT_FOUND'));
      return;
    }
    final publicCycleAdvanced = value.deckCycle > _deckCycle;
    _followOrientation(value.hybridOrientation);
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
      await _switchRound(value);
      return;
    }
    round = value;
    _capturePublicDiscards(value);
    await _closeNormalRoundForRecovery(value);
    await _reconcilePublicLifecycle(value);
    if (_disposed) return;
    switch (value.phase) {
      case NetworkGamePhase.commit:
        if (_cancelCommitRequested) {
          if (!_cancelling) await cancelSelection();
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
                  command: _command('COMMIT', choiceVersion: _choiceVersion),
                  commitment: contract.commit(
                    sessionRound: reveal.sessionRound,
                    playerId: playerId,
                    choice: reveal.choice,
                    nonce: reveal.nonce,
                  ),
                );
                await _apply(updated);
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
    _runtime = _runtime.where((c) => c.zone != CardZone.ENGAGED).toList();
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
          .map((card) => card.occurrenceId)
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
            card.occurrenceId == initial.occurrenceId
                ? card.copyWith(effectiveDirection: direction)
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
      _publicDiscards = List.of(saved.publicDiscards);
      _choiceVersion = saved.choiceVersion;
      _cancelCommitRequested = saved.cancelCommitRequested;
      _usageCheckpoint = saved.conceptCheckpoint!;
      _initialClothing = saved.initialClothing;
      _priorCheckpoints = List.of(saved.priorCheckpoints);
      _clothingObservations = Map.of(saved.clothingObservations);
      if (_usageCheckpoint.sessionId != session.id ||
          _usageCheckpoint.ownerPlayerId != playerId ||
          _usageCheckpoint.cycle != _deckCycle) {
        throw const NetworkRoundException('PRIVATE_CHECKPOINT_SCOPE_MISMATCH');
      }
      _context = _context.copyWith(
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
    _deckCycle = current.deckCycle;
    _deckStyle = current.deckStyle;
    _infiniteMode = current.infiniteMode;
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
    _runtime = _runtime.where((c) => c.zone != CardZone.ENGAGED).toList();
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
    await learning.recordHand(
      cards: visibleHand,
      played: {
        if (reveal != null)
          (reveal.choice.usageId) ??
              '${reveal.choice.cardId}|${reveal.choice.variantId}',
        for (final card in result.compromise)
          if (card.ownerPlayerId == playerId &&
              card.origin == NetworkCompromiseOrigin.AUCTION)
            card.occurrenceId,
      },
      locked: {
        for (final card in _runtime.where((card) => card.locked))
          for (final descriptor in visibleHand)
            if (descriptor.occurrenceId == card.occurrenceId)
              descriptor.identity,
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
        _runtime.where((c) => c.zone == CardZone.HAND).length;
    if (needed <= 0) return;
    if (decksEmpty &&
        _infiniteMode &&
        !_runtime.any(
          (c) => c.zone == CardZone.HAND || c.zone == CardZone.ENGAGED,
        )) {
      _deckCycle++;
      _buildDeckCycle();
    }
    final random = Random(_stableHash('$playerId/$targetRound/$_deckCycle'));
    while (needed > 0) {
      final concept = _conceptPool(excludeHeld: true).draw(random);
      if (concept == null) break;
      _runtime = [
        ..._runtime,
        CardRuntimeState(cardId: concept.concept.id, zone: CardZone.HAND),
      ];
      _history[concept.concept.id] = CardHistoryState.seenUnplayed;
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
    _deckShortages = [];
  }

  NetworkDuelCard? _networkCard(
    String cardId, {
    String? occurrenceId,
    String? variantId,
    ConceptActionOption? option,
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
    final options = choicesFor(cardId);
    final selected =
        option ??
        options
            .where((o) => variantId == null || o.choice.actionId == variantId)
            .firstOrNull;
    if (selected == null) return null;
    final eligible = selected.variant;
    final variant = definition.variants.firstWhere(
      (v) => v.stableId == eligible.id,
    );
    final preferenceIds = eligible.tags
        .where((t) => t.startsWith('v3.preference.'))
        .toList();
    if (preferenceIds.isEmpty) return null;
    bool allows(ProfileRole role) => preferenceIds.every((id) {
      final value = _profile(playerId).preference(id);
      return value.status == PreferenceStatus.ACCEPTED &&
          value.valueFor(role) != null;
    });
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
    if (!allows(role)) return null;
    final elementId = preferenceIds.first;
    final value = _privateValue(elementId, role);
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
            ? _privateValue(elementId, ProfileRole.FAIRE)
            : null,
        recevoir: allows(ProfileRole.RECEVOIR)
            ? _privateValue(elementId, ProfileRole.RECEVOIR)
            : null,
      ),
      occurrenceId: occurrenceId ?? cardId,
      nativeDirection: direction.nativeDirection,
      effectiveDirection: direction.effectiveDirection,
    );
  }

  NetworkDuelCard _cardFromUsage(NetworkUsageProjection usage) {
    final action = usage.resolvedAction;
    final actionId = (action['stage_id'] ?? action['variant_id'])! as String;
    final template = _definitions[usage.conceptId] ?? _definitions.values.first;
    final variant = CardVariantDefinition.fromJson({
      ...template.variants.first.reader.json,
      'stable_id': actionId,
      'card_id': usage.conceptId,
      'action_text': action['action_text'],
      'details_text': null,
      'chili_level': action['effective_chili'],
    });
    final definition = CardDefinition.fromJson({
      ...template.reader.json,
      'stable_id': usage.conceptId,
      'title': _definitions[usage.conceptId]?.title ?? usage.conceptId,
      'action_text': action['action_text'],
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
      ),
      occurrenceId: usage.usageId,
      nativeDirection: CardOccurrenceDirection.values.byName(
        usage.toJson()['native_direction']! as String,
      ),
      effectiveDirection: direction,
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
      deckCycle: _deckCycle,
      infiniteMode: _infiniteMode,
      deckStyle: _deckStyle,
      deckShortages: _deckShortages,
      publicDiscards: _publicDiscards,
      choiceVersion: _choiceVersion,
      cancelCommitRequested: _cancelCommitRequested,
      conceptCheckpoint: _usageCheckpoint,
      priorCheckpoints: _priorCheckpoints,
      activeChili: _context.chiliActive,
      initialClothing: _initialClothing,
      clothesByPlayer: _context.clothesByPlayer,
      clothingObservations: _clothingObservations,
    ),
  );

  void _capturePublicDiscards(NetworkGameRoundStateDto value) {
    if (value.finalResolution == null) return;
    final known = _publicDiscards.map((card) => card.occurrenceId).toSet();
    void add(
      String cardId,
      String variantId,
      String occurrenceId, [
      NetworkUsageProjection? usage,
    ]) {
      if (!known.add(occurrenceId)) return;
      _publicDiscards = [
        ..._publicDiscards,
        NetworkPlayedCardRecord(
          cardId: cardId,
          variantId: variantId,
          occurrenceId: occurrenceId,
          roundNumber: value.roundNumber,
          usage: usage,
        ),
      ];
    }

    for (final card in value.finalResolution!.compromise) {
      add(card.cardId, card.variantId, card.occurrenceId, card.usage);
    }
    for (final reveal in [value.ownReveal, value.opponentReveal]) {
      if (reveal == null) continue;
      add(
        reveal.choice.cardId,
        reveal.choice.variantId,
        (reveal.choice.usageId) ?? '${value.roundId}:${reveal.playerId}',
        reveal.choice.usage,
      );
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

  @override
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    super.dispose();
  }
}
