import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart' as p;
import 'package:prism_ui/icons/icons.dart';

import '../data/task.dart';
import '../data/task_views.dart';

class MonthCalendar extends StatelessWidget {
  const MonthCalendar({
    super.key,
    required this.month,
    required this.selected,
    required this.onSelected,
    required this.onMonthDelta,
    required this.onToday,
    this.counts = const {},
  });
  final DateTime month, selected;
  final ValueChanged<DateTime> onSelected;
  final ValueChanged<int> onMonthDelta;
  final VoidCallback onToday;
  final Map<DateTime, int> counts;
  @override
  Widget build(BuildContext context) {
    final colors = p.Theme.of(context).colorScheme;
    final first = DateTime.utc(month.year, month.month);
    final start = first.subtract(Duration(days: first.weekday - 1));
    final today = taskDay(businessNow());
    return p.Card(
      inert: true,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                p.IconButton(
                  onPressed: () => onMonthDelta(-1),
                  icon: const GlyphIcon(Glyphs.chevronBack),
                  tooltip: '上个月',
                ),
                Expanded(
                  child: Text(
                    '${month.year}年${month.month}月',
                    textAlign: TextAlign.center,
                    style: p.AppTextStyle.title3.of(context, emphasized: true),
                  ),
                ),
                p.TextButton(onPressed: onToday, child: const Text('今天')),
                p.IconButton(
                  onPressed: () => onMonthDelta(1),
                  icon: const GlyphIcon(Glyphs.chevronForward),
                  tooltip: '下个月',
                ),
              ],
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: math.max(336, constraints.maxWidth),
                child: Column(
                  children: [
                    Row(
                      children: [
                        for (final day in ['一', '二', '三', '四', '五', '六', '日'])
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                day,
                                textAlign: TextAlign.center,
                                style: p.AppTextStyle.caption1
                                    .of(context)
                                    .copyWith(color: colors.onSurfaceVariant),
                              ),
                            ),
                          ),
                      ],
                    ),
                    for (var week = 0; week < 6; week++)
                      Row(
                        children: [
                          for (var weekday = 0; weekday < 7; weekday++)
                            Expanded(
                              child: Builder(
                                builder: (context) {
                                  final day = start.add(
                                        Duration(days: week * 7 + weekday),
                                      ),
                                      count =
                                          counts[start.add(
                                            Duration(days: week * 7 + weekday),
                                          )] ??
                                          0;
                                  final active = taskDay(selected) == day,
                                      currentMonth = day.month == month.month;
                                  final ink = active
                                      ? colors.onPrimary
                                      : currentMonth
                                      ? colors.onSurface
                                      : colors.onSurfaceVariant.withValues(
                                          alpha: .55,
                                        );
                                  return Semantics(
                                    button: true,
                                    onTap: () => onSelected(day),
                                    selected: active,
                                    label:
                                        '${day.year}年${day.month}月${day.day}日，$count项任务',
                                    excludeSemantics: true,
                                    child: p.PressRegion(
                                      onTap: () => onSelected(day),
                                      shape: p.AppShape.md,
                                      child: Padding(
                                        padding: const EdgeInsets.all(2),
                                        child: p.Surface(
                                          color: active
                                              ? colors.primary
                                              : day == today
                                              ? colors.primary.withValues(
                                                  alpha: .1,
                                                )
                                              : const Color(0x00000000),
                                          shape: p.AppShape.md,
                                          child: SizedBox(
                                            height: 48,
                                            child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Text(
                                                  day.day.toString(),
                                                  style: p.AppTextStyle.callout
                                                      .of(
                                                        context,
                                                        emphasized:
                                                            active ||
                                                            day == today,
                                                      )
                                                      .copyWith(color: ink),
                                                ),
                                                const SizedBox(height: 4),
                                                SizedBox(
                                                  height: 4,
                                                  child: Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .center,
                                                    children: [
                                                      for (
                                                        var dot = 0;
                                                        dot <
                                                            math.min(3, count);
                                                        dot++
                                                      )
                                                        Padding(
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                horizontal: 1,
                                                              ),
                                                          child: Container(
                                                            width: 3,
                                                            height: 3,
                                                            decoration: BoxDecoration(
                                                              shape: BoxShape
                                                                  .circle,
                                                              color: active
                                                                  ? colors
                                                                        .onPrimary
                                                                  : colors
                                                                        .primary,
                                                            ),
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
