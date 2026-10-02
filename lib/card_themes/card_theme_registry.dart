import 'card_theme_models.dart';
import 'classic_theme.dart';

abstract final class CardThemeRegistry {
  static ThemeBundle _classic = ClassicCardTheme.bundle;

  static ThemeBundle get classic => _classic;

  static void installClassic(ThemeBundle bundle) {
    if (bundle.pack.id != 'classic_v1' ||
        bundle.layout.id != 'classic_v1' ||
        bundle.skin.id != 'classic_v1') {
      throw ArgumentError('The canonical theme must use classic_v1 IDs.');
    }
    _classic = bundle;
  }

  static void resetForTesting() => _classic = ClassicCardTheme.bundle;
}
