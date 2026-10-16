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
    this.oppositePa,
    this.oppositeDirection,
    this.details,
    this.illustrationId,
  });

  final String cardId, title;
  final String? variantId, subtitle, action, direction, details, illustrationId;
  final List<String> zones;
  final int spice;
  final int? personalPa;
  final int? oppositePa;
  final String? oppositeDirection;

  CardRenderDefinition copyWith({
    int? personalPa,
    int? oppositePa,
    String? oppositeDirection,
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
    oppositePa: removePersonalPa ? null : (oppositePa ?? this.oppositePa),
    oppositeDirection: oppositeDirection ?? this.oppositeDirection,
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
    this.illustrationProvider,
    super.key,
  });

  final CardRenderDefinition definition;
  final ThemeBundle? bundle;
  final CardVisualState state;
  final bool locked;
  final String? playerName, selectedBlockId;
  final ValueChanged<String>? onBlockSelected;
  final ValueChanged<CardLayoutBlock>? onBlockChanged;
  final ImageProvider<Object>? Function(IllustrationAsset asset)?
  illustrationProvider;

  bool get _back => state == CardVisualState.hidden;
  bool get _interactiveEditor => onBlockChanged != null;

  @override
  Widget build(BuildContext context) {
    final theme = bundle ?? CardThemeRegistry.selected;
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
              key: const Key('card-outer-frame'),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: _back
                      ? [
                          Color(skin.backBackground),
                          Color(skin.backgroundGradientEnd ?? skin.background),
                        ]
                      : [
                          Color(skin.background),
                          Color(skin.backgroundGradientEnd ?? skin.background),
                        ],
                ),
                borderRadius: BorderRadius.circular(skin.resolvedCornerRadius),
                border: Border.all(
                  color: Color(
                    selected ? skin.primary : skin.resolvedOuterBorderColor,
                  ),
                  width: selected
                      ? math.max(3, skin.resolvedOuterBorderWidth)
                      : skin.resolvedOuterBorderWidth,
                ),
                boxShadow: [
                  if (skin.shadow > 0)
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .14),
                      blurRadius: skin.shadow,
                      offset: Offset(0, skin.shadow / 3),
                    ),
                  if (skin.resolvedGlowRadius > 0)
                    BoxShadow(
                      color: Color(skin.primary).withValues(
                        alpha: (skin.glowOpacity * skin.glowIntensity).clamp(
                          0,
                          1,
                        ),
                      ),
                      blurRadius: skin.resolvedGlowRadius,
                      spreadRadius: skin.glowIntensity * 2,
                    ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(
                  math.max(
                    0,
                    skin.resolvedCornerRadius - skin.resolvedOuterBorderWidth,
                  ),
                ),
                child: Stack(
                  children: [
                    if (skin.textureOpacity > 0)
                      Positioned.fill(
                        child: CustomPaint(
                          key: const Key('card-texture'),
                          painter: _CardTexturePainter(
                            color: Color(skin.textureColor),
                            opacity: skin.textureOpacity,
                          ),
                        ),
                      ),
                    for (final block in blocks.where(
                      (block) => block.type == CardBlockType.illustration,
                    ))
                      _positioned(context, theme, block, size),
                    if (skin.innerBorderWidth > 0)
                      Positioned.fill(
                        child: Padding(
                          padding: EdgeInsets.all(
                            skin.resolvedOuterBorderWidth + skin.borderGap,
                          ),
                          child: IgnorePointer(
                            child: DecoratedBox(
                              key: const Key('card-inner-border'),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(
                                  math.max(
                                    0,
                                    skin.resolvedCornerRadius -
                                        skin.borderGap -
                                        skin.resolvedOuterBorderWidth,
                                  ),
                                ),
                                border: Border.all(
                                  color: Color(skin.resolvedInnerBorderColor),
                                  width: skin.innerBorderWidth,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    for (final block in blocks.where(
                      (block) => block.type != CardBlockType.illustration,
                    ))
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
    if (_usesPanel(block.type) && theme.skin.panelBorderWidth > 0) {
      content = DecoratedBox(
        key: Key('card-panel-${block.id}'),
        decoration: BoxDecoration(
          color: Color(theme.skin.panel),
          borderRadius: BorderRadius.circular(theme.skin.panelRadius),
          border: Border.all(
            color: Color(theme.skin.resolvedPanelBorderColor),
            width: theme.skin.panelBorderWidth,
          ),
          boxShadow: [
            if (theme.skin.panelShadow > 0)
              BoxShadow(
                color: Colors.black.withValues(alpha: .22),
                blurRadius: theme.skin.panelShadow,
                offset: Offset(0, theme.skin.panelShadow / 3),
              ),
          ],
        ),
        child: content,
      );
    }
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
                        box: _resizedBox(theme, block, size, details.delta),
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
      key: Key('card-block-${block.id}'),
      left: left,
      top: top,
      width: width,
      height: height,
      child: content,
    );
  }

  RelativeBox _resizedBox(
    ThemeBundle theme,
    CardLayoutBlock block,
    Size size,
    Offset delta,
  ) {
    final box = block.box;
    final preserve =
        block.type == CardBlockType.illustration &&
        (theme
                .illustrationFor(
                  definition.cardId,
                  theme.pack.illustrationStyleId,
                )
                ?.preserveAspectRatio ??
            true);
    if (!preserve) {
      return box.copyWith(
        width: (box.width + delta.dx / size.width).clamp(.03, 1 - box.x),
        height: (box.height + delta.dy / size.height).clamp(.03, 1 - box.y),
      );
    }
    final ratio = box.width / box.height;
    var width = (box.width + delta.dx / size.width).clamp(.03, 1 - box.x);
    var height = width / ratio;
    if (height > 1 - box.y) {
      height = 1 - box.y;
      width = height * ratio;
    }
    return box.copyWith(width: width, height: height);
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
        fontFamilyFallback: spec.fontFamilyFallback,
        letterSpacing: spec.letterSpacing * scale,
        height: spec.height,
      ),
    );
    final lockedAtRest = locked || state == CardVisualState.locked;
    final expanded =
        state == CardVisualState.focused || state == CardVisualState.full;
    final premiumExpanded = skin.panelBorderWidth > 0 && expanded;
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
      CardBlockType.action =>
        premiumExpanded
            ? _labeledPanelContent(
                icon: Icons.adjust_rounded,
                label: 'ACTION',
                value: definition.action ?? '',
                skin: skin,
                scale: scale,
                maxLines: 4,
              )
            : text(definition.action ?? '', skin.bodyStyle, maxLines: 3),
      CardBlockType.direction =>
        premiumExpanded
            ? _labeledPanelContent(
                icon: Icons.auto_awesome_outlined,
                label: 'SENSATION',
                value: definition.direction ?? 'GÉNÉRAL',
                skin: skin,
                scale: scale,
                maxLines: 1,
              )
            : text(
                definition.direction ?? '',
                skin.directionStyle ?? skin.badgeStyle,
                maxLines: 1,
              ),
      CardBlockType.zones =>
        premiumExpanded
            ? _labeledPanelContent(
                icon: Icons.place_outlined,
                label: 'ZONES / NOMBRE',
                value: definition.zones.isEmpty
                    ? 'LIBRE'
                    : '${definition.zones.join(' · ')}  ${definition.zones.length}',
                skin: skin,
                scale: scale,
                maxLines: 2,
              )
            : text(definition.zones.join(' · '), skin.badgeStyle, maxLines: 1),
      CardBlockType.spice =>
        premiumExpanded
            ? _spiceBlock(skin, scale)
            : text(
                List.filled(definition.spice, '🌶️').join(),
                skin.spiceStyle ?? skin.badgeStyle,
                maxLines: 1,
              ),
      CardBlockType.details =>
        premiumExpanded
            ? _labeledPanelContent(
                icon: Icons.info_outline_rounded,
                label: 'PRÉCISIONS',
                value: definition.details ?? 'Aucune précision supplémentaire.',
                skin: skin,
                scale: scale,
                maxLines: 4,
                muted: true,
              )
            : text(definition.details ?? '', skin.bodyStyle, maxLines: 2),
      CardBlockType.pa => _paBlock(skin, scale, lockedAtRest, expanded),
      CardBlockType.illustration => _illustration(theme, skin),
      CardBlockType.decoration => _ornament(block.id, skin),
      CardBlockType.backIdentity => _backIdentity(skin, scale),
      CardBlockType.backSlogan => text(
        'En chair et en cartes.',
        skin.bodyStyle.copyForBack(),
        maxLines: 2,
      ),
      CardBlockType.backPlayer => text(
        playerName?.toUpperCase() ?? '',
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
          if (skin.panelBorderWidth > 0 && expanded && scale >= .72)
            Text(
              'VALEUR PERSONNELLE',
              style: _textStyle(skin.badgeStyle, scale),
            ),
          if (skin.panelBorderWidth > 0 && expanded && scale >= .72)
            SizedBox(height: 4 * scale),
          if (pa != null)
            Text(
              '$pa PA',
              key: Key('personal-value-${definition.cardId}'),
              style: TextStyle(
                color: Color(style.color),
                fontSize: style.size * scale,
                fontWeight: FontWeight.bold,
                fontFamily: style.fontFamily,
                fontFamilyFallback: style.fontFamilyFallback,
                letterSpacing: style.letterSpacing * scale,
                height: style.height,
              ),
            ),
          if (expanded &&
              definition.oppositePa != null &&
              definition.oppositeDirection != null)
            Text(
              '${definition.oppositeDirection} : ${definition.oppositePa} PA',
              key: Key('opposite-value-${definition.cardId}'),
              style: TextStyle(
                color: Color(style.color).withValues(alpha: .78),
                fontSize: style.size * scale * .48,
                fontWeight: FontWeight.w500,
                fontFamily: skin.bodyStyle.fontFamily,
                fontFamilyFallback: skin.bodyStyle.fontFamilyFallback,
                letterSpacing: skin.bodyStyle.letterSpacing * scale,
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
    final provider = asset == null ? null : illustrationProvider?.call(asset);
    final image = asset == null || asset.assetPath.isEmpty
        ? placeholder
        : Opacity(
            key: Key('illustration-opacity-${definition.cardId}'),
            opacity: asset.opacity.clamp(0, 1),
            child: Image(
              key: Key('illustration-${definition.cardId}'),
              image: provider ?? AssetImage(asset.assetPath),
              fit: asset.fit == IllustrationFit.contain
                  ? BoxFit.contain
                  : BoxFit.cover,
              alignment: Alignment(asset.focusX * 2 - 1, asset.focusY * 2 - 1),
              errorBuilder: (_, _, _) => placeholder,
            ),
          );
    return ClipRRect(
      borderRadius: BorderRadius.circular(skin.panelRadius),
      child: image,
    );
  }

  bool _usesPanel(CardBlockType type) => switch (type) {
    CardBlockType.action ||
    CardBlockType.details ||
    CardBlockType.direction ||
    CardBlockType.pa ||
    CardBlockType.spice ||
    CardBlockType.zones => true,
    _ => false,
  };

  Widget _labeledPanelContent({
    required IconData icon,
    required String label,
    required String value,
    required CardSkin skin,
    required double scale,
    required int maxLines,
    bool muted = false,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.max,
    children: [
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14 * scale, color: Color(skin.primary)),
          SizedBox(width: 6 * scale),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _textStyle(skin.badgeStyle, scale),
            ),
          ),
        ],
      ),
      SizedBox(height: 5 * scale),
      Expanded(
        child: Text(
          value,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          style: _textStyle(
            muted ? (skin.panelStyle ?? skin.bodyStyle) : skin.bodyStyle,
            scale,
          ),
        ),
      ),
    ],
  );

  Widget _spiceBlock(CardSkin skin, double scale) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.max,
    children: [
      Text('PIMENT', style: _textStyle(skin.badgeStyle, scale)),
      const Spacer(),
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          children: [
            Text(
              List.filled(definition.spice, '🌶').join(),
              style: _textStyle(skin.spiceStyle ?? skin.badgeStyle, scale),
            ),
            SizedBox(width: 4 * scale),
            Text(
              '${definition.spice}',
              style: _textStyle(
                (skin.paStyle ?? skin.badgeStyle).copyWith(size: 16),
                scale,
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _backIdentity(CardSkin skin, double scale) => FittedBox(
    fit: BoxFit.scaleDown,
    child: Text.rich(
      TextSpan(
        style: _textStyle(skin.titleStyle.copyForBack(), scale),
        children: [
          const TextSpan(text: 'EN'),
          TextSpan(
            text: 'CHA',
            style: TextStyle(color: Color(skin.primary)),
          ),
          const TextSpan(text: 'IRE'),
        ],
      ),
    ),
  );

  Widget _ornament(String id, CardSkin skin) => CustomPaint(
    key: Key('card-$id'),
    painter: _SignatureOrnamentPainter(
      color: Color(skin.innerBorderColor ?? skin.primary),
      inverted: id.contains('bottom'),
    ),
  );

  TextStyle _textStyle(CardTextStyleSpec spec, double scale) => TextStyle(
    color: Color(spec.color),
    fontSize: spec.size * scale,
    fontWeight:
        FontWeight.values[((spec.weight / 100).round() - 1).clamp(0, 8)],
    fontFamily: spec.fontFamily,
    fontFamilyFallback: spec.fontFamilyFallback,
    letterSpacing: spec.letterSpacing * scale,
    height: spec.height,
  );

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
    fontFamilyFallback: fontFamilyFallback,
    letterSpacing: letterSpacing,
    height: height,
  );
}

final class _CardTexturePainter extends CustomPainter {
  const _CardTexturePainter({required this.color, required this.opacity});
  final Color color;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color.withValues(alpha: opacity);
    const spacing = 13.0;
    for (var y = 5.0; y < size.height; y += spacing) {
      final row = (y / spacing).floor();
      for (var x = row.isEven ? 4.0 : 10.0; x < size.width; x += 19) {
        final pulse = ((x * 17 + y * 31).round() % 5) / 10 + .35;
        paint.color = color.withValues(alpha: opacity * pulse);
        canvas.drawCircle(Offset(x, y), .42, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_CardTexturePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.opacity != opacity;
}

final class _SignatureOrnamentPainter extends CustomPainter {
  const _SignatureOrnamentPainter({
    required this.color,
    required this.inverted,
  });
  final Color color;
  final bool inverted;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: .82)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(.8, size.width / 280);
    final center = Offset(size.width / 2, size.height / 2);
    final direction = inverted ? -1.0 : 1.0;
    final path = Path()
      ..moveTo(size.width * .06, center.dy)
      ..lineTo(size.width * .34, center.dy)
      ..moveTo(size.width * .66, center.dy)
      ..lineTo(size.width * .94, center.dy)
      ..moveTo(center.dx, center.dy - direction * size.height * .34)
      ..cubicTo(
        size.width * .38,
        center.dy - direction * size.height * .08,
        size.width * .38,
        center.dy + direction * size.height * .22,
        center.dx,
        center.dy + direction * size.height * .30,
      )
      ..cubicTo(
        size.width * .62,
        center.dy + direction * size.height * .22,
        size.width * .62,
        center.dy - direction * size.height * .08,
        center.dx,
        center.dy - direction * size.height * .34,
      );
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_SignatureOrnamentPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.inverted != inverted;
}
