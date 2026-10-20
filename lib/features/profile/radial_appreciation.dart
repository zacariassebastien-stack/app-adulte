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
    super.key,
  });
  final Widget child;
  final ValueChanged<DetailedPreferenceCategory> onSelected;
  final VoidCallback? onTap;
  final bool enabled;
  @override
  State<RadialAppreciation> createState() => _RadialAppreciationState();
}

class _RadialAppreciationState extends State<RadialAppreciation> {
  OverlayEntry? _overlay;
  Offset _center = Offset.zero, _origin = Offset.zero;
  double _radius = 140;
  int? _selected;
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
                  child: CustomPaint(
                    key: const Key('appreciation-radial'),
                    painter: _Sectors(_selected, Theme.of(context).colorScheme),
                    child: Stack(
                      children: [
                        for (
                          var i = 0;
                          i < DetailedPreferenceCategory.values.length;
                          i++
                        )
                          Positioned(
                            left:
                                _radius +
                                math.cos(-math.pi / 2 + i * math.pi / 5) *
                                    _radius *
                                    .67 -
                                _radius * .29,
                            top:
                                _radius +
                                math.sin(-math.pi / 2 + i * math.pi / 5) *
                                    _radius *
                                    .67 -
                                22,
                            width: _radius * .58,
                            height: 44,
                            child: Center(
                              child: Text(
                                DetailedPreferenceCategory.values[i].label,
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
                            width: _radius * .55,
                            child: const Text(
                              'Glisse puis relâche',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 11),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
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
    final delta = details.globalPosition - _center;
    _selected = delta.distance < 25 || delta.distance > _radius * 1.5
        ? null
        : (((math.atan2(delta.dy, delta.dx) + math.pi / 2 + math.pi / 10) %
                      (2 * math.pi)) /
                  (math.pi / 5))
              .floor();
    _overlay!.markNeedsBuild();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: widget.onTap,
    onLongPressStart: widget.enabled ? _start : null,
    onLongPressMoveUpdate: widget.enabled ? _move : null,
    onLongPressCancel: _close,
    onLongPressEnd: (_) {
      final choice = _selected;
      _close();
      if (choice != null) {
        widget.onSelected(DetailedPreferenceCategory.values[choice]);
      }
    },
    child: widget.child,
  );
}

class _Sectors extends CustomPainter {
  const _Sectors(this.selected, this.colors);
  final int? selected;
  final ColorScheme colors;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    for (var i = 0; i < 10; i++) {
      canvas.drawArc(
        rect,
        -math.pi / 2 - math.pi / 10 + i * math.pi / 5,
        math.pi / 5,
        true,
        Paint()..color = selected == i ? colors.primary : colors.surface,
      );
      canvas.drawArc(
        rect,
        -math.pi / 2 - math.pi / 10 + i * math.pi / 5,
        math.pi / 5,
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
      oldDelegate.selected != selected || oldDelegate.colors != colors;
}
