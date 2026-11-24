import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart' as p;

import '../../data/planner_models.dart';
import '../../ui/task_widgets.dart';
import '../../ui/todo_glyphs.dart';
import '../../ui/todo_motion.dart';
import 'planner_controls.dart';

typedef PlannerTimeRange = ({String? start, String? end});

final _timePattern = RegExp(r'^(\d{1,2}):([0-5]\d)$');

int? plannerTimeMinutes(String? value) {
  final match = value == null ? null : _timePattern.firstMatch(value.trim());
  if (match == null) return null;
  final hour = int.parse(match[1]!);
  return hour < 24 ? hour * 60 + int.parse(match[2]!) : null;
}

Future<PlannerTimeRange?> selectPlannerTimeRange(
  BuildContext context, {
  required List<PlanInterval> gaps,
  required String? start,
  required String? end,
}) => showTodoFormSheet<PlannerTimeRange>(
  context: context,
  props: const p.SheetProps(detents: [.82]),
  builder: (_) => _TimeRangePicker(
    gaps: gaps,
    start: plannerTimeMinutes(start),
    end: plannerTimeMinutes(end),
  ),
);

class _TimeRangePicker extends StatefulWidget {
  const _TimeRangePicker({required this.gaps, this.start, this.end});

  final List<PlanInterval> gaps;
  final int? start, end;

  @override
  State<_TimeRangePicker> createState() => _TimeRangePickerState();
}

class _TimeRangePickerState extends State<_TimeRangePicker> {
  PlanInterval? _gap;
  int _start = 0, _end = 0;

  @override
  void initState() {
    super.initState();
    final start = widget.start, end = widget.end;
    for (final gap in widget.gaps) {
      if (start != null &&
          end != null &&
          gap.start <= start &&
          start < end &&
          end <= gap.end) {
        _gap = gap;
        _start = start;
        _end = end;
        return;
      }
    }
    if (widget.gaps.length == 1) _selectGap(widget.gaps.single);
  }

  void _selectGap(PlanInterval gap) {
    _gap = gap;
    _start = gap.start;
    _end = math.min(gap.end, gap.start + 60);
  }

  @override
  Widget build(BuildContext context) {
    final gap = _gap;
    return p.PrismScaffold(
      bar: todoBar(
        context,
        gap == null && widget.gaps.isNotEmpty ? '选择空档' : '设置安排时间',
        actions: [
          p.TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
      body: Builder(
        builder: (context) => ListView(
          padding: EdgeInsets.fromLTRB(16, context.appBarInset + 12, 16, 28),
          children: [
            if (gap != null) ...[
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: p.Card(
                    inert: true,
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
                    child: _GapDial(
                      key: ValueKey(gap),
                      gap: gap,
                      start: _start,
                      end: _end,
                      onChanged: (isStart, minute) => setState(() {
                        if (isStart) {
                          _start = minute;
                        } else {
                          _end = minute;
                        }
                      }),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              p.FilledButton(
                onPressed: () => Navigator.of(context)
                    .pop((start: plannerTime(_start), end: plannerTime(_end))),
                child: const Text('应用时间'),
              ),
              if (widget.gaps.length > 1)
                p.TextButton(
                  onPressed: () => setState(() => _gap = null),
                  child: const Text('换一个空档'),
                ),
            ] else if (widget.gaps.isEmpty)
              const PlannerNotice('这一天没有可用空档。')
            else
              for (final option in widget.gaps)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: p.Card(
                    padding: EdgeInsets.zero,
                    onPressed: () => setState(() => _selectGap(option)),
                    child: p.ListRow(
                      title: Text(
                        '${plannerTime(option.start)}–${plannerTime(option.end)}',
                      ),
                    ),
                  ),
                ),
            p.TextButton(
              onPressed: () =>
                  Navigator.of(context)
                      .pop<PlannerTimeRange>((start: null, end: null)),
              child: const Text('不设置时间'),
            ),
          ],
        ),
      ),
    );
  }
}

// Leave space below the arc so the two ends of the free interval stay distinct.
const _origin = 3 * math.pi / 4;
const _sweep = 3 * math.pi / 2;
const _turn = 2 * math.pi;

class _DialGeometry {
  _DialGeometry(double width, this.gap)
    : radius = width / 2 - 26,
      center = Offset(width / 2, width / 2);

  final PlanInterval gap;
  final Offset center;
  final double radius;

  Rect get track => Rect.fromCircle(center: center, radius: radius);
  double angle(int minute) =>
      _origin + _sweep * (minute - gap.start) / (gap.end - gap.start);

  Offset point(double angle, double distance) =>
      center + Offset(math.cos(angle), math.sin(angle)) * distance;

  ({Offset start, Offset end}) handles(int start, int end) {
    final first = angle(start), last = angle(end);
    final startPoint = point(first, radius), endPoint = point(last, radius);
    if ((startPoint - endPoint).distance >= 26) {
      return (start: startPoint, end: endPoint);
    }
    // Offset nearby handles so short selections still have two drag targets.
    return (start: point(first, radius - 13), end: point(last, radius + 13));
  }

  double pointerAngle(Offset position) {
    final offset = position - center;
    return math.atan2(offset.dy, offset.dx);
  }
}

class _GapDial extends StatefulWidget {
  const _GapDial({
    super.key,
    required this.gap,
    required this.start,
    required this.end,
    required this.onChanged,
  });

  final PlanInterval gap;
  final int start, end;
  final void Function(bool isStart, int minute) onChanged;

  @override
  State<_GapDial> createState() => _GapDialState();
}

class _GapDialState extends State<_GapDial> {
  bool? _draggingStart;
  double _lastAngle = 0, _travel = 0;
  int _anchorMinute = 0;

  int _limit(bool isStart, int minute) => isStart
      ? minute.clamp(widget.gap.start, widget.end - 1)
      : minute.clamp(widget.start + 1, widget.gap.end);

  void _update(bool isStart, int minute) {
    final next = _limit(isStart, minute);
    if (next != (isStart ? widget.start : widget.end)) {
      widget.onChanged(isStart, next);
    }
  }

  bool? _handleAt(_DialGeometry geometry, Offset point) {
    final handles = geometry.handles(widget.start, widget.end);
    final toStart = (point - handles.start).distance;
    final toEnd = (point - handles.end).distance;
    return math.min(toStart, toEnd) <= 26 ? toStart < toEnd : null;
  }

  void _grab(_DialGeometry geometry, Offset point) {
    final isStart = _handleAt(geometry, point);
    _draggingStart = isStart;
    if (isStart == null) return;
    _anchorMinute = isStart ? widget.start : widget.end;
    _lastAngle = geometry.pointerAngle(point);
    _travel = 0;
  }

  void _drag(_DialGeometry geometry, Offset point) {
    final isStart = _draggingStart;
    if (isStart == null || (point - geometry.center).distance < 12) return;
    final angle = geometry.pointerAngle(point);
    _travel += (angle - _lastAngle + math.pi) % _turn - math.pi;
    _lastAngle = angle;
    final minutes = (_travel / _sweep * (widget.gap.end - widget.gap.start))
        .round();
    _update(isStart, _anchorMinute + minutes);
  }

  Widget _readout(BuildContext context, {required bool isStart}) {
    final colors = p.Theme.of(context).colorScheme;
    final minute = isStart ? widget.start : widget.end;
    final label = isStart ? '开始' : '结束';
    final boundary = plannerTime(isStart ? widget.gap.start : widget.gap.end);
    final canDecrease = _limit(isStart, minute - 1) < minute;
    final canIncrease = _limit(isStart, minute + 1) > minute;

    return Column(
      children: [
        Text(
          '$label时间',
          style: p.AppTextStyle.footnote.of(context, emphasized: true),
        ),
        const SizedBox(height: 6),
        p.Surface(
          color: p.SurfaceLevel.block.colorOf(colors),
          shape: p.AppShape.full,
          child: Row(
            children: [
              p.IconButton(
                onPressed: canDecrease
                    ? () => _update(isStart, minute - 1)
                    : null,
                tooltip: '$label时间减 1 分钟',
                iconSize: 18,
                icon: const GlyphIcon(TodoGlyphs.subtract),
              ),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Semantics(
                    label: '$label时间',
                    value: plannerTime(minute),
                    excludeSemantics: true,
                    child: Text(
                      plannerTime(minute),
                      style: p.AppTextStyle.title3
                          .of(context, emphasized: true)
                          .copyWith(
                            color: colors.onSurface,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                    ),
                  ),
                ),
              ),
              p.IconButton(
                onPressed: canIncrease
                    ? () => _update(isStart, minute + 1)
                    : null,
                tooltip: '$label时间加 1 分钟',
                iconSize: 18,
                icon: const GlyphIcon(TodoGlyphs.add),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '空档${isStart ? '起点' : '终点'} $boundary',
          textAlign: TextAlign.center,
          style: p.AppTextStyle.caption1
              .of(context)
              .copyWith(
                color: colors.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = p.Theme.of(context).colorScheme;
    final duration = widget.end - widget.start;
    final hours = duration ~/ 60, minutes = duration % 60;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.maxWidth;
        final geometry = _DialGeometry(size, widget.gap);
        return Column(
          children: [
            RawGestureDetector(
              excludeFromSemantics: true,
              gestures: {
                _HandleDragRecognizer:
                    GestureRecognizerFactoryWithHandlers<_HandleDragRecognizer>(
                      _HandleDragRecognizer.new,
                      (recognizer) =>
                          recognizer.isHandle = (point) =>
                              _handleAt(geometry, point) != null,
                    ),
              },
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (event) => _grab(geometry, event.localPosition),
                onPointerMove: (event) => _drag(geometry, event.localPosition),
                child: CustomPaint(
                  painter: _GapDialFace(
                    geometry: geometry,
                    start: widget.start,
                    end: widget.end,
                    track: colors.secondaryContainer,
                    onTrack: colors.onSecondaryContainer,
                    accent: colors.primary,
                    onAccent: colors.onPrimary,
                    handleSurface: p.SurfaceLevel.card.colorOf(colors),
                  ),
                  child: SizedBox(
                    width: size,
                    height: size * .88,
                    child: Align(
                      alignment: const Alignment(0, .19),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '已选时长',
                            style: p.AppTextStyle.footnote
                                .of(context)
                                .copyWith(color: colors.onSurfaceVariant),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            hours == 0
                                ? '$minutes 分钟'
                                : minutes == 0
                                ? '$hours 小时'
                                : '$hours 小时 $minutes 分钟',
                            style: p.AppTextStyle.title1
                                .of(context, emphasized: true)
                                .copyWith(
                                  color: colors.onSurface,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 8,
              children: [
                Expanded(child: _readout(context, isStart: true)),
                Expanded(child: _readout(context, isStart: false)),
              ],
            ),
          ],
        );
      },
    );
  }
}

// A drag starting on a handle belongs to the dial even when it moves vertically.
class _HandleDragRecognizer extends EagerGestureRecognizer {
  late bool Function(Offset) isHandle;

  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      super.isPointerAllowed(event) && isHandle(event.localPosition);
}

class _GapDialFace extends CustomPainter {
  const _GapDialFace({
    required this.geometry,
    required this.start,
    required this.end,
    required this.track,
    required this.onTrack,
    required this.accent,
    required this.onAccent,
    required this.handleSurface,
  });

  final _DialGeometry geometry;
  final int start, end;
  final Color track, onTrack, accent, onAccent, handleSurface;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 13
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      geometry.track,
      _origin,
      _sweep,
      false,
      paint..color = track,
    );
    final startAngle = geometry.angle(start), endAngle = geometry.angle(end);
    canvas.drawArc(
      geometry.track,
      startAngle,
      endAngle - startAngle,
      false,
      paint..color = accent,
    );

    paint.style = PaintingStyle.fill;
    for (var tick = 0; tick <= 12; tick++) {
      final angle = _origin + _sweep * tick / 12;
      final nearHandle = math.min(
        (angle - startAngle).abs(),
        (angle - endAngle).abs(),
      );
      if (nearHandle * geometry.radius < 10) continue;
      final selected = angle >= startAngle && angle <= endAngle;
      canvas.drawCircle(
        geometry.point(angle, geometry.radius),
        tick % 3 == 0 ? 1.8 : 1.2,
        paint..color = (selected ? onAccent : onTrack).withValues(alpha: .56),
      );
    }

    final handles = geometry.handles(start, end);
    _paintHandle(canvas, handles.start, startAngle, filled: false);
    _paintHandle(canvas, handles.end, endAngle, filled: true);
  }

  void _paintHandle(
    Canvas canvas,
    Offset center,
    double angle, {
    required bool filled,
  }) {
    canvas
      ..save()
      ..translate(center.dx, center.dy)
      ..rotate(angle + math.pi / 2);
    final pill = RSuperellipse.fromRectAndRadius(
      const Rect.fromLTWH(-7, -15, 14, 30),
      const Radius.circular(7),
    );
    final paint = Paint();
    canvas.drawRSuperellipse(
      pill,
      paint..color = filled ? accent : handleSurface,
    );
    canvas.drawRSuperellipse(
      pill,
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = filled ? handleSurface : accent,
    );
    canvas.drawLine(
      const Offset(0, -5),
      const Offset(0, 5),
      paint
        ..strokeCap = StrokeCap.round
        ..color = filled ? onAccent : accent,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GapDialFace old) =>
      start != old.start ||
      end != old.end ||
      geometry.gap != old.geometry.gap ||
      geometry.radius != old.geometry.radius ||
      track != old.track ||
      onTrack != old.onTrack ||
      accent != old.accent ||
      onAccent != old.onAccent ||
      handleSurface != old.handleSurface;
}
