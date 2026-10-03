import 'package:flutter/painting.dart';

import 'card_theme_models.dart';

/// Windows editor bridge. The mobile application does not provide one.
abstract interface class CardIllustrationEditorAdapter {
  Future<String?> chooseAndImport({
    required ThemeBundle bundle,
    required String cardId,
  });

  Future<void> remove(IllustrationAsset asset);

  ImageProvider<Object>? previewProvider(IllustrationAsset asset);
}
