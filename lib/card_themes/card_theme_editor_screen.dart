import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/asset_catalog.dart';
import '../domain/catalog/catalog.dart';
import '../domain/catalog/definitions.dart';
import '../domain/catalog/enums.dart';
import 'card_illustration_editor_adapter.dart';
import 'card_renderer.dart';
import 'card_theme_models.dart';
import 'card_theme_repository.dart';
import 'card_theme_validator.dart';

enum _PreviewMode { single, representative, catalogue }

enum CardEditorPreviewDirection { faire, recevoir, mutuel }

class CardThemeEditorScreen extends StatefulWidget {
  const CardThemeEditorScreen({
    this.repository = const SharedPreferencesCardThemeRepository(),
    this.initialCatalog,
    this.initialBundles,
    this.illustrationAdapter,
    super.key,
  });

  final CardThemeRepository repository;
  final Catalog? initialCatalog;
  final List<ThemeBundle>? initialBundles;
  final CardIllustrationEditorAdapter? illustrationAdapter;

  @override
  State<CardThemeEditorScreen> createState() => _CardThemeEditorScreenState();
}

class _CardThemeEditorScreenState extends State<CardThemeEditorScreen> {
  List<ThemeBundle> bundles = const [];
  Catalog? catalog;
  ThemeBundle? active;
  CardDefinition? previewCard;
  CardVariantDefinition? previewVariant;
  String? selectedBlockId;
  bool showBack = false;
  _PreviewMode previewMode = _PreviewMode.single;
  CardEditorPreviewDirection directionPreview =
      CardEditorPreviewDirection.faire;
  List<ThemeValidationIssue> issues = const [];
  String? message;

  @override
  void initState() {
    super.initState();
    if (widget.initialCatalog != null && widget.initialBundles != null) {
      catalog = widget.initialCatalog;
      bundles = widget.initialBundles!;
      active = bundles.first;
      previewCard = catalog!.cards.firstWhere((card) => card.v3DeckEnabled);
      previewVariant = _previewVariants(previewCard!).first;
      _validate();
    } else {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final result = await Future.wait<Object>([
      widget.repository.loadAll(),
      loadAssetCatalog(),
    ]);
    final loadedBundles = result[0] as List<ThemeBundle>;
    final loadedCatalog = result[1] as Catalog;
    if (!mounted) return;
    setState(() {
      bundles = loadedBundles;
      active = loadedBundles.first;
      catalog = loadedCatalog;
      previewCard = loadedCatalog.cards.firstWhere(
        (card) => card.v3DeckEnabled,
      );
      previewVariant = _previewVariants(previewCard!).first;
      _validate();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Card Theme Editor'),
      actions: [
        IconButton(
          key: const Key('theme-import'),
          tooltip: 'Importer un thème',
          onPressed: _import,
          icon: const Icon(Icons.file_download_outlined),
        ),
        IconButton(
          key: const Key('theme-export'),
          tooltip: 'Exporter le thème',
          onPressed: active == null ? null : _export,
          icon: const Icon(Icons.file_upload_outlined),
        ),
        IconButton(
          key: const Key('theme-save'),
          tooltip: 'Sauvegarder',
          onPressed: active == null || !_canEdit ? null : _save,
          icon: const Icon(Icons.save_outlined),
        ),
      ],
    ),
    body: catalog == null || active == null
        ? const Center(child: CircularProgressIndicator())
        : LayoutBuilder(
            builder: (context, constraints) => constraints.maxWidth >= 900
                ? Row(
                    children: [
                      SizedBox(width: 300, child: _library()),
                      const VerticalDivider(width: 1),
                      Expanded(child: _preview()),
                      const VerticalDivider(width: 1),
                      SizedBox(width: 330, child: _properties()),
                    ],
                  )
                : ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      _library(),
                      const SizedBox(height: 12),
                      SizedBox(height: 520, child: _preview()),
                      const SizedBox(height: 12),
                      _properties(),
                    ],
                  ),
          ),
  );

  Widget _library() => ListView(
    shrinkWrap: true,
    padding: const EdgeInsets.all(12),
    children: [
      DropdownButtonFormField<String>(
        key: const Key('theme-selector'),
        isExpanded: true,
        initialValue: active!.pack.id,
        decoration: const InputDecoration(labelText: 'Theme pack'),
        items: [
          for (final bundle in bundles)
            DropdownMenuItem(
              value: bundle.pack.id,
              child: Text(bundle.pack.name),
            ),
        ],
        onChanged: (id) => setState(() {
          active = bundles.firstWhere((bundle) => bundle.pack.id == id);
          selectedBlockId = null;
          _validate();
        }),
      ),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        key: const Key('layout-selector'),
        isExpanded: true,
        initialValue: active!.layout.id,
        decoration: const InputDecoration(labelText: 'Layout'),
        items: [
          for (final layout in _layouts)
            DropdownMenuItem(value: layout.id, child: Text(layout.name)),
        ],
        onChanged: (id) {
          if (id != null) _selectLayout(id);
        },
      ),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        key: const Key('skin-selector'),
        isExpanded: true,
        initialValue: active!.skin.id,
        decoration: const InputDecoration(labelText: 'Skin'),
        items: [
          for (final skin in _skins)
            DropdownMenuItem(value: skin.id, child: Text(skin.name)),
        ],
        onChanged: (id) {
          if (id != null) _selectSkin(id);
        },
      ),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        key: const Key('preview-card-selector'),
        isExpanded: true,
        initialValue: previewCard!.stableId,
        decoration: const InputDecoration(labelText: 'Carte de preview'),
        items: [
          for (final card in catalog!.cards.where((item) => item.v3DeckEnabled))
            DropdownMenuItem(
              value: card.stableId,
              child: Text(card.title ?? card.titleKey ?? card.stableId),
            ),
        ],
        onChanged: (id) => setState(() {
          previewCard = catalog!.cards.firstWhere(
            (card) => card.stableId == id,
          );
          previewVariant = _previewVariants(previewCard!).first;
          selectedBlockId = null;
        }),
      ),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        key: const Key('preview-variant-selector'),
        isExpanded: true,
        initialValue: previewVariant!.stableId,
        decoration: const InputDecoration(labelText: 'Variante de preview'),
        items: [
          for (final variant in _previewVariants(previewCard!))
            DropdownMenuItem(
              value: variant.stableId,
              child: Text(variant.title ?? variant.stableId),
            ),
        ],
        onChanged: (id) => setState(() {
          previewVariant = _previewVariants(
            previewCard!,
          ).firstWhere((variant) => variant.stableId == id);
        }),
      ),
      if (widget.illustrationAdapter != null) ...[
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          key: const Key('associate-illustration'),
          onPressed: _associateIllustration,
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: Text(
            _currentIllustration == null
                ? 'Associer une illustration'
                : 'Remplacer l’illustration',
          ),
        ),
        if (_currentIllustration != null)
          TextButton.icon(
            key: const Key('remove-illustration'),
            onPressed: _removeIllustration,
            icon: const Icon(Icons.hide_image_outlined),
            label: const Text('Supprimer l’illustration'),
          ),
      ],
      const SizedBox(height: 12),
      SegmentedButton<CardEditorPreviewDirection>(
        key: const Key('direction-preview-selector'),
        segments: const [
          ButtonSegment(
            value: CardEditorPreviewDirection.faire,
            label: Text('Faire'),
          ),
          ButtonSegment(
            value: CardEditorPreviewDirection.recevoir,
            label: Text('Recevoir'),
          ),
          ButtonSegment(
            value: CardEditorPreviewDirection.mutuel,
            label: Text('Mutuel'),
          ),
        ],
        selected: {directionPreview},
        onSelectionChanged: (value) =>
            setState(() => directionPreview = value.single),
      ),
      const SizedBox(height: 12),
      SegmentedButton<_PreviewMode>(
        segments: const [
          ButtonSegment(value: _PreviewMode.single, label: Text('Une')),
          ButtonSegment(
            value: _PreviewMode.representative,
            label: Text('Test'),
          ),
          ButtonSegment(value: _PreviewMode.catalogue, label: Text('Toutes')),
        ],
        selected: {previewMode},
        onSelectionChanged: (value) =>
            setState(() => previewMode = value.single),
      ),
      SwitchListTile(
        key: const Key('toggle-card-face'),
        contentPadding: EdgeInsets.zero,
        title: const Text('Afficher le verso'),
        value: showBack,
        onChanged: (value) => setState(() => showBack = value),
      ),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          OutlinedButton(
            onPressed: () => _duplicate('layout'),
            child: const Text('Dupliquer layout'),
          ),
          OutlinedButton(
            onPressed: () => _duplicate('skin'),
            child: const Text('Dupliquer skin'),
          ),
          OutlinedButton(
            onPressed: () => _duplicate('theme'),
            child: const Text('Dupliquer pack'),
          ),
        ],
      ),
      if (!active!.pack.system)
        TextButton.icon(
          onPressed: _delete,
          icon: const Icon(Icons.delete_outline),
          label: const Text('Supprimer ce thème'),
        ),
      if (message != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(message!, key: const Key('editor-message')),
        ),
    ],
  );

  Widget _preview() => ColoredBox(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    child: switch (previewMode) {
      _PreviewMode.single => Center(
        child: SizedBox(
          width: 330,
          height: 470,
          child: CardRenderer(
            key: const Key('editor-card-preview'),
            definition: _definition(previewCard!, previewVariant),
            bundle: active,
            state: showBack ? CardVisualState.hidden : CardVisualState.full,
            playerName: 'Joueur',
            selectedBlockId: selectedBlockId,
            onBlockSelected: (id) => setState(() => selectedBlockId = id),
            onBlockChanged: _updateBlock,
            illustrationProvider: widget.illustrationAdapter?.previewProvider,
          ),
        ),
      ),
      _PreviewMode.representative => _grid(_representativeCards()),
      _PreviewMode.catalogue => _grid(
        catalog!.cards.where((card) => card.v3DeckEnabled).toList(),
      ),
    },
  );

  Widget _grid(List<CardDefinition> cards) => GridView.builder(
    key: Key('preview-${previewMode.name}'),
    padding: const EdgeInsets.all(12),
    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 190,
      childAspectRatio: .7,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
    ),
    itemCount: cards.length,
    itemBuilder: (_, index) => CardRenderer(
      definition: _definition(cards[index]),
      bundle: active,
      state: showBack ? CardVisualState.hidden : CardVisualState.normal,
      playerName: 'Joueur',
      illustrationProvider: widget.illustrationAdapter?.previewProvider,
    ),
  );

  Widget _properties() {
    final selected = _selectedBlock;
    final skin = active!.skin;
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.all(16),
      children: [
        Text('Propriétés', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text('Layout : ${active!.layout.name}'),
        Text('Skin : ${skin.name}'),
        if (_canEdit) ...[
          TextFormField(
            key: ValueKey('layout-name-${active!.layout.id}'),
            initialValue: active!.layout.name,
            decoration: const InputDecoration(labelText: 'Renommer le layout'),
            onFieldSubmitted: (name) => _renameLayout(name.trim()),
          ),
          TextFormField(
            key: ValueKey('skin-name-${active!.skin.id}'),
            initialValue: active!.skin.name,
            decoration: const InputDecoration(labelText: 'Renommer le skin'),
            onFieldSubmitted: (name) => _renameSkin(name.trim()),
          ),
        ],
        if (selected != null) ...[
          const Divider(),
          Text(
            'Bloc ${selected.id}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Visible'),
            value: selected.visible,
            onChanged: (value) =>
                _updateBlock(selected.copyWith(visible: value)),
          ),
          DropdownButtonFormField<CardTextAlign>(
            initialValue: selected.alignment,
            decoration: const InputDecoration(labelText: 'Alignement'),
            items: [
              for (final value in CardTextAlign.values)
                DropdownMenuItem(value: value, child: Text(value.name)),
            ],
            onChanged: (value) {
              if (value != null) {
                _updateBlock(selected.copyWith(alignment: value));
              }
            },
          ),
          _slider('Rotation', selected.rotation, -3.14, 3.14, (value) {
            _updateBlock(selected.copyWith(rotation: value));
          }),
          _slider('Padding relatif', selected.padding, 0, .1, (value) {
            _updateBlock(selected.copyWith(padding: value));
          }),
          _slider('Marge relative', selected.margin, 0, .1, (value) {
            _updateBlock(selected.copyWith(margin: value));
          }),
          if (selected.type == CardBlockType.illustration) ...[
            _slider('Position X', selected.box.x, 0, 1 - selected.box.width, (
              value,
            ) {
              _updateBlock(
                selected.copyWith(box: selected.box.copyWith(x: value)),
              );
            }),
            _slider('Position Y', selected.box.y, 0, 1 - selected.box.height, (
              value,
            ) {
              _updateBlock(
                selected.copyWith(box: selected.box.copyWith(y: value)),
              );
            }),
            _slider('Largeur', selected.box.width, .03, 1 - selected.box.x, (
              value,
            ) {
              _updateIllustrationSize(selected, width: value);
            }),
            _slider('Hauteur', selected.box.height, .03, 1 - selected.box.y, (
              value,
            ) {
              _updateIllustrationSize(selected, height: value);
            }),
            if (_currentIllustration != null) ...[
              DropdownButtonFormField<IllustrationFit>(
                key: const Key('illustration-fit'),
                initialValue: _currentIllustration!.fit,
                decoration: const InputDecoration(labelText: 'Mode de rendu'),
                items: const [
                  DropdownMenuItem(
                    value: IllustrationFit.cover,
                    child: Text('Cover'),
                  ),
                  DropdownMenuItem(
                    value: IllustrationFit.contain,
                    child: Text('Contain'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    _updateIllustration(
                      _currentIllustration!.copyWith(fit: value),
                    );
                  }
                },
              ),
              SwitchListTile(
                key: const Key('illustration-preserve-ratio'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Conserver les proportions'),
                value: _currentIllustration!.preserveAspectRatio,
                onChanged: (value) => _updateIllustration(
                  _currentIllustration!.copyWith(preserveAspectRatio: value),
                ),
              ),
              _slider('Point focal X', _currentIllustration!.focusX, 0, 1, (
                value,
              ) {
                _updateIllustration(
                  _currentIllustration!.copyWith(focusX: value),
                );
              }),
              _slider('Point focal Y', _currentIllustration!.focusY, 0, 1, (
                value,
              ) {
                _updateIllustration(
                  _currentIllustration!.copyWith(focusY: value),
                );
              }),
              _slider(
                'Opacité (%)',
                _currentIllustration!.opacity * 100,
                0,
                100,
                (value) {
                  _updateIllustration(
                    _currentIllustration!.copyWith(opacity: value / 100),
                  );
                },
              ),
            ],
          ],
        ],
        const Divider(),
        Text('Skin', style: Theme.of(context).textTheme.titleMedium),
        _colorField(
          'Fond',
          skin.background,
          (color) => _updateSkin(skin.copyWith(background: color)),
        ),
        _colorField(
          'Fond dégradé',
          skin.backgroundGradientEnd ?? skin.background,
          (color) => _updateSkin(skin.copyWith(backgroundGradientEnd: color)),
        ),
        _colorField(
          'Bordure externe',
          skin.resolvedOuterBorderColor,
          (color) => _updateSkin(skin.copyWith(outerBorderColor: color)),
        ),
        _colorField(
          'Bordure interne',
          skin.resolvedInnerBorderColor,
          (color) => _updateSkin(skin.copyWith(innerBorderColor: color)),
        ),
        _colorField(
          'Couleur principale',
          skin.primary,
          (color) => _updateSkin(skin.copyWith(primary: color)),
        ),
        _colorField(
          'Panneau',
          skin.panel,
          (color) => _updateSkin(skin.copyWith(panel: color)),
        ),
        _colorField(
          'Bordure panneau',
          skin.resolvedPanelBorderColor,
          (color) => _updateSkin(skin.copyWith(panelBorderColor: color)),
        ),
        _colorField(
          'Texte titre',
          skin.titleStyle.color,
          (color) => _updateSkin(
            skin.copyWith(titleStyle: skin.titleStyle.copyWith(color: color)),
          ),
        ),
        _colorField(
          'Texte secondaire',
          skin.bodyStyle.color,
          (color) => _updateSkin(
            skin.copyWith(bodyStyle: skin.bodyStyle.copyWith(color: color)),
          ),
        ),
        _colorField(
          'Texte atténué',
          (skin.panelStyle ?? skin.bodyStyle).color,
          (color) => _updateSkin(
            skin.copyWith(
              panelStyle: (skin.panelStyle ?? skin.bodyStyle).copyWith(
                color: color,
              ),
            ),
          ),
        ),
        _colorField(
          'Accent',
          skin.primary,
          (color) => _updateSkin(skin.copyWith(primary: color)),
        ),
        _slider(
          'Épaisseur bordure externe',
          skin.resolvedOuterBorderWidth,
          0,
          8,
          (value) {
            _updateSkin(skin.copyWith(outerBorderWidth: value));
          },
        ),
        _slider('Épaisseur bordure interne', skin.innerBorderWidth, 0, 5, (
          value,
        ) {
          _updateSkin(skin.copyWith(innerBorderWidth: value));
        }),
        _slider('Écart des bordures', skin.borderGap, 0, 20, (value) {
          _updateSkin(skin.copyWith(borderGap: value));
        }),
        _slider('Rayon des coins', skin.resolvedCornerRadius, 0, 48, (value) {
          _updateSkin(skin.copyWith(cornerRadius: value));
        }),
        _slider('Opacité matière', skin.textureOpacity, 0, .12, (value) {
          _updateSkin(skin.copyWith(textureOpacity: value));
        }),
        _slider('Ombre', skin.shadow, 0, 30, (value) {
          _updateSkin(skin.copyWith(shadow: value));
        }),
        _slider('Rayon du glow', skin.resolvedGlowRadius, 0, 30, (value) {
          _updateSkin(skin.copyWith(glowRadius: value));
        }),
        _slider('Intensité du glow', skin.glowIntensity, 0, 1, (value) {
          _updateSkin(skin.copyWith(glowIntensity: value));
        }),
        _slider('Opacité du glow', skin.glowOpacity, 0, 1, (value) {
          _updateSkin(skin.copyWith(glowOpacity: value));
        }),
        _slider('Bordure des panneaux', skin.panelBorderWidth, 0, 4, (value) {
          _updateSkin(skin.copyWith(panelBorderWidth: value));
        }),
        _slider('Rayon des panneaux', skin.panelRadius, 0, 30, (value) {
          _updateSkin(skin.copyWith(panelRadius: value));
        }),
        _slider('Ombre des panneaux', skin.panelShadow, 0, 16, (value) {
          _updateSkin(skin.copyWith(panelShadow: value));
        }),
        _slider('Taille du titre', skin.titleStyle.size, 8, 32, (value) {
          _updateSkin(
            skin.copyWith(titleStyle: skin.titleStyle.copyWith(size: value)),
          );
        }),
        _slider('Taille du corps', skin.bodyStyle.size, 7, 24, (value) {
          _updateSkin(
            skin.copyWith(bodyStyle: skin.bodyStyle.copyWith(size: value)),
          );
        }),
        _slider('Taille des labels', skin.badgeStyle.size, 6, 18, (value) {
          _updateSkin(
            skin.copyWith(badgeStyle: skin.badgeStyle.copyWith(size: value)),
          );
        }),
        _slider('Espacement titre', skin.titleStyle.letterSpacing, -1, 5, (
          value,
        ) {
          _updateSkin(
            skin.copyWith(
              titleStyle: skin.titleStyle.copyWith(letterSpacing: value),
            ),
          );
        }),
        _slider('Espacement labels', skin.badgeStyle.letterSpacing, 0, 5, (
          value,
        ) {
          _updateSkin(
            skin.copyWith(
              badgeStyle: skin.badgeStyle.copyWith(letterSpacing: value),
            ),
          );
        }),
        _slider('Espacement corps', skin.bodyStyle.letterSpacing, -1, 4, (
          value,
        ) {
          _updateSkin(
            skin.copyWith(
              bodyStyle: skin.bodyStyle.copyWith(letterSpacing: value),
            ),
          );
        }),
        _fontField('Police du titre', skin.titleStyle.fontFamily, (font) {
          _updateSkin(
            skin.copyWith(
              titleStyle: skin.titleStyle.copyWith(fontFamily: font),
            ),
          );
        }),
        _fontField('Police des labels', skin.badgeStyle.fontFamily, (font) {
          _updateSkin(
            skin.copyWith(
              badgeStyle: skin.badgeStyle.copyWith(fontFamily: font),
            ),
          );
        }),
        _fontField('Police du corps', skin.bodyStyle.fontFamily, (font) {
          _updateSkin(
            skin.copyWith(bodyStyle: skin.bodyStyle.copyWith(fontFamily: font)),
          );
        }),
        const Divider(),
        Text('Validation', style: Theme.of(context).textTheme.titleMedium),
        if (issues.isEmpty) const Text('Aucune erreur.'),
        for (final issue in issues)
          ListTile(
            dense: true,
            leading: Icon(
              issue.severity == ThemeIssueSeverity.error
                  ? Icons.error_outline
                  : Icons.warning_amber,
            ),
            title: Text(issue.message),
          ),
      ],
    );
  }

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> changed,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('$label · ${value.toStringAsFixed(2)}'),
      Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        onChanged: changed,
      ),
    ],
  );

  Widget _colorField(String label, int value, ValueChanged<int> changed) {
    final controller = TextEditingController(
      text: value.toRadixString(16).padLeft(8, '0').toUpperCase(),
    );
    return TextField(
      controller: controller,
      decoration: InputDecoration(labelText: '$label (ARGB)'),
      onSubmitted: (source) {
        final parsed = int.tryParse(source.replaceAll('#', ''), radix: 16);
        if (parsed != null) changed(parsed);
      },
    );
  }

  Widget _fontField(
    String label,
    String? value,
    ValueChanged<String> changed,
  ) => TextFormField(
    initialValue: value ?? '',
    decoration: InputDecoration(labelText: label),
    onFieldSubmitted: (font) => changed(font.trim()),
  );

  IllustrationAsset? get _currentIllustration => active?.illustrationFor(
    previewCard?.stableId ?? '',
    active?.pack.illustrationStyleId,
  );

  Future<void> _associateIllustration() async {
    final adapter = widget.illustrationAdapter;
    if (adapter == null) return;
    try {
      final path = await adapter.chooseAndImport(
        bundle: active!,
        cardId: previewCard!.stableId,
      );
      if (path == null || !mounted) return;
      final previous = _currentIllustration;
      final asset =
          previous?.copyWith(assetPath: path) ??
          IllustrationAsset(
            illustrationId:
                '${active!.pack.id}.${previewCard!.stableId}.illustration',
            cardId: previewCard!.stableId,
            styleId: active!.pack.illustrationStyleId ?? 'default',
            assetPath: path,
          );
      if (previous != null && previous.assetPath != path) {
        await adapter.remove(previous);
      }
      _updateIllustration(asset);
      selectedBlockId = active!.layout.front
          .where((block) => block.type == CardBlockType.illustration)
          .firstOrNull
          ?.id;
      await widget.repository.save(active!);
      if (mounted) {
        setState(() => message = 'Illustration associée et sauvegardée.');
      }
    } on Object catch (error) {
      if (mounted) setState(() => message = error.toString());
    }
  }

  Future<void> _removeIllustration() async {
    final asset = _currentIllustration;
    final adapter = widget.illustrationAdapter;
    if (asset == null || adapter == null) return;
    try {
      await adapter.remove(asset);
      final illustrations = active!.illustrations
          .where((item) => item.cardId != asset.cardId)
          .toList();
      _replaceActive(
        ThemeBundle(
          pack: active!.pack,
          layout: active!.layout,
          skin: active!.skin,
          illustrations: illustrations,
        ),
      );
      await widget.repository.save(active!);
      if (mounted) {
        setState(
          () => message = 'Illustration supprimée. Le fallback est actif.',
        );
      }
    } on Object catch (error) {
      if (mounted) setState(() => message = error.toString());
    }
  }

  void _updateIllustration(IllustrationAsset changed) {
    final illustrations = <IllustrationAsset>[
      for (final item in active!.illustrations)
        if (item.cardId != changed.cardId) item,
      changed,
    ];
    setState(() {
      _replaceActive(
        ThemeBundle(
          pack: active!.pack,
          layout: active!.layout,
          skin: active!.skin,
          illustrations: illustrations,
        ),
      );
      _validate();
    });
  }

  void _updateIllustrationSize(
    CardLayoutBlock block, {
    double? width,
    double? height,
  }) {
    final preserve = _currentIllustration?.preserveAspectRatio ?? true;
    var nextWidth = width ?? block.box.width;
    var nextHeight = height ?? block.box.height;
    if (preserve) {
      final ratio = block.box.width / block.box.height;
      if (width != null) nextHeight = nextWidth / ratio;
      if (height != null) nextWidth = nextHeight * ratio;
      if (nextWidth > 1 - block.box.x) {
        nextWidth = 1 - block.box.x;
        nextHeight = nextWidth / ratio;
      }
      if (nextHeight > 1 - block.box.y) {
        nextHeight = 1 - block.box.y;
        nextWidth = nextHeight * ratio;
      }
    }
    _updateBlock(
      block.copyWith(
        box: block.box.copyWith(width: nextWidth, height: nextHeight),
      ),
    );
  }

  void _replaceActive(ThemeBundle bundle) {
    active = bundle;
    bundles = [
      for (final item in bundles)
        if (item.pack.id == bundle.pack.id) bundle else item,
    ];
  }

  bool get _canEdit =>
      active?.pack.system == false ||
      active?.pack.id == 'enchaire_signature_v1';

  CardLayoutBlock? get _selectedBlock {
    if (selectedBlockId == null) return null;
    final blocks = showBack ? active!.layout.back : active!.layout.front;
    return blocks.where((block) => block.id == selectedBlockId).firstOrNull;
  }

  List<CardLayout> get _layouts => {
    for (final bundle in bundles) bundle.layout.id: bundle.layout,
  }.values.toList();

  List<CardSkin> get _skins => {
    for (final bundle in bundles) bundle.skin.id: bundle.skin,
  }.values.toList();

  void _selectLayout(String id) {
    final layout = _layouts.firstWhere((item) => item.id == id);
    final pack = _packFor(layoutId: layout.id, skinId: active!.skin.id);
    setState(() {
      active = ThemeBundle(
        pack: pack,
        layout: layout,
        skin: active!.skin,
        illustrations: active!.illustrations,
      );
      selectedBlockId = null;
      _validate();
    });
  }

  void _selectSkin(String id) {
    final skin = _skins.firstWhere((item) => item.id == id);
    final pack = _packFor(layoutId: active!.layout.id, skinId: skin.id);
    setState(() {
      active = ThemeBundle(
        pack: pack,
        layout: active!.layout,
        skin: skin,
        illustrations: active!.illustrations,
      );
      _validate();
    });
  }

  CardThemePack _packFor({required String layoutId, required String skinId}) =>
      CardThemePack(
        id: active!.pack.id,
        name: active!.pack.name,
        version: active!.pack.version,
        layoutId: layoutId,
        skinId: skinId,
        illustrationStyleId: active!.pack.illustrationStyleId,
        previewCardId: active!.pack.previewCardId,
        minimumRendererVersion: active!.pack.minimumRendererVersion,
        premium: active!.pack.premium,
        system: active!.pack.system,
      );

  void _updateBlock(CardLayoutBlock changed) {
    if (!_canEdit) {
      setState(() => message = 'Dupliquez classic_v1 avant de le modifier.');
      return;
    }
    final source = showBack ? active!.layout.back : active!.layout.front;
    final updated = [
      for (final block in source) block.id == changed.id ? changed : block,
    ];
    final layout = active!.layout.copyWith(
      front: showBack ? null : updated,
      back: showBack ? updated : null,
    );
    setState(() {
      active = ThemeBundle(
        pack: active!.pack,
        layout: layout,
        skin: active!.skin,
        illustrations: active!.illustrations,
      );
      _validate();
    });
  }

  void _updateSkin(CardSkin skin) {
    if (!_canEdit) {
      setState(() => message = 'Dupliquez classic_v1 avant de le modifier.');
      return;
    }
    setState(() {
      active = ThemeBundle(
        pack: active!.pack,
        layout: active!.layout,
        skin: skin,
        illustrations: active!.illustrations,
      );
      _validate();
    });
  }

  void _renameLayout(String name) {
    if (name.isEmpty || !_canEdit) return;
    setState(() {
      active = ThemeBundle(
        pack: active!.pack,
        layout: active!.layout.copyWith(name: name),
        skin: active!.skin,
        illustrations: active!.illustrations,
      );
    });
  }

  void _renameSkin(String name) {
    if (name.isEmpty || !_canEdit) return;
    setState(() {
      active = ThemeBundle(
        pack: active!.pack,
        layout: active!.layout,
        skin: active!.skin.copyWith(name: name),
        illustrations: active!.illustrations,
      );
    });
  }

  Future<void> _duplicate(String kind) async {
    final suffix = DateTime.now().millisecondsSinceEpoch;
    final id = '${kind}_$suffix';
    final source = active!;
    final layout = source.layout.duplicate(
      id: '${id}_layout',
      name: '${source.layout.name} copie',
    );
    final skin = source.skin.duplicate(
      id: '${id}_skin',
      name: '${source.skin.name} copie',
    );
    final pack = CardThemePack(
      id: id,
      name: '${source.pack.name} copie',
      version: 1,
      layoutId: layout.id,
      skinId: skin.id,
      illustrationStyleId: source.pack.illustrationStyleId,
      previewCardId: source.pack.previewCardId,
      minimumRendererVersion: source.pack.minimumRendererVersion,
      premium: source.pack.premium,
    );
    final duplicate = ThemeBundle(
      pack: pack,
      layout: layout,
      skin: skin,
      illustrations: source.illustrations,
    );
    await widget.repository.save(duplicate);
    if (!mounted) return;
    setState(() {
      bundles = [...bundles, duplicate];
      active = duplicate;
      message = '${kind == 'theme' ? 'Theme pack' : kind} dupliqué.';
      _validate();
    });
  }

  Future<void> _save() async {
    try {
      await widget.repository.save(active!);
      if (mounted) setState(() => message = 'Thème sauvegardé.');
    } on Object catch (error) {
      if (mounted) setState(() => message = error.toString());
    }
  }

  Future<void> _delete() async {
    await widget.repository.delete(active!.pack.id);
    final loaded = await widget.repository.loadAll();
    if (!mounted) return;
    setState(() {
      bundles = loaded;
      active = loaded.first;
      message = 'Thème supprimé.';
      _validate();
    });
  }

  Future<void> _export() async {
    await Clipboard.setData(
      ClipboardData(text: widget.repository.export(active!)),
    );
    if (mounted) {
      setState(() => message = 'Manifeste copié dans le presse-papiers.');
    }
  }

  Future<void> _import() async {
    final source = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    if (source == null || source.trim().isEmpty) {
      if (mounted) {
        setState(() => message = 'Le presse-papiers ne contient aucun thème.');
      }
      return;
    }
    try {
      final imported = await widget.repository.import(source);
      if (!mounted) return;
      setState(() {
        bundles = [...bundles, imported];
        active = imported;
        message = 'Thème importé.';
        _validate();
      });
    } on Object catch (error) {
      if (mounted) setState(() => message = error.toString());
    }
  }

  void _validate() {
    if (active != null) issues = const CardThemeValidator().validate(active!);
  }

  List<CardDefinition> _representativeCards() {
    final cards = catalog!.cards.where((card) => card.v3DeckEnabled).toList();
    CardDefinition longest(bool details) => cards.reduce((a, b) {
      final aText = details
          ? (a.descriptionKey ?? '')
          : (a.title ?? a.titleKey ?? '');
      final bText = details
          ? (b.descriptionKey ?? '')
          : (b.title ?? b.titleKey ?? '');
      return aText.length >= bText.length ? a : b;
    });
    CardDefinition spice(int value) => cards.firstWhere(
      (card) => card.variants.any((variant) => variant.chiliLevel == value),
      orElse: () => cards.first,
    );
    final chosen = <CardDefinition>{
      cards.reduce(
        (a, b) => (a.title ?? '').length <= (b.title ?? '').length ? a : b,
      ),
      longest(false),
      longest(true),
      spice(1),
      spice(5),
      ...cards.where((card) => card.directionality != null).take(4),
    };
    return chosen.toList();
  }

  List<CardVariantDefinition> _previewVariants(CardDefinition card) {
    final playable = card.variants
        .where((variant) => variant.v3DeckEnabled)
        .toList();
    return playable.isEmpty ? card.variants : playable;
  }

  CardRenderDefinition _definition(
    CardDefinition card, [
    CardVariantDefinition? selectedVariant,
  ]) => buildCardEditorPreviewDefinition(
    card: card,
    variant: selectedVariant ?? _previewVariants(card).first,
    requestedDirection: directionPreview,
  );
}

CardRenderDefinition buildCardEditorPreviewDefinition({
  required CardDefinition card,
  required CardVariantDefinition variant,
  CardEditorPreviewDirection requestedDirection =
      CardEditorPreviewDirection.faire,
}) {
  final editorial = variant.v3 ?? card.v3;
  final tags = editorial?.tags ?? const <String>[];
  final zones = tags
      .where((tag) => tag.startsWith('v3.zone.'))
      .map((tag) => tag.split('.').last.toUpperCase())
      .toList();
  final previewDirection = switch (card.directionality) {
    CardDirectionality.MUTUAL => CardEditorPreviewDirection.mutuel,
    CardDirectionality.FAIRE => CardEditorPreviewDirection.faire,
    CardDirectionality.RECEVOIR => CardEditorPreviewDirection.recevoir,
    _ => requestedDirection,
  };
  final reversible =
      card.directionality == CardDirectionality.FAIRE_RECEVOIR ||
      card.directionality == null;
  final activePa = switch (previewDirection) {
    CardEditorPreviewDirection.faire => 1,
    CardEditorPreviewDirection.recevoir => 20,
    CardEditorPreviewDirection.mutuel => 8,
  };
  final oppositePa = reversible
      ? switch (previewDirection) {
          CardEditorPreviewDirection.faire => 20,
          CardEditorPreviewDirection.recevoir => 1,
          CardEditorPreviewDirection.mutuel => null,
        }
      : null;
  return CardRenderDefinition(
    cardId: card.stableId,
    variantId: variant.stableId,
    title: variant.title ?? card.title ?? card.titleKey ?? card.stableId,
    subtitle: card.directionality?.name,
    action:
        variant.actionText ??
        card.actionText ??
        variant.instructionKey ??
        card.descriptionKey ??
        '',
    direction: previewDirection.name.toUpperCase(),
    zones: zones,
    spice: variant.chiliLevel,
    personalPa: activePa,
    oppositePa: oppositePa,
    oppositeDirection: reversible
        ? switch (previewDirection) {
            CardEditorPreviewDirection.faire => 'Recevoir',
            CardEditorPreviewDirection.recevoir => 'Faire',
            CardEditorPreviewDirection.mutuel => null,
          }
        : null,
    details:
        variant.detailsText ??
        card.detailsText ??
        (zones.isEmpty ? 'Carte ENCHAIRE' : zones.join(' · ')),
    illustrationId: card.illustrationKey,
  );
}
