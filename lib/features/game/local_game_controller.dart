import '../../domain/domain.dart';
import '../../engines/engines.dart';
import 'local_post_duel_controller.dart';

enum LocalRoundPhase {
  choosing,
  waitingForPartner,
  revealed,
  counterAuction,
  finalDefense,
  corruption,
  actionExecution,
  roundComplete,
}

final class LocalGameCard {
  const LocalGameCard({required this.view, required this.engine});

  final GameCardView view;
  final EngineCard engine;
}

final class LocalVariantPreference {
  const LocalVariantPreference({required this.role, required this.preference});

  final ProfileRole role;
  final UserPreference preference;
}

final class LocalPlayerSetup {
  LocalPlayerSetup({
    required this.playerId,
    required this.profile,
    required Iterable<String> initialHandIds,
    required Map<String, LocalVariantPreference> preferencesByVariant,
    Iterable<String> initialDiscardIds = const [],
  }) : initialHandIds = List.unmodifiable(initialHandIds),
       initialDiscardIds = List.unmodifiable(initialDiscardIds),
       preferencesByVariant = Map.unmodifiable(preferencesByVariant);

  final String playerId;
  final PlayerGameProfile profile;
  final List<String> initialHandIds;
  final List<String> initialDiscardIds;
  final Map<String, LocalVariantPreference> preferencesByVariant;
}

final class LocalVariantChoice {
  const LocalVariantChoice({
    required this.variant,
    required this.role,
    required this.preference,
  });

  final EngineVariant variant;
  final ProfileRole role;
  final UserPreference preference;
}

/// Local orchestration only. Every eligibility, commitment, PA, lifecycle and
/// draw decision is delegated to the existing Phase 3 engines.
final class LocalGameController {
  LocalGameController({
    required Iterable<LocalGameCard> cards,
    required this.local,
    required this.partner,
    required this.context,
    required this.hierarchy,
    this.duelEngine = const DuelEngine(),
    this.drawEngine = const DrawEngine(),
    this.lifecycleEngine = const LifecycleEngine(),
    this.auctionEngine = const AuctionEngine(),
    this.corruptionEngine = const CorruptionEngine(),
    RandomSource? random,
    DateTime Function()? clock,
  }) : cards = Map.unmodifiable({
         for (final card in cards) card.engine.id: card,
       }),
       random = random ?? SeededRandomSource(5304),
       clock = clock ?? DateTime.now,
       _actionPoints = {
         local.playerId: duelEngine.config.initialPa,
         partner.playerId: duelEngine.config.initialPa,
       },
       _localCards = [
         for (final id in local.initialHandIds)
           CardRuntimeState(cardId: id, zone: CardZone.HAND),
         for (final id in local.initialDiscardIds)
           CardRuntimeState(cardId: id, zone: CardZone.DISCARD),
       ],
       _partnerCards = [
         for (final id in partner.initialHandIds)
           CardRuntimeState(cardId: id, zone: CardZone.HAND),
         for (final id in partner.initialDiscardIds)
           CardRuntimeState(cardId: id, zone: CardZone.DISCARD),
       ],
       _localHistory = {
         for (final id in local.initialHandIds)
           id: CardHistoryState.seenUnplayed,
         for (final id in local.initialDiscardIds)
           id: CardHistoryState.playedOrDiscarded,
       },
       _partnerHistory = {
         for (final id in partner.initialHandIds)
           id: CardHistoryState.seenUnplayed,
         for (final id in partner.initialDiscardIds)
           id: CardHistoryState.playedOrDiscarded,
       } {
    if (this.cards.length < duelEngine.config.handSize) {
      throw ArgumentError('Local fixture cannot fill a complete hand');
    }
    _validateHand(local.initialHandIds);
    _validateHand(partner.initialHandIds);
    _validateDiscard(local);
    _validateDiscard(partner);
    final localLocked = local.initialHandIds
        .where((id) => this.cards[id]!.view.locked)
        .firstOrNull;
    final partnerLocked = partner.initialHandIds
        .where((id) => this.cards[id]!.view.locked)
        .firstOrNull;
    if (localLocked != null) {
      _localCards = lifecycleEngine.lock(_localCards, localLocked);
    }
    if (partnerLocked != null) {
      _partnerCards = lifecycleEngine.lock(_partnerCards, partnerLocked);
    }
  }

  final Map<String, LocalGameCard> cards;
  final LocalPlayerSetup local, partner;
  final EngineSessionContext context;
  final ProfileHierarchy hierarchy;
  final DuelEngine duelEngine;
  final DrawEngine drawEngine;
  final LifecycleEngine lifecycleEngine;
  final AuctionEngine auctionEngine;
  final CorruptionEngine corruptionEngine;
  final RandomSource random;
  final DateTime Function() clock;

  LocalRoundPhase phase = LocalRoundPhase.choosing;
  int roundNumber = 1;
  DuelCommitment? localCommitment, partnerCommitment;
  DuelResolution? resolution;
  LocalPostDuelController? postDuel;
  Map<String, int>? actionPointsBeforeResolution;
  late Map<String, int> _actionPoints;
  late List<CardRuntimeState> _localCards, _partnerCards;
  late final Map<String, CardHistoryState> _localHistory, _partnerHistory;

  Map<String, int> get actionPoints =>
      postDuel?.actionPoints ?? Map.unmodifiable(_actionPoints);
  List<CardRuntimeState> get localCards => List.unmodifiable(_localCards);
  List<CardRuntimeState> get partnerCards => List.unmodifiable(_partnerCards);
  String? get selectedLocalCardId => localCommitment?.snapshot.cardId;
  String? get selectedPartnerCardId => partnerCommitment?.snapshot.cardId;
  String? get finalWinnerId => postDuel?.finalWinnerId;
  DuelCommitment? get finalActionCommitment => postDuel?.finalActionCommitment;
  bool get inversionRetained => postDuel?.inversionRetained ?? false;
  String? get activeBidderId => postDuel?.activeBidderId;
  int get minimumBid => postDuel?.minimumBid ?? 1;
  bool get inversionAllowed => postDuel?.inversionAllowed ?? false;
  CorruptionOffer? get corruptionOffer => postDuel?.corruptionOffer;
  List<ActionPromise> get executionActions =>
      postDuel?.executionActions ?? const [];
  ActionPromise? get currentExecutionAction => postDuel?.currentAction;
  List<GameEvent> get roundEvents =>
      postDuel?.events ?? resolution?.events ?? const [];

  GameScreenData get screenData => GameScreenData(
    playerId: local.playerId,
    chiliActive: context.chiliActive,
    elapsedSeconds: 0,
    actionPoints: actionPoints[local.playerId],
    privateDataHidden: false,
    hand: [
      for (final state in _localCards.where(
        (card) => card.zone == CardZone.HAND,
      ))
        _view(state),
    ],
    discard: [
      for (final state in _localCards.where(
        (card) => card.zone == CardZone.DISCARD,
      ))
        _view(state),
    ],
    centralActions: const [],
  );

  Set<String> get temporarilyUnavailableCardIds => {
    for (final state in _localCards.where((card) => card.zone == CardZone.HAND))
      if (choicesForLocalCard(state.cardId).isEmpty) state.cardId,
  };

  List<LocalVariantChoice> choicesForLocalCard(String cardId) =>
      _choices(local, partner, cardId);

  void toggleLocalLock(String cardId) {
    if (phase != LocalRoundPhase.choosing) return;
    final current = _localCards
        .where((card) => card.cardId == cardId)
        .firstOrNull;
    if (current == null || current.zone != CardZone.HAND) return;
    if (current.locked) {
      _localCards = [
        for (final card in _localCards)
          card.cardId == cardId ? card.copyWith(locked: false) : card,
      ];
    } else {
      _localCards = lifecycleEngine.lock(_localCards, cardId);
    }
  }

  void selectLocalCard(String cardId, String variantId) {
    if (phase != LocalRoundPhase.choosing) {
      throw StateError('A card is already committed for this round');
    }
    final runtime = _localCards
        .where((card) => card.cardId == cardId && card.zone == CardZone.HAND)
        .firstOrNull;
    final choice = choicesForLocalCard(
      cardId,
    ).where((item) => item.variant.id == variantId).firstOrNull;
    if (runtime == null || choice == null) {
      throw StateError('Card or variant is not eligible');
    }
    localCommitment = duelEngine.commit(
      playerId: local.playerId,
      cardId: cardId,
      variantId: variantId,
      voluntaryRole: choice.role,
      preference: choice.preference,
      committedAt: clock(),
      cardInvertible: choice.variant.invertible,
    );
    _localCards = lifecycleEngine.engage(_localCards, cardId);
    phase = LocalRoundPhase.waitingForPartner;
  }

  void simulatePartnerChoice() {
    if (phase != LocalRoundPhase.waitingForPartner) {
      throw StateError('Local commitment is required');
    }
    for (final runtime in _partnerCards.where(
      (card) => card.zone == CardZone.HAND,
    )) {
      final choices = _choices(partner, local, runtime.cardId);
      if (choices.isEmpty) continue;
      final choice = choices.first;
      partnerCommitment = duelEngine.commit(
        playerId: partner.playerId,
        cardId: runtime.cardId,
        variantId: choice.variant.id,
        voluntaryRole: choice.role,
        preference: choice.preference,
        committedAt: clock(),
        cardInvertible: choice.variant.invertible,
      );
      _partnerCards = lifecycleEngine.engage(_partnerCards, runtime.cardId);
      actionPointsBeforeResolution = Map.unmodifiable(_actionPoints);
      resolution = duelEngine.resolve(
        first: localCommitment!,
        second: partnerCommitment!,
        actionPoints: _actionPoints,
      );
      _actionPoints = Map.of(resolution!.actionPoints);
      postDuel = LocalPostDuelController(
        duel: resolution!,
        duelEngine: duelEngine,
        auctionEngine: auctionEngine,
        corruptionEngine: corruptionEngine,
      );
      phase = LocalRoundPhase.revealed;
      return;
    }
    throw StateError('Partner has no eligible card');
  }

  void continueAfterDuel() {
    _requirePhase(LocalRoundPhase.revealed);
    postDuel!.continueAfterDuel();
    _syncPostDuel();
  }

  void submitCounterBid(int amount, AuctionTarget target) {
    _requirePhase(LocalRoundPhase.counterAuction);
    postDuel!.counter(amount: amount, target: target);
    _syncPostDuel();
  }

  void renounceCounterBid() {
    _requirePhase(LocalRoundPhase.counterAuction);
    postDuel!.renounceCounter();
    _syncPostDuel();
  }

  void submitFinalDefense(int amount) {
    _requirePhase(LocalRoundPhase.finalDefense);
    postDuel!.defend(amount);
    _syncPostDuel();
  }

  void renounceFinalDefense() {
    _requirePhase(LocalRoundPhase.finalDefense);
    postDuel!.renounceDefense();
    _syncPostDuel();
  }

  List<GameCardView> get corruptionAvailableCards {
    final owner = postDuel?.corruptionActorId;
    if (owner == null) return const [];
    final runtime = owner == local.playerId ? _localCards : _partnerCards;
    return [
      for (final card in runtime)
        if (lifecycleEngine.canUseForCorruption(card)) _view(card),
    ];
  }

  void proposeCorruption(
    Iterable<String> cardIds,
    CorruptionObjective objective,
  ) {
    _requirePhase(LocalRoundPhase.corruption);
    final ids = cardIds.toSet();
    final allowed = corruptionAvailableCards.map((card) => card.cardId).toSet();
    if (ids.isEmpty || !allowed.containsAll(ids)) {
      throw StateError(
        'Corruption actions must come from the proposer discard',
      );
    }
    postDuel!.proposeCorruption(
      objective: objective,
      cardIds: ids.toList(growable: false),
    );
  }

  void respondToCorruption({required bool accepted}) {
    _requirePhase(LocalRoundPhase.corruption);
    if (accepted) {
      postDuel!.acceptCorruption();
    } else {
      _applyCorruptionResult(postDuel!.refuseCorruption(_corruptionActorCards));
    }
    _syncPostDuel();
  }

  void recordCurrentAction(ActionExecutionStatus status) {
    _requirePhase(LocalRoundPhase.actionExecution);
    postDuel!.recordCurrentAction(status);
  }

  void finishCorruptionActions() {
    _requirePhase(LocalRoundPhase.actionExecution);
    _applyCorruptionResult(postDuel!.finishActions(_corruptionActorCards));
    _syncPostDuel();
  }

  void consentStop() {
    _requirePhase(LocalRoundPhase.actionExecution);
    _applyCorruptionResult(postDuel!.stop(_corruptionActorCards));
    _syncPostDuel();
  }

  void skipCorruption() {
    _requirePhase(LocalRoundPhase.corruption);
    postDuel!.skipCorruption();
    _syncPostDuel();
  }

  void continueToNextRound() {
    if (phase != LocalRoundPhase.roundComplete) {
      throw StateError('The post-duel resolution must be complete');
    }
    final localPlayed = localCommitment!.snapshot.cardId;
    final partnerPlayed = partnerCommitment!.snapshot.cardId;
    _localCards = lifecycleEngine.closeRoundWithEvents(_localCards).cards;
    _partnerCards = lifecycleEngine.closeRoundWithEvents(_partnerCards).cards;
    _localHistory[localPlayed] = CardHistoryState.playedOrDiscarded;
    _partnerHistory[partnerPlayed] = CardHistoryState.playedOrDiscarded;
    _localCards = _refill(local, partner, _localCards, _localHistory);
    _partnerCards = _refill(partner, local, _partnerCards, _partnerHistory);
    roundNumber++;
    localCommitment = null;
    partnerCommitment = null;
    resolution = null;
    postDuel = null;
    actionPointsBeforeResolution = null;
    phase = LocalRoundPhase.choosing;
  }

  List<LocalVariantChoice> _choices(
    LocalPlayerSetup actor,
    LocalPlayerSetup other,
    String cardId,
  ) {
    final card = cards[cardId];
    if (card == null) return const [];
    final eligibility = const EligibilityEngine().evaluate(
      card: card.engine,
      context: context,
      actor: actor.profile,
      partner: other.profile,
      hierarchy: hierarchy,
      requirePersonalValue: true,
    );
    return [
      for (final variant in eligibility.eligibleVariants)
        if (actor.preferencesByVariant[variant.id] case final preference?)
          if (preference.preference.status == PreferenceStatus.ACCEPTED &&
              preference.preference.valueFor(preference.role) != null)
            LocalVariantChoice(
              variant: variant,
              role: preference.role,
              preference: preference.preference,
            ),
    ];
  }

  List<CardRuntimeState> _refill(
    LocalPlayerSetup actor,
    LocalPlayerSetup other,
    List<CardRuntimeState> runtime,
    Map<String, CardHistoryState> history,
  ) {
    final current = runtime
        .where((state) => state.zone == CardZone.HAND)
        .map((state) => cards[state.cardId]!.engine)
        .toList();
    final hand = drawEngine.refill(
      currentHand: current,
      cards: cards.values.map((card) => card.engine).toList(),
      context: context.copyWith(
        exhaustedCardIds: {
          ...context.exhaustedCardIds,
          for (final card in runtime)
            if (card.zone == CardZone.EXHAUSTED) card.cardId,
        },
      ),
      actor: actor.profile,
      partner: other.profile,
      hierarchy: hierarchy,
      style: PlayerStyle.EPICE,
      history: DrawHistory(cards: history),
      random: random,
    );
    final handIds = hand.map((card) => card.id).toSet();
    final updated = <CardRuntimeState>[
      for (final state in runtime)
        if (handIds.contains(state.cardId))
          state.copyWith(zone: CardZone.HAND)
        else
          state,
    ];
    for (final card in hand) {
      if (!updated.any((state) => state.cardId == card.id)) {
        updated.add(CardRuntimeState(cardId: card.id, zone: CardZone.HAND));
      }
      history[card.id] = CardHistoryState.seenUnplayed;
    }
    return updated;
  }

  GameCardView _view(CardRuntimeState state) {
    final source = cards[state.cardId]!.view;
    return GameCardView(
      cardId: source.cardId,
      category: source.category,
      chiliLevels: source.chiliLevels,
      locked: state.locked,
      titleKey: source.titleKey,
      descriptionKey: source.descriptionKey,
      illustrationKey: source.illustrationKey,
      personalValue: source.personalValue,
      instructionKeys: source.instructionKeys,
    );
  }

  void _validateHand(List<String> ids) {
    if (ids.length != duelEngine.config.handSize ||
        ids.toSet().length != ids.length ||
        ids.any((id) => !cards.containsKey(id))) {
      throw ArgumentError('Initial hand must contain configured unique cards');
    }
  }

  void _validateDiscard(LocalPlayerSetup player) {
    final ids = player.initialDiscardIds;
    if (ids.toSet().length != ids.length ||
        ids.any((id) => !cards.containsKey(id)) ||
        ids.any(player.initialHandIds.contains)) {
      throw ArgumentError('Initial discard must contain known unique cards');
    }
  }

  List<CardRuntimeState> get _corruptionActorCards =>
      postDuel!.corruptionActorId == local.playerId
      ? _localCards
      : _partnerCards;

  void _applyCorruptionResult(CorruptionResolution result) {
    if (postDuel!.corruptionActorId == local.playerId) {
      _localCards = List.of(result.cards);
    } else {
      _partnerCards = List.of(result.cards);
    }
  }

  void _syncPostDuel() {
    _actionPoints = Map.of(postDuel!.actionPoints);
    phase = switch (postDuel!.phase) {
      LocalPostDuelPhase.duelRevealed => LocalRoundPhase.revealed,
      LocalPostDuelPhase.counterAuction => LocalRoundPhase.counterAuction,
      LocalPostDuelPhase.finalDefense => LocalRoundPhase.finalDefense,
      LocalPostDuelPhase.corruption => LocalRoundPhase.corruption,
      LocalPostDuelPhase.actionExecution => LocalRoundPhase.actionExecution,
      LocalPostDuelPhase.roundComplete => LocalRoundPhase.roundComplete,
    };
  }

  void _requirePhase(LocalRoundPhase expected) {
    if (phase != expected) throw StateError('Expected $expected, found $phase');
  }
}

extension on UserPreference {
  int? valueFor(ProfileRole role) => switch (role) {
    ProfileRole.GENERAL => generalValue,
    ProfileRole.FAIRE => faireValue,
    ProfileRole.RECEVOIR => recevoirValue,
  };
}
