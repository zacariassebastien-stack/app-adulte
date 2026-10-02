import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../engines/deck/session_deck_builder.dart';
import 'card_hand_surface.dart';

class GameplayHud extends StatelessWidget {
  const GameplayHud({
    required this.child,
    required this.actionPoints,
    required this.status,
    required this.roundNumber,
    required this.spice,
    required this.orientation,
    required this.stage,
    required this.onSettings,
    this.onOrientationChanged,
    this.onDiscard,
    this.discardVisible = false,
    this.animationsEnabled = true,
    super.key,
  });

  final Widget child;
  final int actionPoints, roundNumber, spice;
  final String status;
  final HybridDeckOrientation orientation;
  final CardHandStage stage;
  final VoidCallback onSettings;
  final ValueChanged<HybridDeckOrientation>? onOrientationChanged;
  final VoidCallback? onDiscard;
  final bool discardVisible;
  final bool animationsEnabled;

  @override
  Widget build(BuildContext context) {
    final full = stage == CardHandStage.open;
    return Stack(
      children: [
        Positioned.fill(child: child),
        Positioned(
          top: 8,
          left: 16,
          child: ActionPointGaugeText(points: actionPoints),
        ),
        Positioned(
          top: 4,
          left: 92,
          right: 92,
          child: Text(
            status,
            key: const Key('game-status'),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        Positioned(
          top: 2,
          right: 6,
          child: IconButton(
            key: const Key('open-private-profile-settings'),
            tooltip: 'Réglages',
            onPressed: onSettings,
            icon: const Icon(Icons.settings),
          ),
        ),
        if (!full)
          Positioned(
            top: 48,
            left: 0,
            right: 0,
            child: Text(
              'TOUR $roundNumber',
              key: const Key('game-round'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
        if (!full && spice > 0)
          Positioned(
            top: 90,
            left: 0,
            right: 0,
            child: Text(
              List.filled(spice, '🌶️').join(),
              key: const Key('active-spice'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22),
            ),
          ),
        if (!full && onOrientationChanged != null)
          Positioned(
            left: 4,
            top: 0,
            bottom: 0,
            child: Center(
              child: OrientationFlipButton(
                orientation: orientation,
                animationsEnabled: animationsEnabled,
                onChanged: onOrientationChanged!,
              ),
            ),
          ),
        if (!full && discardVisible && onDiscard != null)
          Positioned(
            right: 6,
            top: 0,
            bottom: 0,
            child: Center(
              child: IconButton(
                key: const Key('open-discard-gallery'),
                tooltip: 'Défausse',
                onPressed: onDiscard,
                icon: const _DiscardStackIcon(),
              ),
            ),
          ),
      ],
    );
  }
}

class ActionPointGaugeText extends StatelessWidget {
  const ActionPointGaugeText({required this.points, super.key});

  final int points;

  @override
  Widget build(BuildContext context) {
    final text = '$points PA';
    final style = Theme.of(
      context,
    ).textTheme.titleLarge!.copyWith(fontWeight: FontWeight.w800);
    final fraction = (points / 100).clamp(0.0, 1.0);
    return Semantics(
      label: text,
      child: Stack(
        key: const Key('own-action-points'),
        children: [
          Text(text, style: style.copyWith(color: Colors.black26)),
          ClipRect(
            clipper: _FractionClipper(fraction),
            child: Text(
              text,
              key: Key('own-action-points-fill-${(fraction * 100).round()}'),
              style: style.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FractionClipper extends CustomClipper<Rect> {
  const _FractionClipper(this.fraction);
  final double fraction;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * fraction, size.height);

  @override
  bool shouldReclip(_FractionClipper oldClipper) =>
      oldClipper.fraction != fraction;
}

class OrientationFlipButton extends StatefulWidget {
  const OrientationFlipButton({
    required this.orientation,
    required this.onChanged,
    this.animationsEnabled = true,
    super.key,
  });

  final HybridDeckOrientation orientation;
  final ValueChanged<HybridDeckOrientation> onChanged;
  final bool animationsEnabled;

  @override
  State<OrientationFlipButton> createState() => _OrientationFlipButtonState();
}

class _OrientationFlipButtonState extends State<OrientationFlipButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  bool _busy = false;

  Future<void> _flip() async {
    if (_busy) return;
    _busy = true;
    final target = widget.orientation == HybridDeckOrientation.faceToFace
        ? HybridDeckOrientation.distance
        : HybridDeckOrientation.faceToFace;
    if (widget.animationsEnabled) {
      await _controller.forward(from: 0);
    }
    widget.onChanged(target);
    _busy = false;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, child) {
      final angle = _controller.value * math.pi;
      final targetSide = _controller.value >= .5;
      final current = targetSide
          ? (widget.orientation == HybridDeckOrientation.faceToFace
                ? HybridDeckOrientation.distance
                : HybridDeckOrientation.faceToFace)
          : widget.orientation;
      return Transform.scale(
        scaleX: math.cos(angle).abs().clamp(.05, 1),
        child: IconButton.filledTonal(
          key: const Key('switch-hybrid-orientation'),
          tooltip: current == HybridDeckOrientation.faceToFace
              ? 'Face à face'
              : 'Distance',
          onPressed: _flip,
          icon: Icon(
            current == HybridDeckOrientation.faceToFace
                ? Icons.people_alt_outlined
                : Icons.phone_android,
          ),
        ),
      );
    },
  );
}

class _DiscardStackIcon extends StatelessWidget {
  const _DiscardStackIcon();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 30,
    height: 30,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Transform.rotate(
          angle: -.22,
          child: const Icon(Icons.crop_portrait, size: 28),
        ),
        Transform.rotate(
          angle: .12,
          child: const Icon(Icons.crop_portrait, size: 28),
        ),
        const Icon(Icons.crop_portrait, size: 28),
      ],
    ),
  );
}
