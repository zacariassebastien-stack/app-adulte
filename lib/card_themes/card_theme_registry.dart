import 'card_theme_models.dart';
import 'classic_theme.dart';
import 'signature_theme.dart';

abstract final class CardThemeRegistry {
  static ThemeBundle _classic = ClassicCardTheme.bundle;
  static ThemeBundle _signature = EnchaireSignatureTheme.bundle;
  static ThemeBundle? _selected;

  static ThemeBundle get classic => _classic;
  static ThemeBundle get signature => _signature;
  static ThemeBundle get selected => _selected ?? _signature;

  static void select(ThemeBundle bundle) => _selected = bundle;

  static void installClassic(ThemeBundle bundle) {
    if (bundle.pack.id != 'classic_v1' ||
        bundle.layout.id != 'classic_v1' ||
        bundle.skin.id != 'classic_v1') {
      throw ArgumentError('The canonical theme must use classic_v1 IDs.');
    }
    _classic = bundle;
  }

  static void installSignature(ThemeBundle bundle) {
    if (bundle.pack.id != EnchaireSignatureTheme.id ||
        bundle.layout.id != EnchaireSignatureTheme.id ||
        bundle.skin.id != EnchaireSignatureTheme.id) {
      throw ArgumentError(
        'The canonical signature theme must use enchaire_signature_v1 IDs.',
      );
    }
    _signature = bundle;
  }

  static void resetForTesting() {
    _classic = ClassicCardTheme.bundle;
    _signature = EnchaireSignatureTheme.bundle;
    _selected = null;
  }
}
