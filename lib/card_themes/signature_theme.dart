import 'card_theme_models.dart';

/// Canonical ENCHAIRE visual language derived from the approved collector-card
/// reference. It remains data-driven so the Windows editor can alter every
/// layout and skin value without changing the renderer.
abstract final class EnchaireSignatureTheme {
  static const id = 'enchaire_signature_v1';

  static final CardLayout layout = CardLayout(
    id: id,
    name: 'ENCHAIRE Signature V1',
    version: 1,
    aspectRatio: .7,
    system: true,
    front: const [
      CardLayoutBlock(
        id: 'illustration',
        type: CardBlockType.illustration,
        box: RelativeBox(x: .045, y: .04, width: .62, height: .44),
      ),
      CardLayoutBlock(
        id: 'direction',
        type: CardBlockType.direction,
        box: RelativeBox(x: .045, y: .04, width: .38, height: .095),
        padding: .018,
        zIndex: 3,
      ),
      CardLayoutBlock(
        id: 'spice',
        type: CardBlockType.spice,
        box: RelativeBox(x: .69, y: .04, width: .265, height: .105),
        padding: .018,
        zIndex: 3,
      ),
      CardLayoutBlock(
        id: 'pa',
        type: CardBlockType.pa,
        box: RelativeBox(x: .69, y: .155, width: .265, height: .185),
        padding: .018,
        zIndex: 3,
      ),
      CardLayoutBlock(
        id: 'zones',
        type: CardBlockType.zones,
        box: RelativeBox(x: .69, y: .35, width: .265, height: .13),
        padding: .018,
        zIndex: 3,
      ),
      CardLayoutBlock(
        id: 'title',
        type: CardBlockType.title,
        box: RelativeBox(x: .055, y: .50, width: .89, height: .105),
        alignment: CardTextAlign.center,
        zIndex: 2,
      ),
      CardLayoutBlock(
        id: 'action',
        type: CardBlockType.action,
        box: RelativeBox(x: .045, y: .62, width: .91, height: .17),
        padding: .025,
        zIndex: 2,
      ),
      CardLayoutBlock(
        id: 'details',
        type: CardBlockType.details,
        box: RelativeBox(x: .045, y: .80, width: .91, height: .155),
        padding: .025,
        zIndex: 2,
      ),
    ],
    back: const [
      CardLayoutBlock(
        id: 'ornament_top',
        type: CardBlockType.decoration,
        box: RelativeBox(x: .15, y: .12, width: .70, height: .23),
      ),
      CardLayoutBlock(
        id: 'back_identity',
        type: CardBlockType.backIdentity,
        box: RelativeBox(x: .08, y: .36, width: .84, height: .12),
        alignment: CardTextAlign.center,
        zIndex: 1,
      ),
      CardLayoutBlock(
        id: 'back_slogan',
        type: CardBlockType.backSlogan,
        box: RelativeBox(x: .12, y: .49, width: .76, height: .08),
        alignment: CardTextAlign.center,
        zIndex: 1,
      ),
      CardLayoutBlock(
        id: 'ornament_bottom',
        type: CardBlockType.decoration,
        box: RelativeBox(x: .15, y: .58, width: .70, height: .20),
      ),
      CardLayoutBlock(
        id: 'back_player',
        type: CardBlockType.backPlayer,
        box: RelativeBox(x: .20, y: .88, width: .60, height: .05),
        alignment: CardTextAlign.center,
        zIndex: 1,
      ),
    ],
  );

  static const CardSkin skin = CardSkin(
    id: id,
    name: 'ENCHAIRE Signature V1',
    version: 1,
    system: true,
    background: 0xFF0D0C0E,
    backgroundGradientEnd: 0xFF191316,
    textureColor: 0xFFFFE9E4,
    textureOpacity: .022,
    border: 0xFFFF527A,
    primary: 0xFFFF3F70,
    secondary: 0xFF251C21,
    panel: 0xE6110F12,
    backBackground: 0xFF0A090B,
    borderThickness: 3,
    radius: 28,
    glow: 12,
    shadow: 16,
    outerBorderColor: 0xFFFF527A,
    innerBorderColor: 0xFFF7A0B4,
    outerBorderWidth: 3,
    innerBorderWidth: 1.15,
    borderGap: 9,
    cornerRadius: 28,
    glowRadius: 12,
    glowIntensity: .45,
    glowOpacity: .28,
    panelBorderColor: 0xFF80666D,
    panelBorderWidth: .8,
    panelRadius: 11,
    panelShadow: 4,
    separatorColor: 0xFF8C6E76,
    titleStyle: CardTextStyleSpec(
      color: 0xFFFFF7F2,
      size: 25,
      weight: 600,
      fontFamily: 'Georgia',
      fontFamilyFallback: ['Noto Serif', 'serif'],
      letterSpacing: .15,
      height: 1.02,
    ),
    bodyStyle: CardTextStyleSpec(
      color: 0xFFEDE4E0,
      size: 11.5,
      fontFamily: 'Segoe UI',
      fontFamilyFallback: ['Roboto', 'sans-serif'],
      height: 1.32,
    ),
    badgeStyle: CardTextStyleSpec(
      color: 0xFFF8EFEB,
      size: 8.5,
      weight: 600,
      fontFamily: 'Segoe UI',
      fontFamilyFallback: ['Roboto', 'sans-serif'],
      letterSpacing: 1.55,
      height: 1.1,
    ),
    paStyle: CardTextStyleSpec(
      color: 0xFFFF4777,
      size: 22,
      weight: 700,
      fontFamily: 'Segoe UI',
      fontFamilyFallback: ['Roboto', 'sans-serif'],
      height: 1,
    ),
    spiceStyle: CardTextStyleSpec(
      color: 0xFFFF4777,
      size: 11,
      weight: 600,
      fontFamily: 'Segoe UI',
      fontFamilyFallback: ['Roboto', 'sans-serif'],
    ),
    directionStyle: CardTextStyleSpec(
      color: 0xFFFFF4EF,
      size: 10,
      weight: 600,
      fontFamily: 'Segoe UI',
      fontFamilyFallback: ['Roboto', 'sans-serif'],
      letterSpacing: 1.35,
    ),
    panelStyle: CardTextStyleSpec(
      color: 0xFFD7C8C4,
      size: 9.5,
      fontFamily: 'Segoe UI',
      fontFamilyFallback: ['Roboto', 'sans-serif'],
      height: 1.28,
    ),
  );

  static const CardThemePack pack = CardThemePack(
    id: id,
    name: 'ENCHAIRE Signature V1',
    version: 1,
    layoutId: id,
    skinId: id,
    illustrationStyleId: 'signature',
    previewCardId: 'card.kiss_me',
    premium: true,
    system: true,
  );

  static final ThemeBundle bundle = ThemeBundle(
    pack: pack,
    layout: layout,
    skin: skin,
  );
}
