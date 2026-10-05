import 'package:flutter/material.dart';

import '../../domain/catalog/v3_taxonomy.dart';
import '../../domain/profile/adaptive_profile.dart';
import '../../engines/profile/profile_learning_engine.dart';
import '../game/network_profile_learning.dart';

class InitialProfileScreen extends StatefulWidget {
  const InitialProfileScreen({
    required this.playerId,
    required this.taxonomy,
    required this.store,
    required this.onCompleted,
    super.key,
  });

  final String playerId;
  final V3Taxonomy taxonomy;
  final NetworkProfileLearningStore store;
  final VoidCallback onCompleted;

  @override
  State<InitialProfileScreen> createState() => _InitialProfileScreenState();
}

class _InitialProfileScreenState extends State<InitialProfileScreen> {
  final Map<String, InitialSwipeChoice> _choices = {};
  late final List<V3TagDefinition> _preferences;
  var _index = 0;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    _preferences = widget.taxonomy.tags
        .where(
          (tag) => tag.category == V3TagCategory.PREFERENCE && tag.scoreable,
        )
        .toList(growable: false);
  }

  Future<void> _select(InitialSwipeChoice choice) async {
    if (_saving || _preferences.isEmpty) return;
    _choices[_preferences[_index].stableId] = choice;
    if (_index < _preferences.length - 1) {
      setState(() => _index++);
      return;
    }
    setState(() => _saving = true);
    final profile = const ProfileLearningEngine().initialize(
      profileId: widget.playerId,
      choices: _choices,
    );
    await widget.store.save(profile);
    if (mounted) widget.onCompleted();
  }

  @override
  Widget build(BuildContext context) {
    final preference = _preferences[_index];
    return Scaffold(
      appBar: AppBar(title: const Text('Créer mon profil')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Tes préférences restent privées sur ce téléphone.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 24),
                  LinearProgressIndicator(
                    value: (_index + 1) / _preferences.length,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${_index + 1} / ${_preferences.length}',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  Text(
                    _label(preference.key),
                    key: const Key('initial-profile-preference'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 32),
                  _choice('J’adore', InitialSwipeChoice.love),
                  const SizedBox(height: 12),
                  _choice('Ça me plaît', InitialSwipeChoice.like),
                  const SizedBox(height: 12),
                  _choice('Je ne sais pas', InitialSwipeChoice.unsure),
                  const SizedBox(height: 12),
                  _choice('Exclu', InitialSwipeChoice.excluded),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _choice(String label, InitialSwipeChoice choice) => FilledButton.tonal(
    onPressed: _saving ? null : () => _select(choice),
    child: Text(label),
  );

  String _label(String key) => key
      .toLowerCase()
      .split('_')
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}
