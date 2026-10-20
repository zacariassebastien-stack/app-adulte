import '../../card_themes/card_theme_models.dart';
import 'package:flutter/material.dart';

import '../../card_themes/card_renderer.dart';
import '../../domain/catalog/catalog.dart';
import '../../domain/catalog/concept_catalog.dart';
import '../../domain/catalog/concept_editorial.dart';
import '../../domain/catalog/enums.dart';
import '../../domain/game/game_models.dart';
import '../../domain/profile/adaptive_profile.dart';
import '../../domain/profile/v4_profile.dart';
import '../../domain/catalog/v4_catalog.dart';
import '../../engines/corruption/corruption_engine.dart';
import '../../engines/deck/deck_cycle_state.dart';
import '../../engines/recovery/recovery_engine.dart';
import '../../engines/runtime/v4_runtime_engine.dart';
import '../../sync/rounds/network_game.dart';
import '../lobby/lobby_models.dart';
import '../lobby/active_session_store.dart';
import '../lobby/game_history.dart';
import '../profile/v4_accessory_profile_screen.dart';
import 'game_preferences.dart';
import 'network_duel_secret_store.dart';
import 'network_duel_controller.dart' show NetworkDuelCard;
import 'network_auction_form_controller.dart';
import 'network_game_controller.dart';
import 'network_profile_learning.dart';
import '../../engines/eligibility/concept_action_options.dart';
import 'ui/card_hand_surface.dart';
import 'ui/discard_gallery_screen.dart';
import 'ui/gameplay_hud.dart';
import 'ui/game_settings_panel.dart';

class NetworkDuelScreen extends StatefulWidget {
  const NetworkDuelScreen({
    required this.session,
    required this.playerId,
    required this.repository,
    required this.catalog,
    this.secretStore = const SharedPreferencesNetworkDuelSecretStore(),
    this.activeSessionStore = const SharedPreferencesActiveSessionStore(),
    this.historyStore = const SharedPreferencesGameHistoryStore(),
    this.preferences,
    this.privateProfile,
    this.v4Profile,
    this.scoringCatalog,
    this.sessionMode = V4SessionMode.presentiel,
    this.initialClothingCounts = const {},
    this.profileAccessories = const [],
    this.profileStore = const SharedPreferencesV4ProfileStore(),
    super.key,
  });

  final LobbySession session;
  final String playerId;
  final NetworkGameRepository repository;
  final Catalog catalog;
  final NetworkDuelSecretStore secretStore;
  final ActiveSessionStore activeSessionStore;
  final GameHistoryStore historyStore;
  final GamePreferencesController? preferences;
  final PlayerGameProfile? privateProfile;
  final V4Profile? v4Profile;
  final V4ScoringCatalog? scoringCatalog;
  final V4SessionMode sessionMode;
  final Map<String, int> initialClothingCounts;
  final List<V4Accessory> profileAccessories;
  final V4ProfileStore profileStore;

  @override
  State<NetworkDuelScreen> createState() => _NetworkDuelScreenState();
}

enum NetworkDuelExit { finished, newGame }

enum _PostDuelChoice { compromise, corruption }

class _NetworkDuelScreenState extends State<NetworkDuelScreen> {
  late final NetworkGameController controller;
  final auctionForm = NetworkAuctionFormController();
  final Set<String> _negotiationCards = {};
  final Set<String> _corruptionCards = {};
  _PostDuelChoice? _postDuelChoice;
  bool _requestInversion = false;
  String? actionError;
  CardHandStage _handStage = CardHandStage.resting;
  final Map<String, String> _displayedActions = {};
  late final GamePreferencesController preferences;
  late final bool _ownsPreferences;
  bool _historyRecorded = false;
  bool _leavingForNewGame = false;
  int? _pendingClothingCount;

  @override
  void initState() {
    super.initState();
    _ownsPreferences = widget.preferences == null;
    preferences = widget.preferences ?? GamePreferencesController();
    preferences.addListener(_refresh);
    preferences.load();
    controller = NetworkGameController(
      session: widget.session,
      playerId: widget.playerId,
      repository: widget.repository,
      privateStore: widget.secretStore,
      catalog: widget.catalog,
      privateProfile: widget.privateProfile,
      v4Profile: widget.v4Profile,
      scoringCatalog: widget.scoringCatalog,
      sessionMode: widget.sessionMode,
      initialClothingCounts: widget.initialClothingCounts,
      profileAccessories: widget.profileAccessories,
    )..addListener(_refresh);
    controller.start();
  }

  void _refresh() {
    if (!mounted) return;
    final changedRound = auctionForm.enterRound(controller.roundNumber);
    setState(() {
      if ((_postDuelChoice == _PostDuelChoice.compromise &&
              !controller.canAttemptNegotiation) ||
          (_postDuelChoice == _PostDuelChoice.corruption &&
              !controller.canAttemptCorruption)) {
        _postDuelChoice = null;
      }
      if (changedRound) {
        _displayedActions.clear();
        actionError = null;
        _negotiationCards.clear();
        _corruptionCards.clear();
        _postDuelChoice = null;
        _requestInversion = false;
        _pendingClothingCount = null;
      }
    });
  }

  @override
  void dispose() {
    controller
      ..removeListener(_refresh)
      ..dispose();
    preferences.removeListener(_refresh);
    if (_ownsPreferences) preferences.dispose();
    auctionForm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final calm = controller.viewState == NetworkGameViewState.choosing;
    return Scaffold(
      body: SafeArea(
        child: GameplayHud(
          actionPoints: controller.actionPoints[controller.playerId] ?? 0,
          status: _status,
          roundNumber: controller.roundNumber,
          spice: controller.activeSpice,
          orientation: controller.orientation,
          stage:
              controller.viewState == NetworkGameViewState.waitingForPartner ||
                  controller.viewState == NetworkGameViewState.revealing
              ? CardHandStage.committed
              : _handStage,
          onSettings: _openSettings,
          animationsEnabled: preferences.value.animations,
          onOrientationChanged:
              controller.viewState == NetworkGameViewState.waitingNext
              ? controller.switchOrientation
              : null,
          discardVisible: calm && _handStage != CardHandStage.open,
          onDiscard: _openDiscard,
          child: Padding(
            padding: const EdgeInsets.only(top: 58),
            child: _body(),
          ),
        ),
      ),
    );
  }

  String get _status => switch (controller.viewState) {
    NetworkGameViewState.choosing => 'À toi de jouer',
    NetworkGameViewState.committing ||
    NetworkGameViewState.waitingForPartner ||
    NetworkGameViewState.revealing => 'En attente de ton partenaire',
    NetworkGameViewState.negotiationProposal ||
    NetworkGameViewState.negotiationResponse ||
    NetworkGameViewState.negotiationAdaptation ||
    NetworkGameViewState.negotiationValidation => 'Compromis à valider',
    NetworkGameViewState.recovery ||
    NetworkGameViewState.recoveryResponse ||
    NetworkGameViewState.recoveryExecution => 'Récupération',
    NetworkGameViewState.loading => 'Connexion à la partie',
    NetworkGameViewState.error => 'Partie interrompue',
    NetworkGameViewState.sessionEnded => 'Partie terminée',
    _ => 'Résolution du tour',
  };

  Widget _body() {
    final body = _phaseBody();
    final card = controller.personalDuelCard;
    final decision = const {
      NetworkGameViewState.corruptionDecision,
      NetworkGameViewState.corruptionResponse,
      NetworkGameViewState.negotiationProposal,
      NetworkGameViewState.negotiationResponse,
      NetworkGameViewState.negotiationAdaptation,
      NetworkGameViewState.negotiationValidation,
    }.contains(controller.viewState);
    if (!decision || card == null) return body;
    return LayoutBuilder(
      builder: (context, bounds) => Column(
        children: [
          Expanded(child: body),
          SizedBox(
            height: bounds.maxHeight / 3,
            child: IgnorePointer(
              child: CardRenderer(
                key: const Key('personal-duel-card'),
                definition: _handItem(card).definition,
                state: CardVisualState.full,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _phaseBody() => switch (controller.viewState) {
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
    NetworkGameViewState.tieDecision => _tieDecision(),
    NetworkGameViewState.actionInProgress => _actionInProgress(),
    NetworkGameViewState.corruptionDecision => _corruptionDecision(),
    NetworkGameViewState.corruptionResponse => _corruptionResponse(),
    NetworkGameViewState.corruptionExecution => _actionInProgress(),
    NetworkGameViewState.recovery => _recovery(),
    NetworkGameViewState.recoveryResponse => _recoveryResponse(),
    NetworkGameViewState.recoveryExecution => _recoveryExecution(),
    NetworkGameViewState.waitingNext => _waitingNext(),
    NetworkGameViewState.sessionEnded => _sessionEnded(),
    NetworkGameViewState.error => _error(),
  };

  Widget _choosing() => CardHandSurface(
    key: const Key('network-game-hand'),
    cards: _conceptHandItems(),
    onStageChanged: (stage) {
      if (mounted) setState(() => _handStage = stage);
    },
    onLockChanged: (item) => controller.toggleLock(item.id),
    onTabChanged: (item, actionId) =>
        setState(() => _displayedActions[item.id] = actionId),
    animationsEnabled: preferences.value.animations,
    onPlay: (item) async {
      if (controller.viewState != NetworkGameViewState.choosing) return;
      controller.selectCard(item.id);
      await controller.reserveSelection();
      final concept = controller.conceptFor(item.id);
      final selectedIsFree = concept.variants.any(
        (v) => v.id == item.definition.variantId && v.freeZone,
      );
      final choices = controller
          .choicesFor(item.id)
          .where(
            (o) =>
                (concept.kind != ConceptKind.zones &&
                    concept.stages.isEmpty &&
                    !selectedIsFree) ||
                o.choice.actionId == item.definition.variantId,
          )
          .toList();
      if (!mounted) return;
      ConceptActionOption? choice;
      if (choices.length == 1) {
        choice = choices.single;
      } else {
        choice = await showDialog<ConceptActionOption>(
          context: context,
          builder: (dialogContext) => SimpleDialog(
            title: const Text('Choisir l’action'),
            children: [
              for (final option in choices)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(dialogContext, option),
                  child: Text('${option.title} · 🌶️${option.choice.chili}'),
                ),
            ],
          ),
        );
      }
      if (choice == null) {
        await controller.cancelPendingSelection();
        return;
      }
      try {
        controller.chooseAction(choice);
        await controller.confirmSelection();
      } catch (error) {
        await controller.cancelPendingSelection();
        if (mounted) {
          setState(() => actionError = 'Ce choix n’est plus disponible.');
        }
      }
    },
  );

  List<CardHandItem> _conceptHandItems() {
    final available = {for (final card in controller.hand) card.id: card};
    return [
      for (final concept in controller.heldConcepts)
        if (available[concept.id] case final card?)
          _conceptHandItem(concept.id, card)
        else
          CardHandItem(
            id: concept.id,
            available: false,
            locked: controller.lockedCardId == concept.id,
            tabs: [
              for (var i = 0; i < concept.stages.length; i++)
                CardHandTab(
                  id: concept.stages[i].id,
                  label: '${i + 1}',
                  enabled: false,
                  consumed: controller.stageConsumed(
                    concept.id,
                    concept.stages[i].id,
                  ),
                ),
            ],
            definition: CardRenderDefinition(
              cardId: concept.id,
              title: concept.title,
              action: 'Indisponible dans le contexte actuel.',
              spice:
                  concept.intrinsicChili ??
                  [
                    ...concept.stages.map((s) => s.chili),
                    ...concept.variants.map((v) => v.chili).nonNulls,
                  ].reduce((a, b) => a < b ? a : b),
            ),
          ),
    ];
  }

  CardHandItem _conceptHandItem(String id, NetworkDuelCard fallback) {
    final concept = controller.conceptFor(id);
    final options = controller.choicesFor(id);
    final option =
        options
            .where((o) => o.choice.actionId == _displayedActions[id])
            .firstOrNull ??
        controller.materializedAction(id, options);
    final card = option == null
        ? fallback
        : controller.previewAction(id, option) ?? fallback;
    final item = _handItem(card);
    return CardHandItem(
      id: item.id,
      definition: item.definition,
      available: item.available,
      locked: item.locked,
      tabs: [
        for (var i = 0; i < concept.stages.length; i++)
          CardHandTab(
            id: concept.stages[i].id,
            label: '${i + 1}',
            enabled: options.any(
              (o) => o.choice.actionId == concept.stages[i].id,
            ),
            consumed: controller.stageConsumed(id, concept.stages[i].id),
          ),
      ],
    );
  }

  Widget _waiting() {
    final card = controller.selectedCard;
    if (card == null) {
      return _centerMessage(
        controller.viewState == NetworkGameViewState.revealing
            ? 'Validation sécurisée des choix…'
            : 'En attente de ton partenaire…',
        key: const Key('network-duel-waiting'),
      );
    }
    return CardHandSurface(
      committedCard: _handItem(card),
      cards: const [],
      canCancelCommitted: controller.canCancelSelection,
      animationsEnabled: preferences.value.animations,
      onCancelCommitted: () async {
        final cancelled = await controller.cancelSelection();
        if (!cancelled && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('La révélation a déjà commencé.')),
          );
        }
      },
      onStageChanged: (stage) {
        if (mounted) setState(() => _handStage = stage);
      },
    );
  }

  CardHandItem _handItem(NetworkDuelCard card) {
    final editorialVariant = card.definition.variants
        .where((variant) => variant.stableId == card.variant.id)
        .firstOrNull;
    final concept = widget.catalog.concepts!.concepts
        .where((c) => c.id == card.id)
        .firstOrNull;
    final free =
        card.id == '024' ||
        (concept?.variants.any((v) => v.id == card.variant.id && v.freeZone) ??
            false);
    final option = controller
        .choicesFor(card.id)
        .where((o) => o.choice.actionId == card.variant.id)
        .firstOrNull;
    final editorialRenderer = ConceptEditorialRenderer(
      widget.catalog.concepts!,
    );
    final editorial = concept == null ||
            option == null ||
            !editorialRenderer.appliesTo(
              concept: concept,
              actionId: option.choice.actionId,
            )
        ? null
        : editorialRenderer.render(
            concept: concept,
            actionId: option.choice.actionId,
            direction: card.effectiveDirection,
          );
    return CardHandItem(
      id: card.identity,
      locked: controller.lockedCardId == card.identity,
      available: controller.isCardPlayable(card),
      definition: CardRenderDefinition(
        cardId: card.id,
        variantId: card.variant.id,
        title: card.title,
        action: card.identity != card.id
            ? editorialVariant?.actionText ?? card.definition.actionText
            : editorial?.actionText ??
                  (free && option != null
                      ? option.title
                      : '${editorialVariant?.actionText ?? card.definition.actionText ?? card.definition.descriptionKey}${editorialVariant?.title == null ? '' : ' · ${editorialVariant!.title}'}'),
        zones: [
          if (controller.zoneForCard(card) case final zone?)
            widget.catalog.concepts!.zones
                    .where((z) => z.id == zone)
                    .firstOrNull
                    ?.title ??
                'Zone indiquée'
          else if (free)
            'LIBRE',
        ],
        details: card.identity != card.id
            ? editorialVariant?.detailsText ?? card.definition.detailsText
            : editorial?.detailsText ??
                  editorialVariant?.detailsText ??
                  card.definition.detailsText,
        direction: card.effectiveDirection.name,
        spice: card.chiliLevel,
        personalPa: card.personalValue,
        oppositePa: card.oppositePersonalValue,
        oppositeDirection: switch (card.oppositeRole) {
          ProfileRole.FAIRE => 'Faire',
          ProfileRole.RECEVOIR => 'Recevoir',
          _ => null,
        },
        illustrationId: card.definition.illustrationKey,
      ),
    );
  }

  void _openDiscard() {
    final now = DateTime.now();
    final cards = controller.visibleDiscardUsages;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DiscardGalleryScreen(
          cards: [
            for (var index = 0; index < cards.length; index++)
              DiscardGalleryItem(
                id: cards[index].usageId,
                definition: CardRenderDefinition(
                  cardId: cards[index].conceptId,
                  title: controller.titleFor(cards[index].conceptId),
                  action: cards[index].resolvedAction['action_text']! as String,
                  spice: cards[index].resolvedAction['effective_chili']! as int,
                  direction:
                      cards[index].resolvedAction['direction']! as String,
                  personalPa: cards[index].snapshotValue,
                ),
                playedAt: now.subtract(Duration(seconds: index)),
              ),
          ],
        ),
      ),
    );
  }

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
    bool? canEdit,
    bool requireNonEmpty = false,
    Widget? leading,
  }) => ListView(
    key: Key(title),
    padding: const EdgeInsets.all(16),
    children: [
      _initialResult(controller.initialResolution!),
      const SizedBox(height: 12),
      ?leading,
      if (!(canEdit ?? controller.isInitialLoser))
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
            controller: auctionForm.directPaAmount,
            onChanged: (_) => setState(() {}),
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
              onChanged: controller.isAuctionCardPlayable(card)
                  ? (selected) => setState(() {
                      if (selected == true) {
                        _negotiationCards.add(card.identity);
                      } else {
                        _negotiationCards.remove(card.identity);
                      }
                    })
                  : null,
              title: Text(card.title),
              subtitle: Text(
                controller.isAuctionCardPlayable(card)
                    ? '${card.role.name} · ${_chilies(card.chiliLevel)}'
                    : 'Indisponible au niveau 🌶️ actuel',
              ),
            ),
        ],
        FilledButton(
          key: const Key('submit-negotiation'),
          onPressed: requireNonEmpty && !_hasNegotiationProposal
              ? null
              : onSubmit,
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
        if (!controller.isNegotiationResponder)
          _waitingCard('Ton partenaire répond à ta proposition…')
        else ...[
          Text(
            'Proposition de compromis',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          NetworkNegotiationOfferSummary(offer: proposal, titleForCard: _title),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('accept-negotiation'),
            onPressed: () => controller.respondNegotiation(accepted: true),
            child: const Text('Accepter le compromis'),
          ),
          OutlinedButton(
            key: const Key('keep-initial-result'),
            onPressed: () => controller.respondNegotiation(accepted: false),
            child: const Text('Conserver le résultat initial'),
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
          for (final card in offer.cards)
            Text(
              '${card.usage.resolvedAction['action_text']} · 🌶️${card.usage.resolvedAction['effective_chili']}',
            ),
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

  Widget _actionInProgress() {
    final result = controller.finalResolution!;
    final projection = controller.actionProjection;
    final cards = projection?.cards.isNotEmpty == true
        ? projection!.cards
        : [
            for (final card in result.compromise)
              NetworkResolvedActionCardDto.fromUsage(card.usage),
          ];
    final title = result.mutualAbandon
        ? 'Round abandonné mutuellement'
        : result.retainedPlayerId == controller.playerId
        ? 'Ton action est retenue'
        : 'Action du partenaire retenue';
    return ListView(
      key: const Key('network-action-in-progress'),
      padding: const EdgeInsets.all(16),
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        if (!result.mutualAbandon) ...[
          const SizedBox(height: 12),
          if (cards.isNotEmpty) ...[
            _ResolutionCards(
              key: ValueKey(
                'resolution:${controller.round!.roundId}:${cards.map((card) => card.usageId).join(',')}',
              ),
              cards: [for (final card in cards) _resolvedActionCard(card)],
            ),
          ] else if (result.cardId != null) ...[
            Text('Carte : ${_title(result.cardId!)}'),
            Text('Variante : ${result.variantId}'),
            if (result.inverted) const Text('Rôles physiques inversés'),
          ],
        ],
        if (controller.persistentEffects.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Effets actifs', style: Theme.of(context).textTheme.titleMedium),
          for (final effect in controller.persistentEffects)
            Text(
              '${_title(effect.cardId)} · ${effect.remainingActions} action(s) restante(s)',
            ),
        ],
        if (controller.ownClothingResyncRequired &&
            controller.ownClothingChangeIsDeterministic) ...[
          const SizedBox(height: 12),
          OutlinedButton(
            key: const Key('adjust-deterministic-clothing-count'),
            onPressed: _adjustClothingCount,
            child: Text(
              'Ajuster les vêtements (${_pendingClothingCount ?? controller.suggestedOwnClothingCount()})',
            ),
          ),
        ],
        const SizedBox(height: 20),
        FilledButton(
          key: const Key('complete-network-action'),
          onPressed: controller.actionCompletionSubmitted
              ? null
              : _completeAction,
          child: Text(
            controller.actionCompletionSubmitted &&
                    controller.waitingForClothingResync
                ? 'En attente de ton partenaire…'
                : 'Terminé',
          ),
        ),
      ],
    );
  }

  Future<void> _completeAction() async {
    if (controller.ownClothingResyncRequired) {
      final count = controller.ownClothingChangeIsDeterministic
          ? _pendingClothingCount ?? controller.suggestedOwnClothingCount()
          : await _requestClothingCount(controller.suggestedOwnClothingCount());
      if (count == null) return;
      await controller.updateOwnClothingCount(count);
    }
    await controller.completeAction();
  }

  Future<void> _adjustClothingCount() async {
    final count = await _requestClothingCount(
      _pendingClothingCount ?? controller.suggestedOwnClothingCount(),
    );
    if (count != null && mounted) setState(() => _pendingClothingCount = count);
  }

  Future<int?> _requestClothingCount(int initialCount) => showDialog<int>(
    context: context,
    builder: (context) => _ClothingCountDialog(initialCount: initialCount),
  );

  Widget _resolvedActionCard(NetworkResolvedActionCardDto card) {
    final action = card.usage.resolvedAction;
    final parameters = action['parameters']! as Map;
    final concept = widget.catalog.concepts?.concepts
        .where((c) => c.id == card.cardId)
        .firstOrNull;
    final variant = concept?.variants
        .where((v) => v.id == card.variantId)
        .firstOrNull;
    final source = widget.catalog.cards
        .where(
          (c) =>
              c.stableId == card.cardId ||
              c.stableId == 'card.v4.${card.cardId}',
        )
        .firstOrNull;
    final zone = widget.catalog.concepts?.zones
        .where((z) => z.id == card.zoneId)
        .firstOrNull;
    final definition = CardRenderDefinition(
      cardId: card.cardId,
      variantId: card.variantId,
      title: parameters['display_title'] as String? ?? _title(card.cardId),
      subtitle:
          concept?.stages
              .where((s) => s.id == card.variantId)
              .firstOrNull
              ?.title ??
          variant?.title,
      action: action['action_text']! as String,
      direction: card.direction.name,
      spice: card.effectiveSpice,
      zones: [
        if (card.zoneId != null)
          zone?.title ?? card.zoneId!
        else if (variant?.freeZone == true || card.cardId == '024')
          'LIBRE',
      ],
      details: parameters.containsKey('display_details')
          ? parameters['display_details'] as String?
          : concept?.detailsText,
      illustrationId: parameters.containsKey('display_illustration')
          ? parameters['display_illustration'] as String?
          : source?.illustrationKey,
    );
    return Column(
      key: Key('resolved-action-${card.usageId}'),
      children: [
        SizedBox(
          height: 440,
          child: CardRenderer(
            definition: definition,
            state: CardVisualState.full,
            showPa: false,
          ),
        ),
        if (card.direction == NetworkCardDirection.RECEVOIR)
          Text(
            card.cardId == '032'
                ? card.targetPlayerIds.contains(controller.playerId)
                      ? "Ton partenaire choisit l’ordre que tu devras suivre."
                      : "Choisis l’ordre que ton partenaire devra suivre."
                : card.targetPlayerIds.contains(controller.playerId)
                ? 'Ton partenaire réalise cette action pour toi.'
                : 'Tu réalises cette action pour ton partenaire.',
          ),
        Text(
          [
            'Pour : ${card.targetPlayerIds.map((id) => id == controller.playerId ? 'toi' : 'ton partenaire').join(', ')}',
            for (final accessory in action['accessories']! as List)
              'accessoire : ${(accessory as Map)['label']}',
          ].join(' · '),
        ),
      ],
    );
  }

  Widget _waitingNext() => Center(
    key: const Key('network-round-boundary'),
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Action terminée'),
          const SizedBox(height: 12),
          if (controller.deckExhausted)
            ..._cycleEndControls()
          else if (controller.mustSwitchHybridContext)
            const Text(
              'Change le contexte hybride pour continuer : aucune carte '
              'n’est jouable dans le contexte actuel.',
              textAlign: TextAlign.center,
            )
          else
            const Text('Préparation du prochain tour…'),
        ],
      ),
    ),
  );

  List<Widget> _cycleEndControls() => [
    Text(
      'Cycle de cartes terminé',
      style: Theme.of(context).textTheme.titleMedium,
    ),
    if (controller.postGameProfileChoice == null) ...[
      const Text('Souhaitez-vous ajuster vos préférences après cette partie ?'),
      TextButton(
        onPressed: _openProfileCustomization,
        child: const Text('Personnaliser mon profil'),
      ),
      TextButton(
        onPressed: () =>
            controller.choosePostGameProfile(PostGameProfileChoice.trustGame),
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
        key: const Key('continue-same-style'),
        onPressed: () =>
            controller.continueDeck(DeckExhaustionChoice.keepStyle),
        child: const Text('Continuer avec le même style'),
      ),
      if (controller.round?.cycleStyleVotes.values.contains(false) == true)
        const Text('L’augmentation a été refusée. Le style est inchangé.'),
      if (controller.round?.cycleStyleProposal != null) ...[
        Text('Style proposé : ${controller.round!.cycleStyleProposal!.name}'),
        if (controller.round!.cycleStyleProposer == controller.playerId)
          const Text('En attente de l’accord de ton partenaire…')
        else ...[
          FilledButton(
            key: const Key('accept-cycle-style'),
            onPressed: () =>
                controller.continueDeck(DeckExhaustionChoice.continueSpicier),
            child: const Text('Accepter ce style et continuer'),
          ),
          OutlinedButton(
            key: const Key('refuse-cycle-style'),
            onPressed: () =>
                controller.continueDeck(DeckExhaustionChoice.refuseStyle),
            child: const Text('Refuser l’augmentation'),
          ),
        ],
      ] else if (controller.deckStyle != PlayerStyle.INTENABLE)
        OutlinedButton(
          key: const Key('continue-spicier'),
          onPressed: () =>
              controller.continueDeck(DeckExhaustionChoice.continueSpicier),
          child: Text(
            controller.deckStyle == PlayerStyle.SOFT
                ? 'Proposer Épicé'
                : 'Proposer Intenable',
          ),
        ),
      OutlinedButton(
        key: const Key('enable-infinite'),
        onPressed: () => controller.continueDeck(DeckExhaustionChoice.infinite),
        child: const Text('Mode Infini'),
      ),
      OutlinedButton(
        key: const Key('new-customized-game'),
        onPressed: _startNewGame,
        child: const Text('Nouvelle partie'),
      ),
      TextButton(
        key: const Key('finish-game'),
        onPressed: () => controller.continueDeck(DeckExhaustionChoice.finish),
        child: const Text('Terminer'),
      ),
    ] else
      _waitingCard('Ton partenaire choisit la suite de la partie…'),
  ];

  bool get _hasNegotiationProposal {
    final directPa = int.tryParse(auctionForm.directPaAmount.text.trim()) ?? 0;
    return directPa > 0 || _requestInversion || _negotiationCards.isNotEmpty;
  }

  Widget _corruptionDecision() {
    if (!controller.isCorruptionActor) {
      return ListView(
        key: const Key('network-post-duel-waiting'),
        padding: const EdgeInsets.all(16),
        children: [
          _waitingCard(
            'Tu as gagné le duel.\nEn attente de la réponse de ton partenaire…',
          ),
        ],
      );
    }
    if (_postDuelChoice == _PostDuelChoice.compromise) {
      return _negotiationEditor(
        title: 'Tenter un compromis',
        waiting: 'Ton partenaire prépare une proposition…',
        buttonLabel: 'Envoyer la proposition',
        onSubmit: () => _submitNegotiation(adaptation: false),
        canEdit: controller.isFinalLoser,
        requireNonEmpty: true,
        leading: Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const Key('back-to-post-duel-choice'),
            onPressed: () => setState(() => _postDuelChoice = null),
            icon: const Icon(Icons.arrow_back),
            label: const Text('Retour'),
          ),
        ),
      );
    }
    if (_postDuelChoice == null) {
      return ListView(
        key: const Key('network-post-duel-choice'),
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Tu as perdu le duel.\nChoisis la suite.',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('choose-negotiation'),
            onPressed: !controller.canAttemptNegotiation
                ? null
                : () => setState(
                    () => _postDuelChoice = _PostDuelChoice.compromise,
                  ),
            child: const Text('Tenter un compromis'),
          ),
          FilledButton.tonal(
            key: const Key('choose-corruption'),
            onPressed: !controller.canAttemptCorruption
                ? null
                : () => setState(
                    () => _postDuelChoice = _PostDuelChoice.corruption,
                  ),
            child: const Text('Proposer une corruption'),
          ),
          OutlinedButton(
            key: const Key('accept-final-result'),
            onPressed: controller.skipCorruption,
            child: const Text('Accepter le résultat'),
          ),
        ],
      );
    }
    return ListView(
      key: const Key('network-corruption-decision'),
      padding: const EdgeInsets.all(16),
      children: [
        Text('Corruption', style: Theme.of(context).textTheme.headlineSmall),
        const Text('Seules les cartes proposées sont rendues publiques.'),
        const SizedBox(height: 16),
        ...[
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('back-to-post-duel-choice'),
              onPressed: () => setState(() => _postDuelChoice = null),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Retour'),
            ),
          ),
          for (final card in controller.corruptionCards)
            CheckboxListTile(
              key: Key('corruption-card-${card.identity}'),
              title: Text(card.title),
              subtitle: Text(
                controller.isCorruptionCardPlayable(card)
                    ? 'Carte de la défausse · 🌶️ ${card.chiliLevel}'
                    : 'Indisponible au niveau 🌶️ actuel',
              ),
              value: _corruptionCards.contains(card.identity),
              onChanged: controller.isCorruptionCardPlayable(card)
                  ? (selected) => setState(() {
                      if (selected ?? false) {
                        _corruptionCards.add(card.identity);
                      } else {
                        _corruptionCards.remove(card.identity);
                      }
                    })
                  : null,
            ),
          FilledButton(
            key: const Key('propose-network-corruption'),
            onPressed: _corruptionCards.isEmpty
                ? null
                : () async {
                    await controller.proposeCorruption(
                      Set<String>.from(_corruptionCards),
                      CorruptionObjective.OWN_INITIAL_ACTION,
                    );
                    if (mounted) setState(_corruptionCards.clear);
                  },
            child: Text('Proposer le lot (${_corruptionCards.length})'),
          ),
          OutlinedButton(
            key: const Key('skip-network-corruption'),
            onPressed: controller.skipCorruption,
            child: const Text('Continuer sans corruption'),
          ),
        ],
      ],
    );
  }

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
          Text(
            '${action.usage.resolvedAction['action_text']} · 🌶️${action.usage.resolvedAction['effective_chili']}',
          ),
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
                onPressed: () => _proposeRecovery(card),
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
        Text(
          '${proposal.usage.resolvedAction['action_text']} · 🌶️${proposal.usage.resolvedAction['effective_chili']}',
        ),
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

  Widget _error() => Center(
    key: const Key('network-game-error'),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Impossible de poursuivre la partie.\n${controller.errorMessage ?? ''}',
        ),
        TextButton(
          onPressed: controller.retryCurrentAction,
          child: const Text('Réessayer'),
        ),
      ],
    ),
  );

  Widget _errorText(String message) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Text(
      message,
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    ),
  );

  Future<void> _openSettings() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => GameSettingsPanel(
        preferences: preferences,
        privateProfile: _privateProfileSettings(),
        onQuit: _quitGame,
      ),
    );
  }

  Widget _privateProfileSettings() => StatefulBuilder(
    builder: (context, setPanelState) => FutureBuilder<AdaptiveProfileState>(
      future: controller.profileState(),
      builder: (context, snapshot) {
        final entries = snapshot.data?.entries.values.toList() ?? [];
        final pending = entries
            .where(
              (entry) =>
                  entry.lastProposal?.decision == ProposalDecision.pending,
            )
            .toList();
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              key: Key('private-profile-notice'),
              'Ce réglage et tes valeurs restent uniquement sur cet appareil.',
            ),
            if (pending.isNotEmpty) ...[
              const Divider(),
              const Text('Évolutions proposées'),
              for (final entry in pending)
                ListTile(
                  dense: true,
                  title: Text(entry.key.preferenceId),
                  subtitle: Text(
                    '${entry.currentCategory.label} → ${entry.lastProposal!.toCategory.label}',
                  ),
                ),
            ],
            for (final choice in PostGameProfileChoice.values)
              ListTile(
                selected: controller.postGameProfileChoice == choice,
                title: Text(_profileChoiceLabel(choice)),
                trailing: controller.postGameProfileChoice == choice
                    ? const Icon(Icons.check_circle)
                    : null,
                onTap: () async {
                  await controller.choosePostGameProfile(choice);
                  setPanelState(() {});
                },
              ),
            if (controller.postGameProfileChoice ==
                PostGameProfileChoice.customize) ...[
              const Divider(),
              ListTile(
                key: const Key('customize-v4-accessories'),
                leading: const Icon(Icons.extension),
                title: const Text('Gérer mes accessoires'),
                onTap: _openAccessoryProfile,
              ),
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
                      await controller.customizePreference(entry.key, category);
                      setPanelState(() {});
                    },
                    items: [
                      for (final category in DetailedPreferenceCategory.values)
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
  );

  Future<void> _openProfileCustomization() async {
    await controller.choosePostGameProfile(PostGameProfileChoice.customize);
    await _openAccessoryProfile();
  }

  Future<void> _openAccessoryProfile() async {
    final profile =
        await widget.profileStore.load(widget.playerId) ?? widget.v4Profile;
    if (profile == null || !mounted) return;
    final temporary = [
      for (final item in controller.sessionAccessories)
        if (item.temporary && item.ownerPlayerId == widget.playerId)
          V4ProfileAccessory(
            id: item.id,
            name: item.name,
            ownerProfileId: widget.playerId,
            tags: {for (final tag in item.tags) tag.name.toUpperCase()},
          ),
    ];
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => V4AccessoryProfileScreen(
          profile: profile,
          store: widget.profileStore,
          temporaryAccessories: temporary,
        ),
      ),
    );
  }

  Future<void> _quitGame() async {
    try {
      await controller.closeSession();
      await _finishLocally(NetworkDuelExit.finished);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impossible de quitter la partie pour le moment.'),
        ),
      );
    }
  }

  Future<void> _startNewGame() async {
    if (_leavingForNewGame) return;
    _leavingForNewGame = true;
    await controller.continueDeck(DeckExhaustionChoice.newCustomizedGame);
    if (!mounted) return;
    await _finishLocally(NetworkDuelExit.newGame);
  }

  Widget _sessionEnded() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Partie terminée',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 20),
          FilledButton(
            key: const Key('return-home-after-session-end'),
            onPressed: () => _finishLocally(NetworkDuelExit.finished),
            child: const Text('Retour à l’accueil'),
          ),
        ],
      ),
    ),
  );

  Future<void> _finishLocally(NetworkDuelExit exit) async {
    await controller.clearLocalSessionState();
    await widget.activeSessionStore.clear();
    if (!_historyRecorded) {
      _historyRecorded = true;
      await widget.historyStore.add(
        GameHistoryEntry.forRounds(controller.roundNumber),
      );
    }
    if (mounted) {
      final gameRoute = ModalRoute.of(context)!;
      final navigator = Navigator.of(context);
      // Settings/confirmation dialogs may still cover the game. Return the
      // result from this route, not from whichever modal happens to be on top.
      navigator.popUntil((route) => route == gameRoute);
      navigator.pop(exit);
    }
  }

  static String _profileChoiceLabel(PostGameProfileChoice choice) =>
      switch (choice) {
        PostGameProfileChoice.customize => 'Personnaliser mon profil',
        PostGameProfileChoice.trustGame => 'Faire confiance au jeu',
        PostGameProfileChoice.later => 'Ne rien faire pour l’instant',
      };

  Future<ConceptActionOption?> _chooseSecondary(
    String conceptId, {
    bool recovery = false,
  }) async {
    final available = recovery
        ? controller.recoveryChoicesFor(conceptId)
        : controller.choicesFor(conceptId);
    final displayed = controller.materializedAction(conceptId, available);
    final isFree = controller
        .conceptFor(conceptId)
        .variants
        .any((v) => v.id == displayed?.choice.actionId && v.freeZone);
    final choices =
        controller.conceptFor(conceptId).kind == ConceptKind.zones || isFree
        ? available
              .where((o) => o.choice.actionId == displayed!.choice.actionId)
              .toList()
        : available;
    if (choices.isEmpty) return null;
    if (choices.length == 1) return choices.single;
    return showDialog<ConceptActionOption>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Choisir l’action'),
        children: [
          for (final option in choices)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, option),
              child: Text('${option.title} · 🌶️${option.choice.chili}'),
            ),
        ],
      ),
    );
  }

  Future<void> _proposeRecovery(NetworkDuelCard card) async {
    final option = card.identity == card.id
        ? await _chooseSecondary(card.id, recovery: true)
        : null;
    if (!mounted || (card.identity == card.id && option == null)) return;
    await controller.recoverWith(card.identity, option: option);
  }

  Future<void> _submitNegotiation({required bool adaptation}) async {
    final amount = auctionForm.directPaAmount.text.trim().isEmpty
        ? 0
        : int.tryParse(auctionForm.directPaAmount.text);
    if (amount == null) {
      setState(() => actionError = 'Montant invalide.');
      return;
    }
    final actionChoices = <String, ConceptActionOption>{};
    final selectedIds =
        adaptation && !controller.negotiation!.response!.acceptAuction
        ? <String>{}
        : Set<String>.of(_negotiationCards);
    for (final id in selectedIds) {
      if (!controller.heldConcepts.any((c) => c.id == id)) continue;
      final option = await _chooseSecondary(id);
      if (!mounted || option == null) return;
      actionChoices[id] = option;
    }
    try {
      if (adaptation) {
        final response = controller.negotiation!.response!;
        await controller.adaptNegotiation(
          inversion: response.acceptInversion && _requestInversion,
          directPa: response.acceptAuction ? amount : 0,
          cardIds: response.acceptAuction ? _negotiationCards : const {},
          actionChoices: actionChoices,
        );
      } else {
        await controller.proposeNegotiation(
          inversion: _requestInversion,
          directPa: amount,
          cardIds: _negotiationCards,
          actionChoices: actionChoices,
        );
      }
      if (mounted) setState(() => actionError = null);
    } catch (error) {
      if (mounted) setState(() => actionError = error.toString());
    }
  }

  String _title(String cardId) {
    return controller.titleFor(cardId);
  }

  String _chilies(int level) => List.filled(level, '🌶️').join();
}

class NetworkNegotiationOfferSummary extends StatelessWidget {
  const NetworkNegotiationOfferSummary({
    required this.offer,
    required this.titleForCard,
    super.key,
  });

  final NetworkNegotiationOfferDto offer;
  final String Function(String cardId) titleForCard;

  @override
  Widget build(BuildContext context) => Column(
    key: const Key('negotiation-offer-summary'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (offer.inversionRequested)
        const Text('• Inversion de la carte initiale'),
      if (offer.directPa > 0) Text('• ${offer.directPa} PA personnels'),
      if (offer.cards.isNotEmpty) ...[
        const SizedBox(height: 8),
        const Text('Cartes ajoutées'),
        for (final card in offer.cards)
          ListTile(
            key: Key('proposed-card-${card.usageId}'),
            contentPadding: EdgeInsets.zero,
            title: Text(titleForCard(card.cardId)),
            subtitle: Text(
              [
                _directionLabel(card.effectiveDirection),
                if (card.usage.resolvedAction['effective_chili']
                    case final int spice)
                  List.filled(spice, '🌶️').join(),
              ].join(' · '),
            ),
          ),
      ],
    ],
  );

  static String _directionLabel(NetworkCardDirection direction) =>
      switch (direction) {
        NetworkCardDirection.FAIRE => 'Faire',
        NetworkCardDirection.RECEVOIR => 'Recevoir',
        NetworkCardDirection.MUTUEL => 'Mutuel',
        NetworkCardDirection.SOLO => 'Solo',
        NetworkCardDirection.SIMULTANE => 'Simultané',
        NetworkCardDirection.GENERAL => 'Général',
      };
}

class _ClothingCountDialog extends StatefulWidget {
  const _ClothingCountDialog({required this.initialCount});

  final int initialCount;

  @override
  State<_ClothingCountDialog> createState() => _ClothingCountDialogState();
}

class _ClothingCountDialogState extends State<_ClothingCountDialog> {
  late final TextEditingController input;

  @override
  void initState() {
    super.initState();
    input = TextEditingController(text: '${widget.initialCount}');
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Vêtements'),
    content: TextField(
      key: const Key('clothing-resync-count'),
      controller: input,
      autofocus: true,
      keyboardType: TextInputType.number,
      decoration: const InputDecoration(
        labelText: 'Combien de vêtements portes-tu actuellement ?',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      FilledButton(
        onPressed: () {
          final value = int.tryParse(input.text);
          if (value != null && value >= 0) Navigator.pop(context, value);
        },
        child: const Text('Valider'),
      ),
    ],
  );
}

/// Navigation through retained snapshots only; completion remains on the screen.
class _ResolutionCards extends StatefulWidget {
  const _ResolutionCards({required this.cards, super.key});
  final List<Widget> cards;

  @override
  State<_ResolutionCards> createState() => _ResolutionCardsState();
}

class _ResolutionCardsState extends State<_ResolutionCards> {
  int index = 0;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      widget.cards[index],
      if (widget.cards.length > 1)
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              key: const Key('resolution-previous'),
              tooltip: 'Action précédente',
              onPressed: index == 0 ? null : () => setState(() => index--),
              icon: const Icon(Icons.chevron_left),
            ),
            Text(
              '${index + 1}/${widget.cards.length}',
              key: const Key('resolution-page'),
            ),
            IconButton(
              key: const Key('resolution-next'),
              tooltip: 'Action suivante',
              onPressed: index == widget.cards.length - 1
                  ? null
                  : () => setState(() => index++),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
    ],
  );
}
