import 'card_theme_models.dart';

abstract final class ClassicCardTheme {
  static final CardLayout layout = CardLayout(
    id: 'classic_v1',
    name: 'Classic V1',
    version: 1,
    aspectRatio: 0.7,
    system: true,
    front: const [
      CardLayoutBlock(
        id: 'direction',
        type: CardBlockType.direction,
        box: RelativeBox(x: .06, y: .04, width: .54, height: .07),
        zIndex: 2,
      ),
      CardLayoutBlock(
        id: 'pa',
        type: CardBlockType.pa,
        box: RelativeBox(x: .78, y: .035, width: .16, height: .08),
        alignment: CardTextAlign.end,
        zIndex: 3,
      ),
      CardLayoutBlock(
        id: 'illustration',
        type: CardBlockType.illustration,
        box: RelativeBox(x: .06, y: .13, width: .88, height: .43),
        zIndex: 0,
      ),
      CardLayoutBlock(
        id: 'title',
        type: CardBlockType.title,
        box: RelativeBox(x: .06, y: .59, width: .88, height: .10),
        zIndex: 2,
      ),
      CardLayoutBlock(
        id: 'action',
        type: CardBlockType.action,
        box: RelativeBox(x: .06, y: .69, width: .88, height: .11),
        zIndex: 2,
      ),
      CardLayoutBlock(
        id: 'zones',
        type: CardBlockType.zones,
        box: RelativeBox(x: .06, y: .81, width: .55, height: .06),
        zIndex: 2,
      ),
      CardLayoutBlock(
        id: 'spice',
        type: CardBlockType.spice,
        box: RelativeBox(x: .06, y: .89, width: .42, height: .07),
        zIndex: 2,
      ),
      CardLayoutBlock(
        id: 'details',
        type: CardBlockType.details,
        box: RelativeBox(x: .5, y: .89, width: .44, height: .07),
        alignment: CardTextAlign.end,
        zIndex: 2,
      ),
    ],
    back: const [
      CardLayoutBlock(
        id: 'back_identity',
        type: CardBlockType.backIdentity,
        box: RelativeBox(x: .08, y: .30, width: .84, height: .15),
        alignment: CardTextAlign.center,
      ),
      CardLayoutBlock(
        id: 'back_slogan',
        type: CardBlockType.backSlogan,
        box: RelativeBox(x: .12, y: .48, width: .76, height: .10),
        alignment: CardTextAlign.center,
      ),
      CardLayoutBlock(
        id: 'back_player',
        type: CardBlockType.backPlayer,
        box: RelativeBox(x: .12, y: .72, width: .76, height: .08),
        alignment: CardTextAlign.center,
      ),
    ],
  );

  static const CardSkin skin = CardSkin(
    id: 'classic_v1',
    name: 'Classic V1',
    version: 1,
    system: true,
    background: 0xFFF5EFF4,
    border: 0xFFD8C8D5,
    primary: 0xFF73546F,
    secondary: 0xFFEADDE8,
    panel: 0xFFF0E6EE,
    backBackground: 0xFF73546F,
    borderThickness: 1,
    radius: 18,
    glow: 0,
    shadow: 8,
    titleStyle: CardTextStyleSpec(color: 0xFF2C252B, size: 18, weight: 700),
    bodyStyle: CardTextStyleSpec(color: 0xFF4F454D, size: 12),
    badgeStyle: CardTextStyleSpec(color: 0xFF73546F, size: 11, weight: 700),
    paStyle: CardTextStyleSpec(color: 0xFF73546F, size: 11, weight: 700),
    spiceStyle: CardTextStyleSpec(color: 0xFF73546F, size: 11),
    directionStyle: CardTextStyleSpec(color: 0xFF73546F, size: 11, weight: 700),
    panelStyle: CardTextStyleSpec(color: 0xFF4F454D, size: 12),
  );

  static const CardThemePack pack = CardThemePack(
    id: 'classic_v1',
    name: 'Classic V1',
    version: 1,
    layoutId: 'classic_v1',
    skinId: 'classic_v1',
    illustrationStyleId: 'default',
    system: true,
  );

  static final ThemeBundle bundle = ThemeBundle(
    pack: pack,
    layout: layout,
    skin: skin,
  );
}
