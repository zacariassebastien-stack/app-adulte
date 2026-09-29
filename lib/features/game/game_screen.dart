import 'package:flutter/material.dart';

import '../../domain/game/game_screen_data.dart';
import '../../engines/engines.dart';
import 'local_game_controller.dart';

/// Game layout with local hand interactions.
///
/// A [LocalGameController] connects the prototype to the existing gameplay
/// engines; omitting it keeps the lightweight fixture mode used by UI tests.
class GameScreen extends StatefulWidget {
  const GameScreen({
    required this.data,
    this.privacyTransition = false,
    this.temporarilyUnavailableCardIds = const {},
    this.onCardSelected,
    this.prototypePartnerCard,
    this.controller,
    super.key,
  });

  final GameScreenData data;
  final bool privacyTransition;
  final Set<String> temporarilyUnavailableCardIds;
  final ValueChanged<GameCardView>? onCardSelected;
  final GameCardView? prototypePartnerCard;
  final LocalGameController? controller;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  String? _lockedCardId;
  String? _selectedCardId;
  bool _detailOpen = false;
  String? _resolutionError;
  LocalRoundPhase _roundState = LocalRoundPhase.choosing;

  bool get _hidePrivateData =>
      widget.privacyTransition || _data.privateDataHidden;
  GameScreenData get _data => widget.controller?.screenData ?? widget.data;
  LocalRoundPhase get _phase => widget.controller?.phase ?? _roundState;
  GameCardView? get _selectedCard {
    final id = widget.controller?.selectedLocalCardId ?? _selectedCardId;
    return widget.controller?.cards[id]?.view ??
        widget.data.hand.where((card) => card.cardId == id).firstOrNull;
  }

  GameCardView get _partnerCard =>
      widget
          .controller
          ?.cards[widget.controller?.selectedPartnerCardId]
          ?.view ??
      widget.prototypePartnerCard ??
      GameCardView(
        cardId: 'prototype-partner-card',
        category: 'PARTENAIRE',
        chiliLevels: [_data.chiliActive],
        locked: false,
        titleKey: 'Carte partenaire',
      );

  @override
  void initState() {
    super.initState();
    _lockedCardId = _data.hand.where((card) => card.locked).firstOrNull?.cardId;
  }

  @override
  void didUpdateWidget(covariant GameScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_hidePrivateData && _detailOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _detailOpen) Navigator.of(context).maybePop();
      });
    }
  }

  Future<void> _openCard(GameCardView card) async {
    if (_hidePrivateData) return;
    final choices =
        widget.controller?.choicesForLocalCard(card.cardId) ?? const [];
    var selectedVariantId = choices.firstOrNull?.variant.id;
    _detailOpen = true;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final locked = _lockedCardId == card.cardId;
          final unavailable =
              widget.temporarilyUnavailableCardIds.contains(card.cardId) ||
              (widget.controller?.temporarilyUnavailableCardIds.contains(
                    card.cardId,
                  ) ??
                  false);
          return _CardDetail(
            card: card,
            locked: locked,
            unavailable: unavailable,
            selected: _selectedCardId == card.cardId,
            variantChoices: choices,
            selectedVariantId: selectedVariantId,
            onVariantChanged: (id) =>
                setSheetState(() => selectedVariantId = id),
            onToggleLock: () {
              if (_hidePrivateData) return;
              setState(() {
                if (widget.controller case final controller?) {
                  controller.toggleLocalLock(card.cardId);
                  _lockedCardId = controller.localCards
                      .where((item) => item.locked)
                      .firstOrNull
                      ?.cardId;
                } else {
                  _lockedCardId = locked ? null : card.cardId;
                }
              });
              setSheetState(() {});
            },
            onSelect:
                unavailable ||
                    _hidePrivateData ||
                    (widget.controller != null && selectedVariantId == null)
                ? null
                : () {
                    setState(() {
                      _selectedCardId = card.cardId;
                      if (widget.controller case final controller?) {
                        controller.selectLocalCard(
                          card.cardId,
                          selectedVariantId!,
                        );
                      } else {
                        _roundState = LocalRoundPhase.waitingForPartner;
                      }
                    });
                    widget.onCardSelected?.call(card);
                    Navigator.of(sheetContext).pop();
                  },
          );
        },
      ),
    );
    _detailOpen = false;
  }

  void _revealPrototypeRound() {
    if (_phase != LocalRoundPhase.waitingForPartner || _hidePrivateData) {
      return;
    }
    setState(() {
      if (widget.controller case final controller?) {
        controller.simulatePartnerChoice();
      } else {
        _roundState = LocalRoundPhase.revealed;
      }
    });
  }

  void _finishPrototypeRound() {
    setState(() {
      widget.controller?.continueToNextRound();
      _selectedCardId = null;
      _roundState = LocalRoundPhase.choosing;
      _lockedCardId = _data.hand
          .where((card) => card.locked)
          .firstOrNull
          ?.cardId;
    });
  }

  void _applyControllerAction(void Function(LocalGameController) action) {
    if (_hidePrivateData || widget.controller == null) return;
    setState(() {
      try {
        action(widget.controller!);
        _resolutionError = null;
      } on Object catch (error) {
        _resolutionError = error.toString().replaceFirst(
          RegExp(r'^(?:StateError|Invalid argument\(s\)): '),
          '',
        );
      }
    });
  }

  bool get _resolvingRound =>
      _phase != LocalRoundPhase.choosing &&
      _phase != LocalRoundPhase.waitingForPartner;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _GameHeader(data: _data, hidePrivateData: _hidePrivateData),
              const SizedBox(height: 10),
              Expanded(
                child: _resolvingRound && _selectedCard != null
                    ? _RevealArea(
                        localCard: _selectedCard!,
                        partnerCard: _partnerCard,
                        resolution: widget.controller?.resolution,
                        actionPointsBefore:
                            widget.controller?.actionPointsBeforeResolution,
                        localPlayerId: widget.controller?.local.playerId,
                        controller: widget.controller,
                        phase: _phase,
                        hidePrivateData: _hidePrivateData,
                        error: _resolutionError,
                        onControllerAction: _applyControllerAction,
                        onFinish: _finishPrototypeRound,
                      )
                    : _CentralArea(
                        action: _data.centralActions.firstOrNull,
                        hidePrivateData: _hidePrivateData,
                      ),
              ),
              const SizedBox(height: 10),
              _DiscardAccess(count: _data.discard.length),
              const SizedBox(height: 10),
              SizedBox(
                height: 168,
                child: _hidePrivateData
                    ? const _PrivacyPlaceholder()
                    : _phase == LocalRoundPhase.waitingForPartner
                    ? _WaitingForPartner(onSimulate: _revealPrototypeRound)
                    : _resolvingRound
                    ? _RevealedStatus(phase: _phase)
                    : _PlayerHand(
                        cards: _data.hand,
                        lockedCardId: _lockedCardId,
                        selectedCardId: _selectedCardId,
                        unavailableCardIds: {
                          ...widget.temporarilyUnavailableCardIds,
                          ...?widget.controller?.temporarilyUnavailableCardIds,
                        },
                        onCardTap: _openCard,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GameHeader extends StatelessWidget {
  const _GameHeader({required this.data, required this.hidePrivateData});

  final GameScreenData data;
  final bool hidePrivateData;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: _HeaderMetric(
          key: const Key('action-points'),
          icon: Icons.bolt_rounded,
          label: 'PA',
          value: hidePrivateData ? '—' : '${data.actionPoints ?? '—'}',
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: _HeaderMetric(
          key: const Key('session-timer'),
          icon: Icons.timer_outlined,
          label: 'Temps',
          value: _duration(data.elapsedSeconds),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: _HeaderMetric(
          key: const Key('active-chili'),
          icon: Icons.local_fire_department_outlined,
          label: 'Niveau',
          value: '🌶️ ${data.chiliActive}',
        ),
      ),
      const SizedBox(width: 8),
      IconButton.filledTonal(
        key: const Key('settings-button'),
        tooltip: 'Réglages',
        onPressed: () {},
        icon: const Icon(Icons.settings_outlined),
      ),
    ],
  );

  static String _duration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    return '$minutes:${remainder.toString().padLeft(2, '0')}';
  }
}

class _HeaderMetric extends StatelessWidget {
  const _HeaderMetric({
    required this.icon,
    required this.label,
    required this.value,
    super.key,
  });

  final IconData icon;
  final String label, value;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 80;
      return Container(
        height: 58,
        padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(14),
        ),
        child: compact
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 18, semanticLabel: label),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      value,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 20),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            value,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      );
    },
  );
}

class _CentralArea extends StatelessWidget {
  const _CentralArea({required this.action, required this.hidePrivateData});

  final GameCardView? action;
  final bool hidePrivateData;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: action == null
          ? const Center(child: Text('Action révélée'))
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: GameCard(
                  card: action!,
                  prominent: true,
                  hidePersonalValue: hidePrivateData,
                ),
              ),
            ),
    ),
  );
}

class _WaitingForPartner extends StatelessWidget {
  const _WaitingForPartner({required this.onSimulate});

  final VoidCallback onSimulate;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('waiting-for-partner'),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Carte choisie — En attente de ton partenaire',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        OutlinedButton(
          key: const Key('simulate-partner-choice'),
          onPressed: onSimulate,
          child: const Text('Simuler le choix du partenaire'),
        ),
      ],
    ),
  );
}

class _RevealedStatus extends StatelessWidget {
  const _RevealedStatus({required this.phase});

  final LocalRoundPhase phase;

  @override
  Widget build(BuildContext context) => Center(
    child: Text(
      switch (phase) {
        LocalRoundPhase.revealed => 'Les deux cartes sont révélées',
        LocalRoundPhase.counterAuction => 'Étape · Contre-enchère',
        LocalRoundPhase.finalDefense => 'Étape · Défense finale',
        LocalRoundPhase.corruption => 'Étape · Tentations',
        LocalRoundPhase.actionExecution => 'Étape · Exécution',
        LocalRoundPhase.roundComplete => 'Manche prête à être terminée',
        _ => '',
      },
      key: const Key('revealed-status'),
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.titleSmall,
    ),
  );
}

class _RevealArea extends StatelessWidget {
  const _RevealArea({
    required this.localCard,
    required this.partnerCard,
    required this.resolution,
    required this.actionPointsBefore,
    required this.localPlayerId,
    required this.controller,
    required this.phase,
    required this.hidePrivateData,
    required this.error,
    required this.onControllerAction,
    required this.onFinish,
  });

  final GameCardView localCard, partnerCard;
  final DuelResolution? resolution;
  final Map<String, int>? actionPointsBefore;
  final String? localPlayerId;
  final LocalGameController? controller;
  final LocalRoundPhase phase;
  final bool hidePrivateData;
  final String? error;
  final void Function(void Function(LocalGameController)) onControllerAction;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('round-reveal'),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: hidePrivateData
        ? const _PrivacyPlaceholder()
        : SingleChildScrollView(
            child: Column(
              children: [
                Text(
                  'Révélation',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 150,
                  child: Row(
                    children: [
                      Expanded(
                        child: _RevealedCard(
                          key: const Key('revealed-local-card'),
                          label: 'Ta carte',
                          card: localCard,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _RevealedCard(
                          key: const Key('revealed-partner-card'),
                          label: 'Partenaire',
                          card: partnerCard,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                if (resolution case final duel?) ...[
                  _DuelResult(
                    resolution: duel,
                    actionPointsBefore: actionPointsBefore ?? const {},
                    localPlayerId: localPlayerId,
                  ),
                  const SizedBox(height: 8),
                ],
                if (controller case final game?)
                  _PostDuelControls(
                    controller: game,
                    phase: phase,
                    error: error,
                    onAction: onControllerAction,
                    onFinish: onFinish,
                  )
                else
                  FilledButton(
                    key: const Key('finish-round-button'),
                    onPressed: onFinish,
                    child: const Text('Terminer la manche'),
                  ),
              ],
            ),
          ),
  );
}

class _DuelResult extends StatelessWidget {
  const _DuelResult({
    required this.resolution,
    required this.actionPointsBefore,
    required this.localPlayerId,
  });

  final DuelResolution resolution;
  final Map<String, int> actionPointsBefore;
  final String? localPlayerId;

  @override
  Widget build(BuildContext context) {
    final winnerId = resolution.winnerPlayerId;
    final resultText = resolution.tied
        ? 'Égalité — négociation nécessaire'
        : winnerId == localPlayerId
        ? 'Tu remportes le duel'
        : 'Ton partenaire remporte le duel';
    final pointsPlayer = winnerId ?? localPlayerId;
    final before = pointsPlayer == null
        ? null
        : actionPointsBefore[pointsPlayer];
    final after = pointsPlayer == null
        ? null
        : resolution.actionPoints[pointsPlayer];
    return Container(
      key: const Key('duel-result'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            resultText,
            key: const Key('duel-result-label'),
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          Text(
            'Écart : ${resolution.gap} · Coût : ${resolution.gapCost} PA',
            key: const Key('duel-cost'),
            style: Theme.of(context).textTheme.labelSmall,
          ),
          if (before != null && after != null)
            Text(
              'PA : $before → $after',
              key: const Key('duel-pa-change'),
              style: Theme.of(context).textTheme.labelSmall,
            ),
        ],
      ),
    );
  }
}

class _PostDuelControls extends StatefulWidget {
  const _PostDuelControls({
    required this.controller,
    required this.phase,
    required this.error,
    required this.onAction,
    required this.onFinish,
  });

  final LocalGameController controller;
  final LocalRoundPhase phase;
  final String? error;
  final void Function(void Function(LocalGameController)) onAction;
  final VoidCallback onFinish;

  @override
  State<_PostDuelControls> createState() => _PostDuelControlsState();
}

class _PostDuelControlsState extends State<_PostDuelControls> {
  late final TextEditingController _bidController;
  AuctionTarget _auctionTarget = AuctionTarget.OWN_INITIAL_ACTION;
  CorruptionObjective _corruptionObjective =
      CorruptionObjective.OWN_INITIAL_ACTION;
  final Set<String> _selectedCorruptionCards = {};

  @override
  void initState() {
    super.initState();
    _bidController = TextEditingController(
      text: widget.controller.minimumBid.toString(),
    );
  }

  @override
  void didUpdateWidget(covariant _PostDuelControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.phase != widget.phase &&
        (widget.phase == LocalRoundPhase.counterAuction ||
            widget.phase == LocalRoundPhase.finalDefense)) {
      _bidController.text = widget.controller.minimumBid.toString();
    }
  }

  @override
  void dispose() {
    _bidController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _ActionPointsSummary(controller: widget.controller),
      const SizedBox(height: 8),
      switch (widget.phase) {
        LocalRoundPhase.revealed => _revealed(),
        LocalRoundPhase.counterAuction ||
        LocalRoundPhase.finalDefense => _auction(),
        LocalRoundPhase.corruption => _corruption(),
        LocalRoundPhase.actionExecution => _execution(),
        LocalRoundPhase.roundComplete => _complete(),
        _ => const SizedBox.shrink(),
      },
      if (widget.error case final error?) ...[
        const SizedBox(height: 8),
        Text(
          error,
          key: const Key('post-duel-error'),
          textAlign: TextAlign.center,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ],
    ],
  );

  Widget _revealed() => FilledButton(
    key: const Key('continue-after-duel'),
    onPressed: () => widget.onAction((game) => game.continueAfterDuel()),
    child: Text(
      widget.controller.resolution!.tied
          ? 'Clore la négociation prototype'
          : 'Continuer après le duel',
    ),
  );

  Widget _auction() {
    final isDefense = widget.phase == LocalRoundPhase.finalDefense;
    final actor = widget.controller.activeBidderId;
    final actorLabel = actor == widget.controller.local.playerId
        ? 'Toi'
        : 'Partenaire';
    return Container(
      key: Key(isDefense ? 'final-defense-panel' : 'counter-auction-panel'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            isDefense
                ? 'Défense finale · $actorLabel'
                : 'Contre-enchère · $actorLabel',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          if (!isDefense)
            DropdownButtonFormField<AuctionTarget>(
              key: const Key('auction-target'),
              isExpanded: true,
              initialValue: _auctionTarget,
              decoration: const InputDecoration(
                labelText: 'Objectif',
                isDense: true,
              ),
              items: [
                const DropdownMenuItem(
                  value: AuctionTarget.OWN_INITIAL_ACTION,
                  child: Text('Défendre sa carte originale'),
                ),
                if (widget.controller.inversionAllowed)
                  const DropdownMenuItem(
                    value: AuctionTarget.INVERT_WINNING_ACTION,
                    child: Text('Inverser la carte gagnante'),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _auctionTarget = value);
              },
            ),
          TextField(
            key: const Key('auction-amount'),
            controller: _bidController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText:
                  'PA proposés · minimum ${widget.controller.minimumBid}',
              helperText: 'Les PA engagés sont dépensés définitivement.',
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: Key(isDefense ? 'renounce-defense' : 'renounce-counter'),
                  onPressed: () => widget.onAction(
                    isDefense
                        ? (game) => game.renounceFinalDefense()
                        : (game) => game.renounceCounterBid(),
                  ),
                  child: const Text('Renoncer'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  key: Key(isDefense ? 'confirm-defense' : 'confirm-counter'),
                  onPressed: () {
                    final amount = int.tryParse(_bidController.text) ?? 0;
                    widget.onAction(
                      isDefense
                          ? (game) => game.submitFinalDefense(amount)
                          : (game) =>
                                game.submitCounterBid(amount, _auctionTarget),
                    );
                  },
                  child: const Text('Confirmer'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _corruption() {
    final offer = widget.controller.corruptionOffer;
    if (offer != null) {
      return Container(
        key: const Key('corruption-offer'),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.tertiaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            const Text('Proposition visible'),
            for (final action in offer.actions)
              Text(
                widget.controller.cards[action.cardId]!.view.titleKey ??
                    action.cardId,
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const Key('refuse-corruption'),
                    onPressed: () => widget.onAction(
                      (game) => game.respondToCorruption(accepted: false),
                    ),
                    child: const Text('Refuser'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    key: const Key('accept-corruption'),
                    onPressed: () => widget.onAction(
                      (game) => game.respondToCorruption(accepted: true),
                    ),
                    child: const Text('Accepter'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }
    final cards = widget.controller.corruptionAvailableCards;
    return Container(
      key: const Key('corruption-panel'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Tentations depuis la défausse',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          if (cards.isEmpty)
            const Text('Aucune carte de défausse disponible.')
          else ...[
            DropdownButtonFormField<CorruptionObjective>(
              key: const Key('corruption-objective'),
              isExpanded: true,
              initialValue: _corruptionObjective,
              decoration: const InputDecoration(labelText: 'Objectif'),
              items: [
                const DropdownMenuItem(
                  value: CorruptionObjective.OWN_INITIAL_ACTION,
                  child: Text('Action originale'),
                ),
                if (widget.controller.finalActionCommitment?.cardInvertible ??
                    false)
                  const DropdownMenuItem(
                    value: CorruptionObjective.INVERT_WINNING_ACTION,
                    child: Text('Inversion de l’action gagnante'),
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _corruptionObjective = value);
                }
              },
            ),
            for (final card in cards)
              Material(
                color: Colors.transparent,
                child: CheckboxListTile(
                  key: Key('corruption-card-${card.cardId}'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: _selectedCorruptionCards.contains(card.cardId),
                  title: Text(card.titleKey ?? card.cardId),
                  onChanged: (selected) => setState(() {
                    if (selected ?? false) {
                      _selectedCorruptionCards.add(card.cardId);
                    } else {
                      _selectedCorruptionCards.remove(card.cardId);
                    }
                  }),
                ),
              ),
            FilledButton(
              key: const Key('propose-corruption'),
              onPressed: _selectedCorruptionCards.isEmpty
                  ? null
                  : () => widget.onAction(
                      (game) => game.proposeCorruption(
                        _selectedCorruptionCards,
                        _corruptionObjective,
                      ),
                    ),
              child: const Text('Faire la proposition'),
            ),
          ],
          TextButton(
            key: const Key('skip-corruption'),
            onPressed: () => widget.onAction((game) => game.skipCorruption()),
            child: const Text('Continuer sans proposition'),
          ),
        ],
      ),
    );
  }

  Widget _execution() {
    final current = widget.controller.currentExecutionAction;
    return Container(
      key: const Key('action-execution-panel'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          const Text('Séquence d’actions promise'),
          for (final action in widget.controller.executionActions)
            Text(
              '${widget.controller.cards[action.cardId]!.view.titleKey ?? action.cardId} · ${_actionStatus(action.status)}',
            ),
          const SizedBox(height: 8),
          if (current != null) ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const Key('skip-action'),
                    onPressed: () => widget.onAction(
                      (game) => game.recordCurrentAction(
                        ActionExecutionStatus.SKIPPED,
                      ),
                    ),
                    child: const Text('Passer'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    key: const Key('complete-action'),
                    onPressed: () => widget.onAction(
                      (game) => game.recordCurrentAction(
                        ActionExecutionStatus.COMPLETED,
                      ),
                    ),
                    child: const Text('Réalisée'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FilledButton.tonal(
              key: const Key('consent-stop'),
              style: FilledButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () => widget.onAction((game) => game.consentStop()),
              child: const Text('STOP'),
            ),
          ] else
            FilledButton(
              key: const Key('finish-action-sequence'),
              onPressed: () =>
                  widget.onAction((game) => game.finishCorruptionActions()),
              child: const Text('Terminer la séquence'),
            ),
        ],
      ),
    );
  }

  Widget _complete() {
    final action = widget.controller.finalActionCommitment;
    final card = action == null
        ? null
        : widget.controller.cards[action.snapshot.cardId]?.view;
    return Column(
      key: const Key('round-complete-panel'),
      children: [
        Text(
          widget.controller.resolution!.tied
              ? 'Égalité — négociation'
              : 'Résultat final enregistré',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        if (card != null)
          Text(
            'Action finale : ${card.titleKey ?? card.cardId}${widget.controller.inversionRetained ? ' · inversion' : ''}',
            key: const Key('final-action'),
            textAlign: TextAlign.center,
          ),
        const SizedBox(height: 8),
        FilledButton(
          key: const Key('finish-round-button'),
          onPressed: widget.onFinish,
          child: const Text('Terminer la manche'),
        ),
      ],
    );
  }

  String _actionStatus(ActionExecutionStatus status) => switch (status) {
    ActionExecutionStatus.ACCEPTED => 'À réaliser',
    ActionExecutionStatus.COMPLETED => 'Réalisée',
    ActionExecutionStatus.SKIPPED => 'Passée',
    ActionExecutionStatus.STOPPED => 'Arrêtée',
    ActionExecutionStatus.PROPOSED => 'Proposée',
  };
}

class _ActionPointsSummary extends StatelessWidget {
  const _ActionPointsSummary({required this.controller});

  final LocalGameController controller;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('post-duel-pa'),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      'PA disponibles · Toi ${controller.actionPoints[controller.local.playerId]} · Partenaire ${controller.actionPoints[controller.partner.playerId]}',
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.labelMedium,
    ),
  );
}

class _RevealedCard extends StatelessWidget {
  const _RevealedCard({required this.label, required this.card, super.key});

  final String label;
  final GameCardView card;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final chili = card.chiliLevels.isEmpty ? '—' : card.chiliLevels.join(' · ');
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          Text(
            card.category,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: colors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: colors.secondaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.image_outlined, size: 34),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            card.titleKey ?? 'Carte',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          Text('🌶️ $chili', style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _DiscardAccess extends StatelessWidget {
  const _DiscardAccess({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    key: const Key('discard-button'),
    onPressed: () {},
    icon: const Icon(Icons.layers_outlined),
    label: Text('Défausse · $count carte${count > 1 ? 's' : ''}'),
  );
}

class _PlayerHand extends StatelessWidget {
  const _PlayerHand({
    required this.cards,
    required this.lockedCardId,
    required this.selectedCardId,
    required this.unavailableCardIds,
    required this.onCardTap,
  });

  final List<GameCardView> cards;
  final String? lockedCardId, selectedCardId;
  final Set<String> unavailableCardIds;
  final ValueChanged<GameCardView> onCardTap;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Ma main · ${cards.length}/4',
        style: Theme.of(context).textTheme.titleSmall,
      ),
      const SizedBox(height: 6),
      Expanded(
        child: Row(
          key: const Key('player-hand'),
          children: [
            for (var index = 0; index < 4; index++) ...[
              if (index > 0) const SizedBox(width: 6),
              Expanded(
                child: index < cards.length
                    ? Material(
                        color: Colors.transparent,
                        child: InkWell(
                          key: Key('hand-card-$index'),
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => onCardTap(cards[index]),
                          child: GameCard(
                            card: cards[index],
                            compact: true,
                            locked: lockedCardId == cards[index].cardId,
                            selected: selectedCardId == cards[index].cardId,
                            unavailable: unavailableCardIds.contains(
                              cards[index].cardId,
                            ),
                          ),
                        ),
                      )
                    : const _EmptyHandSlot(),
              ),
            ],
          ],
        ),
      ),
    ],
  );
}

class _EmptyHandSlot extends StatelessWidget {
  const _EmptyHandSlot();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: const Center(child: Icon(Icons.add, size: 20)),
  );
}

class _PrivacyPlaceholder extends StatelessWidget {
  const _PrivacyPlaceholder();

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('privacy-placeholder'),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.phonelink_lock_outlined, size: 34),
        const SizedBox(height: 8),
        Text(
          'Passe le téléphone à ton partenaire',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        const Text('Tes cartes et informations privées sont masquées.'),
      ],
    ),
  );
}

class _CardDetail extends StatelessWidget {
  const _CardDetail({
    required this.card,
    required this.locked,
    required this.unavailable,
    required this.selected,
    required this.variantChoices,
    required this.selectedVariantId,
    required this.onVariantChanged,
    required this.onToggleLock,
    required this.onSelect,
  });

  final GameCardView card;
  final bool locked, unavailable, selected;
  final List<LocalVariantChoice> variantChoices;
  final String? selectedVariantId;
  final ValueChanged<String> onVariantChanged;
  final VoidCallback onToggleLock;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final description = card.descriptionKey ?? 'Description à venir';
    final chili = card.chiliLevels.isEmpty
        ? 'Non précisé'
        : card.chiliLevels.map((level) => '🌶️ $level').join('  ');
    return FractionallySizedBox(
      heightFactor: 0.9,
      child: SingleChildScrollView(
        key: const Key('card-detail-scroll'),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    card.category,
                    key: const Key('detail-category'),
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Icon(
                  locked ? Icons.lock_rounded : Icons.lock_open_rounded,
                  key: const Key('detail-lock-status'),
                  semanticLabel: locked ? 'Verrouillée' : 'Déverrouillée',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              key: const Key('detail-illustration'),
              height: 220,
              decoration: BoxDecoration(
                color: colors.secondaryContainer,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                Icons.image_outlined,
                size: 68,
                color: colors.onSecondaryContainer.withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              card.titleKey ?? 'Carte',
              key: const Key('detail-title'),
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              key: const Key('detail-description'),
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            if (variantChoices.length > 1) ...[
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                key: const Key('variant-selector'),
                initialValue: selectedVariantId,
                decoration: const InputDecoration(
                  labelText: 'Variante accessible',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final choice in variantChoices)
                    DropdownMenuItem(
                      value: choice.variant.id,
                      child: Text(
                        '🌶️ ${choice.variant.chiliLevel} · ${choice.role.name}',
                      ),
                    ),
                ],
                onChanged: (id) {
                  if (id != null) onVariantChanged(id);
                },
              ),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  key: const Key('detail-chili'),
                  avatar: const Icon(Icons.local_fire_department_outlined),
                  label: Text(chili),
                ),
                if (card.personalValue != null)
                  Chip(
                    key: const Key('detail-personal-value'),
                    avatar: const Icon(Icons.favorite_outline),
                    label: Text('${card.personalValue}/20'),
                  ),
                Chip(
                  key: const Key('detail-lock-label'),
                  avatar: Icon(
                    locked ? Icons.lock_rounded : Icons.lock_open_rounded,
                  ),
                  label: Text(locked ? 'Verrouillée' : 'Déverrouillée'),
                ),
              ],
            ),
            if (unavailable) ...[
              const SizedBox(height: 14),
              Container(
                key: const Key('unavailable-explanation'),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "Cette carte n'est pas disponible dans la situation actuelle.",
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (card.instructionKeys.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(
                'En savoir plus',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              for (final information in card.instructionKeys)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(information),
                ),
            ],
            const SizedBox(height: 22),
            OutlinedButton.icon(
              key: const Key('lock-card-button'),
              onPressed: onToggleLock,
              icon: Icon(locked ? Icons.lock_open_rounded : Icons.lock_rounded),
              label: Text(
                locked ? 'Déverrouiller la carte' : 'Verrouiller la carte',
              ),
            ),
            const SizedBox(height: 10),
            FilledButton(
              key: const Key('choose-card-button'),
              onPressed: onSelect,
              child: Text(
                selected ? 'Carte sélectionnée' : 'Choisir cette carte',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class GameCard extends StatelessWidget {
  const GameCard({
    required this.card,
    this.compact = false,
    this.prominent = false,
    this.hidePersonalValue = false,
    this.locked,
    this.selected = false,
    this.unavailable = false,
    super.key,
  });

  final GameCardView card;
  final bool compact, prominent, hidePersonalValue;
  final bool? locked;
  final bool selected, unavailable;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final title = card.titleKey ?? 'Carte';
    final description =
        card.descriptionKey ??
        card.instructionKeys.firstOrNull ??
        'Description à venir';
    final chili = card.chiliLevels.isEmpty ? '—' : card.chiliLevels.join(' · ');
    final isLocked = locked ?? card.locked;
    return Opacity(
      opacity: unavailable ? 0.48 : 1,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(prominent ? 22 : 14),
          border: Border.all(
            color: selected ? colors.primary : colors.outlineVariant,
            width: selected ? 3 : 1,
          ),
          boxShadow: prominent
              ? [
                  BoxShadow(
                    color: colors.shadow.withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: EdgeInsets.all(compact ? 7 : 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      card.category,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (selected)
                    Icon(
                      Icons.check_circle_rounded,
                      key: Key('card-selected-${card.cardId}'),
                      size: compact ? 15 : 20,
                      color: colors.primary,
                      semanticLabel: 'Carte sélectionnée',
                    ),
                  if (isLocked)
                    Icon(
                      Icons.lock_rounded,
                      key: Key('card-lock-${card.cardId}'),
                      size: compact ? 15 : 20,
                      semanticLabel: 'Carte verrouillée',
                    ),
                ],
              ),
              SizedBox(height: compact ? 4 : 8),
              Expanded(
                flex: prominent ? 3 : 2,
                child: Container(
                  key: Key('illustration-${card.cardId}'),
                  decoration: BoxDecoration(
                    color: colors.secondaryContainer,
                    borderRadius: BorderRadius.circular(compact ? 8 : 14),
                  ),
                  child: Icon(
                    Icons.image_outlined,
                    size: compact ? 22 : 42,
                    color: colors.onSecondaryContainer.withValues(alpha: 0.55),
                  ),
                ),
              ),
              SizedBox(height: compact ? 4 : 8),
              Text(
                title,
                maxLines: compact ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style:
                    (compact
                            ? Theme.of(context).textTheme.labelMedium
                            : Theme.of(context).textTheme.titleMedium)
                        ?.copyWith(fontWeight: FontWeight.w700),
              ),
              if (!compact) ...[
                const SizedBox(height: 3),
                Text(
                  description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              SizedBox(height: compact ? 3 : 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '🌶️ $chili',
                      maxLines: 1,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    if (!hidePersonalValue && card.personalValue != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        '${card.personalValue}/20',
                        key: Key('personal-value-${card.cardId}'),
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
