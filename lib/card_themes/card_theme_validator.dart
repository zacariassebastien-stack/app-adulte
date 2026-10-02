import 'card_theme_models.dart';

enum ThemeIssueSeverity { error, warning }

final class ThemeValidationIssue {
  const ThemeValidationIssue(this.code, this.message, this.severity);
  final String code, message;
  final ThemeIssueSeverity severity;
}

final class CardThemeValidator {
  const CardThemeValidator();

  List<ThemeValidationIssue> validate(ThemeBundle bundle) {
    final issues = <ThemeValidationIssue>[];
    if (bundle.pack.layoutId != bundle.layout.id) {
      issues.add(_error('layout_missing', 'Le layout associé est absent.'));
    }
    if (bundle.pack.skinId != bundle.skin.id) {
      issues.add(_error('skin_missing', 'Le skin associé est absent.'));
    }
    if (bundle.pack.minimumRendererVersion > 1) {
      issues.add(
        _error('theme_incompatible', 'Version du renderer incompatible.'),
      );
    }
    if (bundle.layout.aspectRatio <= 0) {
      issues.add(
        _error('invalid_ratio', 'Le ratio de carte doit être positif.'),
      );
    }
    final ids = <String>{};
    for (final block in [...bundle.layout.front, ...bundle.layout.back]) {
      if (!ids.add(block.id)) {
        issues.add(_error('duplicate_block', 'Bloc dupliqué : ${block.id}.'));
      }
      final box = block.box;
      if (box.width <= 0 || box.height <= 0) {
        issues.add(_error('zero_size', 'Taille nulle : ${block.id}.'));
      }
      if (box.x < 0 ||
          box.y < 0 ||
          box.x + box.width > 1 ||
          box.y + box.height > 1) {
        issues.add(_error('outside_card', 'Bloc hors carte : ${block.id}.'));
      }
    }
    for (final asset in bundle.illustrations) {
      if (asset.assetPath.trim().isEmpty) {
        issues.add(
          _error('image_missing', 'Image absente : ${asset.illustrationId}.'),
        );
      }
      if (asset.focusX < 0 ||
          asset.focusX > 1 ||
          asset.focusY < 0 ||
          asset.focusY > 1) {
        issues.add(
          _error('invalid_focus', 'Focus invalide : ${asset.illustrationId}.'),
        );
      }
    }
    if (!bundle.layout.front.any(
      (block) => block.type == CardBlockType.title && block.visible,
    )) {
      issues.add(
        const ThemeValidationIssue(
          'title_hidden',
          'Le titre est entièrement masqué.',
          ThemeIssueSeverity.warning,
        ),
      );
    }
    return issues;
  }

  ThemeValidationIssue _error(String code, String message) =>
      ThemeValidationIssue(code, message, ThemeIssueSeverity.error);
}
