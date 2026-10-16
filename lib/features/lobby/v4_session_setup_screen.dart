import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/profile/v4_profile.dart';
import '../../engines/runtime/v4_runtime_engine.dart';
import '../../sync/rounds/network_game.dart';
import 'lobby_models.dart';

class V4SessionSetupScreen extends StatefulWidget {
  const V4SessionSetupScreen({
    required this.session,
    required this.playerId,
    required this.repository,
    required this.profile,
    super.key,
  });

  final LobbySession session;
  final String playerId;
  final NetworkSessionSetupRepository repository;
  final V4Profile? profile;

  @override
  State<V4SessionSetupScreen> createState() => _V4SessionSetupScreenState();
}

class _V4SessionSetupScreenState extends State<V4SessionSetupScreen> {
  final clothing = TextEditingController();
  late final List<V4Accessory> accessories;
  final disabled = <String>{};
  V4SessionMode mode = V4SessionMode.presentiel;
  bool allAvailable = true;
  bool submitted = false;
  String? error;
  StreamSubscription<V4SessionSetupDto>? subscription;

  bool get isHost => widget.session.players.any(
    (player) =>
        player.userId == widget.playerId &&
        player.role == LobbyPlayerRole.player1,
  );

  @override
  void initState() {
    super.initState();
    accessories = [
      for (final item
          in widget.profile?.accessories ?? const <V4ProfileAccessory>[])
        V4Accessory(
          id: item.id,
          name: item.name,
          ownerPlayerId: widget.playerId,
          tags: {
            for (final tag in item.tags)
              V4AccessoryTag.values.byName(tag.toLowerCase()),
          },
          normallyActive: item.active,
        ),
    ];
    unawaited(_restore());
  }

  Future<void> _restore() async {
    try {
      final state = await widget.repository.getV4SessionSetup(
        widget.session.id,
      );
      if (!mounted) return;
      if (state.complete) {
        finish(state);
        return;
      }
      final own = state.players
          .where((item) => item.playerId == widget.playerId)
          .firstOrNull;
      if (own != null) {
        clothing.text = '${own.clothingCount}';
        accessories
          ..clear()
          ..addAll(own.accessories);
        setState(() => submitted = true);
        subscription = widget.repository
            .watchV4SessionSetup(widget.session.id)
            .listen((next) {
              if (next.complete) finish(next);
            });
      }
      if (state.mode != null) setState(() => mode = state.mode!);
    } catch (_) {
      // A new session has no setup yet; the editable form is the fallback.
    }
  }

  @override
  void dispose() {
    subscription?.cancel();
    clothing.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    final count = int.tryParse(clothing.text);
    if (count == null || count < 0) {
      setState(() => error = 'Indique un nombre de vêtements positif ou nul.');
      return;
    }
    setState(() {
      submitted = true;
      error = null;
    });
    try {
      final state = await widget.repository.submitV4SessionSetup(
        sessionId: widget.session.id,
        playerId: widget.playerId,
        clothingCount: count,
        mode: isHost ? mode : null,
        accessories: [
          for (final item in accessories)
            if (!disabled.contains(item.id)) item,
        ],
      );
      if (state.complete) return finish(state);
      subscription = widget.repository
          .watchV4SessionSetup(widget.session.id)
          .listen((state) {
            if (state.complete) finish(state);
          });
    } catch (_) {
      if (mounted) {
        setState(() {
          submitted = false;
          error = 'Impossible d’enregistrer la configuration.';
        });
      }
    }
  }

  void finish(V4SessionSetupDto state) {
    if (mounted) Navigator.of(context).pop(state);
  }

  Future<void> addTemporary() async {
    final name = TextEditingController();
    final tags = <V4AccessoryTag>{};
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Accessoire temporaire'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: const Key('temporary-accessory-name'),
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Nom'),
                ),
                for (final tag in V4AccessoryTag.values)
                  CheckboxListTile(
                    value: tags.contains(tag),
                    title: Text(tag.name.toUpperCase()),
                    onChanged: (checked) => setDialogState(() {
                      checked == true ? tags.add(tag) : tags.remove(tag);
                    }),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Ajouter'),
            ),
          ],
        ),
      ),
    );
    if (accepted == true && name.text.trim().isNotEmpty && tags.isNotEmpty) {
      setState(() {
        accessories.add(
          V4Accessory(
            id: 'temporary.${widget.playerId}.${DateTime.now().microsecondsSinceEpoch}',
            name: name.text.trim(),
            ownerPlayerId: widget.playerId,
            tags: tags,
            temporary: true,
          ),
        );
      });
    }
    name.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Préparer la partie')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (isHost) ...[
            const Text('Mode de la session'),
            SegmentedButton<V4SessionMode>(
              segments: [
                for (final value in V4SessionMode.values)
                  ButtonSegment(
                    value: value,
                    label: Text(value.name.toUpperCase()),
                  ),
              ],
              selected: {mode},
              onSelectionChanged: submitted
                  ? null
                  : (selected) => setState(() => mode = selected.single),
            ),
          ] else
            const Text('Le créateur choisit le mode de la session.'),
          TextField(
            key: const Key('initial-clothing-count'),
            controller: clothing,
            enabled: !submitted,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Nombre actuel de vêtements',
            ),
          ),
          const Text(
            'Comptez comme un seul vêtement les éléments portés/retirés ensemble : par exemple, une paire de chaussettes = 1 vêtement et une paire de chaussures = 1 vêtement.',
          ),
          const SizedBox(height: 20),
          SwitchListTile(
            title: const Text(
              'Tous vos accessoires enregistrés sont-ils disponibles pour cette partie ?',
            ),
            value: allAvailable,
            onChanged: submitted
                ? null
                : (value) => setState(() => allAvailable = value),
          ),
          if (!allAvailable)
            for (final accessory in accessories.where(
              (item) => item.normallyActive && !item.temporary,
            ))
              CheckboxListTile(
                title: Text(accessory.name),
                value: !disabled.contains(accessory.id),
                onChanged: submitted
                    ? null
                    : (enabled) => setState(() {
                        enabled == true
                            ? disabled.remove(accessory.id)
                            : disabled.add(accessory.id);
                      }),
              ),
          OutlinedButton.icon(
            key: const Key('add-temporary-accessory'),
            onPressed: submitted ? null : addTemporary,
            icon: const Icon(Icons.add),
            label: const Text('Ajouter temporairement un accessoire'),
          ),
          if (error != null) Text(error!, key: const Key('setup-error')),
          const SizedBox(height: 20),
          FilledButton(
            key: const Key('submit-v4-session-setup'),
            onPressed: submitted ? null : submit,
            child: Text(
              submitted ? 'En attente de ton partenaire…' : 'Valider',
            ),
          ),
        ],
      ),
    ),
  );
}
