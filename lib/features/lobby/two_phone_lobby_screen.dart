import 'package:flutter/material.dart';

import 'lobby_controller.dart';
import 'lobby_repository.dart';

class TwoPhoneLobbyScreen extends StatefulWidget {
  const TwoPhoneLobbyScreen({required this.repository, super.key});
  final LobbyRepository repository;

  @override
  State<TwoPhoneLobbyScreen> createState() => _TwoPhoneLobbyScreenState();
}

class _TwoPhoneLobbyScreenState extends State<TwoPhoneLobbyScreen> {
  late final LobbyController controller;
  final codeController = TextEditingController();
  bool joining = false;

  @override
  void initState() {
    super.initState();
    controller = LobbyController(repository: widget.repository)
      ..addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    controller
      ..removeListener(_refresh)
      ..dispose();
    codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Jouer à deux')),
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: switch (controller.state) {
              LobbyViewState.waiting || LobbyViewState.ready => _session(),
              _ => _menu(),
            },
          ),
        ),
      ),
    ),
  );

  Widget _menu() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Icon(Icons.phone_android_rounded, size: 64),
      const SizedBox(height: 16),
      Text(
        'Jouer à deux',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 24),
      FilledButton(
        key: const Key('create-lobby'),
        onPressed: controller.state == LobbyViewState.creating
            ? null
            : controller.create,
        child: Text(
          controller.state == LobbyViewState.creating
              ? 'Création…'
              : 'Créer une partie',
        ),
      ),
      const SizedBox(height: 12),
      OutlinedButton(
        key: const Key('show-join-lobby'),
        onPressed: () => setState(() => joining = true),
        child: const Text('Rejoindre une partie'),
      ),
      if (joining) ...[
        const SizedBox(height: 16),
        TextField(
          key: const Key('join-code-field'),
          controller: codeController,
          textCapitalization: TextCapitalization.characters,
          maxLength: 6,
          decoration: const InputDecoration(
            labelText: 'Code de partie',
            border: OutlineInputBorder(),
          ),
        ),
        FilledButton.tonal(
          key: const Key('join-lobby'),
          onPressed: controller.state == LobbyViewState.joining
              ? null
              : () => controller.join(codeController.text),
          child: Text(
            controller.state == LobbyViewState.joining
                ? 'Connexion…'
                : 'Rejoindre',
          ),
        ),
      ],
      if (controller.errorMessage case final message?) ...[
        const SizedBox(height: 16),
        Text(
          message,
          key: const Key('lobby-error'),
          textAlign: TextAlign.center,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ],
    ],
  );

  Widget _session() {
    final session = controller.session!;
    return Column(
      children: [
        Icon(
          session.ready ? Icons.check_circle_rounded : Icons.people_outline,
          size: 72,
        ),
        const SizedBox(height: 16),
        Text(
          session.ready ? 'Partie prête' : 'En attente de votre partenaire',
          key: Key(session.ready ? 'lobby-ready' : 'lobby-waiting'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 20),
        const Text('Code de partie'),
        SelectableText(
          session.joinCode,
          key: const Key('lobby-code'),
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.bold,
            letterSpacing: 6,
          ),
        ),
        Text('${session.players.length}/2 joueurs connectés'),
        if (controller.state == LobbyViewState.offline) ...[
          const SizedBox(height: 16),
          Text(controller.errorMessage!, key: const Key('lobby-offline')),
          FilledButton.tonal(
            key: const Key('retry-lobby'),
            onPressed: controller.retry,
            child: const Text('Réessayer'),
          ),
        ],
      ],
    );
  }
}
