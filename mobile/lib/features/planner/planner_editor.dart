import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart' as p;
import 'package:prism_ui/icons/icons.dart';

import '../../data/planner_client.dart';
import '../../data/planner_models.dart';
import '../../data/task.dart';
import '../../data/todo_api.dart';
import '../../ui/task_widgets.dart';
import '../../ui/todo_glyphs.dart';
import '../../ui/todo_motion.dart';
import 'planner_controls.dart';

class PlannerEditor extends StatefulWidget {
  const PlannerEditor({
    super.key,
    required this.client,
    required this.initial,
    required this.earliest,
    required this.today,
    required this.issuedAt,
  });
  final PlannerClient client;
  final Map<String, dynamic> initial;
  final String earliest, today;
  final int Function() issuedAt;

  @override
  State<PlannerEditor> createState() => _PlannerEditorState();
}

class _PlannerEditorState extends State<PlannerEditor> {
  late final String _date;
  late String _target;
  PlanItem? _base, _conflict;
  int? _todoId;
  late PlanStatus _status;
  late bool _history, _canCorrectHistory;
  late final TextEditingController _title, _start, _end, _note;
  Map<String, dynamic>? _pending;
  bool _busy = false, _remove = false;
  String? _error;
  bool get _locked => _busy || _pending != null;
  static final _time = RegExp(r'^(0[0-9]|1[0-9]|2[0-3]):[0-5][0-9]$');

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _date = initial['date'] as String;
    _target = initial['target'] as String? ?? _date;
    _pending = initial['pending'] as Map<String, dynamic>?;
    _history = initial['correctHistory'] == true;
    _canCorrectHistory = initial['canCorrectHistory'] == true;
    _error = initial['error'] as String?;
    if (initial['conflict'] case final Map conflict) {
      _conflict = PlanItem.fromJson(conflict);
    }
    final base = initial['base'] as Map<String, dynamic>?;
    if (base != null) _base = PlanItem.fromJson(base);
    final fields = initial['fields'] as Map<String, dynamic>? ?? {};
    _todoId = fields['todoId'] as int?;
    _status = fields.containsKey('status')
        ? PlanStatus.decode(fields['status'])
        : _base?.status ?? PlanStatus.pending;
    _title = TextEditingController(text: fields['title'] as String?);
    _start = TextEditingController(text: fields['startTime'] as String?);
    _end = TextEditingController(text: fields['endTime'] as String?);
    _note = TextEditingController(text: fields['note'] as String?);
  }

  @override
  void dispose() {
    for (final controller in [_title, _start, _end, _note]) {
      controller.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> _fields() => {
    'title': _title.text.trim(),
    'startTime': _start.text.trim().isEmpty ? null : _start.text.trim(),
    'endTime': _end.text.trim().isEmpty ? null : _end.text.trim(),
    'note': _note.text,
    'status': _status.name,
    'todoId': _todoId,
  };

  Map<String, dynamic> _difference(Map<String, dynamic> fields, PlanItem item) {
    final prior = item.fields();
    return Map.fromEntries(
      fields.entries.where((entry) => entry.value != prior[entry.key]),
    );
  }

  Future<void> _remember() => widget.client.saveDraft({
    'date': _date,
    'target': _target,
    'base': _base?.toJson(),
    'fields': _fields(),
    'pending': _pending,
    'conflict': _conflict?.toJson(),
    'correctHistory': _history,
    'canCorrectHistory': _canCorrectHistory,
    'error': _error,
  });

  Future<void> _pickDate() async {
    final value = await selectPlannerDate(
      context,
      date: _target,
      earliest: widget.earliest,
    );
    if (!mounted || value == null) return;
    setState(() => _target = value);
    await _remember();
  }

  Future<void> _pickTodo(List<TodoTask> tasks) async {
    final task = await showTodoFormSheet<TodoTask>(
      context: context,
      props: const p.SheetProps(detents: [0.94]),
      builder: (context) => p.PrismScaffold(
        bar: todoBar(
          context,
          '从待办选择',
          actions: [
            p.TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
          ],
        ),
        body: Builder(
          builder: (context) => ListView.separated(
            padding: EdgeInsets.fromLTRB(16, context.appBarInset + 12, 16, 24),
            itemCount: tasks.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final task = tasks[index];
              return p.Card(
                padding: EdgeInsets.zero,
                onPressed: () => Navigator.of(context).pop(task),
                child: p.ListRow(title: Text(task.title)),
              );
            },
          ),
        ),
      ),
    );
    if (!mounted || task == null) return;
    setState(() {
      _todoId = task.id;
      _title.text = task.title;
    });
    await _remember();
  }

  Future<void> _submit({bool remove = false}) async {
    if (_busy || _conflict != null || _canCorrectHistory) return;
    final fields = _fields();
    final start = fields['startTime'] as String?,
        end = fields['endTime'] as String?;
    if (_pending == null &&
        !remove &&
        ((fields['title'] as String).isEmpty ||
            (start == null) != (end == null) ||
            (start != null &&
                (!_time.hasMatch(start) ||
                    !_time.hasMatch(end!) ||
                    start.compareTo(end) >= 0)))) {
      setState(() => _error = '填好安排名称，时间两项可留空，或填入有效的 HH:mm 起止时间');
      return;
    }

    final base = _base;
    final diff = base == null ? fields : _difference(fields, base);
    final action = remove
        ? 'delete'
        : base == null
        ? 'create'
        : _target == _date
        ? 'edit'
        : 'move';
    if (_pending == null && action == 'edit' && diff.isEmpty) {
      await widget.client.saveDraft(null);
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final body =
        _pending ??
        {
          'action': action,
          'operationId': newPlannerOperation(),
          'issuedAt': widget.issuedAt(),
          'date': action == 'create' ? _target : _date,
          if (base != null) 'itemId': base.id,
          if (base != null) 'baseVersion': base.version,
          if (action == 'move') 'targetDate': _target,
          if (_history) 'correctHistory': true,
          if (action == 'create' || diff.isNotEmpty && action != 'delete')
            'fields': diff,
        };
    setState(() {
      _busy = true;
      _error = null;
      _pending = body;
    });
    final navigator = Navigator.of(context);
    FocusScope.of(context).unfocus();
    await _remember();
    try {
      await widget.client.write(body);
      await widget.client.saveDraft(null);
      if (mounted) {
        navigator.pop((body['targetDate'] ?? body['date']) as String);
      }
    } on ApiFailure catch (error) {
      if (!error.uncertain) _pending = null;
      if (error is PlannerApiFailure &&
          error.code == 'item_conflict' &&
          error.current != null) {
        _conflict = PlanItem.fromJson(error.current!);
      }
      if (!_history &&
          error is PlannerApiFailure &&
          error.statusCode == 409 &&
          error.code == 'history_read_only' &&
          body['action'] == 'edit') {
        _canCorrectHistory = true;
      }
      _error = error.uncertain ? '提交结果待确认。重试会使用同一操作，避免重复保存。' : error.message;
      await _remember();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _rebase() {
    final latest = _conflict!;
    final changed = _difference(_fields(), _base!);
    final fields = {...latest.fields(), ...changed};
    _title.text = fields['title'] as String;
    _start.text = fields['startTime'] as String? ?? '';
    _end.text = fields['endTime'] as String? ?? '';
    _note.text = fields['note'] as String;
    setState(() {
      _base = latest;
      _status = PlanStatus.decode(fields['status']);
      _todoId = fields['todoId'] as int?;
      _conflict = null;
      _error = null;
      _remove = false;
    });
    _remember();
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    int? maxLength,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) => p.TextField(
    controller: controller,
    enabled: !_locked,
    maxLength: maxLength,
    maxLines: maxLines,
    keyboardType: keyboardType,
    decoration: p.InputDecoration(hintText: label),
    onChanged: (_) {
      _remember();
    },
  );

  @override
  Widget build(BuildContext context) {
    final tasks = widget.client.store.tasks
        .where((task) => !task.done)
        .toList();
    return PopScope(
      canPop: !_busy,
      child: p.PrismScaffold(
        bar: todoBar(
          context,
          _history
              ? '归档补记'
              : _base == null
              ? '添加安排'
              : '编辑安排',
          actions: [
            p.TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        ),
        body: Builder(
          builder: (context) => ListView(
            padding: EdgeInsets.fromLTRB(20, context.appBarInset + 12, 20, 28),
            children: [
              if (_error != null) PlannerNotice(_error!, error: true),
              if (_canCorrectHistory)
                p.TextButton(
                  onPressed: () {
                    setState(() {
                      _history = true;
                      _target = _date;
                      _canCorrectHistory = false;
                      _error = null;
                    });
                    _remember();
                  },
                  child: const Text('转为归档补记'),
                ),
              if (_conflict case final latest?) ...[
                PlannerNotice(
                  '服务端版本：${latest.title} · ${latest.startTime ?? '待排程'}${latest.endTime == null ? '' : '–${latest.endTime}'} · ${latest.status.label}${latest.note.isEmpty ? '' : '\n${latest.note}'}',
                ),
                p.TextButton(
                  onPressed: _rebase,
                  child: const Text('按最新版本继续编辑'),
                ),
              ],
              if (_base == null && tasks.isNotEmpty)
                p.TextButton(
                  onPressed: _locked ? null : () => _pickTodo(tasks),
                  child: const Text('从待办选择'),
                ),
              if (_base == null && _todoId != null)
                p.TextButton(
                  onPressed: _locked
                      ? null
                      : () {
                          setState(() => _todoId = null);
                          _remember();
                        },
                  child: const Text('取消关联待办'),
                ),
              const SectionHeading('安排名称'),
              _field(_title, '安排名称', maxLength: 160),
              const SectionHeading('时间与日期'),
              p.Card(
                padding: EdgeInsets.zero,
                inert: _history,
                onPressed: _locked || _history ? null : _pickDate,
                child: p.ListRow(
                  title: Text(_target),
                  subtitle: Text(
                    _history
                        ? '归档日期'
                        : _target == _date
                        ? '选择日期'
                        : '移动到此日期',
                  ),
                  leading: const GlyphIcon(TodoGlyphs.calendar),
                  trailing: _history
                      ? null
                      : const GlyphIcon(Glyphs.chevronForward),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _field(
                      _start,
                      '开始 HH:mm',
                      keyboardType: TextInputType.datetime,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _field(
                      _end,
                      '结束 HH:mm',
                      keyboardType: TextInputType.datetime,
                    ),
                  ),
                ],
              ),
              if (_history || _target.compareTo(widget.today) <= 0) ...[
                const SectionHeading('完成状态'),
                p.SegmentedControl<PlanStatus>(
                  segments: [
                    for (final status in PlanStatus.values)
                      (status, status.label),
                  ],
                  value: _status,
                  onChanged: (status) {
                    if (_locked) return;
                    setState(() => _status = status);
                    _remember();
                  },
                ),
              ],
              const SectionHeading('备注'),
              _field(_note, '备注（可选）', maxLength: 2000, maxLines: 3),
              const SizedBox(height: 12),
              p.FilledButton(
                onPressed: _busy || _conflict != null || _canCorrectHistory
                    ? null
                    : _submit,
                child: Text(
                  _pending != null
                      ? '重试原操作'
                      : _history
                      ? '保存补记'
                      : '保存安排',
                ),
              ),
              if (_base != null &&
                  !_history &&
                  !_canCorrectHistory &&
                  !_locked &&
                  _conflict == null)
                p.TextButton(
                  onPressed: () {
                    if (_remove) {
                      _submit(remove: true);
                    } else {
                      setState(() => _remove = true);
                    }
                  },
                  child: Text(_remove ? '确认删除安排' : '删除安排'),
                ),
              if (!_locked)
                p.TextButton(
                  onPressed: () async {
                    await widget.client.saveDraft(null);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  child: const Text('放弃草稿'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
