import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart' as p;

import '../../data/planner_models.dart';
import '../../ui/month_calendar.dart';
import '../../ui/task_widgets.dart';
import '../../ui/todo_motion.dart';

Future<String?> selectPlannerDate(
  BuildContext context, {
  required String date,
  required String earliest,
}) {
  var selected = DateTime.parse('${date}T00:00:00Z');
  var month = DateTime.utc(selected.year, selected.month);
  return showTodoFormSheet<String>(
    context: context,
    props: const p.SheetProps(detents: [0.94]),
    builder: (context) => StatefulBuilder(
      builder: (context, update) => p.PrismScaffold(
        bar: todoBar(
          context,
          '选择日期',
          actions: [
            p.TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
          ],
        ),
        body: Builder(
          builder: (context) => ListView(
            padding: EdgeInsets.fromLTRB(16, context.appBarInset + 14, 16, 24),
            children: [
              MonthCalendar(
                month: month,
                selected: selected,
                onSelected: (value) => update(() {
                  selected = value;
                  month = DateTime.utc(value.year, value.month);
                }),
                onMonthDelta: (delta) => update(() {
                  month = DateTime.utc(month.year, month.month + delta);
                }),
                onToday: () => update(() {
                  selected = DateTime.parse('${plannerToday()}T00:00:00Z');
                  month = DateTime.utc(selected.year, selected.month);
                }),
              ),
              const SizedBox(height: 12),
              p.FilledButton(
                onPressed:
                    plannerDate(selected).compareTo(earliest) < 0 ||
                        selected.year > 2099
                    ? null
                    : () => Navigator.of(context).pop(plannerDate(selected)),
                child: Text('选择 ${plannerDate(selected)}'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class PlannerNotice extends StatelessWidget {
  const PlannerNotice(this.message, {super.key, this.error = false});
  final String message;
  final bool error;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Semantics(
      liveRegion: true,
      child: Text(
        message,
        style: p.AppTextStyle.footnote
            .of(context)
            .copyWith(
              color: error ? p.Theme.of(context).colorScheme.error : null,
            ),
      ),
    ),
  );
}
