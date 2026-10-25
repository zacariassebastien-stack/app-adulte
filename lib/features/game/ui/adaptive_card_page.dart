import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Text/buttons retain their natural height; the card takes all remaining space.
/// When content cannot fit, the page scrolls instead of squeezing/overlapping it.
class AdaptiveCardPage extends StatelessWidget {
  const AdaptiveCardPage({
    required this.before,
    required this.after,
    this.card,
    super.key,
  });
  final List<Widget> before, after;
  final Widget? card;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      const padding = 16.0;
      final height = math.max(0.0, bounds.maxHeight - padding * 2);
      final width = math.max(0.0, bounds.maxWidth - padding * 2);
      return SingleChildScrollView(
        padding: const EdgeInsets.all(padding),
        child: _CardFloor(
          height: math.min(width / .68, math.max(180.0, height * .35)),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: height),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ...before,
                  if (card != null) Expanded(child: card!),
                  ...after,
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class FittedActionCard extends StatelessWidget {
  const FittedActionCard({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: context.dependOnInheritedWidgetOfExactType<_CardFloor>()!.height,
    child: Center(child: AspectRatio(aspectRatio: .68, child: child)),
  );
}

class _CardFloor extends InheritedWidget {
  const _CardFloor({required this.height, required super.child});
  final double height;
  @override
  bool updateShouldNotify(_CardFloor oldWidget) => height != oldWidget.height;
}
