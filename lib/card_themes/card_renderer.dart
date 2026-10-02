import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'card_theme_models.dart';
import 'card_theme_registry.dart';

final class CardRenderDefinition {
  const CardRenderDefinition({
    required this.cardId,
    required this.title,
    this.variantId,
    this.subtitle,
    this.action,
    this.direction,
    this.zones = const [],
    this.spice = 1,
    this.personalPa,
    this.details,
    this.illustrationId,
  });

  final String cardId, title;
  final String? variantId, subtitle, action, direction, details, illustrationId;
  final List<String> zones;
  final int spice;
  final int? personalPa;

  CardRenderDefinition copyWith({
    int? personalPa,
    bool removePersonalPa = false,
  }) => CardRenderDefinition(
    cardId: cardId,
    title: title,
    variantId: variantId,
    subtitle: subtitle,
    action: action,
    direction: direction,
    zones: zones,
    spice: spice,
    personalPa: removePersonalPa ? null : (personalPa ?? this.personalPa),
    details: details,
    illustrationId: illustrationId,
  );
}

class CardRenderer extends StatelessWidget {
  const CardRenderer({
    required this.definition,
    this.bundle,
    this.state = CardVisualState.normal,
    this.locked = false,
    this.playerName,
    this.selectedBlockId,
    this.onBlockSelected,
    this.onBlockChanged,
    super.key,
  });

  final CardRenderDefinition definition;
  final ThemeBundle? bundle;
  final CardVisualState state;
  final bool locked;
  final String? playerName, selectedBlockId;
  final ValueChanged<String>? onBlockSelected;
  final ValueChanged<CardLayoutBlock>? onBlockChanged;

  bool get _back => state == CardVisualState.hidden;
  bool get _interactiveEditor => onBlockChanged != null;

  @override
  Widget build(BuildContext context) {
    final theme = bundle ?? CardThemeRegistry.classic;
    final skin = theme.skin;
    final blocks =
        (_back ? theme.layout.back : theme.layout.front)
            .where((block) => block.visible)
            .toList()
          ..sort((a, b) => a.zIndex.compareTo(b.zIndex));
    return LayoutBuilder(
      builder: (context, constraints) {
        var width = constraints.maxWidth;
        var height = constraints.maxHeight;
        if (!width.isFinite && !height.isFinite) width = 280;
        if (!width.isFinite) width = height * theme.layout.aspectRatio;
        if (!height.isFinite) height = width / theme.layout.aspectRatio;
        final expectedHeight = width / theme.layout.aspectRatio;
        if (expectedHeight > height) {
          width = height * theme.layout.aspectRatio;
        } else {
          height = expectedHeight;
        }
        final size = Size(math.max(1, width), math.max(1, height));
        final selected = state == CardVisualState.selected;
        return Center(
          child: SizedBox.fromSize(
            size: size,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color(_back ? skin.backBackground : skin.background),
                borderRadius: BorderRadius.circular(skin.radius),
                border: Border.all(
                  color: Color(selected ? skin.primary : skin.border),
                  width: selected
                      ? math.max(3, skin.borderThickness)
                      : skin.borderThickness,
                ),
                boxShadow: [
                  if (skin.shadow > 0)
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .14),
                      blurRadius: skin.shadow,
                      offset: Offset(0, skin.shadow / 3),
                    ),
                  if (skin.glow > 0)
                    BoxShadow(
                      color: Color(skin.primary).withValues(alpha: .35),
                      blurRadius: skin.glow,
                      spreadRadius: skin.glow / 4,
                    ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(skin.radius),
                child: Stack(
                  children: [
                    for (final block in blocks)
                      _positioned(context, theme, block, size),
                    if (state == CardVisualState.readonly ||
                        state == CardVisualState.discarded ||
                        state == CardVisualState.waiting ||
                        state == CardVisualState.committed)
                      Positioned.fill(child: _stateOverlay(skin)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _positioned(
    BuildContext context,
    ThemeBundle theme,
    CardLayoutBlock block,
    Size size,
  ) {
    final box = block.box;
    final margin = block.margin * size.width;
    final left = box.x * size.width + margin;
    final top = box.y * size.height + margin;
    final width = math.max(1.0, box.width * size.width - margin * 2);
    final height = math.max(1.0, box.height * size.height - margin * 2);
    final selected = selectedBlockId == block.id;
    Widget content = Padding(
      padding: EdgeInsets.all(block.padding * size.width),
      child: _block(context, theme, block, size.width),
    );
    content = Transform.rotate(angle: block.rotation, child: content);
    if (_interactiveEditor) {
      content = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onBlockSelected?.call(block.id),
        onPanUpdate: (details) => onBlockChanged?.call(
          block.copyWith(
            box: box.copyWith(
              x: (box.x + details.delta.dx / size.width).clamp(
                0,
                1 - box.width,
              ),
              y: (box.y + details.delta.dy / size.height).clamp(
                0,
                1 - box.height,
              ),
            ),
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? Colors.blueAccent : Colors.transparent,
              width: 2,
            ),
          ),
          child: Stack(
            children: [
              Positioned.fill(child: content),
              if (selected)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: GestureDetector(
                    key: Key('resize-${block.id}'),
                    onPanUpdate: (details) => onBlockChanged?.call(
                      block.copyWith(
                        box: box.copyWith(
                          width: (box.width + details.delta.dx / size.width)
                              .clamp(.03, 1 - box.x),
                          height: (box.height + details.delta.dy / size.height)
                              .clamp(.03, 1 - box.y),
                        ),
                      ),
                    ),
                    child: const ColoredBox(
                      color: Colors.blueAccent,
                      child: SizedBox(width: 16, height: 16),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }
    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: content,
    );
  }

  Widget _block(
    BuildContext context,
    ThemeBundle theme,
    CardLayoutBlock block,
    double cardWidth,
  ) {
    final skin = theme.skin;
    final scale = (cardWidth / 300).clamp(.35, 1.4);
    final alignment = switch (block.alignment) {
      CardTextAlign.start => TextAlign.start,
      CardTextAlign.center => TextAlign.center,
      CardTextAlign.end => TextAlign.end,
    };
    Text text(String value, CardTextStyleSpec spec, {int? maxLines}) => Text(
      value,
      textAlign: alignment,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: Color(spec.color),
        fontSize: spec.size * scale,
        fontWeight:
            FontWeight.values[((spec.weight / 100).round() - 1).clamp(0, 8)],
        fontFamily: spec.fontFamily,
      ),
    );
    final lockedAtRest = locked || state == CardVisualState.locked;
    final expanded =
        state == CardVisualState.focused || state == CardVisualState.full;
    return switch (block.type) {
      CardBlockType.title => text(
        definition.title,
        skin.titleStyle,
        maxLines: 2,
      ),
      CardBlockType.subtitle => text(
        definition.subtitle ?? '',
        skin.bodyStyle,
        maxLines: 2,
      ),
      CardBlockType.action => text(
        definition.action ?? '',
        skin.bodyStyle,
        maxLines: 3,
      ),
      CardBlockType.direction => text(
        definition.direction ?? '',
        skin.directionStyle ?? skin.badgeStyle,
        maxLines: 1,
      ),
      CardBlockType.zones => text(
        definition.zones.join(' · '),
        skin.badgeStyle,
        maxLines: 1,
      ),
      CardBlockType.spice => text(
        List.filled(definition.spice, '🌶️').join(),
        skin.spiceStyle ?? skin.badgeStyle,
        maxLines: 1,
      ),
      CardBlockType.details => text(
        definition.details ?? '',
        skin.bodyStyle,
        maxLines: 2,
      ),
      CardBlockType.pa => _paBlock(skin, scale, lockedAtRest, expanded),
      CardBlockType.illustration => _illustration(theme, skin),
      CardBlockType.decoration => const SizedBox.shrink(),
      CardBlockType.backIdentity => text(
        'ENCHAIRE',
        skin.titleStyle.copyForBack(),
        maxLines: 1,
      ),
      CardBlockType.backSlogan => text(
        'À deux, chaque choix compte.',
        skin.bodyStyle.copyForBack(),
        maxLines: 2,
      ),
      CardBlockType.backPlayer => text(
        playerName == null ? '' : 'Pour $playerName',
        skin.badgeStyle.copyForBack(),
        maxLines: 1,
      ),
    };
  }

  Widget _paBlock(CardSkin skin, double scale, bool locked, bool expanded) {
    final pa = definition.personalPa;
    final style = skin.paStyle ?? skin.badgeStyle;
    if (locked && !expanded) {
      return Icon(
        Icons.lock_rounded,
        color: Color(skin.primary),
        size: 22 * scale,
      );
    }
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.topRight,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (pa != null)
            Text(
              '$pa/20',
              key: Key('personal-value-${definition.cardId}'),
              style: TextStyle(
                color: Color(style.color),
                fontSize: style.size * scale,
                fontWeight: FontWeight.bold,
              ),
            ),
          if (locked && expanded)
            Icon(
              Icons.lock_rounded,
              color: Color(skin.primary),
              size: 14 * scale,
            ),
        ],
      ),
    );
  }

  Widget _illustration(ThemeBundle theme, CardSkin skin) {
    final asset = theme.illustrationFor(
      definition.cardId,
      theme.pack.illustrationStyleId,
    );
    final placeholder = ColoredBox(
      key: Key('illustration-${definition.cardId}'),
      color: Color(skin.secondary),
      child: Center(
        child: Icon(
          Icons.image_outlined,
          color: Color(skin.primary).withValues(alpha: .55),
        ),
      ),
    );
    if (asset == null || asset.assetPath.isEmpty) return placeholder;
    return Image.asset(
      asset.assetPath,
      fit: BoxFit.cover,
      alignment: Alignment(asset.focusX * 2 - 1, asset.focusY * 2 - 1),
      errorBuilder: (_, _, _) => placeholder,
    );
  }

  Widget _stateOverlay(CardSkin skin) {
    final label = switch (state) {
      CardVisualState.committed => 'CHOISIE',
      CardVisualState.waiting => 'EN ATTENTE',
      CardVisualState.discarded => 'DÉFAUSSÉE',
      CardVisualState.readonly => 'LECTURE',
      _ => '',
    };
    return ColoredBox(
      color: Colors.black.withValues(alpha: .28),
      child: Center(
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

extension on CardTextStyleSpec {
  CardTextStyleSpec copyForBack() => CardTextStyleSpec(
    color: 0xFFFFFFFF,
    size: size,
    weight: weight,
    fontFamily: fontFamily,
  );
}
