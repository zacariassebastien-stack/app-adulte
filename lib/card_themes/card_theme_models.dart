import 'dart:convert';

typedef ThemeJson = Map<String, Object?>;

enum CardBlockType {
  title,
  subtitle,
  illustration,
  action,
  pa,
  spice,
  direction,
  zones,
  details,
  decoration,
  backIdentity,
  backSlogan,
  backPlayer,
}

enum CardTextAlign { start, center, end }

enum CardVisualState {
  normal,
  focused,
  full,
  locked,
  selected,
  committed,
  waiting,
  discarded,
  readonly,
  hidden,
}

final class RelativeBox {
  const RelativeBox({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final double x, y, width, height;

  ThemeJson toJson() => {'x': x, 'y': y, 'width': width, 'height': height};

  factory RelativeBox.fromJson(ThemeJson json) => RelativeBox(
    x: _double(json, 'x'),
    y: _double(json, 'y'),
    width: _double(json, 'width'),
    height: _double(json, 'height'),
  );

  RelativeBox copyWith({double? x, double? y, double? width, double? height}) =>
      RelativeBox(
        x: x ?? this.x,
        y: y ?? this.y,
        width: width ?? this.width,
        height: height ?? this.height,
      );
}

final class CardLayoutBlock {
  const CardLayoutBlock({
    required this.id,
    required this.type,
    required this.box,
    this.alignment = CardTextAlign.start,
    this.rotation = 0,
    this.padding = 0,
    this.margin = 0,
    this.visible = true,
    this.zIndex = 0,
  });

  final String id;
  final CardBlockType type;
  final RelativeBox box;
  final CardTextAlign alignment;
  final double rotation, padding, margin;
  final bool visible;
  final int zIndex;

  ThemeJson toJson() => {
    'id': id,
    'type': type.name,
    'box': box.toJson(),
    'alignment': alignment.name,
    'rotation': rotation,
    'padding': padding,
    'margin': margin,
    'visible': visible,
    'z_index': zIndex,
  };

  factory CardLayoutBlock.fromJson(ThemeJson json) => CardLayoutBlock(
    id: _string(json, 'id'),
    type: CardBlockType.values.byName(_string(json, 'type')),
    box: RelativeBox.fromJson(_map(json, 'box')),
    alignment: CardTextAlign.values.byName(
      (json['alignment'] as String?) ?? CardTextAlign.start.name,
    ),
    rotation: _double(json, 'rotation', fallback: 0),
    padding: _double(json, 'padding', fallback: 0),
    margin: _double(json, 'margin', fallback: 0),
    visible: (json['visible'] as bool?) ?? true,
    zIndex: (json['z_index'] as num?)?.toInt() ?? 0,
  );

  CardLayoutBlock copyWith({
    String? id,
    RelativeBox? box,
    CardTextAlign? alignment,
    double? rotation,
    double? padding,
    double? margin,
    bool? visible,
    int? zIndex,
  }) => CardLayoutBlock(
    id: id ?? this.id,
    type: type,
    box: box ?? this.box,
    alignment: alignment ?? this.alignment,
    rotation: rotation ?? this.rotation,
    padding: padding ?? this.padding,
    margin: margin ?? this.margin,
    visible: visible ?? this.visible,
    zIndex: zIndex ?? this.zIndex,
  );
}

final class CardLayout {
  CardLayout({
    required this.id,
    required this.name,
    required this.version,
    required this.aspectRatio,
    required Iterable<CardLayoutBlock> front,
    required Iterable<CardLayoutBlock> back,
    this.system = false,
  }) : front = List.unmodifiable(front),
       back = List.unmodifiable(back);

  final String id, name;
  final int version;
  final double aspectRatio;
  final List<CardLayoutBlock> front, back;
  final bool system;

  ThemeJson toJson() => {
    'schema_version': 1,
    'id': id,
    'name': name,
    'version': version,
    'aspect_ratio': aspectRatio,
    'system': system,
    'front': front.map((block) => block.toJson()).toList(),
    'back': back.map((block) => block.toJson()).toList(),
  };

  factory CardLayout.fromJson(ThemeJson json) => CardLayout(
    id: _string(json, 'id'),
    name: _string(json, 'name'),
    version: (json['version'] as num?)?.toInt() ?? 1,
    aspectRatio: _double(json, 'aspect_ratio'),
    system: (json['system'] as bool?) ?? false,
    front: _list(
      json,
      'front',
    ).map((item) => CardLayoutBlock.fromJson(item as ThemeJson)),
    back: _list(
      json,
      'back',
    ).map((item) => CardLayoutBlock.fromJson(item as ThemeJson)),
  );

  CardLayout duplicate({required String id, required String name}) =>
      CardLayout(
        id: id,
        name: name,
        version: 1,
        aspectRatio: aspectRatio,
        front: front,
        back: back,
      );

  CardLayout copyWith({
    String? name,
    Iterable<CardLayoutBlock>? front,
    Iterable<CardLayoutBlock>? back,
  }) => CardLayout(
    id: id,
    name: name ?? this.name,
    version: version,
    aspectRatio: aspectRatio,
    front: front ?? this.front,
    back: back ?? this.back,
    system: system,
  );
}

final class CardTextStyleSpec {
  const CardTextStyleSpec({
    required this.color,
    required this.size,
    this.weight = 400,
    this.fontFamily,
    this.fontFamilyFallback = const [],
    this.letterSpacing = 0,
    this.height = 1.2,
  });
  final int color;
  final double size;
  final int weight;
  final String? fontFamily;
  final List<String> fontFamilyFallback;
  final double letterSpacing, height;
  ThemeJson toJson() => {
    'color': color,
    'size': size,
    'weight': weight,
    'font_family': fontFamily,
    'font_family_fallback': fontFamilyFallback,
    'letter_spacing': letterSpacing,
    'height': height,
  };
  factory CardTextStyleSpec.fromJson(ThemeJson json) => CardTextStyleSpec(
    color: (json['color'] as num).toInt(),
    size: _double(json, 'size'),
    weight: (json['weight'] as num?)?.toInt() ?? 400,
    fontFamily: json['font_family'] as String?,
    fontFamilyFallback: List<String>.from(
      (json['font_family_fallback'] as List<Object?>?) ?? const [],
    ),
    letterSpacing: _double(json, 'letter_spacing', fallback: 0),
    height: _double(json, 'height', fallback: 1.2),
  );

  CardTextStyleSpec copyWith({
    int? color,
    double? size,
    int? weight,
    String? fontFamily,
    List<String>? fontFamilyFallback,
    double? letterSpacing,
    double? height,
  }) => CardTextStyleSpec(
    color: color ?? this.color,
    size: size ?? this.size,
    weight: weight ?? this.weight,
    fontFamily: fontFamily ?? this.fontFamily,
    fontFamilyFallback: fontFamilyFallback ?? this.fontFamilyFallback,
    letterSpacing: letterSpacing ?? this.letterSpacing,
    height: height ?? this.height,
  );
}

final class CardSkin {
  const CardSkin({
    required this.id,
    required this.name,
    required this.version,
    required this.background,
    required this.border,
    required this.primary,
    required this.secondary,
    required this.panel,
    required this.backBackground,
    required this.borderThickness,
    required this.radius,
    required this.glow,
    required this.shadow,
    required this.titleStyle,
    required this.bodyStyle,
    required this.badgeStyle,
    this.paStyle,
    this.spiceStyle,
    this.directionStyle,
    this.panelStyle,
    this.backgroundGradientEnd,
    this.textureColor = 0xFFFFFFFF,
    this.textureOpacity = 0,
    this.outerBorderColor,
    this.innerBorderColor,
    this.outerBorderWidth,
    this.innerBorderWidth = 0,
    this.borderGap = 0,
    this.cornerRadius,
    this.glowRadius,
    this.glowIntensity = .5,
    this.glowOpacity = .3,
    this.panelBorderColor,
    this.panelBorderWidth = 0,
    this.panelRadius = 12,
    this.panelShadow = 0,
    this.separatorColor,
    this.decorativeAssets = const [],
    this.system = false,
  });
  final String id, name;
  final int version;
  final int background, border, primary, secondary, panel, backBackground;
  final double borderThickness, radius, glow, shadow;
  final int? backgroundGradientEnd;
  final int textureColor;
  final double textureOpacity;
  final int? outerBorderColor,
      innerBorderColor,
      panelBorderColor,
      separatorColor;
  final double? outerBorderWidth, cornerRadius, glowRadius;
  final double innerBorderWidth, borderGap, glowIntensity, glowOpacity;
  final double panelBorderWidth, panelRadius, panelShadow;
  final CardTextStyleSpec titleStyle, bodyStyle, badgeStyle;
  final CardTextStyleSpec? paStyle, spiceStyle, directionStyle, panelStyle;
  final List<String> decorativeAssets;
  final bool system;

  ThemeJson toJson() => {
    'schema_version': 1,
    'id': id,
    'name': name,
    'version': version,
    'system': system,
    'background': background,
    'border': border,
    'primary': primary,
    'secondary': secondary,
    'panel': panel,
    'back_background': backBackground,
    'border_thickness': borderThickness,
    'radius': radius,
    'glow': glow,
    'shadow': shadow,
    'title_style': titleStyle.toJson(),
    'body_style': bodyStyle.toJson(),
    'badge_style': badgeStyle.toJson(),
    'pa_style': paStyle?.toJson(),
    'spice_style': spiceStyle?.toJson(),
    'direction_style': directionStyle?.toJson(),
    'panel_style': panelStyle?.toJson(),
    'background_gradient_end': backgroundGradientEnd,
    'texture_color': textureColor,
    'texture_opacity': textureOpacity,
    'outer_border_color': resolvedOuterBorderColor,
    'inner_border_color': resolvedInnerBorderColor,
    'outer_border_width': resolvedOuterBorderWidth,
    'inner_border_width': innerBorderWidth,
    'border_gap': borderGap,
    'corner_radius': resolvedCornerRadius,
    'glow_radius': resolvedGlowRadius,
    'glow_intensity': glowIntensity,
    'glow_opacity': glowOpacity,
    'panel_border_color': resolvedPanelBorderColor,
    'panel_border_width': panelBorderWidth,
    'panel_radius': panelRadius,
    'panel_shadow': panelShadow,
    'separator_color': resolvedSeparatorColor,
    'decorative_assets': decorativeAssets,
  };

  factory CardSkin.fromJson(ThemeJson json) => CardSkin(
    id: _string(json, 'id'),
    name: _string(json, 'name'),
    version: (json['version'] as num?)?.toInt() ?? 1,
    system: (json['system'] as bool?) ?? false,
    background: (json['background'] as num).toInt(),
    border: (json['border'] as num).toInt(),
    primary: (json['primary'] as num).toInt(),
    secondary: (json['secondary'] as num).toInt(),
    panel: (json['panel'] as num).toInt(),
    backBackground: (json['back_background'] as num).toInt(),
    borderThickness: _double(json, 'border_thickness'),
    radius: _double(json, 'radius'),
    glow: _double(json, 'glow'),
    shadow: _double(json, 'shadow'),
    titleStyle: CardTextStyleSpec.fromJson(_map(json, 'title_style')),
    bodyStyle: CardTextStyleSpec.fromJson(_map(json, 'body_style')),
    badgeStyle: CardTextStyleSpec.fromJson(_map(json, 'badge_style')),
    paStyle: json['pa_style'] == null
        ? null
        : CardTextStyleSpec.fromJson(json['pa_style']! as ThemeJson),
    spiceStyle: json['spice_style'] == null
        ? null
        : CardTextStyleSpec.fromJson(json['spice_style']! as ThemeJson),
    directionStyle: json['direction_style'] == null
        ? null
        : CardTextStyleSpec.fromJson(json['direction_style']! as ThemeJson),
    panelStyle: json['panel_style'] == null
        ? null
        : CardTextStyleSpec.fromJson(json['panel_style']! as ThemeJson),
    backgroundGradientEnd: (json['background_gradient_end'] as num?)?.toInt(),
    textureColor: (json['texture_color'] as num?)?.toInt() ?? 0xFFFFFFFF,
    textureOpacity: _double(json, 'texture_opacity', fallback: 0),
    outerBorderColor: (json['outer_border_color'] as num?)?.toInt(),
    innerBorderColor: (json['inner_border_color'] as num?)?.toInt(),
    outerBorderWidth: (json['outer_border_width'] as num?)?.toDouble(),
    innerBorderWidth: _double(json, 'inner_border_width', fallback: 0),
    borderGap: _double(json, 'border_gap', fallback: 0),
    cornerRadius: (json['corner_radius'] as num?)?.toDouble(),
    glowRadius: (json['glow_radius'] as num?)?.toDouble(),
    glowIntensity: _double(json, 'glow_intensity', fallback: .5),
    glowOpacity: _double(json, 'glow_opacity', fallback: .3),
    panelBorderColor: (json['panel_border_color'] as num?)?.toInt(),
    panelBorderWidth: _double(json, 'panel_border_width', fallback: 0),
    panelRadius: _double(json, 'panel_radius', fallback: 12),
    panelShadow: _double(json, 'panel_shadow', fallback: 0),
    separatorColor: (json['separator_color'] as num?)?.toInt(),
    decorativeAssets: List<String>.from(
      (json['decorative_assets'] as List<Object?>?) ?? const [],
    ),
  );

  CardSkin duplicate({required String id, required String name}) => CardSkin(
    id: id,
    name: name,
    version: 1,
    background: background,
    border: border,
    primary: primary,
    secondary: secondary,
    panel: panel,
    backBackground: backBackground,
    borderThickness: borderThickness,
    radius: radius,
    glow: glow,
    shadow: shadow,
    titleStyle: titleStyle,
    bodyStyle: bodyStyle,
    badgeStyle: badgeStyle,
    paStyle: paStyle,
    spiceStyle: spiceStyle,
    directionStyle: directionStyle,
    panelStyle: panelStyle,
    backgroundGradientEnd: backgroundGradientEnd,
    textureColor: textureColor,
    textureOpacity: textureOpacity,
    outerBorderColor: outerBorderColor,
    innerBorderColor: innerBorderColor,
    outerBorderWidth: outerBorderWidth,
    innerBorderWidth: innerBorderWidth,
    borderGap: borderGap,
    cornerRadius: cornerRadius,
    glowRadius: glowRadius,
    glowIntensity: glowIntensity,
    glowOpacity: glowOpacity,
    panelBorderColor: panelBorderColor,
    panelBorderWidth: panelBorderWidth,
    panelRadius: panelRadius,
    panelShadow: panelShadow,
    separatorColor: separatorColor,
    decorativeAssets: decorativeAssets,
  );

  CardSkin copyWith({
    String? name,
    int? background,
    int? border,
    int? primary,
    int? secondary,
    int? panel,
    int? backBackground,
    int? backgroundGradientEnd,
    int? textureColor,
    double? textureOpacity,
    double? borderThickness,
    double? radius,
    double? glow,
    double? shadow,
    int? outerBorderColor,
    int? innerBorderColor,
    double? outerBorderWidth,
    double? innerBorderWidth,
    double? borderGap,
    double? cornerRadius,
    double? glowRadius,
    double? glowIntensity,
    double? glowOpacity,
    int? panelBorderColor,
    double? panelBorderWidth,
    double? panelRadius,
    double? panelShadow,
    int? separatorColor,
    CardTextStyleSpec? titleStyle,
    CardTextStyleSpec? bodyStyle,
    CardTextStyleSpec? badgeStyle,
    CardTextStyleSpec? paStyle,
    CardTextStyleSpec? spiceStyle,
    CardTextStyleSpec? directionStyle,
    CardTextStyleSpec? panelStyle,
  }) => CardSkin(
    id: id,
    name: name ?? this.name,
    version: version,
    background: background ?? this.background,
    border: border ?? this.border,
    primary: primary ?? this.primary,
    secondary: secondary ?? this.secondary,
    panel: panel ?? this.panel,
    backBackground: backBackground ?? this.backBackground,
    backgroundGradientEnd: backgroundGradientEnd ?? this.backgroundGradientEnd,
    textureColor: textureColor ?? this.textureColor,
    textureOpacity: textureOpacity ?? this.textureOpacity,
    borderThickness: borderThickness ?? this.borderThickness,
    radius: radius ?? this.radius,
    glow: glow ?? this.glow,
    shadow: shadow ?? this.shadow,
    outerBorderColor: outerBorderColor ?? this.outerBorderColor,
    innerBorderColor: innerBorderColor ?? this.innerBorderColor,
    outerBorderWidth: outerBorderWidth ?? this.outerBorderWidth,
    innerBorderWidth: innerBorderWidth ?? this.innerBorderWidth,
    borderGap: borderGap ?? this.borderGap,
    cornerRadius: cornerRadius ?? this.cornerRadius,
    glowRadius: glowRadius ?? this.glowRadius,
    glowIntensity: glowIntensity ?? this.glowIntensity,
    glowOpacity: glowOpacity ?? this.glowOpacity,
    panelBorderColor: panelBorderColor ?? this.panelBorderColor,
    panelBorderWidth: panelBorderWidth ?? this.panelBorderWidth,
    panelRadius: panelRadius ?? this.panelRadius,
    panelShadow: panelShadow ?? this.panelShadow,
    separatorColor: separatorColor ?? this.separatorColor,
    titleStyle: titleStyle ?? this.titleStyle,
    bodyStyle: bodyStyle ?? this.bodyStyle,
    badgeStyle: badgeStyle ?? this.badgeStyle,
    paStyle: paStyle ?? this.paStyle,
    spiceStyle: spiceStyle ?? this.spiceStyle,
    directionStyle: directionStyle ?? this.directionStyle,
    panelStyle: panelStyle ?? this.panelStyle,
    decorativeAssets: decorativeAssets,
    system: system,
  );

  int get resolvedOuterBorderColor => outerBorderColor ?? border;
  int get resolvedInnerBorderColor => innerBorderColor ?? border;
  int get resolvedPanelBorderColor => panelBorderColor ?? border;
  int get resolvedSeparatorColor => separatorColor ?? secondary;
  double get resolvedOuterBorderWidth => outerBorderWidth ?? borderThickness;
  double get resolvedCornerRadius => cornerRadius ?? radius;
  double get resolvedGlowRadius => glowRadius ?? glow;
}

final class CardThemePack {
  const CardThemePack({
    required this.id,
    required this.name,
    required this.version,
    required this.layoutId,
    required this.skinId,
    this.illustrationStyleId,
    this.previewCardId,
    this.minimumRendererVersion = 1,
    this.premium = false,
    this.system = false,
  });
  final String id, name, layoutId, skinId;
  final int version, minimumRendererVersion;
  final String? illustrationStyleId, previewCardId;
  final bool premium, system;
  ThemeJson toJson() => {
    'schema_version': 1,
    'id': id,
    'name': name,
    'version': version,
    'layout_id': layoutId,
    'skin_id': skinId,
    'illustration_style_id': illustrationStyleId,
    'preview_card_id': previewCardId,
    'minimum_renderer_version': minimumRendererVersion,
    'premium': premium,
    'system': system,
  };
  factory CardThemePack.fromJson(ThemeJson json) => CardThemePack(
    id: _string(json, 'id'),
    name: _string(json, 'name'),
    version: (json['version'] as num?)?.toInt() ?? 1,
    layoutId: _string(json, 'layout_id'),
    skinId: _string(json, 'skin_id'),
    illustrationStyleId: json['illustration_style_id'] as String?,
    previewCardId: json['preview_card_id'] as String?,
    minimumRendererVersion:
        (json['minimum_renderer_version'] as num?)?.toInt() ?? 1,
    premium: (json['premium'] as bool?) ?? false,
    system: (json['system'] as bool?) ?? false,
  );
  CardThemePack duplicate({required String id, required String name}) =>
      CardThemePack(
        id: id,
        name: name,
        version: 1,
        layoutId: layoutId,
        skinId: skinId,
        illustrationStyleId: illustrationStyleId,
        previewCardId: previewCardId,
        minimumRendererVersion: minimumRendererVersion,
        premium: premium,
      );
}

final class IllustrationAsset {
  const IllustrationAsset({
    required this.illustrationId,
    required this.cardId,
    required this.styleId,
    required this.assetPath,
    this.focusX = .5,
    this.focusY = .5,
    this.safeArea,
  });
  final String illustrationId, cardId, styleId, assetPath;
  final double focusX, focusY;
  final RelativeBox? safeArea;
  ThemeJson toJson() => {
    'illustration_id': illustrationId,
    'card_id': cardId,
    'style_id': styleId,
    'asset_path': assetPath,
    'focus_x': focusX,
    'focus_y': focusY,
    'safe_area': safeArea?.toJson(),
  };
  factory IllustrationAsset.fromJson(ThemeJson json) => IllustrationAsset(
    illustrationId: _string(json, 'illustration_id'),
    cardId: _string(json, 'card_id'),
    styleId: _string(json, 'style_id'),
    assetPath: _string(json, 'asset_path'),
    focusX: _double(json, 'focus_x', fallback: .5),
    focusY: _double(json, 'focus_y', fallback: .5),
    safeArea: json['safe_area'] == null
        ? null
        : RelativeBox.fromJson(json['safe_area']! as ThemeJson),
  );
}

final class ThemeBundle {
  const ThemeBundle({
    required this.pack,
    required this.layout,
    required this.skin,
    this.illustrations = const [],
  });
  final CardThemePack pack;
  final CardLayout layout;
  final CardSkin skin;
  final List<IllustrationAsset> illustrations;

  String export() => const JsonEncoder.withIndent('  ').convert({
    'schema_version': 1,
    'pack': pack.toJson(),
    'layout': layout.toJson(),
    'skin': skin.toJson(),
    'illustrations': illustrations.map((asset) => asset.toJson()).toList(),
  });

  factory ThemeBundle.import(String source) {
    final json = jsonDecode(source) as ThemeJson;
    if (json['schema_version'] != 1) {
      throw const FormatException('Unsupported theme schema version');
    }
    return ThemeBundle(
      pack: CardThemePack.fromJson(_map(json, 'pack')),
      layout: CardLayout.fromJson(_map(json, 'layout')),
      skin: CardSkin.fromJson(_map(json, 'skin')),
      illustrations: ((json['illustrations'] as List<Object?>?) ?? const [])
          .map((item) => IllustrationAsset.fromJson(item! as ThemeJson))
          .toList(),
    );
  }

  IllustrationAsset? illustrationFor(String cardId, String? styleId) {
    IllustrationAsset? fallback;
    for (final asset in illustrations) {
      if (asset.cardId != cardId) continue;
      if (asset.styleId == styleId) return asset;
      if (asset.styleId == 'default') fallback = asset;
    }
    return fallback;
  }
}

String _string(ThemeJson json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Missing $key');
  }
  return value;
}

double _double(ThemeJson json, String key, {double? fallback}) {
  final value = json[key];
  if (value == null && fallback != null) return fallback;
  if (value is! num) throw FormatException('Invalid $key');
  return value.toDouble();
}

ThemeJson _map(ThemeJson json, String key) => json[key]! as ThemeJson;
List<Object?> _list(ThemeJson json, String key) => json[key]! as List<Object?>;
