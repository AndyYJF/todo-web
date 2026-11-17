import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart' as p;
import 'package:prism_ui/icons/icons.dart';

import '../data/demo_tasks.dart';
import '../ui/task_widgets.dart';
import '../ui/todo_motion.dart';
import '../ui/todo_glyphs.dart';
import 'task_detail.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.store,
    required this.themeMode,
    required this.onThemeChanged,
  });
  final DemoTaskStore store;
  final p.ThemeMode themeMode;
  final ValueChanged<p.ThemeMode> onThemeChanged;
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _selected = 0;
  int _filter = 0;
  String _query = '';
  final _search = TextEditingController();
  final _bucket = PageStorageBucket();
  static const _titles = ['今天', '任务', '四象限', '更多'];
  static const _glyphs = [
    TodoGlyphs.today,
    TodoGlyphs.tasks,
    TodoGlyphs.quadrant,
    TodoGlyphs.more,
  ];
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 600;
        final content = p.PrismScaffold(
          bar: todoBar(
            context,
            _titles[_selected],
            actions: [
              p.IconButton(
                onPressed: _toggleTheme,
                icon: const GlyphIcon(TodoGlyphs.today),
                tooltip: '切换明暗主题',
              ),
              if (_selected != 3)
                p.IconButton.filled(
                  onPressed: () => openTaskEditor(context, widget.store),
                  icon: const GlyphIcon(TodoGlyphs.add),
                  tooltip: '新建任务',
                ),
            ],
          ),
          foot: wide
              ? null
              : TodoDock(
                  destinations: [
                    for (var i = 0; i < _titles.length; i++)
                      p.NavigationDockDestination(
                        glyph: _glyphs[i],
                        label: _titles[i],
                      ),
                  ],
                  selectedIndex: _selected,
                  onSelected: (value) => setState(() => _selected = value),
                ),
          footInset: wide ? 0 : p.NavigationDock.insetOf(context),
          body: Builder(
            builder: (context) => PageStorage(
              bucket: _bucket,
              child: p.PageTransitionSwitcher(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : p.fadeTabDuration,
                transitionBuilder: (child, animation, secondary) =>
                    p.FadeThroughTransition(
                      animation: animation,
                      secondaryAnimation: secondary,
                      child: child,
                    ),
                child: KeyedSubtree(
                  key: ValueKey(_selected),
                  child: _page(context, wide),
                ),
              ),
            ),
          ),
        );
        if (!wide) return content;
        return Row(
          children: [
            TodoSidebar(
              destinations: [
                for (var i = 0; i < _titles.length; i++)
                  p.SidebarDestination(glyph: _glyphs[i], label: _titles[i]),
              ],
              selectedIndex: _selected,
              expanded: constraints.maxWidth >= 840,
              onSelected: (value) => setState(() => _selected = value),
            ),
            Expanded(child: content),
          ],
        );
      },
    ),
  );

  void _toggleTheme() {
    final dark = p.Theme.of(context).brightness == Brightness.dark;
    widget.onThemeChanged(dark ? p.ThemeMode.light : p.ThemeMode.dark);
  }

  Widget _page(BuildContext context, bool wide) {
    final children = switch (_selected) {
      0 => _today(context),
      1 => _tasks(context),
      2 => _quadrants(context),
      _ => _more(context),
    };
    return ListView(
      key: PageStorageKey('page-$_selected'),
      padding: EdgeInsets.fromLTRB(
        20,
        MediaQuery.paddingOf(context).top + 10,
        20,
        (wide
                ? MediaQuery.paddingOf(context).bottom
                : p.NavigationDock.insetOf(context)) +
            28,
      ),
      children: [
        const Align(alignment: Alignment.centerLeft, child: DemoBadge()),
        const SizedBox(height: 18),
        ...children,
      ],
    );
  }

  List<Widget> _today(BuildContext context) {
    final colors = p.Theme.of(context).colorScheme;
    final today = widget.store.today;
    final tasks = widget.store.tasks;
    final done = tasks.where((t) => t.done).length;
    final now = businessNow();
    return [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 14),
        child: Text(
          '${now.month}月${now.day}日 · 给重要的事一点空间',
          style: p.AppTextStyle.footnote
              .of(context)
              .copyWith(color: colors.onSurfaceVariant),
        ),
      ),
      p.ElasticPress(
        enabled: !MediaQuery.disableAnimationsOf(context),
        child: p.Card(
          onPressed: () => _openGroup('今天的任务', isTodayTask),
          padding: const EdgeInsets.all(22),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        GlyphIcon(
                          TodoGlyphs.today,
                          size: 18,
                          color: colors.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '今日概览',
                          style: p.AppTextStyle.headline.of(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          today.length.toString().padLeft(2, '0'),
                          style: p.AppTextStyle.display.of(context),
                        ),
                        const Padding(
                          padding: EdgeInsets.only(left: 8, bottom: 5),
                          child: Text('件待办'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '慢慢来，也在向前。',
                      style: p.AppTextStyle.footnote
                          .of(context)
                          .copyWith(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Container(
                width: 76,
                height: 76,
                decoration: ShapeDecoration(
                  color: colors.primary.withValues(alpha: 0.13),
                  shape: p.AppShape.xxl,
                ),
                child: Center(
                  child: GlyphIcon(
                    TodoGlyphs.tasks,
                    size: 36,
                    color: colors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: _statCard(context, '已完成', done.toString(), Glyphs.check),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _statCard(
              context,
              '未来安排',
              (tasks.where((t) => !t.done).length - today.length).toString(),
              TodoGlyphs.calendar,
            ),
          ),
        ],
      ),
      SectionHeading('接下来', trailing: '${today.length} 件'),
      if (today.isEmpty) const EmptyTasks(message: '今天的事情都安排好了。'),
      AnimatedSize(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : p.fadeTabDuration,
        alignment: Alignment.topCenter,
        child: Column(children: [for (final task in today) _tile(task)]),
      ),
    ];
  }

  Widget _statCard(
    BuildContext context,
    String label,
    String number,
    Glyph glyph,
  ) => p.Card(
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            GlyphIcon(
              glyph,
              size: 16,
              color: p.Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(label, style: p.AppTextStyle.footnote.of(context)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          number,
          style: p.AppTextStyle.title1.of(context, emphasized: true),
        ),
      ],
    ),
  );

  List<Widget> _tasks(BuildContext context) {
    final list = widget.store.tasks.where((t) {
      final matches = switch (_filter) {
        1 => !t.done,
        2 => t.done,
        3 => t.pinned,
        _ => true,
      };
      return matches &&
          (t.title + t.note + t.project).toLowerCase().contains(
            _query.toLowerCase(),
          );
    }).toList();
    return [
      p.TextField(
        controller: _search,
        onChanged: (value) => setState(() => _query = value),
        decoration: const p.InputDecoration(
          hintText: '搜索任务、备注或项目',
          prefixIcon: GlyphIcon(Glyphs.search),
        ),
      ),
      const SizedBox(height: 16),
      p.SegmentedControl<int>(
        key: MediaQuery.disableAnimationsOf(context) ? ValueKey(_filter) : null,
        segments: const [(0, '全部'), (1, '待办'), (2, '完成'), (3, '置顶')],
        value: _filter,
        onChanged: (value) => setState(() => _filter = value),
      ),
      SectionHeading('任务清单', trailing: '${list.length} 件'),
      if (list.isEmpty) const EmptyTasks(message: '这里暂时没有任务。'),
      for (final task in list) _tile(task),
    ];
  }

  List<Widget> _quadrants(BuildContext context) {
    final colors = p.Theme.of(context).colorScheme;
    final groups = <(String, String, bool, bool, Color)>[
      ('马上做', '重要且紧急', true, true, colors.error),
      ('计划做', '重要不紧急', false, true, colors.primary),
      ('快速处理', '紧急不重要', true, false, colors.secondary),
      ('可以缓缓', '不重要不紧急', false, false, colors.onSurfaceVariant),
    ];
    final pending = widget.store.tasks.where((t) => !t.done).toList();
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 18),
        child: Text(
          '看清轻重缓急，让精力有一个去处。',
          style: p.AppTextStyle.callout
              .of(context)
              .copyWith(color: colors.onSurfaceVariant),
        ),
      ),
      for (final group in groups)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: p.ElasticPress(
            enabled: !MediaQuery.disableAnimationsOf(context),
            child: p.Card(
              onPressed: () => _openGroup(
                group.$1,
                (task) =>
                    !task.done &&
                    task.urgent == group.$3 &&
                    task.important == group.$4,
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: ShapeDecoration(
                          color: group.$5.withValues(alpha: 0.12),
                          shape: p.AppShape.md,
                        ),
                        child: Center(
                          child: GlyphIcon(
                            TodoGlyphs.quadrant,
                            size: 20,
                            color: group.$5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              group.$1,
                              style: p.AppTextStyle.headline.of(context),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              group.$2,
                              style: p.AppTextStyle.caption1
                                  .of(context)
                                  .copyWith(color: colors.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        pending
                            .where(
                              (t) =>
                                  t.urgent == group.$3 &&
                                  t.important == group.$4,
                            )
                            .length
                            .toString(),
                        style: p.AppTextStyle.title1
                            .of(context, emphasized: true)
                            .copyWith(color: group.$5),
                      ),
                      const SizedBox(width: 10),
                      const GlyphIcon(Glyphs.chevronForward, size: 16),
                    ],
                  ),
                  ...pending
                      .where(
                        (t) => t.urgent == group.$3 && t.important == group.$4,
                      )
                      .take(2)
                      .map(
                        (t) => Padding(
                          padding: const EdgeInsets.only(top: 14),
                          child: Text(
                            t.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: p.AppTextStyle.footnote.of(context),
                          ),
                        ),
                      ),
                ],
              ),
            ),
          ),
        ),
      SectionHeading(
        '未分类',
        trailing:
            '${pending.where((t) => t.urgent == null || t.important == null).length} 件',
      ),
      for (final task in pending.where(
        (t) => t.urgent == null || t.important == null,
      ))
        _tile(task),
    ];
  }

  List<Widget> _more(BuildContext context) {
    final colors = p.Theme.of(context).colorScheme;
    return [
      p.Card(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '留一点空白给自己',
              style: p.AppTextStyle.title2.of(context, emphasized: true),
            ),
            const SizedBox(height: 10),
            Text(
              '这是 Todo 的界面与交互演示。任务修改仅保存在本次会话，尚未连接云端。',
              style: p.AppTextStyle.callout
                  .of(context)
                  .copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
      const SectionHeading('外观'),
      p.Card(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('主题', style: p.AppTextStyle.headline.of(context)),
            const SizedBox(height: 14),
            p.SegmentedControl<p.ThemeMode>(
              key: MediaQuery.disableAnimationsOf(context)
                  ? ValueKey(widget.themeMode)
                  : null,
              segments: const [
                (p.ThemeMode.system, '跟随系统'),
                (p.ThemeMode.light, '浅色'),
                (p.ThemeMode.dark, '深色'),
              ],
              value: widget.themeMode,
              onChanged: widget.onThemeChanged,
            ),
          ],
        ),
      ),
      const SectionHeading('浏览'),
      p.Card(
        padding: EdgeInsets.zero,
        onPressed: () => _openGroup('有日期的任务', (t) => t.dueAt != null),
        child: const p.ListRow(
          leading: GlyphIcon(TodoGlyphs.calendar),
          title: Text('日期安排'),
          subtitle: Text('演示任务的时间清单'),
          trailing: GlyphIcon(Glyphs.chevronForward, size: 16),
        ),
      ),
      const SizedBox(height: 8),
      p.Card(
        padding: EdgeInsets.zero,
        onPressed: _openProjects,
        child: const p.ListRow(
          leading: GlyphIcon(TodoGlyphs.tasks),
          title: Text('项目分组'),
          subtitle: Text('从不同生活侧面查看任务'),
          trailing: GlyphIcon(Glyphs.chevronForward, size: 16),
        ),
      ),
      const SectionHeading('云端'),
      const p.Card(
        padding: EdgeInsets.zero,
        child: p.ListRow(
          leading: GlyphIcon(TodoGlyphs.cloud),
          title: Text('云端连接'),
          subtitle: Text('尚未连接 · 当前使用演示数据'),
          trailing: StatusPill(label: '演示'),
        ),
      ),
    ];
  }

  Widget _tile(DemoTask task) => TaskTile(
    key: ValueKey(task.id),
    task: task,
    onToggle: () => widget.store.toggle(task.id),
    onOpen: () => Navigator.of(context).push(
      todoPageRoute<void>(
        context,
        (_) => TaskDetail(store: widget.store, id: task.id),
      ),
    ),
  );

  void _openGroup(String title, bool Function(DemoTask) predicate) {
    Navigator.of(context).push(
      todoPageRoute<void>(
        context,
        (context) => ListenableBuilder(
          listenable: widget.store,
          builder: (context, _) => p.PrismScaffold(
            bar: todoBar(context, title, back: true),
            body: Builder(
              builder: (context) => ListView(
                padding: EdgeInsets.fromLTRB(
                  20,
                  MediaQuery.paddingOf(context).top + 12,
                  20,
                  32,
                ),
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: DemoBadge(),
                  ),
                  const SizedBox(height: 20),
                  if (!widget.store.tasks.any(predicate))
                    const EmptyTasks(message: '这里暂时没有任务。'),
                  for (final task in widget.store.tasks.where(predicate))
                    _tile(task),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openProjects() {
    final projects = widget.store.tasks
        .map((t) => t.project)
        .where((p) => p.isNotEmpty)
        .toSet()
        .toList();
    showTodoFormSheet<void>(
      context: context,
      builder: (context) => p.PrismScaffold(
        bar: todoBar(
          context,
          '项目分组',
          actions: [
            p.IconButton(
              onPressed: () => Navigator.of(context).pop(),
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
              for (final project in projects)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: p.Card(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _openGroup(project, (t) => t.project == project);
                    },
                    child: p.ListRow(
                      title: Text(project),
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
  }
}
