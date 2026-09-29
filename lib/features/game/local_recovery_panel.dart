import 'package:flutter/material.dart';

import '../../engines/engines.dart';
import 'local_game_controller.dart';
import 'local_recovery_controller.dart';

class LocalRecoveryPanel extends StatefulWidget {
  const LocalRecoveryPanel({
    required this.controller,
    required this.privacyTransition,
    required this.error,
    required this.onAction,
    super.key,
  });

  final LocalGameController controller;
  final bool privacyTransition;
  final String? error;
  final void Function(void Function(LocalGameController)) onAction;

  @override
  State<LocalRecoveryPanel> createState() => _LocalRecoveryPanelState();
}

class _LocalRecoveryPanelState extends State<LocalRecoveryPanel> {
  late final TextEditingController _extensionAmount;
  String? _selectedCardId, _selectedVariantId;
  String? _conditionCardId, _conditionVariantId;

  LocalRecoveryController get recovery => widget.controller.recoveryController;

  @override
  void initState() {
    super.initState();
    _extensionAmount = TextEditingController(text: '10');
  }

  @override
  void dispose() {
    _extensionAmount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.privacyTransition ||
        recovery.phase == LocalRecoveryPhase.extensionPrivateTransition) {
      return _privateTransition();
    }
    return Container(
      key: const Key('between-rounds-panel'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Entre les manches',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'PA · Toi ${widget.controller.actionPoints[widget.controller.local.playerId]} · Partenaire ${widget.controller.actionPoints[widget.controller.partner.playerId]}',
              key: const Key('between-round-pa'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            switch (recovery.phase) {
              LocalRecoveryPhase.idle => _idle(),
              LocalRecoveryPhase.choosingAction => _chooseAction(),
              LocalRecoveryPhase.awaitingResponse => _response(),
              LocalRecoveryPhase.choosingCondition => _chooseCondition(),
              LocalRecoveryPhase.executing => _execution(),
              LocalRecoveryPhase.extensionFirstConfirmation =>
                _firstExtensionConfirmation(),
              LocalRecoveryPhase.extensionSecondConfirmation =>
                _secondExtensionConfirmation(),
              LocalRecoveryPhase.complete => _complete(),
              LocalRecoveryPhase.extensionPrivateTransition =>
                const SizedBox.shrink(),
            },
            if (widget.error case final error?) ...[
              const SizedBox(height: 8),
              Text(
                error,
                key: const Key('recovery-error'),
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _idle() {
    final lowPlayers = [
      if (recovery.isLow(widget.controller.local.playerId))
        widget.controller.local.playerId,
      if (recovery.isLow(widget.controller.partner.playerId))
        widget.controller.partner.playerId,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (lowPlayers.isEmpty)
          const Text('Les PA permettent de poursuivre normalement.')
        else ...[
          const Text(
            'PA faibles — Recovery disponible',
            key: Key('recovery-available-label'),
            textAlign: TextAlign.center,
          ),
          for (final playerId in lowPlayers)
            if (widget.controller.recoveryAvailableFor(playerId))
              OutlinedButton(
                key: Key('start-recovery-$playerId'),
                onPressed: () =>
                    widget.onAction((game) => game.startRecovery(playerId)),
                child: Text(
                  playerId == widget.controller.local.playerId
                      ? 'Recovery · Toi'
                      : 'Recovery · Partenaire',
                ),
              ),
        ],
        if (widget.controller.bothPlayersLow) ...[
          const Divider(height: 20),
          TextField(
            key: const Key('extension-amount'),
            controller: _extensionAmount,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Montant identique pour les deux joueurs',
            ),
          ),
          FilledButton.tonal(
            key: const Key('start-mutual-extension'),
            onPressed: () => widget.onAction(
              (game) => game.startMutualExtension(
                int.tryParse(_extensionAmount.text) ?? -1,
              ),
            ),
            child: const Text('Prolonger la partie'),
          ),
        ],
        const SizedBox(height: 8),
        FilledButton(
          key: const Key('start-next-round'),
          onPressed: () => widget.onAction((game) => game.startNextRound()),
          child: const Text('Manche suivante'),
        ),
      ],
    );
  }

  Widget _chooseAction() {
    final options = widget.controller.recoveryOptionsFor(
      recovery.recoveringPlayerId!,
    );
    _selectedCardId ??= options.firstOrNull?.card.id;
    _selectedVariantId ??= options.firstOrNull?.variant.id;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Choisir une action Recovery dans le catalogue local'),
        const SizedBox(height: 6),
        if (options.isEmpty)
          const Text('Aucune action éligible.')
        else ...[
          DropdownButtonFormField<String>(
            key: const Key('recovery-action-selector'),
            isExpanded: true,
            initialValue: _optionKey(_selectedCardId!, _selectedVariantId!),
            items: [
              for (final option in options)
                DropdownMenuItem(
                  value: _optionKey(option.card.id, option.variant.id),
                  child: Text(
                    '${_title(option.card.id)} · 🌶️ ${option.variant.chiliLevel} · ${_source(option.source)}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (value) {
              if (value == null) return;
              final option = options.singleWhere(
                (item) => _optionKey(item.card.id, item.variant.id) == value,
              );
              setState(() {
                _selectedCardId = option.card.id;
                _selectedVariantId = option.variant.id;
              });
            },
          ),
          FilledButton(
            key: const Key('propose-recovery-action'),
            onPressed: () => widget.onAction(
              (game) => game.selectRecoveryAction(
                _selectedCardId!,
                _selectedVariantId!,
              ),
            ),
            child: const Text('Proposer cette action'),
          ),
        ],
      ],
    );
  }

  Widget _response() {
    final action = recovery.selectedAction!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Proposition : ${_title(action.card.id)}'),
        const SizedBox(height: 6),
        OutlinedButton(
          key: const Key('refuse-recovery'),
          onPressed: () => widget.onAction(
            (game) => game.answerRecovery(RecoveryResponse.REFUSE),
          ),
          child: const Text('Refuser'),
        ),
        OutlinedButton(
          key: const Key('condition-recovery'),
          onPressed: recovery.conditionOptions.isEmpty
              ? null
              : () => widget.onAction(
                  (game) => game.answerRecovery(
                    RecoveryResponse.ACCEPT_WITH_ONE_DISCARD_CONDITION,
                  ),
                ),
          child: const Text('Accepter avec une condition'),
        ),
        FilledButton(
          key: const Key('accept-recovery'),
          onPressed: () => widget.onAction(
            (game) => game.answerRecovery(RecoveryResponse.ACCEPT),
          ),
          child: const Text('Accepter'),
        ),
      ],
    );
  }

  Widget _chooseCondition() {
    final options = recovery.conditionOptions;
    _conditionCardId ??= options.first.card.id;
    _conditionVariantId ??= options.first.variant.id;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Condition compatible depuis la défausse Recovery'),
        DropdownButtonFormField<String>(
          key: const Key('recovery-condition-selector'),
          isExpanded: true,
          initialValue: _optionKey(_conditionCardId!, _conditionVariantId!),
          items: [
            for (final option in options)
              DropdownMenuItem(
                value: _optionKey(option.card.id, option.variant.id),
                child: Text(
                  '${_title(option.card.id)} · 🌶️ ${option.variant.chiliLevel}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (value) {
            if (value == null) return;
            final option = options.singleWhere(
              (item) => _optionKey(item.card.id, item.variant.id) == value,
            );
            setState(() {
              _conditionCardId = option.card.id;
              _conditionVariantId = option.variant.id;
            });
          },
        ),
        FilledButton(
          key: const Key('confirm-recovery-condition'),
          onPressed: () => widget.onAction(
            (game) => game.selectRecoveryCondition(
              _conditionCardId!,
              _conditionVariantId!,
            ),
          ),
          child: const Text('Valider la condition'),
        ),
      ],
    );
  }

  Widget _execution() {
    final current = recovery.currentExecution;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Actions Recovery convenues'),
        for (final item in recovery.execution)
          Text('${_title(item.option.card.id)} · ${_status(item.status)}'),
        const SizedBox(height: 8),
        if (current != null) ...[
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const Key('skip-recovery-action'),
                  onPressed: () => widget.onAction(
                    (game) => game.recordRecoveryAction(
                      ActionExecutionStatus.SKIPPED,
                    ),
                  ),
                  child: const Text('Passer'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  key: const Key('complete-recovery-action'),
                  onPressed: () => widget.onAction(
                    (game) => game.recordRecoveryAction(
                      ActionExecutionStatus.COMPLETED,
                    ),
                  ),
                  child: const Text('Réalisée'),
                ),
              ),
            ],
          ),
          FilledButton.tonal(
            key: const Key('stop-recovery'),
            onPressed: () => widget.onAction((game) => game.stopRecovery()),
            child: const Text('STOP'),
          ),
        ] else
          FilledButton(
            key: const Key('finish-recovery-sequence'),
            onPressed: () =>
                widget.onAction((game) => game.finishRecoveryExecution()),
            child: const Text('Terminer la séquence'),
          ),
      ],
    );
  }

  Widget _firstExtensionConfirmation() => Column(
    children: [
      Text('Ajouter ${recovery.extensionAmount} PA à chacun ?'),
      FilledButton(
        key: const Key('confirm-extension-first'),
        onPressed: () =>
            widget.onAction((game) => game.confirmExtensionFirst()),
        child: const Text('Joueur A confirme'),
      ),
    ],
  );

  Widget _secondExtensionConfirmation() => Column(
    children: [
      Text('Même montant : ${recovery.extensionAmount} PA chacun'),
      Row(
        children: [
          Expanded(
            child: OutlinedButton(
              key: const Key('refuse-extension-second'),
              onPressed: () => widget.onAction(
                (game) => game.answerExtensionSecond(accepted: false),
              ),
              child: const Text('Refuser'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton(
              key: const Key('confirm-extension-second'),
              onPressed: () => widget.onAction(
                (game) => game.answerExtensionSecond(accepted: true),
              ),
              child: const Text('Joueur B confirme'),
            ),
          ),
        ],
      ),
    ],
  );

  Widget _complete() {
    final isExtension = recovery.extensionAmount != null;
    return Column(
      children: [
        Text(
          isExtension
              ? recovery.extensionAccepted == true
                    ? 'Extension appliquée à parts égales'
                    : 'Extension refusée — PA inchangés'
              : recovery.response == RecoveryResponse.REFUSE
              ? 'Recovery refusé — aucun changement'
              : 'Recovery terminé · +${recovery.lastGain} PA',
          key: const Key('between-action-result'),
          textAlign: TextAlign.center,
        ),
        FilledButton(
          key: const Key('finish-between-action'),
          onPressed: () =>
              widget.onAction((game) => game.finishBetweenRoundAction()),
          child: const Text('Retour entre les manches'),
        ),
      ],
    );
  }

  Widget _privateTransition() => Container(
    key: const Key('extension-private-transition'),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.visibility_off_outlined, size: 42),
        const SizedBox(height: 8),
        const Text(
          'Passe le téléphone à ton partenaire',
          textAlign: TextAlign.center,
        ),
        if (!widget.privacyTransition)
          FilledButton(
            key: const Key('show-extension-second'),
            onPressed: () =>
                widget.onAction((game) => game.showExtensionToSecondPlayer()),
            child: const Text('Téléphone transmis'),
          ),
      ],
    ),
  );

  String _title(String cardId) =>
      widget.controller.cards[cardId]?.view.titleKey ?? cardId;
  String _optionKey(String cardId, String variantId) => '$cardId::$variantId';
  String _source(RecoverySource source) => switch (source) {
    RecoverySource.HAND => 'main',
    RecoverySource.DISCARD => 'défausse',
    RecoverySource.CATALOG => 'catalogue',
  };
  String _status(ActionExecutionStatus status) => switch (status) {
    ActionExecutionStatus.ACCEPTED => 'À réaliser',
    ActionExecutionStatus.COMPLETED => 'Réalisée',
    ActionExecutionStatus.SKIPPED => 'Passée',
    ActionExecutionStatus.STOPPED => 'Arrêtée',
    ActionExecutionStatus.PROPOSED => 'Proposée',
  };
}
