import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../card_themes/card_renderer.dart';
import '../../../card_themes/card_theme_models.dart';

enum CardHandStage { resting, focused, open, committed }

final class CardHandTab {
  const CardHandTab({
    required this.id,
    required this.label,
    required this.enabled,
    this.consumed = false,
    this.excluded = false,
  });
  final String id, label;
  final bool enabled, consumed;
  final bool excluded;
}

final class CardHandItem {
  const CardHandItem({
    required this.id,
    required this.definition,
    this.locked = false,
    this.available = true,
    this.excluded = false,
    this.replaceable = false,
    this.tabs = const [],
  });

  final String id;
  final CardRenderDefinition definition;
  final bool locked;
  final bool available;
  final bool excluded, replaceable;
  final List<CardHandTab> tabs;
}

class CardHandSurface extends StatefulWidget {
  const CardHandSurface({
    required this.cards,
    this.committedCard,
    this.canCancelCommitted = false,
    this.animationsEnabled = true,
    this.onPlay,
    this.onTabChanged,
    this.onCancelCommitted,
    this.onLockChanged,
    this.onLongPressCard,
    this.onReplace,
    this.onStageChanged,
    this.onRate,
    super.key,
  });

  final List<CardHandItem> cards;
  final CardHandItem? committedCard;
  final bool canCancelCommitted;
  final bool animationsEnabled;
  final ValueChanged<CardHandItem>? onPlay;
  final void Function(CardHandItem card, String tabId)? onTabChanged;
  final VoidCallback? onCancelCommitted;
  final ValueChanged<CardHandItem>? onLockChanged;
  final ValueChanged<CardHandItem>? onLongPressCard;
  final ValueChanged<CardHandItem>? onReplace;
  final ValueChanged<CardHandStage>? onStageChanged;
  final ValueChanged<CardHandItem>? onRate;

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
  bool _replacementPointer = false;
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
      await Future<void>.delayed(
        widget.animationsEnabled ? const Duration(seconds: 1) : Duration.zero,
      );
      if (mounted) {
        setState(() => _showBlockedLock = false);
        _rest();
      }
      return;
    }
    if (item.available) widget.onPlay?.call(item);
  }

  bool _isInHandInteractionZone(Offset position, BoxConstraints constraints) =>
      position.dy >= constraints.maxHeight * (2 / 3) &&
      position.dy <= constraints.maxHeight;

  Rect _focusedCardBounds(BoxConstraints constraints) {
    final width = math.min(constraints.maxWidth * .49, 230).toDouble();
    final height = width / .68;
    return Rect.fromLTWH(
      (constraints.maxWidth - width) / 2,
      math.max(
        70.0,
        constraints.maxHeight - height - constraints.maxHeight * .18,
      ),
      width,
      height,
    );
  }

  void _pointerDown(PointerDownEvent event) {
    if (_replacementPointer) return;
    _start = event.localPosition;
    _dragging = false;
    _longPressTriggered = false;
    _stageAtPointerDown = _stage;
    _longPressTimer?.cancel();
    _longPressTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted || _dragging) return;
      if (_stage == CardHandStage.resting && widget.onLongPressCard != null) {
        final size = context.size;
        if (size == null ||
            _start == null ||
            _start!.dy < size.height * 2 / 3) {
          return;
        }
        _focus(_indexAt(_start!.dx, size.width));
      }
      if (_focused == null) return;
      if (_stage != CardHandStage.focused && _stage != CardHandStage.open) {
        return;
      }
      _longPressTriggered = true;
      final callback = widget.onLongPressCard ?? widget.onLockChanged;
      callback?.call(widget.cards[_focused!]);
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
    if (_dragging &&
        _stageAtPointerDown == CardHandStage.resting &&
        trackingHand) {
      if (_isInHandInteractionZone(event.localPosition, constraints)) {
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
    final dx = end.dx - start.dx;
    if (!_longPressTriggered) {
      if (_dragging &&
          _focused != null &&
          (_stageAtPointerDown == CardHandStage.focused ||
              _stageAtPointerDown == CardHandStage.open) &&
          dx.abs() > _swipeThreshold &&
          dx.abs() > dy.abs()) {
        setState(() {
          _focused = (_focused! + (dx < 0 ? 1 : -1)).clamp(
            0,
            widget.cards.length - 1,
          );
          _setStage(_stageAtPointerDown);
        });
      } else if (_dragging &&
          _focused != null &&
          _stageAtPointerDown != CardHandStage.resting &&
          dy.abs() > dx.abs() &&
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
      } else if (!_dragging &&
          _stage == CardHandStage.focused &&
          _focused != null &&
          _focusedCardBounds(constraints).contains(end)) {
        setState(() => _setStage(CardHandStage.open));
      } else if (!_dragging && _isInHandInteractionZone(end, constraints)) {
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
            for (var i = 0; i < widget.cards.length; i++)
              if (widget.cards[i].excluded &&
                  widget.cards[i].replaceable &&
                  widget.onReplace != null &&
                  !(_focused == i && _stage == CardHandStage.open))
                _positionedCard(constraints, i, replacementOnly: true),
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

  Widget _positionedCard(
    BoxConstraints box,
    int index, {
    bool replacementOnly = false,
  }) {
    final count = widget.cards.length;
    final card = widget.cards[index];
    final selected = _focused == index;
    final open = selected && _stage == CardHandStage.open;
    final focused = selected && _stage == CardHandStage.focused;
    final focusedBounds = _focusedCardBounds(box);
    final width =
        (open
                ? math.min(box.maxWidth * .9, box.maxHeight * .9 * .68)
                : focused
                ? focusedBounds.width
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
        ? focusedBounds.left
        : (box.maxWidth - (width + overlapStep * (count - 1))) / 2 +
              overlapStep * index +
              (_stage == CardHandStage.focused ? centerOffset * 7 : 0);
    final top =
        (open
                ? math.max(56.0, (box.maxHeight - height) / 2)
                : focused
                ? focusedBounds.top
                : box.maxHeight - height * .58 + centerOffset.abs() * 7)
            .toDouble();
    final angle = open
        ? 0.0
        : focused
        ? centerOffset * .012
        : centerOffset * .095;
    final scale = !selected && _stage == CardHandStage.focused ? .9 : 1.0;
    if (replacementOnly) {
      return Positioned(
        left: (left + 4).clamp(0.0, math.max(0.0, box.maxWidth - 48)),
        top: math.min(top + 28, box.maxHeight - 52),
        child: _replacementControl(card, compact: true),
      );
    }
    return AnimatedPositioned(
      key: Key('hand-card-${card.id}'),
      duration: widget.animationsEnabled
          ? const Duration(milliseconds: 190)
          : Duration.zero,
      curve: Curves.easeOutCubic,
      left: left,
      top: top,
      width: width,
      height: height,
      child: IgnorePointer(
        ignoring: open ? false : true,
        child: AnimatedRotation(
          turns: angle / (2 * math.pi),
          duration: widget.animationsEnabled
              ? const Duration(milliseconds: 190)
              : Duration.zero,
          curve: Curves.easeOutCubic,
          child: AnimatedScale(
            scale: scale,
            duration: widget.animationsEnabled
                ? const Duration(milliseconds: 160)
                : Duration.zero,
            child: Column(
              children: [
                if (open && card.tabs.isNotEmpty)
                  SizedBox(
                    height: 38,
                    child: Row(
                      children: [
                        for (final tab in card.tabs)
                          Expanded(
                            child: TextButton(
                              key: Key('stage-tab-${card.id}-${tab.id}'),
                              onPressed: tab.enabled
                                  ? () =>
                                        widget.onTabChanged?.call(card, tab.id)
                                  : null,
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                ),
                                backgroundColor:
                                    card.definition.variantId == tab.id
                                    ? Theme.of(
                                        context,
                                      ).colorScheme.primaryContainer
                                    : null,
                              ),
                              child: Text(
                                '${tab.label}${tab.consumed
                                    ? ' ✓ joué'
                                    : tab.excluded
                                    ? ' 🚫'
                                    : tab.enabled
                                    ? ''
                                    : ' —'}',
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Opacity(
                        opacity: card.available ? 1 : .48,
                        child: CardRenderer(
                          definition: card.definition,
                          locked: card.locked && !card.excluded,
                          state: open
                              ? CardVisualState.full
                              : focused
                              ? CardVisualState.focused
                              : card.locked && !card.excluded
                              ? CardVisualState.locked
                              : CardVisualState.normal,
                        ),
                      ),
                      if (card.locked || card.excluded)
                        Align(
                          alignment: Alignment.topCenter,
                          child: Container(
                            color: Theme.of(context).colorScheme.surface,
                            padding: const EdgeInsets.all(3),
                            child: FittedBox(
                              child: Text(
                                card.excluded ? '🚫 EXCLUE' : '🔒 VERROUILLÉE',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (open && widget.onRate != null)
                  TextButton(
                    key: Key('rate-hand-card-${card.id}'),
                    onPressed: () => widget.onRate?.call(card),
                    child: const Text('Mon appréciation'),
                  ),
                if (open &&
                    card.excluded &&
                    card.replaceable &&
                    widget.onReplace != null)
                  _replacementControl(card, compact: false),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _replacementControl(CardHandItem card, {required bool compact}) =>
      Listener(
        onPointerDown: (_) {
          _replacementPointer = true;
        },
        onPointerUp: (_) {
          _replacementPointer = false;
        },
        onPointerCancel: (_) {
          _replacementPointer = false;
        },
        child: compact
            ? IconButton.filled(
                key: Key('replace-excluded-${card.id}'),
                tooltip: 'Remplacer gratuitement · 0 PA',
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                iconSize: 32,
                onPressed: () => widget.onReplace?.call(card),
                icon: const Icon(Icons.swap_horiz),
              )
            : FilledButton.icon(
                key: Key('replace-excluded-${card.id}'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                ),
                onPressed: () => widget.onReplace?.call(card),
                icon: const Icon(Icons.swap_horiz, size: 32),
                label: const Text('Remplacer · 0 PA'),
              ),
      );

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
