import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart' as p;
import 'package:prism_ui/icons/icons.dart';

import '../data/task.dart';
import '../data/task_write.dart';
import '../data/remote_tasks.dart';
import '../data/todo_api.dart';
import '../ui/read_status.dart';
import '../ui/write_notice.dart';
import '../ui/task_widgets.dart';
import '../ui/todo_motion.dart';
import '../ui/todo_glyphs.dart';
import '../ui/service_actions.dart';
import '../ui/rich_note.dart';
import '../ui/task_date_picker.dart';
import '../data/task_views.dart';

Future<void> openTaskEditor(
  BuildContext context,
  RemoteTaskStore store, {
  TodoTask? task,
  TaskDraft? resumeDraft,
}) async {
  var chosen = resumeDraft;
  final existing = store.activeDraft;
  if (chosen == null && existing != null && existing.taskId != task?.id) {
    final discard = await showTodoFormSheet<bool>(
      context: context,
      builder: (context) => p.PrismScaffold(
        bar: todoBar(
          context,
          '有未保存的草稿',
          actions: [
            p.TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
          ],
        ),
        body: Builder(
          builder: (context) => Padding(
            padding: EdgeInsets.fromLTRB(24, context.appBarInset + 20, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('可以继续原草稿，或丢弃草稿后打开当前任务。'),
                const SizedBox(height: 20),
                p.FilledButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('继续原草稿'),
                ),
                p.TextButton(
                  onPressed: store.pending != null
                      ? null
                      : () => Navigator.of(context).pop(true),
                  child: const Text('丢弃草稿并继续'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (discard == null || !context.mounted) return;
    if (discard) {
      await store.saveDraft(null);
    } else {
      chosen = existing;
    }
  }
  if (!context.mounted) return;
  chosen ??= store.activeDraft?.taskId == task?.id ? store.activeDraft : null;
  final resuming = chosen != null;
  chosen ??= TaskDraft.open(store.origin, task);
  await showTodoFormSheet<void>(
    context: context,
    props: const p.SheetProps(detents: [.7, .94]),
    builder: (_) =>
        TaskEditor(store: store, draft: chosen!, resuming: resuming),
  );
}

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
        bar: todoBar(
          context,
          '任务详情',
          back: true,
          actions: [
            if (task != null)
              p.IconButton(
                onPressed: store.writing
                    ? null
                    : () => openTaskEditor(context, store, task: task),
                icon: const GlyphIcon(TodoGlyphs.edit),
                tooltip: '编辑任务',
              ),
          ],
        ),
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
                      Row(
                        children: [
                          p.Checkbox(
                            value: task.done,
                            isCircle: true,
                            onChanged: store.canWrite
                                ? (value) =>
                                      store.patchTask(id, {'done': value})
                                : null,
                          ),
                          Text(task.done ? '已完成' : '待处理'),
                        ],
                      ),
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
                        trailing: p.Switch(
                          value: task.pinned,
                          onChanged: store.canWrite
                              ? (value) =>
                                    store.patchTask(id, {'pinned': value})
                              : null,
                        ),
                      ),
                      p.ListRow(
                        leading: const GlyphIcon(TodoGlyphs.quadrant),
                        title: const Text('象限'),
                        subtitle: Text(
                          quadrantLabel(task.urgent, task.important),
                        ),
                        trailing: p.IconButton(
                          icon: const GlyphIcon(Glyphs.chevronForward),
                          tooltip: '选择象限',
                          onPressed: store.canWrite
                              ? () => chooseQuadrant(context, store, id)
                              : null,
                        ),
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
                  child: RichNote(store: store, text: task.note),
                ),
                const SizedBox(height: 24),
                p.TextButton.icon(
                  onPressed: store.canWrite
                      ? () => _delete(context, task)
                      : null,
                  icon: GlyphIcon(
                    TodoGlyphs.trash,
                    color: p.Theme.of(context).colorScheme.error,
                  ),
                  label: Text(
                    '删除任务',
                    style: TextStyle(
                      color: p.Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
  Future<void> _delete(BuildContext context, TodoTask task) async {
    final confirmed = await showTodoFormSheet<bool>(
      context: context,
      builder: (context) => p.PrismScaffold(
        bar: todoBar(
          context,
          '删除任务',
          actions: [
            p.TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
          ],
        ),
        body: Builder(
          builder: (context) => Padding(
            padding: EdgeInsets.fromLTRB(24, context.appBarInset + 24, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('确认从服务端删除这条任务？此操作无法撤销。'),
                const SizedBox(height: 12),
                Text(task.title),
                const SizedBox(height: 24),
                p.FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: p.ButtonStyle.from(
                    backgroundColor: p.Theme.of(context).colorScheme.error,
                  ),
                  child: const Text('确认删除'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (confirmed != true) return;
    final outcome = await store.deleteTask(id);
    if (outcome.succeeded && context.mounted) Navigator.of(context).pop();
  }
}

class TaskEditor extends StatefulWidget {
  const TaskEditor({
    super.key,
    required this.store,
    required this.draft,
    required this.resuming,
  });
  final RemoteTaskStore store;
  final TaskDraft draft;
  final bool resuming;
  @override
  State<TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends State<TaskEditor> {
  final _title = TextEditingController(),
      _note = TextEditingController(),
      _project = TextEditingController(),
      _start = TextEditingController(),
      _due = TextEditingController();
  late TaskDraft _draft;
  String _priority = 'normal';
  bool _quick = false,
      _pinned = false,
      _loading = false,
      _fresh = true,
      _missing = false,
      _closing = false,
      _touched = false;
  String? _error;
  Timer? _debounce;
  RemoteTaskStore get store => widget.store;
  bool get _locked => store.writing || store.pending != null;
  bool get _canSave =>
      !_loading &&
      _fresh &&
      !_missing &&
      !_locked &&
      store.canWrite &&
      _title.text.trim().isNotEmpty;
  @override
  void initState() {
    super.initState();
    _draft = widget.draft;
    _apply(_draft);
    for (final controller in [_title, _note, _project, _start, _due]) {
      controller.addListener(_changed);
    }
    store.addListener(_storeChanged);
    if (_draft.taskId != null) unawaited(_load());
  }

  void _apply(TaskDraft draft) {
    _title.text = draft.values['title'] as String;
    _note.text = draft.values['note'] as String;
    _project.text = draft.values['project'] as String;
    _start.text = draft.values['startAt'] as String? ?? '';
    _due.text = draft.values['dueAt'] as String? ?? '';
    _priority = draft.values['priority'] as String;
    _quick = draft.values['quick'] as bool;
    _pinned = draft.values['pinned'] as bool;
  }

  TaskDraft _current() => _draft.withValues({
    'title': _title.text,
    'note': _note.text,
    'project': _project.text,
    'priority': _priority,
    'startAt': _start.text.trim().isEmpty ? null : _start.text,
    'dueAt': _due.text.trim().isEmpty ? null : _due.text,
    'quick': _quick,
    'pinned': _pinned,
  });
  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final task = await store.loadTaskForEdit(_draft.taskId!);
      if (!mounted) return;
      if (task == null) {
        _missing = true;
        _fresh = false;
        _error = '任务已在其他端删除。草稿保留，不会自动重建。';
      } else {
        _missing = false;
        _fresh = true;
        _error = null;
        if (!widget.resuming && !_touched) {
          _draft = TaskDraft.open(store.origin, task);
          _apply(_draft);
        }
      }
    } catch (e) {
      if (mounted) {
        _fresh = false;
        _error = e is ApiFailure ? e.message : '暂时无法核对服务端任务，草稿已保留';
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _changed() {
    if (_loading || _closing) return;
    _touched = true;
    setState(() => _error = null);
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => store.saveDraft(_current()),
    );
  }

  void _storeChanged() {
    if (store.lastCompletedDraftKey == _draft.key) _finish();
  }

  void _finish() {
    if (_closing || !mounted) return;
    _closing = true;
    _debounce?.cancel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    store.removeListener(_storeChanged);
    if (!_closing) {
      final current = _current();
      scheduleMicrotask(() => store.saveDraft(current));
    }
    for (final controller in [_title, _note, _project, _start, _due]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_canSave) return;
    _debounce?.cancel();
    final draft = _current();
    Map<String, dynamic> fields;
    try {
      fields = draft.payload();
    } on FormatException catch (e) {
      setState(() => _error = e.message);
      return;
    }
    await store.saveDraft(draft);
    if (draft.taskId != null && fields.isEmpty) {
      await store.saveDraft(null);
      _finish();
      return;
    }
    final outcome = draft.taskId == null
        ? await store.createTask(fields, draftKey: draft.key)
        : await store.patchTask(draft.taskId!, fields, draftKey: draft.key);
    if (!mounted) return;
    if (outcome.succeeded) {
      _finish();
    } else {
      setState(() => _error = outcome.message);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) => p.PrismScaffold(
      bar: todoBar(
        context,
        _draft.taskId == null ? '新建任务' : '编辑任务',
        actions: [
          p.TextButton(
            onPressed: store.writing ? null : () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
          p.IconButton.filled(
            onPressed: _canSave ? _save : null,
            icon: store.writing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: p.ActivityIndicator(),
                  )
                : const GlyphIcon(Glyphs.check),
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
              const Text('草稿自动保存在本机；保存后提交到服务端。'),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: p.ActivityIndicator()),
                ),
              if (store.cached)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text('当前为缓存，可继续填写草稿，联网刷新后再提交。'),
                ),
              if (store.readAt == null)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text('尚未取得服务端数据，联网刷新后可提交。'),
                ),
              if (store.cached || store.readAt == null)
                p.TextButton(
                  onPressed: store.refreshing || store.writing
                      ? null
                      : () => store.refresh(),
                  child: const Text('重新读取服务端'),
                ),
              WriteNotice(store: store),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: p.Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (!_fresh && !_missing && !_loading)
                p.TextButton(onPressed: _load, child: const Text('重新核对服务端任务')),
              const SectionHeading('想完成什么？'),
              p.TextField(
                controller: _title,
                enabled: !_locked && !_loading,
                maxLines: 2,
                maxLength: 120,
                decoration: const p.InputDecoration(hintText: '写下一个清晰的小目标'),
              ),
              const SectionHeading('补充说明'),
              p.TextField(
                controller: _note,
                enabled: !_locked && !_loading,
                minLines: 3,
                maxLines: 5,
                decoration: const p.InputDecoration(hintText: '备注、步骤，或一个想法'),
              ),
              const SectionHeading('安排'),
              p.Card(
                inert: true,
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    p.ListRow(
                      title: const Text('开始时间'),
                      subtitle: Text(_start.text.isEmpty ? '未设置' : _start.text),
                      trailing: p.IconButton(
                        icon: const GlyphIcon(TodoGlyphs.calendar),
                        tooltip: '选择开始时间',
                        onPressed: _locked || _loading
                            ? null
                            : () => _pickDate(_start, '选择开始时间'),
                      ),
                    ),
                    p.ListRow(
                      title: const Text('截止时间'),
                      subtitle: Text(_due.text.isEmpty ? '未设置' : _due.text),
                      trailing: p.IconButton(
                        icon: const GlyphIcon(TodoGlyphs.calendar),
                        tooltip: '选择截止时间',
                        onPressed: _locked || _loading
                            ? null
                            : () => _pickDate(_due, '选择截止时间'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              p.TextField(
                controller: _project,
                enabled: !_locked && !_loading,
                decoration: const p.InputDecoration(hintText: '项目，例如：学习、个人'),
              ),
              const SectionHeading('优先级'),
              IgnorePointer(
                ignoring: _locked || _loading,
                child: p.SegmentedControl<String>(
                  key: MediaQuery.disableAnimationsOf(context)
                      ? ValueKey(_priority)
                      : null,
                  segments: const [
                    ('low', '低'),
                    ('normal', '普通'),
                    ('high', '高'),
                  ],
                  value: _priority,
                  onChanged: (value) {
                    setState(() => _priority = value);
                    _changed();
                  },
                ),
              ),
              const SizedBox(height: 16),
              p.Card(
                inert: true,
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    p.ListRow(
                      title: const Text('置顶'),
                      trailing: p.Switch(
                        value: _pinned,
                        onChanged: _locked || _loading
                            ? null
                            : (value) {
                                setState(() => _pinned = value);
                                _changed();
                              },
                      ),
                    ),
                    p.ListRow(
                      title: const Text('快速任务'),
                      trailing: p.Switch(
                        value: _quick,
                        onChanged: _locked || _loading
                            ? null
                            : (value) {
                                setState(() => _quick = value);
                                _changed();
                              },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              p.FilledButton(
                onPressed: _canSave ? _save : null,
                child: Text(store.writing ? '正在提交' : '保存任务'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  Future<void> _pickDate(TextEditingController controller, String title) async {
    final picked = await pickTaskDate(
      context,
      title: title,
      value: controller.text.isEmpty ? null : controller.text,
    );
    if (picked != null && mounted) controller.text = picked.value ?? '';
  }
}
