import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/game/game_models.dart';
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
  final clothing = <String, TextEditingController>{};
  final accessories = <String, List<V4Accessory>>{};
  final disabled = <String, Set<String>>{};
  V4SessionSetupDto? state;
  V4SessionMode mode = V4SessionMode.presentiel;
  PlayerStyle? style;
  bool busy = false, finishing = false;
  String? error;
  StreamSubscription<V4SessionSetupDto>? subscription;
  String? pendingCommand;
  String? pendingPayload;
  bool get isHost => widget.session.players.any(
    (p) => p.userId == widget.playerId && p.role == LobbyPlayerRole.player1,
  );
  String get draftKey =>
      'session-setup:${widget.session.id}:${widget.playerId}';
  @override
  void initState() {
    super.initState();
    for (final p in widget.session.players) {
      clothing[p.userId] = TextEditingController();
    }
    unawaited(load());
  }

  Future<void> load() async {
    try {
      final inventory = [
        for (final a in widget.profile?.accessories ?? <V4ProfileAccessory>[])
          V4Accessory(
            id: a.id,
            name: a.name,
            ownerPlayerId: widget.playerId,
            tags: {
              for (final tag in a.tags)
                V4AccessoryTag.values.byName(tag.toLowerCase()),
            },
            normallyActive: a.active,
          ),
      ];
      receive(
        await widget.repository.registerSetupAccessories(
          sessionId: widget.session.id,
          accessories: inventory,
        ),
      );
      if (!mounted || finishing) return;
      final saved = (await SharedPreferences.getInstance()).getString(draftKey);
      if (saved != null) {
        final raw = jsonDecode(saved) as Map<String, Object?>;
        if (isHost && raw['revision'] == state?.revision) {
          mode = V4SessionMode.values.byName(raw['mode'] as String);
          style = raw['style'] == null
              ? null
              : PlayerStyle.values.byName(raw['style'] as String);
        }
        for (final id in clothing.keys) {
          if ((isHost && raw['revision'] == state?.revision) ||
              (!isHost && id == widget.playerId)) {
            if (raw[id] case final Map<String, Object?> data) {
              clothing[id]!.text = data['clothing']! as String;
              accessories[id] = [
                for (final a in data['accessories']! as List<Object?>)
                  V4Accessory.fromJson(
                    Map<String, Object?>.from(a! as Map<String, Object?>),
                  ),
              ];
              disabled[id] = (data['disabled']! as List<Object?>)
                  .cast<String>()
                  .toSet();
            }
          }
        }
      }
      if (!mounted) return;
      setState(() {});
      subscription = widget.repository
          .watchV4SessionSetup(widget.session.id)
          .listen(
            receive,
            onError: (Object e) {
              if (mounted) {
                setState(
                  () => error =
                      'Connexion interrompue. Tes réglages sont conservés.',
                );
              }
            },
          );
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Impossible de charger la préparation.');
      }
    }
  }

  void receive(V4SessionSetupDto next) {
    if (!mounted || finishing) return;
    if (next.complete) {
      finishing = true;
      unawaited(
        SharedPreferences.getInstance().then((p) => p.remove(draftKey)),
      );
      Navigator.of(context).pop(next);
      return;
    }
    final first = state == null;
    setState(() {
      state = next;
      // Fill only untouched environments; incoming updates never erase typing.
      for (final p in next.players) {
        if (!accessories.containsKey(p.playerId) ||
            (accessories[p.playerId]!.isEmpty &&
                p.availableAccessories.isNotEmpty)) {
          accessories[p.playerId] = [
            ...p.availableAccessories,
            for (final a in p.accessories)
              if (!p.availableAccessories.any((b) => b.id == a.id)) a,
          ];
          disabled[p.playerId] = {
            for (final a in accessories[p.playerId]!)
              if (p.environmentReady
                  ? !p.accessories.any((b) => b.id == a.id)
                  : !a.normallyActive)
                a.id,
          };
        }
        if (p.environmentReady && clothing[p.playerId]?.text.isEmpty == true) {
          clothing[p.playerId]!.text = '${p.clothingCount}';
        }
      }
      if (next.mode != null && (!isHost || first)) mode = next.mode!;
      if (next.style != null && (!isHost || first)) style = next.style;
    });
  }

  Future<void> saveDraft() async {
    final data = {
      'revision': state?.revision,
      'mode': mode.name,
      'style': style?.name,
      for (final id in clothing.keys)
        id: {
          'clothing': clothing[id]!.text,
          'accessories': [
            for (final a in accessories[id] ?? <V4Accessory>[]) a.toJson(),
          ],
          'disabled': (disabled[id] ?? {}).toList(),
        },
    };
    await (await SharedPreferences.getInstance()).setString(
      draftKey,
      jsonEncode(data),
    );
  }

  V4PlayerSessionSetupDto environment(String id) {
    final count = int.tryParse(clothing[id]!.text);
    if (count == null || count < 0) {
      throw const FormatException(
        'Indique le nombre de vêtements pour chaque joueur concerné.',
      );
    }
    return V4PlayerSessionSetupDto(
      playerId: id,
      clothingCount: count,
      accessories: [
        for (final a in accessories[id] ?? <V4Accessory>[])
          if (!(disabled[id] ?? {}).contains(a.id)) a,
      ],
    );
  }

  Future<void> submit({bool accepted = true}) async {
    if (busy || state == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final environments = isHost
          ? [
              for (final p in widget.session.players)
                if (mode != V4SessionMode.distance ||
                    p.userId == widget.playerId)
                  environment(p.userId),
            ]
          : <V4PlayerSessionSetupDto>[];
      final own =
          !isHost &&
              mode == V4SessionMode.distance &&
              clothing[widget.playerId]!.text.isNotEmpty
          ? environment(widget.playerId)
          : null;
      if (isHost && style == null) {
        throw const FormatException('Choisis le style de la partie.');
      }
      final payload = jsonEncode({
        'revision': state!.revision,
        'mode': mode.name,
        'style': style?.name,
        'accepted': accepted,
        'players': [for (final p in environments) p.toJson()],
        'own': own?.toJson(),
      });
      if (payload != pendingPayload) {
        pendingPayload = payload;
        pendingCommand =
            'setup:${widget.session.id}:${widget.playerId}:${DateTime.now().microsecondsSinceEpoch}';
      }
      await saveDraft();
      final next = isHost
          ? await widget.repository.proposeSessionSetup(
              sessionId: widget.session.id,
              mode: mode,
              style: style!,
              players: environments,
              expectedRevision: state!.revision,
              commandId: pendingCommand!,
            )
          : await widget.repository.respondSessionSetup(
              sessionId: widget.session.id,
              revision: state!.revision,
              accepted: accepted,
              environment: own,
              commandId: pendingCommand!,
            );
      receive(next);
      if (mounted && !finishing) await saveDraft();
    } on FormatException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Impossible d’enregistrer. Réessaie : tes réglages sont conservés.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> addAccessory(String id) async {
    final name = TextEditingController();
    final tags = <V4AccessoryTag>{};
    final dialog = DialogRoute<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
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
                    onChanged: (v) => update(() {
                      v == true ? tags.add(tag) : tags.remove(tag);
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
    final ok = await Navigator.of(context).push(dialog);
    if (ok == true &&
        name.text.trim().isNotEmpty &&
        tags.isNotEmpty &&
        mounted) {
      setState(() {
        accessories
            .putIfAbsent(id, () => [])
            .add(
              V4Accessory(
                id: 'temporary.$id.${DateTime.now().microsecondsSinceEpoch}',
                name: name.text.trim(),
                ownerPlayerId: id,
                tags: tags,
                temporary: true,
              ),
            );
      });
      await saveDraft();
    }
    await dialog.completed;
    name.dispose();
  }

  Widget environmentForm(String id) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            id == widget.playerId
                ? 'Mon environnement'
                : 'Environnement du partenaire',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          TextField(
            key: Key(
              id == widget.playerId
                  ? 'initial-clothing-count'
                  : 'partner-clothing-count',
            ),
            controller: clothing[id],
            enabled: !busy,
            keyboardType: TextInputType.number,
            onChanged: (_) => unawaited(saveDraft()),
            decoration: const InputDecoration(
              labelText: 'Nombre actuel de vêtements',
            ),
          ),
          const Text(
            'Une paire de chaussettes ou de chaussures compte pour un vêtement.',
          ),
          for (final a in accessories[id] ?? <V4Accessory>[])
            CheckboxListTile(
              title: Text(a.name),
              subtitle: a.temporary ? const Text('Temporaire') : null,
              value: !(disabled[id] ?? {}).contains(a.id),
              onChanged: busy
                  ? null
                  : (v) {
                      setState(() {
                        final excluded = disabled.putIfAbsent(id, () => {});
                        v == true ? excluded.remove(a.id) : excluded.add(a.id);
                      });
                      unawaited(saveDraft());
                    },
            ),
          OutlinedButton.icon(
            key: Key(
              id == widget.playerId
                  ? 'add-temporary-accessory'
                  : 'add-partner-temporary-accessory',
            ),
            onPressed: busy ? null : () => addAccessory(id),
            icon: const Icon(Icons.add),
            label: const Text('Ajouter un accessoire temporaire'),
          ),
        ],
      ),
    ),
  );
  String styleLabel(PlayerStyle s) => switch (s) {
    PlayerStyle.SOFT => 'Soft 🌶️',
    PlayerStyle.EPICE => 'Épicé 🌶️🌶️',
    PlayerStyle.INTENABLE => 'Intenable 🌶️🌶️🌶️',
  };
  Widget summary() => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Proposition de ton partenaire',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text('Mode : ${state?.mode?.name.toUpperCase() ?? 'En attente'}'),
          Text(
            'Style : ${state?.style == null ? 'En attente' : styleLabel(state!.style!)}',
          ),
          for (final p in state?.players ?? <V4PlayerSessionSetupDto>[])
            if (mode != V4SessionMode.distance ||
                p.playerId != widget.playerId) ...[
              const Divider(),
              Text(
                p.playerId == widget.playerId
                    ? 'Mon environnement'
                    : 'Environnement du partenaire',
              ),
              Text(
                'Vêtements : ${p.environmentReady ? p.clothingCount : 'En attente'}',
              ),
              Text(
                p.accessories.isEmpty
                    ? 'Aucun accessoire sélectionné'
                    : p.accessories
                          .map(
                            (a) =>
                                a.name + (a.temporary ? ' (temporaire)' : ''),
                          )
                          .join(', '),
              ),
            ],
        ],
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final proposed = state?.status == 'PROPOSED';
    return Scaffold(
      appBar: AppBar(title: const Text('Préparer la partie')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (state == null) const LinearProgressIndicator(),
            if (state?.status == 'REFUSED')
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Configuration refusée. L’hôte peut la modifier et envoyer une nouvelle proposition.',
                  ),
                ),
              ),
            if (isHost) ...[
              Text(
                'Votre partie',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Text('Mode'),
              SegmentedButton<V4SessionMode>(
                segments: [
                  for (final m in V4SessionMode.values)
                    ButtonSegment(
                      value: m,
                      label: Text(switch (m) {
                        V4SessionMode.presentiel => 'Présentiel',
                        V4SessionMode.distance => 'Distance',
                        V4SessionMode.hybrid => 'Hybride',
                      }),
                    ),
                ],
                selected: {mode},
                onSelectionChanged: busy
                    ? null
                    : (v) {
                        setState(() => mode = v.single);
                        unawaited(saveDraft());
                      },
              ),
              const SizedBox(height: 16),
              const Text('Choisissez votre rythme'),
              for (final s in PlayerStyle.values)
                Card(
                  child: ListTile(
                    key: Key('setup-style-${s.name}'),
                    selected: style == s,
                    leading: Icon(
                      style == s
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                    ),
                    title: Text(styleLabel(s)),
                    subtitle: Text(switch (s) {
                      PlayerStyle.SOFT => 'Prendre le temps de se découvrir.',
                      PlayerStyle.EPICE => 'Faire monter l’intensité.',
                      PlayerStyle.INTENABLE => 'Un rythme plus intense.',
                    }),
                    onTap: busy
                        ? null
                        : () {
                            setState(() => style = s);
                            unawaited(saveDraft());
                          },
                  ),
                ),
              for (final p in widget.session.players)
                if (mode != V4SessionMode.distance ||
                    p.userId == widget.playerId)
                  environmentForm(p.userId),
              if (state?.players.any((p) => !p.inventoryReady) == true)
                const Text(
                  'En attente de la connexion du partenaire pour charger ses accessoires.',
                ),
              FilledButton(
                key: const Key('submit-v4-session-setup'),
                onPressed:
                    busy ||
                        state == null ||
                        state!.players.any((p) => !p.inventoryReady)
                    ? null
                    : submit,
                child: Text(
                  proposed
                      ? 'Envoyer la proposition mise à jour'
                      : 'Proposer cette configuration',
                ),
              ),
              if (proposed)
                const Text('En attente de la validation de ton partenaire…'),
            ] else ...[
              summary(),
              if (state?.mode == V4SessionMode.distance)
                environmentForm(widget.playerId),
              if (proposed) ...[
                FilledButton(
                  key: const Key('accept-v4-session-setup'),
                  onPressed: busy ? null : submit,
                  child: const Text('Valider et commencer'),
                ),
                OutlinedButton(
                  key: const Key('refuse-v4-session-setup'),
                  onPressed: busy ? null : () => submit(accepted: false),
                  child: const Text('Refuser'),
                ),
              ] else
                const Text(
                  'L’hôte prépare votre partie. Tu recevras sa proposition ici.',
                ),
            ],
            if (error != null) Text(error!, key: const Key('setup-error')),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    subscription?.cancel();
    for (final c in clothing.values) {
      c.dispose();
    }
    super.dispose();
  }
}
