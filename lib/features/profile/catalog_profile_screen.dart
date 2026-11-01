import 'dart:math';
import 'package:flutter/material.dart';
import '../../card_themes/card_renderer.dart';
import '../../card_themes/card_theme_models.dart';
import '../../domain/catalog/concept_editorial.dart';
import '../../domain/profile/adaptive_profile.dart';
import 'catalog_profile_controller.dart';
import 'catalog_profile_binder_order.dart';
import '../../domain/game/game_models.dart';
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
  final _pages = PageController(keepPage: false);
  final _search = TextEditingController();
  ProfileBinderSort _sort = ProfileBinderSort.defaultOrder;
  _BinderFilters _filters = const _BinderFilters();
  String _query = '';
  int _page = 0;
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
    _pages.dispose();
    _search.dispose();
    model.dispose();
    super.dispose();
  }

  List<ProfileCatalogItem> get _filtered => ProfileBinderOrder.select(
    items: model.items,
    isEvaluated: model.explicit,
    categoryFor: model.category,
    estimateFor: (item) =>
        model.ratings.explicitEstimate(item.ratingKey(model.playerId)),
    sort: _sort,
    roles: _filters.roles,
    spices: _filters.spices,
    evaluation: _filters.evaluation,
    query: _query,
  );

  void _changeView(VoidCallback change, {bool dismissKeyboard = true}) {
    if (dismissKeyboard) FocusScope.of(context).unfocus();
    setState(() {
      change();
      _page = 0;
    });
    if (_pages.hasClients) _pages.jumpToPage(0);
  }

  Future<void> _rate(
    ProfileCatalogItem item,
    DetailedPreferenceCategory value,
  ) async {
    try {
      await model.rate(item, value);
      if (mounted) {
        final lastPage = max(0, (_filtered.length - 1) ~/ 4);
        if (_page > lastPage) {
          setState(() => _page = lastPage);
          if (_pages.hasClients) _pages.jumpToPage(lastPage);
        }
      }
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
          for (final stage in item.concept.presentationStages.where(
            (s) => s.id == item.actionId,
          ))
            if (stage.zoneId != null)
              model.catalog.concepts!.zones
                  .singleWhere((z) => z.id == stage.zoneId)
                  .title,
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
        details: [
          ?copy.detailsText,
          if (model.bodyLimits(item).isNotEmpty)
            'Tes limites conservées pour cette action : ${model.bodyLimits(item).join(', ')}.',
        ].join(' '),
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
                const SizedBox(height: 12),
                _summary(item),
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
          onPressed: model.saving ? null : () => _allowCard(item),
          child: const Text('Lever l’exclusion de la carte'),
        ),
    ],
  );
  Future<void> _showSex() async {
    if (!model.ready) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Sexe : ${model.profile.sex.label}'),
        content: model.sexLocked
            ? const Text('Non modifiable pendant la partie.')
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
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
                ],
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  Future<void> _showFilters() async {
    FocusScope.of(context).unfocus();
    var roles = {..._filters.roles};
    var spices = {..._filters.spices};
    var evaluation = _filters.evaluation;
    final selected = await showModalBottomSheet<_BinderFilters>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Filtrer le classeur',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              const Text('Rôle · tous si aucun sélectionné'),
              Wrap(
                spacing: 8,
                children: [
                  for (final role in const [
                    CardOccurrenceDirection.FAIRE,
                    CardOccurrenceDirection.RECEVOIR,
                    CardOccurrenceDirection.MUTUEL,
                    CardOccurrenceDirection.SOLO,
                  ])
                    FilterChip(
                      key: Key('binder-role-${role.name}'),
                      label: Text(role.name),
                      selected: roles.contains(role),
                      onSelected: (selected) => update(() {
                        selected ? roles.add(role) : roles.remove(role);
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              const Text('Piment · tous si aucun sélectionné'),
              Wrap(
                spacing: 8,
                children: [
                  for (var spice = 1; spice <= 4; spice++)
                    FilterChip(
                      key: Key('binder-spice-$spice'),
                      label: Text('P$spice'),
                      selected: spices.contains(spice),
                      onSelected: (selected) => update(() {
                        selected ? spices.add(spice) : spices.remove(spice);
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              const Text('Évaluation'),
              Wrap(
                spacing: 8,
                children: [
                  for (final state in ProfileBinderEvaluation.values)
                    ChoiceChip(
                      key: Key('binder-evaluation-${state.name}'),
                      label: Text(_evaluationLabel(state)),
                      selected: evaluation == state,
                      onSelected: (_) => update(() => evaluation = state),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                runSpacing: 8,
                children: [
                  TextButton(
                    key: const Key('binder-reset-filters'),
                    onPressed: () => update(() {
                      roles = {};
                      spices = {};
                      evaluation = ProfileBinderEvaluation.all;
                    }),
                    child: const Text('Réinitialiser'),
                  ),
                  FilledButton(
                    key: const Key('binder-apply-filters'),
                    onPressed: () => Navigator.pop(
                      context,
                      _BinderFilters(
                        roles: roles,
                        spices: spices,
                        evaluation: evaluation,
                      ),
                    ),
                    child: const Text('Appliquer'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (selected != null && mounted) _changeView(() => _filters = selected);
  }

  Widget _binderPage(List<ProfileCatalogItem> items, int page) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final height = max(constraints.maxHeight, 400.0 * max(1.0, scale));
      final slots = items.skip(page * 4).take(4).toList();
      return SingleChildScrollView(
        key: ValueKey('binder-page-$page'),
        child: SizedBox(
          height: height,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: Column(
              children: [
                for (var row = 0; row < 2; row++) ...[
                  if (row > 0) const SizedBox(height: 12),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var column = 0; column < 2; column++) ...[
                          if (column > 0) const SizedBox(width: 12),
                          Expanded(
                            child: row * 2 + column < slots.length
                                ? _miniature(slots[row * 2 + column])
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _miniature(ProfileCatalogItem item) {
    final category = model.category(item);
    final evaluated = model.explicit(item);
    return RadialAppreciation(
      key: ValueKey(item.id),
      enabled: !model.saving,
      initialValue: category,
      onTap: () => _consult(item),
      onSelected: (value) => _rate(item, value),
      child: Semantics(
        button: true,
        label:
            '${item.concept.title}, ${item.actionTitle}, ${item.direction.name}, P${item.chili}, '
            '${evaluated ? category?.label ?? 'Non évaluée' : 'Non évaluée'}',
        child: Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 2,
                  children: [
                    Text(
                      item.direction.name,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'P${item.chili}',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  item.concept.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  item.actionTitle,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Spacer(),
                const SizedBox(height: 6),
                Text(
                  evaluated ? category?.label ?? 'Non évaluée' : 'Non évaluée',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: category == DetailedPreferenceCategory.excluded
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        'Personnaliser mon profil',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      actions: [
        AnimatedBuilder(
          animation: model,
          builder: (context, _) => Tooltip(
            message: model.sexLocked
                ? 'Sexe non modifiable pendant la partie'
                : 'Modifier le sexe du profil',
            child: TextButton.icon(
              key: const Key('profile-sex'),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              ),
              onPressed: _showSex,
              icon: Icon(
                model.sexLocked ? Icons.lock_outline : Icons.person_outline,
              ),
              label: Column(
                key: const Key('profile-sex-summary'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Sexe', style: TextStyle(fontSize: 11)),
                  Text(model.ready ? model.profile.sex.label : '…'),
                ],
              ),
            ),
          ),
        ),
        IconButton(
          key: const Key('edit-game-nickname'),
          tooltip: 'Modifier le pseudo de jeu',
          icon: const Icon(Icons.badge_outlined),
          onPressed: () async {
            if (!model.ready) return;
            await showDialog<void>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                content: SingleChildScrollView(
                  child: GameNicknameForm(
                    initialValue: model.profile.gameNickname,
                    buttonText: 'Enregistrer',
                    onSaved: (name) async {
                      await model.setGameNickname(name);
                      if (dialogContext.mounted) Navigator.pop(dialogContext);
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ],
    ),
    body: _error != null
        ? Center(child: Text(_error!))
        : AnimatedBuilder(
            animation: model,
            builder: (context, _) {
              if (!model.ready) {
                return const Center(child: CircularProgressIndicator());
              }
              final items = _filtered;
              final count = (items.length + 3) ~/ 4;
              final page = min(_page, max(0, count - 1));
              return SafeArea(
                top: false,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: TextField(
                        controller: _search,
                        key: const Key('profile-catalog-search'),
                        decoration: InputDecoration(
                          labelText: 'Rechercher une carte',
                          isDense: true,
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _query.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Effacer la recherche',
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _search.clear();
                                    _changeView(() => _query = '');
                                  },
                                ),
                        ),
                        onChanged: (value) => _changeView(
                          () => _query = value,
                          dismissKeyboard: false,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: DropdownButton<ProfileBinderSort>(
                              key: const Key('profile-binder-sort'),
                              value: _sort,
                              isExpanded: true,
                              underline: const SizedBox.shrink(),
                              items: [
                                for (final sort in ProfileBinderSort.values)
                                  DropdownMenuItem(
                                    value: sort,
                                    child: Text(
                                      sort.label,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                              onChanged: (sort) {
                                if (sort != null) {
                                  _changeView(() => _sort = sort);
                                }
                              },
                            ),
                          ),
                          TextButton.icon(
                            key: const Key('profile-binder-filters'),
                            onPressed: _showFilters,
                            icon: const Icon(Icons.tune, size: 20),
                            label: Text(
                              _filters.activeCount == 0
                                  ? 'Filtres'
                                  : 'Filtres (${_filters.activeCount})',
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${items.length} cartes · ${items.where((i) => !model.explicit(i)).length} non évaluées',
                      key: const Key('profile-binder-count'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    Expanded(
                      child: items.isEmpty
                          ? const Center(
                              child: Text('Aucune carte pour ces filtres.'),
                            )
                          : PageView.builder(
                              controller: _pages,
                              key: const Key('profile-binder-pages'),
                              itemCount: count,
                              onPageChanged: (page) =>
                                  setState(() => _page = page),
                              itemBuilder: (context, page) =>
                                  _binderPage(items, page),
                            ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          key: const Key('binder-previous-page'),
                          tooltip: 'Page précédente',
                          onPressed: page == 0
                              ? null
                              : () => _pages.previousPage(
                                  duration: const Duration(milliseconds: 180),
                                  curve: Curves.easeOut,
                                ),
                          icon: const Icon(Icons.chevron_left),
                        ),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            count == 0 ? '0 / 0' : '${page + 1} / $count',
                            key: const Key('profile-binder-position'),
                          ),
                        ),
                        IconButton(
                          key: const Key('binder-next-page'),
                          tooltip: 'Page suivante',
                          onPressed: page + 1 >= count
                              ? null
                              : () => _pages.nextPage(
                                  duration: const Duration(milliseconds: 180),
                                  curve: Curves.easeOut,
                                ),
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        'Appui court : consulter · Appui long : apprécier',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
  );
}

String _evaluationLabel(ProfileBinderEvaluation evaluation) =>
    switch (evaluation) {
      ProfileBinderEvaluation.all => 'Toutes',
      ProfileBinderEvaluation.evaluated => 'Évaluées',
      ProfileBinderEvaluation.unevaluated => 'Non évaluées',
    };

class _BinderFilters {
  const _BinderFilters({
    this.roles = const {},
    this.spices = const {},
    this.evaluation = ProfileBinderEvaluation.all,
  });
  final Set<CardOccurrenceDirection> roles;
  final Set<int> spices;
  final ProfileBinderEvaluation evaluation;
  int get activeCount =>
      roles.length +
      spices.length +
      (evaluation == ProfileBinderEvaluation.all ? 0 : 1);
}
