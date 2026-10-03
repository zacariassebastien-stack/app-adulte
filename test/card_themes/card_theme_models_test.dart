import 'package:couple_cards/card_themes/card_theme_models.dart';
import 'package:couple_cards/card_themes/card_theme_repository.dart';
import 'package:couple_cards/card_themes/card_theme_validator.dart';
import 'package:couple_cards/card_themes/classic_theme.dart';
import 'package:couple_cards/card_themes/signature_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('card theme format', () {
    test('classic layout uses relative coordinates and round-trips', () {
      final decoded = CardLayout.fromJson(ClassicCardTheme.layout.toJson());

      expect(decoded.id, 'classic_v1');
      expect(decoded.front, hasLength(ClassicCardTheme.layout.front.length));
      expect(
        decoded.front.every(
          (block) =>
              block.box.x >= 0 &&
              block.box.y >= 0 &&
              block.box.x + block.box.width <= 1 &&
              block.box.y + block.box.height <= 1,
        ),
        isTrue,
      );
    });

    test('skin, layout and theme duplication receive editable IDs', () {
      final layout = ClassicCardTheme.layout.duplicate(
        id: 'layout_copy',
        name: 'Copie',
      );
      final skin = ClassicCardTheme.skin.duplicate(
        id: 'skin_copy',
        name: 'Copie',
      );
      final pack = ClassicCardTheme.pack.duplicate(
        id: 'pack_copy',
        name: 'Copie',
      );

      expect(layout.system, isFalse);
      expect(skin.system, isFalse);
      expect(pack.system, isFalse);
      expect(layout.id, 'layout_copy');
      expect(skin.id, 'skin_copy');
      expect(pack.id, 'pack_copy');
    });

    test('signature skin preserves premium frame and typography controls', () {
      final restored = CardSkin.fromJson(EnchaireSignatureTheme.skin.toJson());

      expect(restored.id, 'enchaire_signature_v1');
      expect(restored.resolvedOuterBorderColor, 0xFFFF527A);
      expect(restored.resolvedInnerBorderColor, 0xFFF7A0B4);
      expect(restored.innerBorderWidth, greaterThan(0));
      expect(restored.borderGap, greaterThan(0));
      expect(restored.textureOpacity, inInclusiveRange(0, .05));
      expect(restored.panelBorderWidth, greaterThan(0));
      expect(restored.titleStyle.fontFamily, 'Georgia');
      expect(restored.titleStyle.fontFamilyFallback, contains('Noto Serif'));
      expect(restored.badgeStyle.letterSpacing, greaterThan(1));
    });

    test('theme manifest export and import preserve every model', () {
      final source = ThemeBundle(
        pack: const CardThemePack(
          id: 'pack',
          name: 'Pack',
          version: 2,
          layoutId: 'layout',
          skinId: 'skin',
          illustrationStyleId: 'anime',
        ),
        layout: ClassicCardTheme.layout.duplicate(id: 'layout', name: 'Layout'),
        skin: ClassicCardTheme.skin.duplicate(id: 'skin', name: 'Skin'),
        illustrations: const [
          IllustrationAsset(
            illustrationId: 'alt',
            cardId: 'card.a',
            styleId: 'anime',
            assetPath: 'assets/a.png',
          ),
        ],
      );

      final restored = ThemeBundle.import(source.export());

      expect(restored.pack.toJson(), source.pack.toJson());
      expect(restored.layout.toJson(), source.layout.toJson());
      expect(restored.skin.toJson(), source.skin.toJson());
      expect(restored.illustrations.single.assetPath, 'assets/a.png');
    });

    test('illustration style falls back to default', () {
      final bundle = ThemeBundle(
        pack: ClassicCardTheme.pack,
        layout: ClassicCardTheme.layout,
        skin: ClassicCardTheme.skin,
        illustrations: const [
          IllustrationAsset(
            illustrationId: 'default-a',
            cardId: 'card.a',
            styleId: 'default',
            assetPath: 'default.png',
          ),
          IllustrationAsset(
            illustrationId: 'velvet-a',
            cardId: 'card.a',
            styleId: 'velvet',
            assetPath: 'velvet.png',
          ),
        ],
      );

      expect(
        bundle.illustrationFor('card.a', 'velvet')!.assetPath,
        'velvet.png',
      );
      expect(
        bundle.illustrationFor('card.a', 'missing')!.assetPath,
        'default.png',
      );
      expect(bundle.illustrationFor('card.missing', 'velvet'), isNull);
    });

    test('validator rejects zero size, outside blocks and broken links', () {
      final invalid = ThemeBundle(
        pack: const CardThemePack(
          id: 'bad',
          name: 'Bad',
          version: 1,
          layoutId: 'missing',
          skinId: 'missing',
        ),
        layout: CardLayout(
          id: 'layout',
          name: 'Layout',
          version: 1,
          aspectRatio: .7,
          front: const [
            CardLayoutBlock(
              id: 'bad',
              type: CardBlockType.title,
              box: RelativeBox(x: .9, y: .9, width: 0, height: .2),
            ),
          ],
          back: const [],
        ),
        skin: ClassicCardTheme.skin.duplicate(id: 'skin', name: 'Skin'),
      );

      final codes = const CardThemeValidator()
          .validate(invalid)
          .map((issue) => issue.code);

      expect(
        codes,
        containsAll([
          'layout_missing',
          'skin_missing',
          'zero_size',
          'outside_card',
        ]),
      );
    });

    test(
      'repository rejects import collisions and preserves custom theme',
      () async {
        SharedPreferences.setMockInitialValues({});
        final repository = SharedPreferencesCardThemeRepository(
          preferences: await SharedPreferences.getInstance(),
        );
        final custom = ThemeBundle(
          pack: const CardThemePack(
            id: 'custom',
            name: 'Custom',
            version: 1,
            layoutId: 'custom_layout',
            skinId: 'custom_skin',
          ),
          layout: ClassicCardTheme.layout.duplicate(
            id: 'custom_layout',
            name: 'Layout',
          ),
          skin: ClassicCardTheme.skin.duplicate(
            id: 'custom_skin',
            name: 'Skin',
          ),
        );

        await repository.save(custom);
        expect(
          (await repository.loadAll()).map((item) => item.pack.id),
          contains('custom'),
        );
        await expectLater(
          repository.import(custom.export()),
          throwsFormatException,
        );
      },
    );

    test('repository rejects a missing illustration asset', () async {
      SharedPreferences.setMockInitialValues({});
      final repository = SharedPreferencesCardThemeRepository(
        preferences: await SharedPreferences.getInstance(),
      );
      final bundle = ThemeBundle(
        pack: const CardThemePack(
          id: 'missing_asset',
          name: 'Missing',
          version: 1,
          layoutId: 'layout',
          skinId: 'skin',
        ),
        layout: ClassicCardTheme.layout.duplicate(id: 'layout', name: 'Layout'),
        skin: ClassicCardTheme.skin.duplicate(id: 'skin', name: 'Skin'),
        illustrations: const [
          IllustrationAsset(
            illustrationId: 'missing',
            cardId: 'card.a',
            styleId: 'default',
            assetPath: 'assets/does-not-exist.png',
          ),
        ],
      );

      await expectLater(
        repository.import(bundle.export()),
        throwsFormatException,
      );
    });
  });
}
