import 'package:flutter/material.dart';

import '../../card_themes/card_renderer.dart';
import '../../card_themes/card_theme_models.dart';
import '../../domain/catalog/catalog.dart';
import '../../domain/game/game_models.dart';
import '../../domain/profile/adaptive_profile.dart';
import '../../engines/auction/auction_engine.dart';
import '../../engines/corruption/corruption_engine.dart';
import '../../engines/deck/session_deck_builder.dart';
import '../../engines/recovery/recovery_engine.dart';
import '../../sync/rounds/network_game.dart';
import '../lobby/lobby_models.dart';
import 'network_duel_secret_store.dart';
import 'network_auction_form_controller.dart';
import 'network_game_controller.dart';
import 'network_profile_learning.dart';

class NetworkDuelScreen extends StatefulWidget {
  const NetworkDuelScreen({
    required this.session,
    required this.playerId,
    required this.repository,
    required this.catalog,
    this.secretStore = const SharedPreferencesNetworkDuelSecretStore(),
    super.key,
  });

  final LobbySession session;
  final String playerId;
  final NetworkGameRepository repository;
  final Catalog catalog;
  final NetworkDuelSecretStore secretStore;

  @override
  State<NetworkDuelScreen> createState() => _NetworkDuelScreenState();
}

class _NetworkDuelScreenState extends State<NetworkDuelScreen> {
  late final NetworkGameController controller;
  final auctionForm = NetworkAuctionFormController();
  final Set<String> _negotiationCards = {};
  bool _requestInversion = false;
  bool _acceptInversion = false;
  bool _acceptAuction = false;
  String? actionError;

  @override
  void initState() {
    super.initState();
    controller = NetworkGameController(
      session: widget.session,
      playerId: widget.playerId,
      repository: widget.repository,
      privateStore: widget.secretStore,
      catalog: widget.catalog,
    )..addListener(_refresh);
    controller.start();
  }

  void _refresh() {
    if (!mounted) return;
    final changedRound = auctionForm.enterRound(controller.roundNumber);
    setState(() {
      if (changedRound) {
        actionError = null;
        _negotiationCards.clear();
        _requestInversion = false;
        _acceptInversion = false;
        _acceptAuction = false;
      }
    });
  }

  @override
  void dispose() {
    controller
      ..removeListener(_refresh)
      ..dispose();
    auctionForm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('TOUR ${controller.roundNumber}'),
      actions: [
        IconButton(
          key: const Key('open-private-profile-settings'),
          tooltip: 'Profil privé',
          onPressed: _openProfileSettings,
          icon: const Icon(Icons.manage_accounts),
        ),
        IconButton(
          key: const Key('switch-hybrid-orientation'),
          tooltip: controller.orientation == HybridDeckOrientation.faceToFace
              ? 'Passer en orientation distance'
              : 'Passer en orientation face à face',
          onPressed: () => controller.switchOrientation(
            controller.orientation == HybridDeckOrientation.faceToFace
                ? HybridDeckOrientation.distance
                : HybridDeckOrientation.faceToFace,
          ),
          icon: Icon(
            controller.orientation == HybridDeckOrientation.faceToFace
                ? Icons.people
                : Icons.phone_android,
          ),
        ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          if (controller.actionPoints.isNotEmpty) _points(),
          Expanded(child: _body()),
        ],
      ),
    ),
  );

  Widget _points() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('Tes PA : ${controller.actionPoints[controller.playerId]}'),
        Text(
          'Partenaire : ${controller.actionPoints[controller.opponentId]} PA',
        ),
      ],
    ),
  );

  Widget _body() => switch (controller.viewState) {
    NetworkGameViewState.loading => const Center(
      child: CircularProgressIndicator(key: Key('duel-loading')),
    ),
    NetworkGameViewState.choosing ||
    NetworkGameViewState.committing => _choosing(),
    NetworkGameViewState.waitingForPartner ||
    NetworkGameViewState.revealing => _waiting(),
    NetworkGameViewState.negotiationProposal => _negotiationProposal(),
    NetworkGameViewState.negotiationResponse => _negotiationResponse(),
    NetworkGameViewState.negotiationAdaptation => _negotiationAdaptation(),
    NetworkGameViewState.negotiationValidation => _negotiationValidation(),
    NetworkGameViewState.counterDecision => _counterDecision(),
    NetworkGameViewState.finalDefenseDecision => _finalDefense(),
    NetworkGameViewState.tieDecision => _tieDecision(),
    NetworkGameViewState.finalResult => _finalResult(),
    NetworkGameViewState.corruptionDecision => _corruptionDecision(),
    NetworkGameViewState.corruptionResponse => _corruptionResponse(),
    NetworkGameViewState.corruptionExecution => _corruptionExecution(),
    NetworkGameViewState.recovery => _recovery(),
    NetworkGameViewState.recoveryResponse => _recoveryResponse(),
    NetworkGameViewState.recoveryExecution => _recoveryExecution(),
    NetworkGameViewState.waitingNext => _waitingNext(),
    NetworkGameViewState.error => _error(),
  };

  Widget _choosing() => ListView(
    key: const Key('network-game-hand'),
    padding: const EdgeInsets.all(16),
    children: [
      Text(
        'Choisis une carte',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const Text('Ta main, ton verrou et tes notes restent privés.'),
      const SizedBox(height: 12),
      for (final card in controller.hand) ...[
        SizedBox(
          height: 250,
          child: Stack(
            children: [
              Positioned.fill(
                child: InkWell(
                  key: Key('network-card-${card.identity}'),
                  onTap: controller.viewState == NetworkGameViewState.choosing
                      ? () => controller.selectCard(card.identity)
                      : null,
                  child: CardRenderer(
                    definition: CardRenderDefinition(
                      cardId: card.id,
                      variantId: card.variant.id,
                      title: card.title,
                      action: card.definition.descriptionKey,
                      direction: card.role.name,
                      spice: card.chiliLevel,
                      personalPa: card.personalValue,
                      illustrationId: card.definition.illustrationKey,
                    ),
                    state: controller.selectedCard?.identity == card.identity
                        ? CardVisualState.selected
                        : controller.lockedCardId == card.identity
                        ? CardVisualState.locked
                        : CardVisualState.normal,
                  ),
                ),
              ),
              Positioned(
                left: 8,
                top: 8,
                child: IconButton.filledTonal(
                  key: Key('lock-${card.identity}'),
                  tooltip: controller.lockedCardId == card.identity
                      ? 'Déverrouiller'
                      : 'Verrouiller',
                  onPressed: () => controller.toggleLock(card.identity),
                  icon: Icon(
                    controller.lockedCardId == card.identity
                        ? Icons.lock
                        : Icons.lock_open,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
      ],
      FilledButton(
        key: const Key('confirm-network-card'),
        onPressed:
            controller.selectedCard != null &&
                controller.viewState == NetworkGameViewState.choosing
            ? controller.confirmSelection
            : null,
        child: const Text('Valider ce choix'),
      ),
    ],
  );

  Widget _waiting() => _centerMessage(
    controller.viewState == NetworkGameViewState.revealing
        ? 'Validation sécurisée des choix…'
        : 'En attente de ton partenaire…',
    key: const Key('network-duel-waiting'),
  );

  Widget _negotiationProposal() => _negotiationEditor(
    title: 'Proposer un compromis',
    waiting: 'Ton partenaire prépare une proposition…',
    buttonLabel: 'Envoyer la proposition',
    onSubmit: () => _submitNegotiation(adaptation: false),
  );

  Widget _negotiationAdaptation() {
    final response = controller.negotiation!.response!;
    return _negotiationEditor(
      title: 'Adapter ma proposition',
      waiting: 'Ton partenaire adapte sa proposition…',
      buttonLabel: 'Envoyer le choix final',
      allowInversion: response.acceptInversion,
      allowAuction: response.acceptAuction,
      onSubmit: () => _submitNegotiation(adaptation: true),
    );
  }

  Widget _negotiationEditor({
    required String title,
    required String waiting,
    required String buttonLabel,
    required VoidCallback onSubmit,
    bool allowInversion = true,
    bool allowAuction = true,
  }) => ListView(
    key: Key(title),
    padding: const EdgeInsets.all(16),
    children: [
      _initialResult(controller.initialResolution!),
      const SizedBox(height: 12),
      if (!controller.isInitialLoser)
        _waitingCard(waiting)
      else ...[
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        if (controller.inversionAllowed && allowInversion)
          SwitchListTile(
            key: const Key('negotiation-inversion'),
            value: _requestInversion,
            onChanged: (value) => setState(() => _requestInversion = value),
            title: const Text('Proposer une inversion'),
          ),
        if (allowAuction) ...[
          TextField(
            key: const Key('negotiation-direct-pa'),
            controller: auctionForm.counterAmount,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'PA personnels (facultatif)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          const Text('Cartes ajoutées au compromis'),
          for (final card in controller.auctionCards)
            CheckboxListTile(
              key: Key('negotiation-card-${card.identity}'),
              value: _negotiationCards.contains(card.identity),
              onChanged: (selected) => setState(() {
                if (selected == true) {
                  _negotiationCards.add(card.identity);
                } else {
                  _negotiationCards.remove(card.identity);
                }
              }),
              title: Text(card.title),
              subtitle: Text(
                '${card.role.name} · ${_chilies(card.chiliLevel)}',
              ),
            ),
        ],
        FilledButton(
          key: const Key('submit-negotiation'),
          onPressed: onSubmit,
          child: Text(buttonLabel),
        ),
      ],
      if (actionError case final message?) _errorText(message),
    ],
  );

  Widget _negotiationResponse() {
    final proposal = controller.negotiation!.proposal!;
    return ListView(
      key: const Key('negotiation-response'),
      padding: const EdgeInsets.all(16),
      children: [
        _initialResult(controller.initialResolution!),
        if (!controller.isInitialWinner)
          _waitingCard('Ton partenaire répond à ta proposition…')
        else ...[
          Text(
            'Répondre au compromis',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          if (proposal.inversionRequested)
            SwitchListTile(
              key: const Key('accept-negotiation-inversion'),
              value: _acceptInversion,
              onChanged: (value) => setState(() => _acceptInversion = value),
              title: const Text('Accepter l’inversion'),
            ),
          if (proposal.totalValue > 0)
            SwitchListTile(
              key: const Key('accept-negotiation-auction'),
              value: _acceptAuction,
              onChanged: (value) => setState(() => _acceptAuction = value),
              title: Text('Accepter l’enchère (${proposal.totalValue})'),
            ),
          FilledButton(
            key: const Key('respond-negotiation'),
            onPressed: () => controller.respondNegotiation(
              acceptInversion: _acceptInversion,
              acceptAuction: _acceptAuction,
            ),
            child: const Text('Envoyer ma réponse'),
          ),
        ],
      ],
    );
  }

  Widget _negotiationValidation() {
    final offer = controller.negotiation!.finalOffer!;
    return ListView(
      key: const Key('negotiation-validation'),
      padding: const EdgeInsets.all(16),
      children: [
        _initialResult(controller.initialResolution!),
        if (!controller.isInitialWinner)
          _waitingCard('Ton partenaire valide le compromis…')
        else ...[
          Text(
            'Compromis final',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          if (offer.inversionRequested)
            const Text('• Inversion de la carte initiale'),
          if (offer.directPa > 0) Text('• ${offer.directPa} PA personnels'),
          for (final card in offer.cards) Text('• ${_title(card.cardId)}'),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('validate-negotiation'),
            onPressed: () => controller.validateNegotiation(accepted: true),
            child: const Text('Valider le compromis'),
          ),
          OutlinedButton(
            key: const Key('refuse-negotiation'),
            onPressed: () => controller.validateNegotiation(accepted: false),
            child: const Text('Conserver le résultat initial'),
          ),
        ],
      ],
    );
  }

  Widget _counterDecision() {
    final initial = controller.initialResolution!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _initialResult(initial),
        const SizedBox(height: 16),
        if (!controller.isInitialLoser)
          _waitingCard('Ton partenaire choisit s’il contre-enchérit.')
        else ...[
          FilledButton.tonal(
            key: const Key('accept-initial-result'),
            onPressed: controller.acceptInitialResult,
            child: const Text('Accepter le résultat'),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('counter-amount'),
            controller: auctionForm.counterAmount,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Montant de la contre-enchère',
              border: OutlineInputBorder(),
            ),
          ),
          RadioGroup<AuctionTarget>(
            groupValue: auctionForm.counterTarget,
            onChanged: (value) =>
                setState(() => auctionForm.counterTarget = value!),
            child: Column(
              children: [
                const RadioListTile(
                  value: AuctionTarget.OWN_INITIAL_ACTION,
                  title: Text('Défendre ma carte'),
                ),
                if (controller.inversionAllowed)
                  const RadioListTile(
                    value: AuctionTarget.INVERT_WINNING_ACTION,
                    title: Text('Inverser la carte gagnante'),
                  ),
              ],
            ),
          ),
          FilledButton(
            key: const Key('submit-counter-bid'),
            onPressed: _submitCounter,
            child: const Text('Contre-enchérir'),
          ),
        ],
        if (actionError case final message?) _errorText(message),
      ],
    );
  }

  Widget _finalDefense() {
    final initial = controller.initialResolution!;
    final counter = controller.round!.counterBid!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _initialResult(initial),
        Text('Contre-enchère : ${counter.amount} PA'),
        const SizedBox(height: 16),
        if (!controller.isInitialWinner)
          _waitingCard('Ton partenaire choisit sa défense finale.')
        else ...[
          FilledButton.tonal(
            key: const Key('yield-final-defense'),
            onPressed: controller.yieldFinalDefense,
            child: const Text('Laisser gagner'),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('defense-amount'),
            controller: auctionForm.defenseAmount,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText:
                  'Défense finale (minimum ${controller.minimumDefense})',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('submit-final-defense'),
            onPressed: _submitDefense,
            child: const Text('Défendre'),
          ),
        ],
        if (actionError case final message?) _errorText(message),
      ],
    );
  }

  Widget _tieDecision() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      _initialResult(controller.initialResolution!),
      const SizedBox(height: 16),
      FilledButton.tonal(
        key: const Key('concede-tie'),
        onPressed: controller.hasSubmittedTieDecision
            ? null
            : controller.concedeTie,
        child: const Text('Concéder'),
      ),
      const SizedBox(height: 12),
      OutlinedButton(
        key: const Key('abandon-tie'),
        onPressed: controller.hasSubmittedTieDecision
            ? null
            : controller.abandonTie,
        child: const Text('Abandonner ce round'),
      ),
      if (controller.round!.tieDecisions[controller.playerId] ==
          TieDecision.abandon)
        const Padding(
          padding: EdgeInsets.only(top: 16),
          child: Text('En attente de la décision du partenaire…'),
        ),
    ],
  );

  Widget _finalResult() {
    final result = controller.finalResolution!;
    final title = result.mutualAbandon
        ? 'Round abandonné mutuellement'
        : result.retainedPlayerId == controller.playerId
        ? 'Ton action est retenue'
        : 'Action du partenaire retenue';
    return ListView(
      key: const Key('network-final-result'),
      padding: const EdgeInsets.all(16),
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        if (!result.mutualAbandon) ...[
          const SizedBox(height: 12),
          if (result.compromise.isNotEmpty) ...[
            for (final card in result.compromise)
              ListTile(
                title: Text(_title(card.cardId)),
                subtitle: Text(
                  '${card.effectiveDirection.name} · ${card.origin.name}',
                ),
              ),
          ] else if (result.cardId != null) ...[
            Text('Carte : ${_title(result.cardId!)}'),
            Text('Variante : ${result.variantId}'),
            if (result.inverted) const Text('Rôles physiques inversés'),
          ],
        ],
        const SizedBox(height: 20),
        if (controller.deckExhausted) ...[
          Text(
            'Cycle de cartes terminé',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (controller.deckShortages.isNotEmpty) _deckAdjustmentMessage(),
          if (controller.postGameProfileChoice == null) ...[
            const Text('Pour la suite de ton profil privé :'),
            TextButton(
              onPressed: () => controller.choosePostGameProfile(
                PostGameProfileChoice.customize,
              ),
              child: const Text('Personnaliser mon profil'),
            ),
            TextButton(
              onPressed: () => controller.choosePostGameProfile(
                PostGameProfileChoice.trustGame,
              ),
              child: const Text('Faire confiance au jeu'),
            ),
            TextButton(
              onPressed: () =>
                  controller.choosePostGameProfile(PostGameProfileChoice.later),
              child: const Text('Ne rien faire pour l’instant'),
            ),
          ],
          if (controller.isCycleController) ...[
            FilledButton(
              key: const Key('continue-spicier'),
              onPressed: () => controller.continueDeck(
                controller.deckStyle == PlayerStyle.INTENABLE
                    ? DeckExhaustionChoice.continueIntenable
                    : DeckExhaustionChoice.continueSpicier,
              ),
              child: Text(
                controller.deckStyle == PlayerStyle.SOFT
                    ? 'Continuer en Épicé'
                    : 'Continuer en Intenable',
              ),
            ),
            OutlinedButton(
              key: const Key('enable-infinite'),
              onPressed: () =>
                  controller.continueDeck(DeckExhaustionChoice.infinite),
              child: const Text('Mode Infini'),
            ),
            OutlinedButton(
              key: const Key('new-customized-game'),
              onPressed: () => controller.continueDeck(
                DeckExhaustionChoice.newCustomizedGame,
              ),
              child: const Text('Nouvelle partie'),
            ),
            TextButton(
              key: const Key('finish-game'),
              onPressed: () =>
                  controller.continueDeck(DeckExhaustionChoice.finish),
              child: const Text('Terminer'),
            ),
          ] else
            _waitingCard('Ton partenaire choisit la suite de la partie…'),
        ] else
          FilledButton(
            key: const Key('ready-next-round'),
            onPressed: controller.readyForNextRound,
            child: const Text('Tour suivant'),
          ),
      ],
    );
  }

  Widget _corruptionDecision() => ListView(
    key: const Key('network-corruption-decision'),
    padding: const EdgeInsets.all(16),
    children: [
      Text('Corruption', style: Theme.of(context).textTheme.headlineSmall),
      const Text('Seule la carte proposée est rendue publique.'),
      const SizedBox(height: 16),
      if (!controller.isCorruptionActor)
        _waitingCard('Ton partenaire décide s’il propose une corruption.')
      else ...[
        for (final card in controller.corruptionCards)
          ListTile(
            key: Key('corruption-card-${card.id}'),
            title: Text(card.title),
            subtitle: const Text('Carte de la défausse'),
            trailing: FilledButton.tonal(
              onPressed: () => controller.proposeCorruption(
                card.identity,
                CorruptionObjective.OWN_INITIAL_ACTION,
              ),
              child: const Text('Proposer'),
            ),
          ),
        OutlinedButton(
          key: const Key('skip-network-corruption'),
          onPressed: controller.skipCorruption,
          child: const Text('Continuer sans corruption'),
        ),
      ],
    ],
  );

  Widget _corruptionResponse() {
    final offer = controller.corruption!;
    return ListView(
      key: const Key('network-corruption-response'),
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Proposition de corruption',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        for (final action in offer.actions)
          Text('Carte : ${_title(action.cardId)}'),
        const SizedBox(height: 16),
        if (offer.offeredBy == controller.playerId)
          _waitingCard('En attente de la réponse du partenaire…')
        else ...[
          FilledButton(
            key: const Key('accept-network-corruption'),
            onPressed: () => controller.respondToCorruption(accepted: true),
            child: const Text('Accepter'),
          ),
          OutlinedButton(
            key: const Key('refuse-network-corruption'),
            onPressed: () => controller.respondToCorruption(accepted: false),
            child: const Text('Refuser'),
          ),
        ],
      ],
    );
  }

  Widget _corruptionExecution() => ListView(
    key: const Key('network-corruption-execution'),
    padding: const EdgeInsets.all(16),
    children: [
      const Text('Corruption acceptée'),
      if (controller.corruption!.offeredBy != controller.playerId)
        _waitingCard('Le partenaire exécute l’action convenue…')
      else ...[
        FilledButton(
          key: const Key('complete-network-corruption'),
          onPressed: () => controller.completeCorruption(completed: true),
          child: const Text('Action exécutée'),
        ),
        OutlinedButton(
          key: const Key('skip-network-corruption-action'),
          onPressed: () => controller.completeCorruption(completed: false),
          child: const Text('Action non exécutée'),
        ),
      ],
    ],
  );

  Widget _recovery() {
    final done = controller.round!.recoveryDonePlayerIds.contains(
      controller.playerId,
    );
    return ListView(
      key: const Key('network-recovery'),
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Entre les rounds',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        if (done)
          _waitingCard('Recovery enregistré — attente du partenaire.')
        else if (controller.recoveryAvailable) ...[
          const Text('PA faibles — Recovery disponible'),
          for (final card in controller.recoveryCards.take(4))
            ListTile(
              title: Text(card.title),
              subtitle: Text(
                'Gain si acceptée : ${(card.personalValue * 1.5).ceil()} PA',
              ),
              trailing: FilledButton.tonal(
                key: Key('recover-with-${card.identity}'),
                onPressed: () => controller.recoverWith(card.identity),
                child: const Text('Recovery'),
              ),
            ),
          OutlinedButton(
            key: const Key('skip-network-recovery'),
            onPressed: controller.skipRecovery,
            child: const Text('Passer'),
          ),
        ] else
          FilledButton(
            key: const Key('continue-without-recovery'),
            onPressed: controller.skipRecovery,
            child: const Text('Continuer'),
          ),
      ],
    );
  }

  Widget _recoveryResponse() {
    final proposal = controller.pendingRecovery!;
    return ListView(
      key: const Key('network-recovery-response'),
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Proposition Recovery',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        Text('Carte : ${_title(proposal.cardId)}'),
        if (proposal.playerId == controller.playerId)
          _waitingCard('En attente du consentement du partenaire…')
        else ...[
          FilledButton(
            key: const Key('accept-network-recovery'),
            onPressed: () =>
                controller.respondToRecovery(RecoveryResponse.ACCEPT),
            child: const Text('Accepter'),
          ),
          OutlinedButton(
            key: const Key('refuse-network-recovery'),
            onPressed: () =>
                controller.respondToRecovery(RecoveryResponse.REFUSE),
            child: const Text('Refuser'),
          ),
        ],
      ],
    );
  }

  Widget _recoveryExecution() {
    final proposal = controller.pendingRecovery!;
    return ListView(
      key: const Key('network-recovery-execution'),
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Recovery accepté'),
        if (proposal.playerId != controller.playerId)
          _waitingCard('Le partenaire exécute l’action Recovery…')
        else ...[
          FilledButton(
            key: const Key('complete-network-recovery'),
            onPressed: () => controller.completeRecovery(completed: true),
            child: const Text('Action exécutée'),
          ),
          OutlinedButton(
            key: const Key('skip-network-recovery-action'),
            onPressed: () => controller.completeRecovery(completed: false),
            child: const Text('Action non exécutée'),
          ),
        ],
      ],
    );
  }

  Widget _waitingNext() => _centerMessage(
    'Prêt pour le prochain tour — En attente de ton partenaire…',
    key: const Key('waiting-next-round'),
  );

  Widget _initialResult(NetworkInitialResolutionDto initial) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text(
            initial.tied
                ? 'Égalité'
                : initial.winnerPlayerId == controller.playerId
                ? 'Tu remportes le duel initial'
                : 'Ton partenaire remporte le duel initial',
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          Text('Écart : ${initial.gap} · Coût PA : ${initial.gapCost}'),
        ],
      ),
    ),
  );

  Widget _waitingCard(String message) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Text(message, textAlign: TextAlign.center),
    ),
  );

  Widget _centerMessage(String message, {required Key key}) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          Text(
            message,
            key: key,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ],
      ),
    ),
  );

  Widget _error() => _centerMessage(
    'Impossible de poursuivre la partie.\n${controller.errorMessage ?? ''}',
    key: const Key('network-game-error'),
  );

  Widget _errorText(String message) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Text(
      message,
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    ),
  );

  Widget _deckAdjustmentMessage() => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Répartition ajustée',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          for (final shortage in controller.deckShortages)
            Text(
              '• ${shortage.missingCount} carte${shortage.missingCount > 1 ? 's' : ''} '
              '${List.filled(shortage.requestedSpice, '🌶️').join()} manquante${shortage.missingCount > 1 ? 's' : ''}',
            ),
          const SizedBox(height: 6),
          const Text(
            'Des cartes d’intensité proche ont été utilisées afin de préserver la variété du deck.',
          ),
        ],
      ),
    ),
  );

  Future<void> _openProfileSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              MediaQuery.viewInsetsOf(context).bottom + 16,
            ),
            child: FutureBuilder<AdaptiveProfileState>(
              future: controller.profileState(),
              builder: (context, snapshot) {
                final entries = snapshot.data?.entries.values.toList() ?? [];
                return ListView(
                  shrinkWrap: true,
                  children: [
                    Text(
                      'Profil privé',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const Text(
                      'Ce réglage et tes valeurs restent uniquement sur cet appareil.',
                    ),
                    for (final choice in PostGameProfileChoice.values)
                      ListTile(
                        selected: controller.postGameProfileChoice == choice,
                        title: Text(_profileChoiceLabel(choice)),
                        trailing: controller.postGameProfileChoice == choice
                            ? const Icon(Icons.check_circle)
                            : null,
                        onTap: () async {
                          await controller.choosePostGameProfile(choice);
                          setSheetState(() {});
                        },
                      ),
                    if (controller.postGameProfileChoice ==
                        PostGameProfileChoice.customize) ...[
                      const Divider(),
                      const Text('Préférences rencontrées'),
                      if (entries.isEmpty)
                        const Text(
                          'Les préférences apparaîtront ici après les premières observations.',
                        ),
                      for (final entry in entries)
                        ListTile(
                          title: Text(entry.key.preferenceId),
                          subtitle: Text(entry.key.role.name),
                          trailing: DropdownButton<DetailedPreferenceCategory>(
                            value: entry.currentCategory,
                            onChanged: (category) async {
                              if (category == null) return;
                              await controller.customizePreference(
                                entry.key,
                                category,
                              );
                              setSheetState(() {});
                            },
                            items: [
                              for (final category
                                  in DetailedPreferenceCategory.values)
                                DropdownMenuItem(
                                  value: category,
                                  child: Text(category.label),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  static String _profileChoiceLabel(PostGameProfileChoice choice) =>
      switch (choice) {
        PostGameProfileChoice.customize => 'Personnaliser mon profil',
        PostGameProfileChoice.trustGame => 'Faire confiance au jeu',
        PostGameProfileChoice.later => 'Ne rien faire pour l’instant',
      };

  Future<void> _submitCounter() async {
    final amount = int.tryParse(auctionForm.counterAmount.text);
    if (amount == null) {
      setState(() => actionError = 'Montant invalide.');
      return;
    }
    try {
      await controller.submitCounterBid(amount, auctionForm.counterTarget);
      if (mounted) setState(() => actionError = null);
    } catch (error) {
      if (mounted) setState(() => actionError = error.toString());
    }
  }

  Future<void> _submitNegotiation({required bool adaptation}) async {
    final amount = auctionForm.counterAmount.text.trim().isEmpty
        ? 0
        : int.tryParse(auctionForm.counterAmount.text);
    if (amount == null) {
      setState(() => actionError = 'Montant invalide.');
      return;
    }
    try {
      if (adaptation) {
        final response = controller.negotiation!.response!;
        await controller.adaptNegotiation(
          inversion: response.acceptInversion && _requestInversion,
          directPa: response.acceptAuction ? amount : 0,
          cardIds: response.acceptAuction ? _negotiationCards : const {},
        );
      } else {
        await controller.proposeNegotiation(
          inversion: _requestInversion,
          directPa: amount,
          cardIds: _negotiationCards,
        );
      }
      if (mounted) setState(() => actionError = null);
    } catch (error) {
      if (mounted) setState(() => actionError = error.toString());
    }
  }

  Future<void> _submitDefense() async {
    final amount = int.tryParse(auctionForm.defenseAmount.text);
    if (amount == null) {
      setState(() => actionError = 'Montant invalide.');
      return;
    }
    try {
      await controller.submitFinalDefense(amount);
      if (mounted) setState(() => actionError = null);
    } catch (error) {
      if (mounted) setState(() => actionError = error.toString());
    }
  }

  String _title(String cardId) {
    final card = widget.catalog.cards.firstWhere(
      (item) => item.stableId == cardId,
    );
    return card.title ?? card.titleKey ?? cardId;
  }

  String _chilies(int level) => List.filled(level, '🌶️').join();
}
