import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart' as p;
import 'package:prism_ui/icons/icons.dart';

import '../../data/planner_client.dart';
import '../../data/planner_models.dart';
import '../../data/todo_api.dart';
import '../../ui/task_widgets.dart';
import '../../ui/todo_glyphs.dart';
import 'planner_controls.dart';

class PlannerHistory extends StatefulWidget {
  const PlannerHistory({super.key, required this.client});
  final PlannerClient client;

  @override
  State<PlannerHistory> createState() => _PlannerHistoryState();
}

class _PlannerHistoryState extends State<PlannerHistory> {
  PlanHistory? _page;
  List<PlanHistoryDay> _days = const [];
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read({String? before}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final page = await widget.client.loadHistory(before: before);
      if (!mounted) return;
      final earliest = page.earliestDate;
      setState(() {
        _page = page;
        _days = [
          if (before != null && earliest != null)
            ..._days.where((day) => day.date.compareTo(earliest) >= 0),
          ...page.items,
        ];
      });
    } on ApiFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _size(int bytes) => bytes < 1000000
      ? '${(bytes / 1000).toStringAsFixed(1)} KB'
      : '${(bytes / 1000000).toStringAsFixed(1)} MB';

  @override
  Widget build(BuildContext context) {
    final page = _page;
    return p.PrismScaffold(
      bar: todoBar(
        context,
        '历史记录',
        back: true,
        actions: [
          p.TextButton(
            onPressed: _busy ? null : _read,
            child: const Text('刷新历史'),
          ),
        ],
      ),
      body: Builder(
        builder: (context) => ListView(
          padding: EdgeInsets.fromLTRB(16, context.appBarInset + 16, 16, 28),
          children: [
            if (page != null)
              PlannerNotice(
                [
                  '${_size(page.bytes)} / ${_size(page.limitBytes)}',
                  if (page.earliestDate case final date?) '最早 $date',
                ].join(' · '),
              ),
            if (_error != null) PlannerNotice(_error!, error: true),
            if (_busy && page == null)
              const Center(child: p.ActivityIndicator()),
            if (!_busy && _error == null && _days.isEmpty)
              const PlannerNotice('还没有归档的日计划。'),
            for (final day in _days)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: p.Card(
                  padding: EdgeInsets.zero,
                  onPressed: () => Navigator.of(context).pop(day.date),
                  child: p.ListRow(
                    leading: const GlyphIcon(TodoGlyphs.calendar),
                    title: Text(day.date),
                    subtitle: Text('已完成 ${day.doneCount} / ${day.itemCount}'),
                    trailing: const GlyphIcon(Glyphs.chevronForward),
                  ),
                ),
              ),
            if (page?.nextBefore case final before?)
              p.TextButton(
                onPressed: _busy ? null : () => _read(before: before),
                child: const Text('加载更早记录'),
              ),
          ],
        ),
      ),
    );
  }
}
