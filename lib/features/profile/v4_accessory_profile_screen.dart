import 'package:flutter/material.dart';

import '../../domain/profile/v4_profile.dart';
import '../game/network_profile_learning.dart';

class V4AccessoryProfileScreen extends StatefulWidget {
  const V4AccessoryProfileScreen({
    required this.profile,
    required this.store,
    this.temporaryAccessories = const [],
    super.key,
  });

  final V4Profile profile;
  final V4ProfileStore store;
  final List<V4ProfileAccessory> temporaryAccessories;

  @override
  State<V4AccessoryProfileScreen> createState() =>
      _V4AccessoryProfileScreenState();
}

class _V4AccessoryProfileScreenState extends State<V4AccessoryProfileScreen> {
  late final List<V4ProfileAccessory> accessories = [
    ...widget.profile.accessories,
  ];

  static const presets = <(String, Set<String>)>[
    ('Vibromasseur', {'VAGINAL', 'EXTERNE', 'VIBRANT'}),
    ('Stimulateur externe', {'EXTERNE', 'VIBRANT'}),
    ('Accessoire anal', {'ANAL'}),
    ('Accessoire pour pénis/phallus', {'PHALLUS'}),
  ];

  Future<void> _add({String? presetName, Set<String>? presetTags}) async {
    final name = TextEditingController(text: presetName);
    final tags = <String>{...?presetTags};
    final values = <ProfilePreferenceRole, double?>{
      ProfilePreferenceRole.faire: 18,
      ProfilePreferenceRole.recevoir: 18,
      ProfilePreferenceRole.soi: 18,
    };
    final modifiedRoles = <ProfilePreferenceRole>{};
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Ajouter un accessoire'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: const Key('profile-accessory-name'),
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Nom'),
                ),
                const SizedBox(height: 8),
                for (final tag in v4AccessoryTags)
                  CheckboxListTile(
                    dense: true,
                    title: Text(tag),
                    value: tags.contains(tag),
                    onChanged: (checked) => update(() {
                      checked == true ? tags.add(tag) : tags.remove(tag);
                    }),
                  ),
                for (final role in const [
                  ProfilePreferenceRole.faire,
                  ProfilePreferenceRole.recevoir,
                  ProfilePreferenceRole.soi,
                ])
                  DropdownButtonFormField<double?>(
                    initialValue: values[role],
                    decoration: InputDecoration(
                      labelText: role.wireName,
                      helperText: '18 = valeur inconnue, Exclu reste distinct',
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Exclu')),
                      for (var pa = 1; pa <= 20; pa++)
                        DropdownMenuItem(
                          value: pa.toDouble(),
                          child: Text('$pa PA'),
                        ),
                    ],
                    onChanged: (value) => update(() {
                      values[role] = value;
                      modifiedRoles.add(role);
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
      final inherited = widget.profile.accessoryPreferencesForExactTags(tags);
      final persistedValues = {
        for (final role in const [
          ProfilePreferenceRole.faire,
          ProfilePreferenceRole.recevoir,
          ProfilePreferenceRole.soi,
        ])
          role: modifiedRoles.contains(role)
              ? values[role]
              : inherited.containsKey(role)
              ? inherited[role]
              : values[role],
      };
      setState(() {
        accessories.add(
          V4ProfileAccessory(
            id: 'accessory.${widget.profile.profileId}.${DateTime.now().microsecondsSinceEpoch}',
            name: name.text.trim(),
            ownerProfileId: widget.profile.profileId,
            tags: tags,
            preferences: persistedValues,
          ),
        );
      });
    }
    name.dispose();
  }

  Future<void> _save() async {
    await widget.store.save(widget.profile.copyWith(accessories: accessories));
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Mes accessoires')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Les préférences sont propres à l’ensemble exact de tags. PHALLUS désigne un usage sur ou autour d’un pénis/phallus.',
        ),
        for (final accessory in accessories)
          SwitchListTile(
            title: Text(accessory.name),
            subtitle: Text(accessory.tags.join(' · ')),
            value: accessory.active,
            onChanged: (active) => setState(() {
              final index = accessories.indexOf(accessory);
              accessories[index] = V4ProfileAccessory(
                id: accessory.id,
                name: accessory.name,
                ownerProfileId: accessory.ownerProfileId,
                tags: accessory.tags,
                active: active,
                preferences: accessory.preferences,
              );
            }),
          ),
        if (widget.temporaryAccessories.isNotEmpty) ...[
          const Divider(),
          const Text('Accessoires temporaires de cette partie'),
          for (final accessory in widget.temporaryAccessories)
            ListTile(
              title: Text(accessory.name),
              subtitle: Text(accessory.tags.join(' · ')),
              trailing: TextButton(
                onPressed: () => setState(() {
                  if (!accessories.any((item) => item.id == accessory.id)) {
                    accessories.add(accessory);
                  }
                }),
                child: const Text('Enregistrer'),
              ),
            ),
        ],
        const Divider(),
        const Text('Accessoires courants'),
        for (final preset in presets)
          TextButton(
            onPressed: () => _add(presetName: preset.$1, presetTags: preset.$2),
            child: Text('Ajouter ${preset.$1}'),
          ),
        OutlinedButton.icon(
          key: const Key('add-custom-profile-accessory'),
          onPressed: _add,
          icon: const Icon(Icons.add),
          label: const Text('Ajouter un accessoire personnalisé'),
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('save-profile-accessories'),
          onPressed: _save,
          child: const Text('Enregistrer'),
        ),
      ],
    ),
  );
}
