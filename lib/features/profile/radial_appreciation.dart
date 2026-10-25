import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../domain/profile/adaptive_profile.dart';

/// One continuous long-press gesture: hold, drag to a sector, release.
class RadialAppreciation extends StatefulWidget {
  const RadialAppreciation({
    required this.child,
    required this.onSelected,
    this.onTap,
    this.enabled = true,
    this.allowExclusion = true,
    this.visible = false,
    this.initialValue,
    super.key,
  });
  final Widget child;
  final ValueChanged<DetailedPreferenceCategory> onSelected;
  final VoidCallback? onTap;
  final bool enabled;
  final bool allowExclusion;
  final bool visible;
  final DetailedPreferenceCategory? initialValue;
  @override
  State<RadialAppreciation> createState() => _RadialAppreciationState();
}

class _RadialAppreciationState extends State<RadialAppreciation> {
  List<DetailedPreferenceCategory> get _choices => DetailedPreferenceCategory
      .values
      .where(
        (value) =>
            widget.allowExclusion ||
            value != DetailedPreferenceCategory.excluded,
      )
      .toList();
  double get _sector => 2 * math.pi / _choices.length;
  OverlayEntry? _overlay;
  Offset _center = Offset.zero, _origin = Offset.zero;
  double _radius = 140;
  int? _selected;
  bool _moved = false;

  @override
  void initState() {
    super.initState();
    _selected = _initialIndex;
  }

  int? get _initialIndex {
    final index = _choices.indexOf(
      widget.initialValue ?? DetailedPreferenceCategory.unsure,
    );
    return widget.initialValue == null || index < 0 ? null : index;
  }

  int? _choiceAt(Offset delta, double radius) =>
      delta.distance < radius * .15 || delta.distance > radius
      ? null
      : (((math.atan2(delta.dy, delta.dx) + math.pi / 2 + _sector / 2) %
                    (2 * math.pi)) /
                _sector)
            .floor();

  Widget _wheel(BuildContext context, double radius) => CustomPaint(
    key: const Key('appreciation-radial'),
    painter: _Sectors(
      _selected,
      Theme.of(context).colorScheme,
      _choices.length,
    ),
    child: Stack(
      children: [
        for (var i = 0; i < _choices.length; i++)
          Positioned(
            left:
                radius +
                math.cos(-math.pi / 2 + i * _sector) * radius * .67 -
                radius * .29,
            top:
                radius +
                math.sin(-math.pi / 2 + i * _sector) * radius * .67 -
                22,
            width: radius * .58,
            height: 44,
            child: Center(
              child: Text(
                _choices[i].label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: _selected == i
                      ? Theme.of(context).colorScheme.onPrimary
                      : Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ),
        Center(
          child: SizedBox(
            width: radius * .55,
            child: Text(
              widget.visible ? 'Ton choix' : 'Glisse puis relâche',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11),
            ),
          ),
        ),
      ],
    ),
  );
  void _close() {
    _overlay?.remove();
    _overlay = null;
    _selected = null;
  }

  @override
  void dispose() {
    _close();
    super.dispose();
  }

  void _start(LongPressStartDetails details) {
    final size = MediaQuery.sizeOf(context);
    _radius = math.min(170, math.min(size.width, size.height) / 2 - 12);
    _origin = details.globalPosition;
    _selected = _initialIndex;
    _moved = false;
    _center = Offset(
      _origin.dx.clamp(_radius + 8, size.width - _radius - 8),
      _origin.dy.clamp(_radius + 8, size.height - _radius - 8),
    );
    _overlay = OverlayEntry(
      builder: (_) => Positioned.fill(
        child: IgnorePointer(
          child: Material(
            color: Colors.black38,
            child: Stack(
              children: [
                Positioned(
                  left: _center.dx - _radius,
                  top: _center.dy - _radius,
                  width: _radius * 2,
                  height: _radius * 2,
                  child: _wheel(context, _radius),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_overlay!);
  }

  void _move(LongPressMoveUpdateDetails details) {
    if (_overlay == null ||
        ((details.globalPosition - _origin).distance < 8 &&
            _selected == null)) {
      return;
    }
    _moved = true;
    _selected = _choiceAt(details.globalPosition - _center, _radius);
    _overlay!.markNeedsBuild();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.visible) {
      return LayoutBuilder(
        builder: (context, bounds) {
          final radius = bounds.maxWidth / 2;
          void choose(Offset point) => setState(
            () => _selected = _choiceAt(point - Offset(radius, radius), radius),
          );
          void submit() {
            if (widget.enabled && _selected != null) {
              widget.onSelected(_choices[_selected!]);
            }
          }

          return AspectRatio(
            aspectRatio: 1,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: widget.enabled
                  ? (details) {
                      choose(details.localPosition);
                      submit();
                    }
                  : null,
              onPanStart: widget.enabled
                  ? (details) => choose(details.localPosition)
                  : null,
              onPanUpdate: widget.enabled
                  ? (details) => choose(details.localPosition)
                  : null,
              onPanEnd: widget.enabled ? (_) => submit() : null,
              child: _wheel(context, radius),
            ),
          );
        },
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onLongPressStart: widget.enabled ? _start : null,
      onLongPressMoveUpdate: widget.enabled ? _move : null,
      onLongPressCancel: _close,
      onLongPressEnd: (_) {
        final choice = _moved ? _selected : null;
        _close();
        if (widget.enabled && choice != null) {
          widget.onSelected(_choices[choice]);
        }
      },
      child: widget.child,
    );
  }
}

class _Sectors extends CustomPainter {
  const _Sectors(this.selected, this.colors, this.count);
  final int count;
  final int? selected;
  final ColorScheme colors;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final sector = 2 * math.pi / count;
    for (var i = 0; i < count; i++) {
      canvas.drawArc(
        rect,
        -math.pi / 2 - sector / 2 + i * sector,
        sector,
        true,
        Paint()..color = selected == i ? colors.primary : colors.surface,
      );
      canvas.drawArc(
        rect,
        -math.pi / 2 - sector / 2 + i * sector,
        sector,
        true,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = colors.outline,
      );
    }
    canvas.drawCircle(
      size.center(Offset.zero),
      size.width * .15,
      Paint()..color = colors.surface,
    );
  }

  @override
  bool shouldRepaint(_Sectors oldDelegate) =>
      oldDelegate.selected != selected ||
      oldDelegate.colors != colors ||
      oldDelegate.count != count;
}
