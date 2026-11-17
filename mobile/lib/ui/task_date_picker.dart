import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart' as p;
import 'package:prism_ui/icons/icons.dart';

import '../data/task.dart';
import '../data/task_views.dart';
import 'month_calendar.dart';
import 'task_widgets.dart';
import 'todo_motion.dart';

class TaskDateChoice {
  const TaskDateChoice(this.value);
  final String? value;
}

Future<TaskDateChoice?> pickTaskDate(
  BuildContext context, {
  required String title,
  String? value,
}) => showTodoFormSheet<TaskDateChoice>(
  context: context,
  props: const p.SheetProps(detents: [.94]),
  builder: (_) => _TaskDatePicker(title: title, value: value),
);

class _TaskDatePicker extends StatefulWidget {
  const _TaskDatePicker({required this.title, this.value});
  final String title;
  final String? value;
  @override
  State<_TaskDatePicker> createState() => _TaskDatePickerState();
}

class _TaskDatePickerState extends State<_TaskDatePicker> {
  late DateTime _selected, _month;
  final _time = TextEditingController();
  String? _error;
  @override
  void initState() {
    super.initState();
    DateTime? initial;
    try {
      initial = parseBusinessDate(widget.value);
    } catch (_) {}
    final now = businessNow();
    _selected = taskDay(initial ?? now);
    _month = DateTime.utc(_selected.year, _selected.month);
    _time.text = initial == null
        ? '18:00'
        : '${initial.hour.toString().padLeft(2, '0')}:${initial.minute.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _time.dispose();
    super.dispose();
  }

  void _save() {
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(_time.text.trim());
    if (match == null ||
        int.parse(match[1]!) > 23 ||
        int.parse(match[2]!) > 59) {
      setState(() => _error = '请填写有效时间，例如 18:00');
      return;
    }
    final value = DateTime.utc(
      _selected.year,
      _selected.month,
      _selected.day,
      int.parse(match[1]!),
      int.parse(match[2]!),
    );
    Navigator.of(context).pop(TaskDateChoice(businessDateString(value)));
  }

  @override
  Widget build(BuildContext context) => p.PrismScaffold(
    bar: todoBar(
      context,
      widget.title,
      actions: [
        p.TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        p.IconButton.filled(
          onPressed: _save,
          icon: const GlyphIcon(Glyphs.check),
          tooltip: '应用时间',
        ),
      ],
    ),
    body: Builder(
      builder: (context) => ListView(
        padding: EdgeInsets.fromLTRB(12, context.appBarInset + 12, 12, 24),
        children: [
          MonthCalendar(
            month: _month,
            selected: _selected,
            onSelected: (day) => setState(() {
              _selected = day;
              _month = DateTime.utc(day.year, day.month);
            }),
            onMonthDelta: (delta) => setState(
              () => _month = DateTime.utc(_month.year, _month.month + delta),
            ),
            onToday: () => setState(() {
              _selected = taskDay(businessNow());
              _month = DateTime.utc(_selected.year, _selected.month);
            }),
          ),
          const SizedBox(height: 16),
          Text(
            '已选：${_selected.year}年${_selected.month}月${_selected.day}日（UTC+8）',
            style: p.AppTextStyle.headline.of(context),
          ),
          const SizedBox(height: 12),
          p.TextField(
            controller: _time,
            keyboardType: TextInputType.datetime,
            decoration: const p.InputDecoration(hintText: '时间 HH:mm'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: TextStyle(color: p.Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 16),
          p.FilledButton(onPressed: _save, child: const Text('应用时间')),
          p.TextButton(
            onPressed: () =>
                Navigator.of(context).pop(const TaskDateChoice(null)),
            child: const Text('不设置时间'),
          ),
        ],
      ),
    ),
  );
}
