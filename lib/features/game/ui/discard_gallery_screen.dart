import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../card_themes/card_renderer.dart';
import '../../../card_themes/card_theme_models.dart';

final class DiscardGalleryItem {
  const DiscardGalleryItem({
    required this.id,
    required this.definition,
    required this.playedAt,
  });

  final String id;
  final CardRenderDefinition definition;
  final DateTime playedAt;
}

class DiscardGalleryScreen extends StatefulWidget {
  const DiscardGalleryScreen({required this.cards, super.key});
  final List<DiscardGalleryItem> cards;

  @override
  State<DiscardGalleryScreen> createState() => _DiscardGalleryScreenState();
}

class _DiscardGalleryScreenState extends State<DiscardGalleryScreen> {
  DiscardGalleryItem? _opened;

  @override
  Widget build(BuildContext context) {
    final cards = [...widget.cards]
      ..sort((a, b) => b.playedAt.compareTo(a.playedAt));
    return Scaffold(
      appBar: AppBar(title: const Text('Défausse')),
      body: _opened != null
          ? GestureDetector(
              key: const Key('discard-readonly-zoom'),
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _opened = null),
              child: LayoutBuilder(
                builder: (context, box) {
                  final width = math.min(
                    box.maxWidth * .9,
                    box.maxHeight * .9 * .68,
                  );
                  return Center(
                    child: SizedBox(
                      width: width,
                      height: width / .68,
                      child: CardRenderer(
                        definition: _opened!.definition.copyWith(
                          removePersonalPa: true,
                        ),
                        state: CardVisualState.readonly,
                      ),
                    ),
                  );
                },
              ),
            )
          : GridView.builder(
              key: const Key('discard-grid'),
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: .68,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: cards.length,
              itemBuilder: (context, index) {
                final item = cards[index];
                return GestureDetector(
                  key: Key('discard-card-${item.id}'),
                  onTap: () => setState(() => _opened = item),
                  child: CardRenderer(
                    definition: item.definition,
                    state: CardVisualState.discarded,
                  ),
                );
              },
            ),
    );
  }
}
