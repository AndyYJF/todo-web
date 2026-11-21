import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart' as p;

import '../../data/planner_client.dart';
import '../../data/planner_models.dart';
import '../../data/todo_api.dart';
import '../../ui/task_widgets.dart';
import 'planner_controls.dart';

class PlannerImport extends StatefulWidget {
  const PlannerImport({super.key, required this.client});
  final PlannerClient client;

  @override
  State<PlannerImport> createState() => _PlannerImportState();
}

class _PlannerImportState extends State<PlannerImport> {
  static const _picker = MethodChannel('todo/planner_files');
  final _text = TextEditingController();
  Map<String, dynamic>? _preview;
  String? _filename, _error;
  int _previewReadAt = 0;
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    FocusScope.of(context).unfocus();
    try {
      final result = await _picker.invokeMapMethod<String, String>('pickIcs');
      if (mounted && result != null) {
        setState(() {
          _text.text = result['text']!;
          _filename = result['name'];
          _preview = null;
        });
      }
    } on PlatformException catch (error) {
      if (mounted) setState(() => _error = error.message ?? '无法打开课表');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _readPreview() async {
    final text = _text.text;
    if (text.trim().isEmpty || utf8.encode(text).length > 1024 * 1024) {
      setState(() => _error = '请选择或粘贴不超过 1 MiB 的 .ics 课表');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _preview = null;
      _error = null;
    });
    try {
      final result = await widget.client.timetable({
        'action': 'preview',
        'ics': text,
      });
      if (mounted) {
        setState(() {
          _preview = result;
          _previewReadAt = DateTime.now().millisecondsSinceEpoch;
        });
      }
    } on ApiFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _commit() async {
    final preview = _preview;
    final retry = widget.client.importAttempt;
    if (_busy || (retry == null && preview == null)) return;
    final body =
        retry ??
        {
          'action': 'commit',
          'ics': _text.text,
          'operationId': newPlannerOperation(),
          'issuedAt':
              (preview!['serverTime'] as int) +
              DateTime.now().millisecondsSinceEpoch -
              _previewReadAt,
          'baseVersion': preview['baseVersion'],
          'checksum': preview['checksum'],
          'effectiveFrom': preview['effectiveFrom'],
        };
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    widget.client.importAttempt = body;
    try {
      final result = await widget.client.timetable(body);
      widget.client.importAttempt = null;
      if (mounted) {
        navigator.pop(
          '课表已导入 · 新增 ${result['added']}，更新 ${result['updated']}，移除 ${result['removed']}',
        );
      }
    } on ApiFailure catch (error) {
      if (!error.uncertain) {
        widget.client.importAttempt = null;
        if (mounted) _text.text = body['ics'] as String;
        _preview = null;
      }
      _error = error.uncertain ? '导入结果待确认，可以重试同一操作。' : error.message;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final retry = widget.client.importAttempt != null;
    final preview = _preview;
    return PopScope(
      canPop: !_busy,
      child: p.PrismScaffold(
        bar: todoBar(
          context,
          '导入课表',
          actions: [
            p.TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        ),
        body: Builder(
          builder: (context) => ListView(
            padding: EdgeInsets.fromLTRB(20, context.appBarInset + 16, 20, 26),
            children: [
              if (_error != null) PlannerNotice(_error!, error: true),
              if (retry) ...[
                const PlannerNotice('上一次导入结果待确认。'),
                p.FilledButton(
                  onPressed: _busy ? null : _commit,
                  child: const Text('重试原导入'),
                ),
              ] else ...[
                const Text('选择 WakeUp 导出的 .ics 文件，先预览课程和覆盖范围。'),
                const SizedBox(height: 12),
                p.FilledButton(
                  onPressed: _busy ? null : _pick,
                  child: const Text('选择 .ics 文件'),
                ),
                if (_filename != null) PlannerNotice(_filename!),
                const SizedBox(height: 8),
                p.TextField(
                  controller: _text,
                  enabled: !_busy,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const p.InputDecoration(hintText: '或粘贴 .ics 文本'),
                  onChanged: (_) => setState(() {
                    _filename = null;
                    _preview = null;
                  }),
                ),
                const SizedBox(height: 8),
                p.TextButton(
                  onPressed: _busy ? null : _readPreview,
                  child: const Text('预览课表'),
                ),
                if (preview != null) ...[
                  const SectionHeading('导入预览'),
                  Text(
                    '${preview['from']} 至 ${preview['through']} · ${preview['count']} 条',
                  ),
                  PlannerNotice(
                    '从 ${preview['effectiveFrom']} 起，新增 ${preview['added']} · 更新 ${preview['updated']} · 移除 ${preview['removed']}',
                  ),
                  p.FilledButton(
                    onPressed: _busy ? null : _commit,
                    child: const Text('确认导入'),
                  ),
                  const SizedBox(height: 12),
                  for (final raw in (preview['sample'] as List).take(6))
                    p.ListRow(
                      title: Text(raw['title'] as String),
                      subtitle: Text(
                        (raw['startsAt'] as String)
                            .replaceFirst('T', ' ')
                            .substring(0, 16),
                      ),
                    ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
