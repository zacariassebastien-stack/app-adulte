import 'package:flutter/material.dart';

import '../../domain/catalog/catalog.dart';
import '../../sync/rounds/network_round.dart';
import '../lobby/lobby_models.dart';
import 'network_duel_controller.dart';
import 'network_duel_secret_store.dart';

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
  final NetworkRoundRepository repository;
  final Catalog catalog;
  final NetworkDuelSecretStore secretStore;

  @override
  State<NetworkDuelScreen> createState() => _NetworkDuelScreenState();
}

class _NetworkDuelScreenState extends State<NetworkDuelScreen> {
  late final NetworkDuelController controller;

  @override
  void initState() {
    super.initState();
    controller = NetworkDuelController(
      session: widget.session,
      playerId: widget.playerId,
      repository: widget.repository,
      secretStore: widget.secretStore,
      catalog: widget.catalog,
    )..addListener(_refresh);
    controller.start();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    controller
      ..removeListener(_refresh)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Premier duel')),
    body: SafeArea(
      child: switch (controller.state) {
        NetworkDuelViewState.loading => const Center(
          child: CircularProgressIndicator(key: Key('duel-loading')),
        ),
        NetworkDuelViewState.choosing ||
        NetworkDuelViewState.committing => _choosing(),
        NetworkDuelViewState.waitingForPartner ||
        NetworkDuelViewState.revealing => _waiting(),
        NetworkDuelViewState.resolved => _result(),
        NetworkDuelViewState.error => _error(),
      },
    ),
  );

  Widget _choosing() => ListView(
    key: const Key('network-duel-hand'),
    padding: const EdgeInsets.all(16),
    children: [
      Text(
        'Choisis une carte',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 8),
      const Text('Cette main reste uniquement sur ce téléphone.'),
      const SizedBox(height: 16),
      for (final card in controller.hand) ...[
        Card(
          color: controller.selectedCard?.id == card.id
              ? Theme.of(context).colorScheme.secondaryContainer
              : null,
          child: ListTile(
            key: Key('network-card-${card.id}'),
            onTap: controller.state == NetworkDuelViewState.choosing
                ? () => controller.selectCard(card.id)
                : null,
            leading: const Icon(Icons.style_outlined),
            title: Text(card.title),
            subtitle: Text(
              '${card.role.name} · ${_chilies(card.chiliLevel)} · ${card.personalValue}/20',
            ),
            trailing: controller.selectedCard?.id == card.id
                ? const Icon(Icons.check_circle)
                : null,
          ),
        ),
        const SizedBox(height: 8),
      ],
      const SizedBox(height: 8),
      FilledButton(
        key: const Key('confirm-network-card'),
        onPressed:
            controller.selectedCard != null &&
                controller.state == NetworkDuelViewState.choosing
            ? controller.confirmSelection
            : null,
        child: Text(
          controller.state == NetworkDuelViewState.committing
              ? 'Validation…'
              : 'Valider ce choix',
        ),
      ),
    ],
  );

  Widget _waiting() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 24),
          Text(
            controller.state == NetworkDuelViewState.revealing
                ? 'Validation sécurisée des choix…'
                : 'En attente de ton partenaire…',
            key: const Key('network-duel-waiting'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text(
            'Les cartes restent secrètes jusqu’à la révélation des deux choix.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );

  Widget _result() {
    final duel = controller.resolution!;
    final own = controller.localRevealedChoice!;
    final other = controller.opponentRevealedChoice!;
    final ownSnapshot = duel.first.snapshot.playerId == controller.playerId
        ? duel.first.snapshot
        : duel.second.snapshot;
    final otherSnapshot = duel.first.snapshot.playerId == controller.playerId
        ? duel.second.snapshot
        : duel.first.snapshot;
    final winner = duel.winnerPlayerId;
    final resultText = duel.tied
        ? 'Égalité'
        : winner == controller.playerId
        ? 'Tu remportes le duel'
        : 'Ton partenaire remporte le duel';
    return ListView(
      key: const Key('network-duel-result'),
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Cartes révélées',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 16),
        _revealedCard('Ta carte', own.choice.cardId, ownSnapshot.personalValue),
        _revealedCard(
          'Carte du partenaire',
          other.choice.cardId,
          otherSnapshot.personalValue,
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Text(
                  resultText,
                  key: const Key('network-duel-outcome'),
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text('Écart : ${duel.gap} · Coût PA : ${duel.gapCost}'),
                Text(
                  'PA : ${duel.actionPoints[controller.playerId]} · '
                  'Partenaire : ${duel.actionPoints[controller.opponentId]}',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _revealedCard(String label, String cardId, int value) {
    final card = widget.catalog.cards.firstWhere(
      (item) => item.stableId == cardId,
    );
    final variant = card.variants.firstWhere(
      (item) =>
          item.stableId ==
          (label == 'Ta carte'
              ? controller.localRevealedChoice!.choice.variantId
              : controller.opponentRevealedChoice!.choice.variantId),
    );
    return Card(
      child: ListTile(
        leading: const Icon(Icons.auto_awesome),
        title: Text('$label — ${card.title ?? card.titleKey ?? cardId}'),
        subtitle: Text('${_chilies(variant.chiliLevel)} · Puissance $value/20'),
      ),
    );
  }

  Widget _error() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        'Impossible de poursuivre ce duel.\n${controller.errorMessage ?? ''}',
        key: const Key('network-duel-error'),
        textAlign: TextAlign.center,
      ),
    ),
  );

  String _chilies(int level) => List.filled(level, '🌶️').join();
}
