import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart' as p;
import 'package:prism_ui/icons/icons.dart';

import '../../data/planner_client.dart';
import '../../data/planner_models.dart';
import '../../data/todo_api.dart';
import '../../ui/task_widgets.dart';
import '../../ui/todo_glyphs.dart';
import '../../ui/todo_motion.dart';
import 'planner_controls.dart';
import 'planner_editor.dart';
import 'planner_import.dart';
import 'planner_history.dart';
import 'planner_reminder_settings.dart';

class PlannerPage extends StatefulWidget {
  const PlannerPage({super.key, required this.client, this.initialDate});
  final PlannerClient client;
  final String? initialDate;
  @override
  State<PlannerPage> createState() => _PlannerPageState();
}

class _PlannerPageState extends State<PlannerPage> with WidgetsBindingObserver {
  late String _date = widget.initialDate ?? plannerShift(plannerToday(), 1);
  PlanDay? _day;
  String? _error, _notice, _academic;
  bool _ready = false, _fresh = false, _pullReady = false;
  bool _marking = false, _hideDone = false;
  int _sequence = 0, _serverTime = 0, _readAt = 0;
  late final Timer _refreshTimer;

  String get _today => _day?.today ?? plannerToday();
  String get _earliest => _day?.openFrom ?? _today;
  bool get _canEdit =>
      _day != null && !_day!.archived && _date.compareTo(_earliest) >= 0;
  bool get _canMark => _canEdit && _date.compareTo(_today) <= 0;
  bool get _itemControlsEnabled => !_marking && widget.client.draft == null;
  int _issuedAt() => _serverTime == 0
      ? DateTime.now().millisecondsSinceEpoch
      : _serverTime + DateTime.now().millisecondsSinceEpoch - _readAt;

  bool get _visible => mounted && ModalRoute.of(context)?.isCurrent == true;
  bool get _foreground =>
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_ready && _foreground && _visible) _read();
    });
  }

  Future<void> _start() async {
    await widget.client.load();
    if (!mounted) return;
    setState(() {
      _ready = true;
      _day = widget.client.cached(_date);
    });
    final initial = _date;
    if (widget.initialDate != null) {
      unawaited(_readWeek(initial));
      await _read();
      return;
    }
    try {
      final current = await widget.client.loadDay(null, isCurrent: () => false);
      if (!mounted || _date != initial || _sequence != 0) return;
      _select(plannerShift(current.today, 1));
      if (_date == initial) unawaited(_readWeek(_date));
    } on ApiFailure {
      if (!mounted || _date != initial || _sequence != 0) return;
      unawaited(_readWeek(_date));
      await _read();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _ready && _visible) _read();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer.cancel();
    super.dispose();
  }

  Future<void> _read() async {
    final date = _date, request = ++_sequence;
    bool current() => mounted && _date == date && _sequence == request;
    try {
      final result = await widget.client.loadDay(date, isCurrent: current);
      if (!current()) return;
      _serverTime = result.serverTime;
      _readAt = DateTime.now().millisecondsSinceEpoch;
      setState(() {
        if (_day == null || result.revision >= _day!.revision) _day = result;
        _fresh = true;
        _error = null;
      });
    } on ApiFailure catch (error) {
      if (current()) {
        setState(() {
          _fresh = false;
          _error = error.statusCode == 404 ? '当前站点尚未启用规划明天' : error.message;
          if (error.statusCode == 410) _day = null;
        });
      }
    }
  }

  Future<void> _readWeek(String date) async {
    try {
      final result = await widget.client.schoolWeek(date);
      final week = result['current'] as Map?;
      if (!mounted || _date != date || week == null) return;
      final phase = switch (week['phase']) {
        'exam' => '考试周',
        'practice' => '实践周',
        _ => '教学周',
      };
      setState(
        () => _academic =
            '$phase · 第 ${week['week']} 周${week['source'] == 'bugaoshan' ? '（参考）' : ''}',
      );
    } on ApiFailure {
      // Teaching weeks are supplementary to the imported calendar.
    }
  }

  void _select(String next) {
    if (next != _date) {
      setState(() {
        _date = next;
        _day = widget.client.cached(next);
        _academic = null;
        _notice = null;
        _error = null;
        _fresh = false;
        _hideDone = false;
      });
      unawaited(_readWeek(next));
    }
    unawaited(_read());
  }

  Future<void> _pickDate() async {
    final next = await selectPlannerDate(
      context,
      date: _date,
      earliest: _earliest,
    );
    if (mounted && next != null) _select(next);
  }

  Future<void> _history() async {
    final date = await Navigator.of(context).push(
      todoPageRoute<String>(
        context,
        (_) => PlannerHistory(client: widget.client),
      ),
    );
    if (mounted && date != null) _select(date);
  }

  Future<void> _mark(PlanItem item) async {
    if (!_canMark || !_itemControlsEnabled) return;
    final date = _date;
    final status = item.status == PlanStatus.done
        ? PlanStatus.pending
        : PlanStatus.done;
    final body = {
      'action': 'edit',
      'date': date,
      'operationId': newPlannerOperation(),
      'issuedAt': _issuedAt(),
      'itemId': item.id,
      'baseVersion': item.version,
      'fields': {'status': status.name},
    };
    final draft = <String, dynamic>{
      'date': date,
      'base': item.toJson(),
      'fields': {...item.fields(), 'status': status.name},
      'pending': body,
    };
    setState(() {
      _marking = true;
      _notice = null;
    });
    await widget.client.saveDraft(draft);
    try {
      await widget.client.write(body);
      await widget.client.saveDraft(null);
      if (mounted) {
        setState(() => _notice = '状态已同步');
        await _read();
      }
    } on ApiFailure catch (error) {
      final response = error is PlannerApiFailure ? error : null;
      await widget.client.saveDraft({
        ...draft,
        'pending': error.uncertain ? body : null,
        'error': error.uncertain ? '提交结果待确认，可以重试原操作。' : error.message,
        'conflict': response?.code == 'item_conflict'
            ? response?.current
            : null,
        'canCorrectHistory':
            response?.statusCode == 409 &&
            response?.code == 'history_read_only',
      });
    } finally {
      if (mounted) setState(() => _marking = false);
    }
  }

  Future<void> _edit({PlanItem? item, PlanInterval? gap}) async {
    if (_marking) return;
    final fields =
        item?.fields() ??
        {
          if (gap != null) 'startTime': plannerTime(gap.start),
          if (gap != null)
            'endTime': plannerTime(math.min(gap.end, gap.start + 60)),
        };
    final draft =
        widget.client.draft ??
        {
          'date': _date,
          'base': item?.toJson(),
          'fields': fields,
          'correctHistory': _day?.archived == true,
        };
    final result = await showTodoFormSheet<String>(
      context: context,
      props: const p.SheetProps(detents: [0.94]),
      builder: (_) => PlannerEditor(
        client: widget.client,
        initial: draft,
        earliest: _earliest,
        today: _today,
        issuedAt: _issuedAt,
      ),
    );
    if (!mounted) return;
    if (result != null) {
      _select(result);
      setState(() => _notice = '安排已保存');
    } else {
      setState(() {});
      unawaited(_read());
    }
  }

  Future<void> _import() async {
    final result = await showTodoFormSheet<String>(
      context: context,
      props: const p.SheetProps(detents: [0.94]),
      builder: (_) => PlannerImport(client: widget.client),
    );
    if (!mounted || result == null) return;
    setState(() => _notice = result);
    await _read();
  }

  bool _pullToRefresh(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification is ScrollStartNotification) _pullReady = false;
    if (notification is ScrollUpdateNotification &&
        notification.metrics.pixels < -72) {
      _pullReady = true;
    }
    if (notification is ScrollEndNotification && _pullReady) {
      _pullReady = false;
      if (_ready) unawaited(_read());
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final day = _day;
    final timeline = day == null
        ? const <PlanInterval>[]
        : plannerTimeline(day);
    final unscheduled =
        day?.items.where(
          (item) =>
              item.startTime == null &&
              (!_hideDone || item.status != PlanStatus.done),
        ) ??
        const <PlanItem>[];
    final tomorrow = plannerShift(_today, 1);
    final hasDraft = widget.client.draft != null;
    final done =
        day?.items.where((item) => item.status == PlanStatus.done).length ?? 0;
    final unfinished =
        day?.items
            .where((item) => item.status == PlanStatus.unfinished)
            .length ??
        0;
    final colors = p.Theme.of(context).colorScheme;
    final calendar = DateTime.parse('${_date}T00:00:00Z');
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    return p.PrismScaffold(
      bar: todoBar(
        context,
        '规划明天',
        back: true,
        actions: [
          if (day?.archived != true)
            p.TextButton(
              onPressed: _ready && !_marking ? _import : null,
              child: const Text('导入课表'),
            ),
        ],
      ),
      body: Builder(
        builder: (context) => NotificationListener<ScrollNotification>(
          onNotification: _pullToRefresh,
          child: ListView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            padding: EdgeInsets.fromLTRB(16, context.appBarInset + 16, 16, 28),
            children: [
              p.SegmentedControl<String>(
                key: ValueKey((_today, _earliest)),
                segments: [
                  if (_earliest.compareTo(_today) < 0) (_earliest, '昨天待补记'),
                  (_today, '今天'),
                  (tomorrow, '明天'),
                  if (_date != _today &&
                      _date != tomorrow &&
                      _date != _earliest)
                    (_date, '所选日期'),
                ],
                value: _date,
                onChanged: (day) {
                  if (!_marking) _select(day);
                },
              ),
              const SizedBox(height: 10),
              p.Card(
                padding: EdgeInsets.zero,
                inert: day?.archived == true,
                onPressed: _marking || day?.archived == true ? null : _pickDate,
                child: p.ListRow(
                  leading: const GlyphIcon(TodoGlyphs.calendar),
                  title: Text(
                    '${calendar.month}月${calendar.day}日 星期${weekdays[calendar.weekday - 1]}',
                  ),
                  subtitle: Text(_academic ?? _date),
                  trailing: day?.archived == true
                      ? null
                      : const GlyphIcon(Glyphs.chevronForward),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (hasDraft)
                    p.FilledButton(
                      onPressed: !_marking ? _edit : null,
                      child: const Text('继续规划草稿'),
                    )
                  else if (_canEdit)
                    p.FilledButton(
                      onPressed: !_marking ? _edit : null,
                      child: const Text('添加安排'),
                    ),
                  p.TextButton(
                    onPressed: _ready && !_marking ? _history : null,
                    child: const Text('历史'),
                  ),
                  if (widget.client.store.background != null)
                    p.TextButton(
                      onPressed: _ready && !_marking
                          ? () => Navigator.of(context).push(
                              todoPageRoute<void>(
                                context,
                                (_) => PlannerReminderSettings(
                                  client: widget.client,
                                ),
                              ),
                            )
                          : null,
                      child: const Text('提醒设置'),
                    ),
                  p.TextButton(
                    onPressed: _ready ? _read : null,
                    child: const Text('刷新'),
                  ),
                ],
              ),
              if (_notice != null) PlannerNotice(_notice!),
              if (_error != null) PlannerNotice(_error!, error: true),
              if (day == null && _error == null)
                const Padding(
                  padding: EdgeInsets.all(22),
                  child: Center(child: p.ActivityIndicator()),
                ),
              if (day != null) ...[
                if (!_fresh) const PlannerNotice('正在显示本机保存的快照'),
                if (day.archived) const PlannerNotice('已归档，可补记已有安排。'),
                if ((_date.compareTo(_today) <= 0 || done > 0) &&
                    day.items.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      PlannerNotice(
                        '已完成 $done · 未完成 $unfinished · 未记录 ${day.items.length - done - unfinished}',
                      ),
                      if (done > 0)
                        p.TextButton(
                          onPressed: () =>
                              setState(() => _hideDone = !_hideDone),
                          child: Text(_hideDone ? '显示已完成' : '收起已完成'),
                        ),
                    ],
                  ),
                SectionHeading('当天时间线', trailing: '${day.courses.length} 节课'),
                for (final course in day.courses.where(
                  (course) => course.allDay,
                ))
                  _slot(title: course.title, subtitle: '全天 · 课程', course: true),
                for (final slot in timeline)
                  if (slot.isGap) ...[
                    if (!day.archived)
                      _slot(
                        title:
                            '${plannerTime(slot.start)}–${plannerTime(slot.end)} 空档',
                        onPressed: _canEdit && _itemControlsEnabled
                            ? () => _edit(gap: slot)
                            : null,
                        gap: true,
                      ),
                  ] else if (slot.course case final course?)
                    _slot(
                      title: course.title,
                      subtitle: [
                        '${plannerTime(slot.start)}–${plannerTime(slot.end)}',
                        '课程',
                        if (course.location.isNotEmpty) course.location,
                      ].join(' · '),
                      course: true,
                    )
                  else if (!_hideDone || slot.item!.status != PlanStatus.done)
                    _itemSlot(
                      slot.item!,
                      time:
                          '${plannerTime(slot.start)}–${plannerTime(slot.end)}',
                      warningColor: slot.overlap ? colors.error : null,
                    ),
                if (unscheduled.isNotEmpty) ...[
                  const SectionHeading('待排程'),
                  for (final item in unscheduled) _itemSlot(item),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _itemSlot(PlanItem item, {String? time, Color? warningColor}) {
    final archived = _day?.archived == true;
    final edit = (_canEdit || archived) && _itemControlsEnabled
        ? () => _edit(item: item)
        : null;
    final done = item.status == PlanStatus.done;
    final subtitle = [
      [
        ?time,
        if (_date.compareTo(_today) <= 0 || item.status != PlanStatus.pending)
          item.status.label,
        if (warningColor != null) '与课程重叠',
      ].join(' · '),
      if (item.note.isNotEmpty) item.note,
    ].where((line) => line.isNotEmpty).join('\n');
    return _slot(
      title: item.title,
      subtitle: subtitle.isEmpty ? null : subtitle,
      warningColor: warningColor,
      onPressed: edit,
      trailing: archived
          ? p.TextButton(onPressed: edit, child: const Text('补记'))
          : _canMark
          ? Semantics(
              label: '${done ? '撤销完成' : '勾选完成'} ${item.title}',
              child: p.Checkbox(
                value: done,
                isCircle: true,
                onChanged: _itemControlsEnabled ? (_) => _mark(item) : null,
              ),
            )
          : null,
    );
  }

  Widget _slot({
    required String title,
    String? subtitle,
    VoidCallback? onPressed,
    Color? warningColor,
    Widget? trailing,
    bool course = false,
    bool gap = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: p.Card(
      inert: onPressed == null,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      child: p.ListRow(
        leading: GlyphIcon(
          course
              ? TodoGlyphs.calendar
              : gap
              ? TodoGlyphs.add
              : TodoGlyphs.tasks,
        ),
        title: Text(title),
        subtitle: subtitle == null
            ? null
            : Text(subtitle, style: TextStyle(color: warningColor)),
        trailing:
            trailing ??
            (onPressed == null ? null : const GlyphIcon(Glyphs.chevronForward)),
      ),
    ),
  );
}
