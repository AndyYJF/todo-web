import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart' as p;
import 'package:prism_ui/icons/icons.dart';

import '../data/demo_tasks.dart';
import '../data/task.dart';
import '../data/remote_tasks.dart';
import '../ui/read_status.dart';
import '../ui/task_widgets.dart';
import '../ui/todo_motion.dart';
import '../ui/todo_glyphs.dart';

Future<void> openTaskEditor(
  BuildContext context,
  DemoTaskStore store, {
  TodoTask? task,
}) => showTodoFormSheet<void>(
  context: context,
  props: const p.SheetProps(detents: [0.7, 0.94]),
  builder: (_) => TaskEditor(store: store, task: task),
);

class TaskDetail extends StatelessWidget {
  const TaskDetail({super.key, required this.store, required this.id});
  final RemoteTaskStore store;
  final int id;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final task = store.task(id);
      return p.PrismScaffold(
        bar: todoBar(context, '任务详情', back: true),
        body: Builder(
          builder: (context) => ListView(
            padding: EdgeInsets.fromLTRB(
              20,
              context.appBarInset + 12,
              20,
              32 + MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              ReadStatus(store: store),
              const SizedBox(height: 20),
              if (task == null)
                const EmptyTasks(message: '任务已从最新快照中移除。')
              else ...[
                p.Card(
                  inert: true,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        style: p.AppTextStyle.title2.of(
                          context,
                          emphasized: true,
                        ),
                      ),
                      const SizedBox(height: 18),
                      StatusPill(label: task.done ? '已完成' : '待处理'),
                    ],
                  ),
                ),
                const SectionHeading('任务信息'),
                p.Card(
                  inert: true,
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      p.ListRow(
                        leading: const GlyphIcon(TodoGlyphs.calendar),
                        title: const Text('截止时间'),
                        subtitle: Text(dueLabel(task.dueAt)),
                      ),
                      if (task.startAt != null)
                        p.ListRow(
                          title: const Text('开始时间'),
                          subtitle: Text(dueLabel(task.startAt)),
                        ),
                      p.ListRow(
                        leading: const GlyphIcon(TodoGlyphs.tasks),
                        title: const Text('项目'),
                        subtitle: Text(
                          task.project.isEmpty ? '未分组' : task.project,
                        ),
                      ),
                      p.ListRow(
                        leading: const GlyphIcon(Glyphs.pin),
                        title: const Text('置顶'),
                        trailing: Text(task.pinned ? '是' : '否'),
                      ),
                      p.ListRow(
                        title: const Text('来源'),
                        trailing: Text(
                          task.externalId == null ? '个人任务' : '校园同步',
                        ),
                      ),
                    ],
                  ),
                ),
                const SectionHeading('备注'),
                p.Card(
                  inert: true,
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    task.note.isEmpty ? '暂无备注' : task.note,
                    style: p.AppTextStyle.body.of(context),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'A2 为只读预览，修改操作将在 A3 接入。',
                  style: p.AppTextStyle.footnote.of(context),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

class TaskEditor extends StatefulWidget {
  const TaskEditor({super.key, required this.store, this.task});
  final DemoTaskStore store;
  final TodoTask? task;
  @override
  State<TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends State<TaskEditor> {
  late final TextEditingController _title = TextEditingController(
    text: widget.task?.title ?? '',
  );
  late final TextEditingController _note = TextEditingController(
    text: widget.task?.note ?? '',
  );
  late final TextEditingController _project = TextEditingController(
    text: widget.task?.project ?? '',
  );
  late String _priority = widget.task?.priority ?? 'normal';
  late DateTime? _due = widget.task?.dueAt;
  @override
  void initState() {
    super.initState();
    _title.addListener(_changed);
  }

  void _changed() => setState(() {});
  @override
  void dispose() {
    _title.removeListener(_changed);
    _title.dispose();
    _note.dispose();
    _project.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => p.PrismScaffold(
    resizeToAvoidBottomInset: true,
    bar: todoBar(
      context,
      widget.task == null ? '新建任务' : '编辑任务',
      actions: [
        p.TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        p.IconButton.filled(
          onPressed: _title.text.trim().isEmpty ? null : _save,
          icon: const GlyphIcon(Glyphs.check),
          tooltip: '保存任务',
        ),
      ],
    ),
    body: Builder(
      builder: (context) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, context.appBarInset + 14, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Align(alignment: Alignment.centerLeft, child: DemoBadge()),
            const SectionHeading('想完成什么？'),
            p.TextField(
              controller: _title,
              maxLines: 2,
              maxLength: 120,
              decoration: const p.InputDecoration(hintText: '写下一个清晰的小目标'),
            ),
            const SectionHeading('补充说明'),
            p.TextField(
              controller: _note,
              minLines: 3,
              maxLines: 5,
              decoration: const p.InputDecoration(hintText: '备注、步骤，或一个想法'),
            ),
            const SectionHeading('安排'),
            p.Card(
              onPressed: _pickDate,
              padding: EdgeInsets.zero,
              child: p.ListRow(
                leading: const GlyphIcon(TodoGlyphs.calendar),
                title: const Text('截止时间'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(dueLabel(_due)),
                    const SizedBox(width: 8),
                    const GlyphIcon(Glyphs.chevronForward, size: 16),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            p.TextField(
              controller: _project,
              decoration: const p.InputDecoration(hintText: '项目，例如：学习、个人'),
            ),
            const SectionHeading('优先级'),
            p.SegmentedControl<String>(
              key: MediaQuery.disableAnimationsOf(context)
                  ? ValueKey(_priority)
                  : null,
              segments: const [('low', '低'), ('normal', '普通'), ('high', '高')],
              value: _priority,
              onChanged: (value) => setState(() => _priority = value),
            ),
            const SizedBox(height: 24),
            p.FilledButton(
              onPressed: _title.text.trim().isEmpty ? null : _save,
              child: const Text('保存演示任务'),
            ),
          ],
        ),
      ),
    ),
  );

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    final original = widget.task;
    if (original == null) {
      widget.store.add(
        title: title,
        note: _note.text.trim(),
        project: _project.text.trim(),
        priority: _priority,
        dueAt: _due,
      );
    } else {
      widget.store.save(
        original.copyWith(
          title: title,
          note: _note.text.trim(),
          project: _project.text.trim(),
          priority: _priority,
          dueAt: _due,
          clearDue: _due == null,
        ),
      );
    }
    Navigator.of(context).pop();
  }

  Future<void> _pickDate() async {
    final now = businessNow();
    final day = DateTime.utc(now.year, now.month, now.day);
    final options = <(String, DateTime?)>[
      ('不设日期', null),
      ('今天 20:00', day.add(const Duration(hours: 20))),
      ('明天 18:00', day.add(const Duration(days: 1, hours: 18))),
      ('一周后 18:00', day.add(const Duration(days: 7, hours: 18))),
    ];
    final picked = await showTodoFormSheet<_DueChoice>(
      context: context,
      builder: (sheetContext) => p.PrismScaffold(
        bar: todoBar(
          sheetContext,
          '安排时间',
          actions: [
            p.IconButton(
              onPressed: () => Navigator.of(sheetContext).pop(),
              icon: const GlyphIcon(Glyphs.close),
              tooltip: '关闭',
            ),
          ],
        ),
        body: Builder(
          builder: (context) => ListView(
            shrinkWrap: true,
            padding: EdgeInsets.fromLTRB(20, context.appBarInset + 20, 20, 20),
            children: [
              for (final option in options)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: p.Card(
                    onPressed: () =>
                        Navigator.of(sheetContext).pop(_DueChoice(option.$2)),
                    child: p.ListRow(
                      leading: const GlyphIcon(TodoGlyphs.calendar),
                      title: Text(option.$1),
                      trailing: const GlyphIcon(
                        Glyphs.chevronForward,
                        size: 16,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null && mounted) setState(() => _due = picked.value);
  }
}

class _DueChoice {
  const _DueChoice(this.value);
  final DateTime? value;
}
