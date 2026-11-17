import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart' as p;
import 'package:prism_ui/icons/icons.dart';

import '../data/remote_tasks.dart';
import '../data/task.dart';
import '../data/task_views.dart';
import '../ui/month_calendar.dart';
import '../ui/read_status.dart';
import '../ui/task_widgets.dart';
import '../ui/todo_motion.dart';
import 'task_detail.dart';

Widget viewTaskTile(
  BuildContext context,
  RemoteTaskStore store,
  TodoTask task,
) => TaskTile(
  key: ValueKey(task.id),
  task: task,
  onToggle: store.canWrite
      ? () => store.patchTask(task.id, {'done': !task.done})
      : null,
  onOpen: () => Navigator.of(context).push(
    todoPageRoute<void>(context, (_) => TaskDetail(store: store, id: task.id)),
  ),
);
Widget statusFilter(
  BuildContext context,
  int value,
  ValueChanged<int> onChanged,
) => p.SegmentedControl<int>(
  key: MediaQuery.disableAnimationsOf(context) ? ValueKey(value) : null,
  segments: const [(0, '全部'), (1, '待办'), (2, '完成')],
  value: value,
  onChanged: onChanged,
);
bool matchesStatus(TodoTask task, int filter) =>
    filter == 0 || (filter == 1 ? !task.done : task.done);

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key, required this.store});
  final RemoteTaskStore store;
  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  DateTime _selected = taskDay(businessNow());
  late DateTime _month = DateTime.utc(_selected.year, _selected.month);
  int _filter = 1;
  bool _undated = false;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      final store = widget.store,
          tasks = store.tasks.where((t) => matchesStatus(t, _filter)).toList();
      final list = tasks
          .where(
            (t) => _undated
                ? t.startAt == null && t.dueAt == null
                : taskOnDay(t, _selected),
          )
          .toList();
      final first = DateTime.utc(_month.year, _month.month);
      final start = first.subtract(Duration(days: first.weekday - 1));
      final counts = <DateTime, int>{
        for (var i = 0; i < 42; i++)
          start.add(Duration(days: i)): tasks
              .where((t) => taskOnDay(t, start.add(Duration(days: i))))
              .length,
      };
      return p.PrismScaffold(
        bar: todoBar(context, '日历', back: true),
        body: Builder(
          builder: (context) => ListView(
            padding: EdgeInsets.fromLTRB(12, context.appBarInset + 12, 12, 32),
            children: [
              ReadStatus(store: store),
              const SizedBox(height: 16),
              statusFilter(
                context,
                _filter,
                (v) => setState(() => _filter = v),
              ),
              const SizedBox(height: 16),
              MonthCalendar(
                month: _month,
                selected: _selected,
                counts: counts,
                onSelected: (day) => setState(() {
                  _selected = day;
                  _month = DateTime.utc(day.year, day.month);
                  _undated = false;
                }),
                onMonthDelta: (delta) => setState(
                  () =>
                      _month = DateTime.utc(_month.year, _month.month + delta),
                ),
                onToday: () => setState(() {
                  _selected = taskDay(businessNow());
                  _month = DateTime.utc(_selected.year, _selected.month);
                  _undated = false;
                }),
              ),
              const SizedBox(height: 8),
              Text(
                '按 UTC+8 展示；起止时间之间的每一天均显示任务。',
                style: p.AppTextStyle.caption1.of(context),
              ),
              p.TextButton(
                onPressed: () => setState(() => _undated = !_undated),
                child: Text(_undated ? '查看已选日期' : '查看未设日期任务'),
              ),
              SectionHeading(
                _undated ? '未设日期' : '${_selected.month}月${_selected.day}日',
                trailing: '${list.length} 件',
              ),
              if (list.isEmpty)
                EmptyTasks(message: _undated ? '没有未设日期的任务。' : '这一天暂时没有任务。'),
              for (final task in list) viewTaskTile(context, store, task),
            ],
          ),
        ),
      );
    },
  );
}

class ProjectsPage extends StatefulWidget {
  const ProjectsPage({super.key, required this.store});
  final RemoteTaskStore store;
  @override
  State<ProjectsPage> createState() => _ProjectsPageState();
}

class _ProjectsPageState extends State<ProjectsPage> {
  String _query = '';
  final _search = TextEditingController();
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      final store = widget.store;
      final names = projectNames(store.tasks, store.projects)
          .where(
            (n) => (n.isEmpty ? '未分组' : n).toLowerCase().contains(
              _query.toLowerCase(),
            ),
          )
          .toList();
      return p.PrismScaffold(
        bar: todoBar(context, '项目', back: true),
        body: Builder(
          builder: (context) => ListView(
            padding: EdgeInsets.fromLTRB(20, context.appBarInset + 12, 20, 32),
            children: [
              ReadStatus(store: store),
              const SizedBox(height: 16),
              p.TextField(
                controller: _search,
                onChanged: (v) => setState(() => _query = v),
                decoration: const p.InputDecoration(
                  hintText: '搜索项目',
                  prefixIcon: GlyphIcon(Glyphs.search),
                ),
              ),
              const SectionHeading('项目分组'),
              if (names.isEmpty) const EmptyTasks(message: '没有匹配的项目。'),
              for (final name in names)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: p.Card(
                    onPressed: () => Navigator.of(context).push(
                      todoPageRoute<void>(
                        context,
                        (_) => ProjectTasksPage(store: store, project: name),
                      ),
                    ),
                    child: p.ListRow(
                      title: Text(name.isEmpty ? '未分组' : name),
                      subtitle: Text(
                        '待办 ${store.tasks.where((t) => t.project == name && !t.done).length} · 共 ${store.tasks.where((t) => t.project == name).length} 件',
                      ),
                      trailing: const GlyphIcon(Glyphs.chevronForward),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

class ProjectTasksPage extends StatefulWidget {
  const ProjectTasksPage({
    super.key,
    required this.store,
    required this.project,
  });
  final RemoteTaskStore store;
  final String project;
  @override
  State<ProjectTasksPage> createState() => _ProjectTasksPageState();
}

class _ProjectTasksPageState extends State<ProjectTasksPage> {
  int _filter = 0;
  String _query = '';
  final _search = TextEditingController();
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      final store = widget.store;
      final tasks = store.tasks
          .where(
            (t) =>
                t.project == widget.project &&
                matchesStatus(t, _filter) &&
                (t.title + t.note).toLowerCase().contains(_query.toLowerCase()),
          )
          .toList();
      return p.PrismScaffold(
        bar: todoBar(
          context,
          widget.project.isEmpty ? '未分组' : widget.project,
          back: true,
        ),
        body: Builder(
          builder: (context) => ListView(
            padding: EdgeInsets.fromLTRB(20, context.appBarInset + 12, 20, 32),
            children: [
              ReadStatus(store: store),
              const SizedBox(height: 16),
              p.TextField(
                controller: _search,
                onChanged: (v) => setState(() => _query = v),
                decoration: const p.InputDecoration(hintText: '搜索项目中的任务'),
              ),
              const SizedBox(height: 16),
              statusFilter(
                context,
                _filter,
                (v) => setState(() => _filter = v),
              ),
              SectionHeading('任务', trailing: '${tasks.length} 件'),
              if (tasks.isEmpty) const EmptyTasks(message: '这里暂时没有任务。'),
              for (final task in tasks) viewTaskTile(context, store, task),
            ],
          ),
        ),
      );
    },
  );
}
