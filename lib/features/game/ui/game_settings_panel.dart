import 'package:flutter/material.dart';

import '../game_preferences.dart';

class GameSettingsPanel extends StatelessWidget {
  const GameSettingsPanel({
    required this.preferences,
    required this.privateProfile,
    required this.onQuit,
    super.key,
  });

  final GamePreferencesController preferences;
  final Widget privateProfile;
  final Future<void> Function() onQuit;

  static const help = <(String, String)>[
    ('Choix', 'Choisis une carte de ta main puis confirme-la.'),
    ('Duel', 'Les valeurs engagées déterminent le résultat initial.'),
    (
      'Révélation',
      'Les deux cartes sont révélées ensemble lorsque les choix sont verrouillés.',
    ),
    (
      'Inversion',
      'Une inversion échange les rôles prévus par la carte retenue.',
    ),
    ('Enchère', 'Le perdant initial peut proposer des PA ou des cartes.'),
    ('Réponse du gagnant', 'Le gagnant choisit les éléments qu’il accepte.'),
    (
      'Adaptation',
      'La proposition peut être ajustée une seule fois selon cette réponse.',
    ),
    ('Validation finale', 'Le gagnant confirme le compromis final.'),
    ('Compromis', 'Chaque élément accepté rejoint l’action retenue.'),
    (
      'Récupération',
      'Une action acceptée peut rendre des PA entre deux duels.',
    ),
    ('Fin de tour', 'Les deux joueurs confirment avant le tour suivant.'),
    (
      'Face à face / Distance',
      'L’orientation adapte le tirage aux conditions de la session.',
    ),
    (
      'Fin de cycle',
      'Le joueur qui a créé la partie choisit de continuer ou terminer.',
    ),
  ];

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 36),
    child: Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 520,
        height: MediaQuery.sizeOf(context).height * .84,
        child: Column(
          children: [
            ListTile(
              title: Text(
                'Réglages',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              trailing: IconButton(
                key: const Key('close-game-settings'),
                tooltip: 'Fermer',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: AnimatedBuilder(
                animation: preferences,
                builder: (context, _) => ListView(
                  padding: const EdgeInsets.only(bottom: 20),
                  children: [
                    ExpansionTile(
                      title: const Text('Son et vibrations'),
                      leading: const Icon(Icons.volume_up_outlined),
                      children: [
                        SwitchListTile(
                          key: const Key('setting-sound'),
                          value: preferences.value.sound,
                          onChanged: preferences.setSound,
                          title: const Text('Sons'),
                        ),
                        SwitchListTile(
                          key: const Key('setting-vibrations'),
                          value: preferences.value.vibrations,
                          onChanged: preferences.setVibrations,
                          title: const Text('Vibrations'),
                        ),
                      ],
                    ),
                    ExpansionTile(
                      title: const Text('Affichage'),
                      leading: const Icon(Icons.display_settings_outlined),
                      children: [
                        ListTile(
                          title: const Text('Thème des cartes'),
                          trailing: DropdownButton<String>(
                            key: const Key('setting-card-theme'),
                            value: preferences.value.themeId,
                            items: [
                              for (final theme in preferences.availableThemes)
                                DropdownMenuItem(
                                  value: theme.pack.id,
                                  child: Text(theme.pack.name),
                                ),
                            ],
                            onChanged: (id) {
                              if (id == null) return;
                              preferences.setTheme(
                                preferences.availableThemes.firstWhere(
                                  (t) => t.pack.id == id,
                                ),
                              );
                            },
                          ),
                        ),
                        const ListTile(
                          key: Key('setting-brightness'),
                          title: Text('Luminosité'),
                          subtitle: Text(
                            'Utilise le réglage système de ton téléphone.',
                          ),
                        ),
                        SwitchListTile(
                          key: const Key('setting-animations'),
                          value: preferences.value.animations,
                          onChanged: preferences.setAnimations,
                          title: const Text('Animations'),
                        ),
                      ],
                    ),
                    ExpansionTile(
                      title: const Text('Profil privé'),
                      leading: const Icon(Icons.person_outline),
                      children: [privateProfile],
                    ),
                    ExpansionTile(
                      title: const Text('Aide'),
                      leading: const Icon(Icons.help_outline),
                      children: [
                        for (final item in help)
                          ListTile(
                            title: Text(item.$1),
                            subtitle: Text(item.$2),
                          ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: OutlinedButton.icon(
                        key: const Key('quit-network-game'),
                        onPressed: () => _confirmQuit(context),
                        icon: const Icon(Icons.logout),
                        label: const Text('Quitter la partie'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _confirmQuit(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Quitter la partie ?'),
        content: const Text('La partie sera terminée pour les deux joueurs.'),
        actions: [
          TextButton(
            key: const Key('cancel-quit-game'),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Non'),
          ),
          FilledButton(
            key: const Key('confirm-quit-game'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Oui, quitter'),
          ),
        ],
      ),
    );
    if (confirmed == true) await onQuit();
  }
}
