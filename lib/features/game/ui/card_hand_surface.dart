import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../card_themes/card_renderer.dart';
import '../../../card_themes/card_theme_models.dart';

enum CardHandStage { resting, focused, open, committed }

final class CardHandItem {
  const CardHandItem({
    required this.id,
    required this.definition,
    this.locked = false,
    this.available = true,
  });

  final String id;
  final CardRenderDefinition definition;
  final bool locked;
  final bool available;
}

class CardHandSurface extends StatefulWidget {
  const CardHandSurface({
    required this.cards,
    this.committedCard,
    this.canCancelCommitted = false,
    this.onPlay,
    this.onCancelCommitted,
    this.onLockChanged,
    this.onStageChanged,
    super.key,
  });

  final List<CardHandItem> cards;
  final CardHandItem? committedCard;
  final bool canCancelCommitted;
  final ValueChanged<CardHandItem>? onPlay;
  final VoidCallback? onCancelCommitted;
  final ValueChanged<CardHandItem>? onLockChanged;
  final ValueChanged<CardHandStage>? onStageChanged;

  @override
  State<CardHandSurface> createState() => _CardHandSurfaceState();
}

class _CardHandSurfaceState extends State<CardHandSurface> {
  static const _dragThreshold = 12.0;
  static const _swipeThreshold = 58.0;
  CardHandStage _stage = CardHandStage.resting;
  int? _focused;
  Offset? _start;
  bool _dragging = false;
  bool _showBlockedLock = false;
  bool _back = false;
  double _committedDy = 0;
  Timer? _longPressTimer;
  bool _longPressTriggered = false;
  CardHandStage _stageAtPointerDown = CardHandStage.resting;

  @override
  void didUpdateWidget(covariant CardHandSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    var stageChanged = false;
    final committed = widget.committedCard != null;
    if (committed != (oldWidget.committedCard != null)) {
      _back = false;
      _stage = committed ? CardHandStage.committed : CardHandStage.resting;
      stageChanged = true;
    }
    if (_focused != null && _focused! >= widget.cards.length) {
      _focused = null;
      _stage = CardHandStage.resting;
      stageChanged = true;
    }
    if (stageChanged) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onStageChanged?.call(_stage);
      });
    }
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    super.dispose();
  }

  void _setStage(CardHandStage value) {
    if (_stage == value) return;
    _stage = value;
    widget.onStageChanged?.call(value);
  }

  int _indexAt(double x, double width) {
    if (widget.cards.isEmpty) return 0;
    return ((x / width) * widget.cards.length).floor().clamp(
      0,
      widget.cards.length - 1,
    );
  }

  void _focus(int index) {
    setState(() {
      _focused = index;
      _setStage(CardHandStage.focused);
    });
  }

  void _rest() => setState(() {
    _focused = null;
    _setStage(CardHandStage.resting);
  });

  Future<void> _play(CardHandItem item) async {
    if (item.locked) {
      setState(() => _showBlockedLock = true);
      await Future<void>.delayed(const Duration(seconds: 1));
      if (mounted) {
        setState(() => _showBlockedLock = false);
        _rest();
      }
      return;
    }
    if (item.available) widget.onPlay?.call(item);
  }

  void _pointerDown(PointerDownEvent event) {
    _start = event.localPosition;
    _dragging = false;
    _longPressTriggered = false;
    _stageAtPointerDown = _stage;
    _longPressTimer?.cancel();
    _longPressTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted || _dragging || _focused == null) return;
      if (_stage != CardHandStage.focused && _stage != CardHandStage.open) {
        return;
      }
      _longPressTriggered = true;
      widget.onLockChanged?.call(widget.cards[_focused!]);
    });
  }

  void _pointerMove(PointerMoveEvent event, BoxConstraints constraints) {
    final start = _start;
    if (start == null) return;
    final delta = event.localPosition - start;
    if (!_dragging && delta.distance > _dragThreshold) {
      _dragging = true;
      _longPressTimer?.cancel();
    }
    final trackingHand =
        _stage == CardHandStage.resting || delta.dx.abs() > delta.dy.abs();
    if (_dragging && _stage != CardHandStage.open && trackingHand) {
      final handTop = constraints.maxHeight * .58;
      if (event.localPosition.dy >= handTop &&
          event.localPosition.dy <= constraints.maxHeight) {
        _focus(_indexAt(event.localPosition.dx, constraints.maxWidth));
      }
    }
  }

  void _pointerUp(PointerUpEvent event, BoxConstraints constraints) {
    _longPressTimer?.cancel();
    final start = _start;
    final end = event.localPosition;
    if (start == null) return;
    final dy = end.dy - start.dy;
    if (!_longPressTriggered) {
      if (_dragging &&
          _focused != null &&
          _stageAtPointerDown != CardHandStage.resting &&
          dy < -_swipeThreshold) {
        _play(widget.cards[_focused!]);
      } else if (_dragging &&
          _stage == CardHandStage.open &&
          dy > _swipeThreshold) {
        _rest();
      } else if (_dragging &&
          (end.dy < constraints.maxHeight * .5 ||
              end.dx < 0 ||
              end.dx > constraints.maxWidth)) {
        _rest();
      } else if (!_dragging) {
        final index = _indexAt(end.dx, constraints.maxWidth);
        if (_stage == CardHandStage.focused && _focused == index) {
          setState(() => _setStage(CardHandStage.open));
        } else if (_stage != CardHandStage.open) {
          _focus(index);
        }
      }
    }
    _start = null;
    _dragging = false;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (widget.committedCard case final committed?) {
        return _committed(context, constraints, committed);
      }
      return Listener(
        key: const Key('card-hand-surface'),
        behavior: HitTestBehavior.translucent,
        onPointerDown: _pointerDown,
        onPointerMove: (event) => _pointerMove(event, constraints),
        onPointerUp: (event) => _pointerUp(event, constraints),
        onPointerCancel: (_) => _longPressTimer?.cancel(),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (var i = 0; i < widget.cards.length; i++)
              _positionedCard(constraints, i),
            if (_showBlockedLock && _focused != null)
              Center(
                child: Icon(
                  Icons.lock_rounded,
                  key: const Key('blocked-card-lock'),
                  size: 96,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
          ],
        ),
      );
    },
  );

  Widget _positionedCard(BoxConstraints box, int index) {
    final count = widget.cards.length;
    final card = widget.cards[index];
    final selected = _focused == index;
    final open = selected && _stage == CardHandStage.open;
    final focused = selected && _stage == CardHandStage.focused;
    final width =
        (open
                ? math.min(box.maxWidth * .9, box.maxHeight * .9 * .68)
                : focused
                ? math.min(box.maxWidth * .49, 230)
                : math.min(box.maxWidth * .31, 150))
            .toDouble();
    final height = width / .68;
    final centerOffset = index - (count - 1) / 2;
    final overlapStep = math.min(
      width * .58,
      box.maxWidth / math.max(count, 1),
    );
    final left = open
        ? (box.maxWidth - width) / 2
        : focused
        ? (box.maxWidth - width) / 2
        : (box.maxWidth - (width + overlapStep * (count - 1))) / 2 +
              overlapStep * index +
              (_stage == CardHandStage.focused ? centerOffset * 7 : 0);
    final top =
        (open
                ? math.max(56.0, (box.maxHeight - height) / 2)
                : focused
                ? math.max(70.0, box.maxHeight - height - box.maxHeight * .18)
                : box.maxHeight - height * .58 + centerOffset.abs() * 7)
            .toDouble();
    final angle = open
        ? 0.0
        : focused
        ? centerOffset * .012
        : centerOffset * .095;
    final scale = !selected && _stage == CardHandStage.focused ? .9 : 1.0;
    return AnimatedPositioned(
      key: Key('hand-card-${card.id}'),
      duration: const Duration(milliseconds: 190),
      curve: Curves.easeOutCubic,
      left: left,
      top: top,
      width: width,
      height: height,
      child: IgnorePointer(
        ignoring: open ? false : true,
        child: AnimatedRotation(
          turns: angle / (2 * math.pi),
          duration: const Duration(milliseconds: 190),
          curve: Curves.easeOutCubic,
          child: AnimatedScale(
            scale: scale,
            duration: const Duration(milliseconds: 160),
            child: Opacity(
              opacity: card.available ? 1 : .48,
              child: CardRenderer(
                definition: card.definition,
                locked: card.locked,
                state: open
                    ? CardVisualState.full
                    : focused
                    ? CardVisualState.focused
                    : card.locked
                    ? CardVisualState.locked
                    : CardVisualState.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _committed(
    BuildContext context,
    BoxConstraints box,
    CardHandItem card,
  ) {
    final width = math.min(box.maxWidth * .86, box.maxHeight * .72 * .68);
    return GestureDetector(
      key: const Key('committed-card'),
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _back = !_back),
      onVerticalDragStart: widget.canCancelCommitted
          ? (_) => _committedDy = 0
          : null,
      onVerticalDragUpdate: widget.canCancelCommitted
          ? (details) => _committedDy += details.delta.dy
          : null,
      onVerticalDragEnd: widget.canCancelCommitted
          ? (details) {
              if (details.primaryVelocity case final velocity?
                  when velocity > 400 || _committedDy > _swipeThreshold) {
                widget.onCancelCommitted?.call();
              }
            }
          : null,
      child: Center(
        child: SizedBox(
          width: width,
          height: width / .68,
          child: CardRenderer(
            definition: card.definition,
            locked: card.locked,
            state: _back ? CardVisualState.hidden : CardVisualState.waiting,
          ),
        ),
      ),
    );
  }
}
