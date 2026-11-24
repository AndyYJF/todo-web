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

enum _TimelineKind {
  course('课程'),
  gap('空档'),
  lunch('午休'),
  plan('安排');

  const _TimelineKind(this.label);
  final String label;
}

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
  static final _lunchColors = {
    for (final brightness in Brightness.values)
      brightness: p.ColorScheme.fromSeed(
        seedColor: const Color(0xFFFF9F0A),
        brightness: brightness,
        style: p.ColorStyle.vivid,
      ),
  };

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
          if (gap != null) 'gap': [gap.start, gap.end],
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

  static const _actionBarHeight = 56.0;
  static const _actionBarMargin = 10.0;

  Widget _plannerActions() {
    final ready = _ready && !_marking;
    final hasDraft = widget.client.draft != null;
    final colors = p.Theme.of(context).colorScheme;
    final buttons = Row(
      children: [
        if (hasDraft || _canEdit)
          Expanded(
            flex: 2,
            child: p.FilledButton(
              onPressed: !_marking ? _edit : null,
              child: Text(
                hasDraft ? '继续草稿' : '添加安排',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        Expanded(
          child: p.TextButton(
            onPressed: ready ? _history : null,
            child: const Text('历史', maxLines: 1),
          ),
        ),
        if (widget.client.store.background != null)
          Expanded(
            child: p.TextButton(
              onPressed: ready
                  ? () => Navigator.of(context).push(
                      todoPageRoute<void>(
                        context,
                        (_) => PlannerReminderSettings(client: widget.client),
                      ),
                    )
                  : null,
              child: const Text('提醒', maxLines: 1),
            ),
          ),
        Expanded(
          child: p.TextButton(
            onPressed: _ready ? _read : null,
            child: const Text('刷新', maxLines: 1),
          ),
        ),
      ],
    );
    final content = SizedBox(
      height: _actionBarHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        child: buttons,
      ),
    );
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, _actionBarMargin),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: MediaQuery.disableAnimationsOf(context)
              ? p.Surface(
                  color: p.SurfaceLevel.floatingOf(colors).colorOf(colors),
                  shape: p.AppShape.full,
                  child: content,
                )
              : p.LiquidGlass(
                  style: p.LiquidGlassStyle.pill(colors),
                  child: content,
                ),
        ),
      ),
    );
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
      foot: _plannerActions(),
      footInset: _actionBarHeight + _actionBarMargin,
      body: Builder(
        builder: (context) => NotificationListener<ScrollNotification>(
          onNotification: _pullToRefresh,
          child: ListView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            padding: EdgeInsets.fromLTRB(
              16,
              context.appBarInset + 16,
              16,
              context.bottomInset + 16,
            ),
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
                  _slot(
                    kind: _TimelineKind.course,
                    title: course.title,
                    time: '全天',
                    subtitle: course.location,
                  ),
                for (final slot in timeline)
                  if (slot.isGap) ...[
                    if (!day.archived)
                      _slot(
                        kind: _TimelineKind.gap,
                        title: _TimelineKind.gap.label,
                        time:
                            '${plannerTime(slot.start)}–${plannerTime(slot.end)}',
                        onPressed: _canEdit && _itemControlsEnabled
                            ? () => _edit(gap: slot)
                            : null,
                      ),
                  ] else if (slot.isLunch)
                    _slot(
                      kind: _TimelineKind.lunch,
                      title: _TimelineKind.lunch.label,
                      time:
                          '${plannerTime(slot.start)}–${plannerTime(slot.end)}',
                    )
                  else if (slot.course case final course?)
                    _slot(
                      kind: _TimelineKind.course,
                      title: course.title,
                      time:
                          '${plannerTime(slot.start)}–${plannerTime(slot.end)}',
                      subtitle: course.location,
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
    final showState = _canMark || item.status != PlanStatus.pending;
    final marker = showState
        ? Semantics(
            label: '${item.title}，${item.status.label}',
            hint: _canMark ? (done ? '撤销完成' : '勾选完成') : null,
            child: Stack(
              alignment: Alignment.center,
              children: [
                p.Checkbox(
                  value: done,
                  isCircle: true,
                  onChanged: _canMark && _itemControlsEnabled
                      ? (_) => _mark(item)
                      : null,
                ),
                if (item.status == PlanStatus.unfinished)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Center(
                        child: GlyphIcon(
                          Glyphs.close,
                          color: p.Theme.of(context).colorScheme.error,
                          size: 14,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          )
        : null;
    final subtitle = [
      if (_date.compareTo(_today) <= 0 || item.status != PlanStatus.pending)
        item.status.label,
      if (item.note.isNotEmpty) item.note,
    ].join('\n');
    return _slot(
      kind: _TimelineKind.plan,
      title: item.title,
      time: time,
      subtitle: subtitle,
      warningColor: warningColor,
      onPressed: edit,
      trailing: archived
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ?marker,
                p.TextButton(onPressed: edit, child: const Text('补记')),
              ],
            )
          : marker,
    );
  }

  Widget _slot({
    required _TimelineKind kind,
    required String title,
    String? time,
    String? subtitle,
    VoidCallback? onPressed,
    Color? warningColor,
    Widget? trailing,
  }) {
    final colors = p.Theme.of(context).colorScheme;
    final (tint, ink, glyph) = switch (kind) {
      _TimelineKind.course => (
        colors.tertiaryContainer,
        colors.onTertiaryContainer,
        TodoGlyphs.calendar,
      ),
      _TimelineKind.gap => (
        colors.surfaceContainerHighest,
        colors.onSurfaceVariant,
        TodoGlyphs.add,
      ),
      _TimelineKind.lunch => (
        _lunchColors[colors.brightness]!.primaryContainer,
        _lunchColors[colors.brightness]!.onPrimaryContainer,
        TodoGlyphs.lunchBreak,
      ),
      _TimelineKind.plan => (
        colors.primaryContainer,
        colors.onPrimaryContainer,
        TodoGlyphs.tasks,
      ),
    };
    final base = p.SurfaceLevel.card.colorOf(colors);
    final caption = p.AppTextStyle.caption1.of(context, emphasized: true);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: p.PressSurface(
        fill: Color.lerp(base, tint, kind == _TimelineKind.course ? .28 : .54)!,
        shape: p.AppShape.md,
        inert: onPressed == null,
        onPressed: onPressed,
        minimum: p.Card.minimumOf(context),
        child: p.ListRow(
          leading: p.Surface(
            color: tint,
            shape: p.AppShape.sm,
            child: SizedBox.square(
              dimension: 36,
              child: Center(child: GlyphIcon(glyph, size: 21, color: ink)),
            ),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (time != null) ...[
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (kind == _TimelineKind.course ||
                        kind == _TimelineKind.plan)
                      Text(
                        kind.label,
                        style: caption.copyWith(
                          color: Color.lerp(colors.onSurface, ink, .22),
                        ),
                      ),
                    Text(
                      time,
                      style: caption.copyWith(
                        color: colors.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
              ],
              Text(title),
            ],
          ),
          subtitle:
              warningColor == null && (subtitle == null || subtitle.isEmpty)
              ? null
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (warningColor != null)
                      Text('与课程重叠', style: TextStyle(color: warningColor)),
                    if (subtitle != null && subtitle.isNotEmpty) Text(subtitle),
                  ],
                ),
          trailing:
              trailing ??
              (onPressed == null
                  ? null
                  : const GlyphIcon(Glyphs.chevronForward)),
        ),
      ),
    );
  }
}
