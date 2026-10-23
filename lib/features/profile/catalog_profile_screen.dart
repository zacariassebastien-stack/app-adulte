import 'dart:math';
import 'package:flutter/material.dart';
import '../../card_themes/card_renderer.dart';
import '../../card_themes/card_theme_models.dart';
import '../../domain/catalog/concept_editorial.dart';
import '../../domain/profile/adaptive_profile.dart';
import 'catalog_profile_controller.dart';
import 'radial_appreciation.dart';
import 'game_nickname_form.dart';
import '../../domain/profile/v4_profile.dart';

class CatalogProfileScreen extends StatefulWidget {
  const CatalogProfileScreen({required this.controller, super.key});
  final CatalogProfileController controller;
  @override
  State<CatalogProfileScreen> createState() => _CatalogProfileScreenState();
}

class _CatalogProfileScreenState extends State<CatalogProfileScreen> {
  String _mode = 'Liste', _kind = '', _direction = '', _query = '';
  ProfileCatalogItem? _random;
  String? _error;
  CatalogProfileController get model => widget.controller;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      if (!model.ready) await model.load();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Impossible de charger le profil. Réessaie depuis l’accueil.',
        );
      }
    }
  }

  @override
  void dispose() {
    model.dispose();
    super.dispose();
  }

  List<ProfileCatalogItem> get _filtered => model.items
      .where(
        (i) =>
            (_kind.isEmpty || i.concept.kind.name == _kind) &&
            (_direction.isEmpty || i.direction.name == _direction) &&
            ('${i.concept.title} ${i.actionTitle}'.toLowerCase().contains(
              _query.toLowerCase(),
            )),
      )
      .toList();
  void _nextRandom() {
    final pool = _filtered.where((i) => !model.explicit(i)).toList();
    _random = pool.isEmpty ? null : pool[Random().nextInt(pool.length)];
  }

  Future<void> _rate(
    ProfileCatalogItem item,
    DetailedPreferenceCategory value,
  ) async {
    try {
      await model.rate(item, value);
      if (mounted && _mode == 'Aléatoire') setState(_nextRandom);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enregistrement impossible. Réessaie.')),
        );
      }
    }
  }

  Future<void> _allowCard(ProfileCatalogItem item) async {
    try {
      await model.excludeCard(item.concept.id, excluded: false);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enregistrement impossible.')),
        );
      }
    }
  }

  ConceptEditorialText _copy(ProfileCatalogItem item) =>
      ConceptEditorialRenderer(model.catalog.concepts!).render(
        concept: item.concept,
        actionId: item.actionId,
        direction: item.direction,
      );
  Widget _card(ProfileCatalogItem item) {
    final copy = _copy(item);
    return CardRenderer(
      state: CardVisualState.full,
      showPa: false,
      definition: CardRenderDefinition(
        cardId: item.concept.id,
        variantId: item.actionId,
        title: item.concept.title,
        subtitle: item.actionTitle,
        zones: [
          for (final variant in item.concept.variants.where(
            (v) => v.id == item.actionId,
          ))
            if (variant.zoneId case final zoneId?)
              model.catalog.concepts!.zones
                  .singleWhere((z) => z.id == zoneId)
                  .title
            else if (variant.freeZone)
              'LIBRE',
        ],
        action: copy.actionText,
        details: copy.detailsText,
        direction: item.direction.name,
        spice: item.chili,
      ),
    );
  }

  void _consult(ProfileCatalogItem item) {
    final copy = _copy(item);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(item.concept.title),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(height: 340, child: _card(item)),
                Text('${item.actionTitle} · ${item.direction.name}'),
                const SizedBox(height: 12),
                Text(copy.actionText),
                if (copy.detailsText != null) Text(copy.detailsText!),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  Widget _summary(ProfileCatalogItem item) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        '${item.actionTitle} · ${item.direction.name} · ${model.category(item)?.label ?? 'À renseigner'}',
      ),
      if (!model.explicit(item))
        const Text('Estimation du profil — pas encore évalué explicitement'),
      if (model.globalTagVeto(item))
        const Text('Une exclusion globale de préférence reste active.'),
      if (model.cardExcluded(item.concept.id))
        TextButton(
          onPressed: model.saving
              ? null
              : () async {
                  try {
                    await model.excludeCard(item.concept.id, excluded: false);
                  } catch (_) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Enregistrement impossible.'),
                        ),
                      );
                    }
                  }
                },
          child: const Text('Lever l’exclusion de la carte'),
        ),
    ],
  );
  Widget _page(ProfileCatalogItem item) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      child: SizedBox(
        height: max(constraints.maxHeight, 360),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Expanded(
                child: RadialAppreciation(
                  key: ValueKey(item.id),
                  enabled: !model.saving,
                  onTap: () => _consult(item),
                  onSelected: (v) => _rate(item, v),
                  child: _card(item),
                ),
              ),
              _summary(item),
              const Text('Appui court : consulter · Appui long : apprécier'),
            ],
          ),
        ),
      ),
    ),
  );
  Future<void> _showSex() async {
    if (!model.ready) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Sexe : ${model.profile.sex.label}'),
        content: model.sexLocked
            ? const Text('Non modifiable pendant la partie.')
            : Column(mainAxisSize: MainAxisSize.min, children: [
                for (final sex in ProfileSex.values)
                  ListTile(
                    key: Key('profile-sex-${sex.name}'),
                    title: Text(sex.label),
                    selected: model.profile.sex == sex,
                    onTap: () async {
                      await model.setSex(sex);
                      if (dialogContext.mounted) Navigator.pop(dialogContext);
                    },
                  ),
              ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Personnaliser mon profil', maxLines: 1,
      overflow: TextOverflow.ellipsis), actions: [
      AnimatedBuilder(animation: model, builder: (context, _) => Tooltip(
        message: model.sexLocked ? 'Sexe non modifiable pendant la partie' : 'Modifier le sexe du profil',
        child: TextButton.icon(
          key: const Key('profile-sex'),
          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2)),
          onPressed: _showSex,
          icon: Icon(model.sexLocked ? Icons.lock_outline : Icons.person_outline),
          label: Column(key: const Key('profile-sex-summary'),
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Sexe', style: TextStyle(fontSize: 11)),
              Text(model.ready ? model.profile.sex.label : '…'),
            ]),
        ),
      )),
      IconButton(key: const Key('edit-game-nickname'), tooltip: 'Modifier le pseudo de jeu',
        icon: const Icon(Icons.badge_outlined), onPressed: () async {
          if (!model.ready) return;
          await showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(
            content: SingleChildScrollView(child: GameNicknameForm(
              initialValue: model.profile.gameNickname, buttonText: 'Enregistrer',
              onSaved: (name) async {
                await model.setGameNickname(name);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              })),
          ));
        }),
    ]),
    body: _error != null
        ? Center(child: Text(_error!))
        : AnimatedBuilder(
            animation: model,
            builder: (context, _) {
              if (!model.ready) {
                return const Center(child: CircularProgressIndicator());
              }
              final filtered = _filtered;
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: TextField(
                      key: const Key('profile-catalog-search'),
                      decoration: const InputDecoration(
                        labelText: 'Rechercher une carte',
                      ),
                      onChanged: (v) => setState(() {
                        _query = v;
                        _nextRandom();
                      }),
                    ),
                  ),
                  Wrap(
                    spacing: 12,
                    children: [
                      DropdownButton<String>(
                        key: const Key('profile-catalog-kind'),
                        isExpanded: true,
                        value: _kind,
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('Tous les types'),
                          ),
                          for (final kind
                              in model.items
                                  .map((i) => i.concept.kind.name)
                                  .toSet())
                            DropdownMenuItem(
                              value: kind,
                              child: Text(
                                const {
                                      'action': 'Action',
                                      'evolution': 'Évolutive',
                                      'zones': 'Zones',
                                      'accessory': 'Accessoire',
                                    }[kind] ??
                                    kind,
                              ),
                            ),
                        ],
                        onChanged: (v) => setState(() {
                          _kind = v ?? '';
                          _nextRandom();
                        }),
                      ),
                      DropdownButton<String>(
                        key: const Key('profile-catalog-direction'),
                        isExpanded: true,
                        value: _direction,
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('Tous les rôles'),
                          ),
                          for (final d
                              in model.items
                                  .map((i) => i.direction.name)
                                  .toSet())
                            DropdownMenuItem(value: d, child: Text(d)),
                        ],
                        onChanged: (v) => setState(() {
                          _direction = v ?? '';
                          _nextRandom();
                        }),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final mode in ['Liste', 'Cartes', 'Aléatoire'])
                        ChoiceChip(
                          label: Text(mode),
                          selected: _mode == mode,
                          onSelected: (_) => setState(() {
                            FocusScope.of(context).unfocus();
                            _mode = mode;
                            if (mode == 'Aléatoire') _nextRandom();
                          }),
                        ),
                    ],
                  ),
                  Text(
                    '${model.remaining.length} éléments restent à évaluer · Profil privé',
                  ),
                  Expanded(
                    child: _mode == 'Liste'
                        ? ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (context, n) {
                              final item = filtered[n];
                              return ListTile(
                                key: ValueKey(item.id),
                                title: Text(
                                  '${item.concept.title} · ${item.actionTitle}',
                                ),
                                subtitle: Text(
                                  '${item.direction.name} · ${model.category(item)?.label ?? 'À renseigner'}${model.globalTagVeto(item) ? ' · Veto global actif' : ''}',
                                ),
                                onTap: () => _consult(item),
                                trailing: PopupMenuButton<Object>(
                                  enabled: !model.saving,
                                  tooltip: 'Modifier l’appréciation',
                                  onSelected: (v) =>
                                      v is DetailedPreferenceCategory
                                      ? _rate(item, v)
                                      : _allowCard(item),
                                  itemBuilder: (_) => [
                                    if (model.cardExcluded(item.concept.id))
                                      const PopupMenuItem(
                                        value: 'allow-card',
                                        child: Text(
                                          'Lever l’exclusion de la carte',
                                        ),
                                      ),
                                    for (final value
                                        in DetailedPreferenceCategory.values)
                                      PopupMenuItem(
                                        value: value,
                                        child: Text(value.label),
                                      ),
                                  ],
                                ),
                              );
                            },
                          )
                        : _mode == 'Aléatoire'
                        ? (_random == null
                              ? const Center(
                                  child: Text(
                                    'Tous les éléments de cette sélection ont été évalués.',
                                  ),
                                )
                              : _page(_random!))
                        : filtered.isEmpty
                        ? const Center(
                            child: Text('Aucune carte pour ces filtres.'),
                          )
                        : PageView.builder(
                            key: ValueKey('$_kind/$_direction/$_query'),
                            itemCount: filtered.length,
                            itemBuilder: (context, n) => _page(filtered[n]),
                          ),
                  ),
                ],
              );
            },
          ),
  );
}
