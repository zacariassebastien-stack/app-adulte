import '../../domain/domain.dart';
import '../../engines/engines.dart';

enum LocalRecoveryPhase {
  idle,
  choosingAction,
  awaitingResponse,
  choosingCondition,
  executing,
  extensionFirstConfirmation,
  extensionPrivateTransition,
  extensionSecondConfirmation,
  complete,
}

final class LocalRecoveryParticipant {
  const LocalRecoveryParticipant({
    required this.playerId,
    required this.profile,
  });

  final String playerId;
  final PlayerGameProfile profile;
}

final class LocalRecoveryOption {
  const LocalRecoveryOption({
    required this.card,
    required this.variant,
    required this.role,
    required this.preference,
    required this.source,
  });

  final EngineCard card;
  final EngineVariant variant;
  final ProfileRole role;
  final PreferenceValue preference;
  final RecoverySource source;
}

final class LocalRecoveryExecution {
  const LocalRecoveryExecution({
    required this.option,
    this.status = ActionExecutionStatus.ACCEPTED,
  });

  final LocalRecoveryOption option;
  final ActionExecutionStatus status;

  LocalRecoveryExecution copyWith(ActionExecutionStatus status) =>
      LocalRecoveryExecution(option: option, status: status);
}

/// Local between-round orchestration. Thresholds, eligibility, PA gain,
/// lifecycle and mutual extension are delegated to the Phase 3 engines.
final class LocalRecoveryController {
  LocalRecoveryController({
    required Iterable<EngineCard> cards,
    required this.local,
    required this.partner,
    required this.context,
    required this.hierarchy,
    this.recoveryEngine = const RecoveryEngine(),
    this.lifecycleEngine = const LifecycleEngine(),
  }) : cards = Map.unmodifiable({for (final card in cards) card.id: card}),
       _gates = {
         local.playerId: const RecoveryGate(
           betweenRounds: false,
           usedSinceLastNormalDuel: false,
         ),
         partner.playerId: const RecoveryGate(
           betweenRounds: false,
           usedSinceLastNormalDuel: false,
         ),
       };

  final Map<String, EngineCard> cards;
  final LocalRecoveryParticipant local, partner;
  final EngineSessionContext context;
  final ProfileHierarchy hierarchy;
  final RecoveryEngine recoveryEngine;
  final LifecycleEngine lifecycleEngine;

  final Map<String, RecoveryGate> _gates;
  final List<GameEvent> _events = [];
  Map<String, int> _actionPoints = const {};
  Map<String, List<CardRuntimeState>> _runtime = const {};

  LocalRecoveryPhase phase = LocalRecoveryPhase.idle;
  String? recoveringPlayerId;
  LocalRecoveryOption? selectedAction, selectedCondition;
  RecoveryResponse? response;
  List<LocalRecoveryExecution> execution = const [];
  int lastGain = 0;
  int? extensionAmount;
  bool? extensionAccepted;

  Map<String, int> get actionPoints => Map.unmodifiable(_actionPoints);
  Map<String, List<CardRuntimeState>> get runtime => Map.unmodifiable({
    for (final entry in _runtime.entries)
      entry.key: List<CardRuntimeState>.unmodifiable(entry.value),
  });
  List<GameEvent> get events => List.unmodifiable(_events);
  RecoveryGate gateFor(String playerId) => _gates[playerId]!;
  bool get bothPlayersLow => isLow(local.playerId) && isLow(partner.playerId);
  LocalRecoveryExecution? get currentExecution => execution
      .where((item) => item.status == ActionExecutionStatus.ACCEPTED)
      .firstOrNull;

  void afterNormalDuel({
    required Map<String, int> actionPoints,
    required Map<String, List<CardRuntimeState>> runtime,
  }) {
    _actionPoints = Map.of(actionPoints);
    _runtime = {
      for (final entry in runtime.entries) entry.key: List.of(entry.value),
    };
    for (final playerId in _gates.keys) {
      _gates[playerId] = recoveryEngine.afterNormalDuel();
    }
    _resetFlow();
  }

  bool isLow(String playerId) => recoveryEngine.available(
    currentPa: _actionPoints[playerId] ?? 0,
    gate: const RecoveryGate(
      betweenRounds: true,
      usedSinceLastNormalDuel: false,
    ),
  );

  bool recoveryAvailable(String playerId) => recoveryEngine.available(
    currentPa: _actionPoints[playerId] ?? 0,
    gate: _gates[playerId]!,
  );

  List<LocalRecoveryOption> optionsFor(String playerId) {
    final actor = _participant(playerId);
    final other = actor.playerId == local.playerId ? partner : local;
    final actorRuntime = _runtime[playerId] ?? const [];
    final recoveryContext = context.copyWith(
      exhaustedCardIds: {
        ...context.exhaustedCardIds,
        for (final states in _runtime.values)
          for (final card in states)
            if (card.zone == CardZone.EXHAUSTED) card.cardId,
      },
    );
    final result = <LocalRecoveryOption>[];
    for (final card in cards.values) {
      final eligibility = recoveryEngine.actionEligibility(
        card: card,
        context: recoveryContext,
        actor: actor.profile,
        partner: other.profile,
        hierarchy: hierarchy,
      );
      for (final variant in eligibility.eligibleVariants) {
        for (final rule in variant.consentRules) {
          final preference = actor.profile.preference(rule.elementId);
          final excludedByParent = hierarchy
              .ancestorsOf(rule.elementId)
              .any(
                (id) =>
                    actor.profile.preference(id).status ==
                    PreferenceStatus.EXCLUDED,
              );
          if (rule.subject != RequirementSubject.PARTNER &&
              preference.status == PreferenceStatus.ACCEPTED &&
              preference.valueFor(rule.role) != null &&
              !excludedByParent) {
            result.add(
              LocalRecoveryOption(
                card: card,
                variant: variant,
                role: rule.role,
                preference: preference,
                source: _sourceOf(actorRuntime, card.id),
              ),
            );
            break;
          }
        }
      }
    }
    return List.unmodifiable(result);
  }

  List<LocalRecoveryOption> get conditionOptions {
    final playerId = recoveringPlayerId;
    if (playerId == null) return const [];
    return [
      for (final option in optionsFor(playerId))
        if (option.source == RecoverySource.DISCARD &&
            option.card.id != selectedAction?.card.id)
          option,
    ];
  }

  void startRecovery(String playerId) {
    _require(LocalRecoveryPhase.idle);
    if (!recoveryAvailable(playerId)) {
      throw StateError('Recovery is not available');
    }
    recoveringPlayerId = playerId;
    phase = LocalRecoveryPhase.choosingAction;
  }

  void selectAction(String cardId, String variantId) {
    _require(LocalRecoveryPhase.choosingAction);
    selectedAction = optionsFor(recoveringPlayerId!)
        .where(
          (option) =>
              option.card.id == cardId && option.variant.id == variantId,
        )
        .firstOrNull;
    if (selectedAction == null) {
      throw StateError('Recovery action is not eligible');
    }
    _events.add(
      GameEvent(GameEventType.RECOVERY_PROPOSED, {
        'player_id': recoveringPlayerId,
        'card_id': cardId,
        'variant_id': variantId,
      }),
    );
    phase = LocalRecoveryPhase.awaitingResponse;
  }

  void answer(RecoveryResponse answer) {
    _require(LocalRecoveryPhase.awaitingResponse);
    response = answer;
    if (answer == RecoveryResponse.REFUSE) {
      execution = [
        LocalRecoveryExecution(
          option: selectedAction!,
          status: ActionExecutionStatus.SKIPPED,
        ),
      ];
      _resolveRecovery();
    } else if (answer == RecoveryResponse.ACCEPT_WITH_ONE_DISCARD_CONDITION) {
      if (conditionOptions.isEmpty) {
        throw StateError('No eligible discard condition');
      }
      phase = LocalRecoveryPhase.choosingCondition;
    } else {
      execution = [LocalRecoveryExecution(option: selectedAction!)];
      phase = LocalRecoveryPhase.executing;
    }
  }

  void selectCondition(String cardId, String variantId) {
    _require(LocalRecoveryPhase.choosingCondition);
    selectedCondition = conditionOptions
        .where(
          (option) =>
              option.card.id == cardId && option.variant.id == variantId,
        )
        .firstOrNull;
    if (selectedCondition == null) {
      throw StateError('Recovery condition must be an eligible discard card');
    }
    execution = [
      LocalRecoveryExecution(option: selectedAction!),
      LocalRecoveryExecution(option: selectedCondition!),
    ];
    phase = LocalRecoveryPhase.executing;
  }

  void recordCurrent(ActionExecutionStatus status) {
    _require(LocalRecoveryPhase.executing);
    if (status != ActionExecutionStatus.COMPLETED &&
        status != ActionExecutionStatus.SKIPPED) {
      throw ArgumentError('Action must be completed or skipped');
    }
    final current = currentExecution;
    if (current == null) throw StateError('No pending Recovery action');
    execution = [
      for (final item in execution)
        identical(item, current) ? item.copyWith(status) : item,
    ];
  }

  void finishExecution() {
    _require(LocalRecoveryPhase.executing);
    if (currentExecution != null) throw StateError('Pending action remains');
    _resolveRecovery();
  }

  void consentStop() {
    _require(LocalRecoveryPhase.executing);
    final current = currentExecution;
    if (current == null) throw StateError('No pending Recovery action');
    var stopped = false;
    execution = [
      for (final item in execution)
        if (identical(item, current))
          (() {
            stopped = true;
            return item.copyWith(ActionExecutionStatus.STOPPED);
          })()
        else if (stopped || item.status == ActionExecutionStatus.ACCEPTED)
          item.copyWith(ActionExecutionStatus.SKIPPED)
        else
          item,
    ];
    _resolveRecovery();
  }

  void startMutualExtension(int amount) {
    _require(LocalRecoveryPhase.idle);
    if (!bothPlayersLow) throw StateError('Both players must have low PA');
    if (amount < 0) throw ArgumentError.value(amount, 'amount');
    extensionAmount = amount;
    extensionAccepted = null;
    phase = LocalRecoveryPhase.extensionFirstConfirmation;
  }

  void confirmExtensionFirst() {
    _require(LocalRecoveryPhase.extensionFirstConfirmation);
    phase = LocalRecoveryPhase.extensionPrivateTransition;
  }

  void showExtensionToSecondPlayer() {
    _require(LocalRecoveryPhase.extensionPrivateTransition);
    phase = LocalRecoveryPhase.extensionSecondConfirmation;
  }

  void answerExtensionSecond({required bool accepted}) {
    _require(LocalRecoveryPhase.extensionSecondConfirmation);
    extensionAccepted = accepted;
    if (accepted) {
      final result = recoveryEngine.mutualExtension(
        actionPoints: _actionPoints,
        amount: extensionAmount!,
        mutualAgreement: true,
      );
      _actionPoints = Map.of(result.actionPoints);
      _events.add(result.event);
    }
    phase = LocalRecoveryPhase.complete;
  }

  void resetCompletedFlow() {
    _require(LocalRecoveryPhase.complete);
    _resetFlow();
  }

  void _resolveRecovery() {
    final playerId = recoveringPlayerId!;
    final result = recoveryEngine.resolve(
      currentPa: _actionPoints[playerId]!,
      response: response!,
      performedRoles: [
        for (final item in execution)
          (
            item.option.preference,
            item.option.role,
            item.status == ActionExecutionStatus.COMPLETED,
          ),
      ],
      conditionCount: selectedCondition == null ? 0 : 1,
    );
    _actionPoints = {..._actionPoints, playerId: result.actionPoints};
    lastGain = result.gain;
    _events.addAll(result.events);
    var cards = _runtime[playerId]!;
    for (final item in execution) {
      cards = recoveryEngine.applyLifecycle(
        cards: cards,
        cardId: item.option.card.id,
        source: item.option.source,
        completed: item.status == ActionExecutionStatus.COMPLETED,
      );
      _events.add(
        lifecycleEngine.actionEvent(item.status, item.option.card.id),
      );
    }
    _runtime = {..._runtime, playerId: cards};
    _gates[playerId] = recoveryEngine.afterRecovery(_gates[playerId]!);
    _events.add(
      GameEvent(GameEventType.RECOVERY_RESOLVED, {
        'player_id': playerId,
        'response': response!.name,
        'gain': result.gain,
      }),
    );
    phase = LocalRecoveryPhase.complete;
  }

  RecoverySource _sourceOf(List<CardRuntimeState> runtime, String cardId) {
    final zone = runtime
        .where((card) => card.cardId == cardId)
        .firstOrNull
        ?.zone;
    return switch (zone) {
      CardZone.HAND => RecoverySource.HAND,
      CardZone.DISCARD => RecoverySource.DISCARD,
      _ => RecoverySource.CATALOG,
    };
  }

  LocalRecoveryParticipant _participant(String playerId) {
    if (playerId == local.playerId) return local;
    if (playerId == partner.playerId) return partner;
    throw ArgumentError.value(playerId, 'playerId');
  }

  void _resetFlow() {
    phase = LocalRecoveryPhase.idle;
    recoveringPlayerId = null;
    selectedAction = null;
    selectedCondition = null;
    response = null;
    execution = const [];
    lastGain = 0;
    extensionAmount = null;
    extensionAccepted = null;
  }

  void _require(LocalRecoveryPhase expected) {
    if (phase != expected) throw StateError('Expected $expected, found $phase');
  }
}
