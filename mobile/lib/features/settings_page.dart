import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart' as p;

import '../data/remote_tasks.dart';
import '../data/task.dart';
import '../ui/read_status.dart';
import '../ui/service_actions.dart';
import '../ui/task_widgets.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.store,
    required this.themeMode,
    required this.onThemeChanged,
  });
  final RemoteTaskStore store;
  final p.ThemeMode themeMode;
  final ValueChanged<p.ThemeMode> onThemeChanged;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final sync = store.campus;
      return p.PrismScaffold(
        bar: todoBar(context, '设置', back: true),
        body: Builder(
          builder: (context) => ListView(
            padding: EdgeInsets.fromLTRB(20, context.appBarInset + 12, 20, 32),
            children: [
              ReadStatus(store: store),
              const SectionHeading('外观'),
              p.SegmentedControl<p.ThemeMode>(
                key: MediaQuery.disableAnimationsOf(context)
                    ? ValueKey(store.theme)
                    : null,
                segments: const [
                  (p.ThemeMode.system, '跟随系统'),
                  (p.ThemeMode.light, '浅色'),
                  (p.ThemeMode.dark, '深色'),
                ],
                value: p.ThemeMode.values.byName(store.theme),
                onChanged: onThemeChanged,
              ),
              const SectionHeading('服务与会话'),
              p.Card(
                inert: true,
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    p.ListRow(
                      title: const Text('服务地址'),
                      subtitle: Text(store.origin),
                    ),
                    p.ListRow(
                      title: const Text('会话到期（UTC+8）'),
                      subtitle: Text(readTimeLabel(store.sessionExpiresAt)),
                    ),
                    p.ListRow(
                      title: const Text('App 最近读取'),
                      subtitle: Text(readTimeLabel(store.readAt)),
                    ),
                    p.ListRow(
                      title: const Text('本机快照'),
                      subtitle: Text(
                        store.cached
                            ? '缓存模式，联网刷新后可提交'
                            : '当前服务端快照 · ${store.tasks.length} 条任务',
                      ),
                    ),
                  ],
                ),
              ),
              const SectionHeading('校园同步'),
              p.Card(
                inert: true,
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      sync == null
                          ? '服务端尚未记录同步结果'
                          : '最近执行：${businessDateString(sync.at)}',
                      style: p.AppTextStyle.headline.of(context),
                    ),
                    const SizedBox(height: 10),
                    if (sync != null)
                      Text(
                        sync.error == null
                            ? '新增 ${sync.added} · 更新 ${sync.updated} · 完成 ${sync.completed} · 上游共 ${sync.total}'
                            : '上次同步失败：${sync.error}',
                        style: TextStyle(
                          color: sync.error == null
                              ? p.Theme.of(context).colorScheme.onSurfaceVariant
                              : p.Theme.of(context).colorScheme.error,
                        ),
                      ),
                    if (store.campusReadError != null)
                      Text(
                        '状态读取失败：${store.campusReadError}',
                        style: TextStyle(
                          color: p.Theme.of(context).colorScheme.error,
                        ),
                      ),
                    const SizedBox(height: 14),
                    const Text('刷新只读取 Todo 服务；手动校园同步会访问校园上游并更新任务。'),
                    const SizedBox(height: 16),
                    p.FilledButton(
                      onPressed: store.canWrite
                          ? () => syncCampus(context, store)
                          : null,
                      child: Text(store.writing ? '正在提交，请稍候' : '手动校园同步'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              p.FilledButton(
                onPressed: store.refreshing || store.writing
                    ? null
                    : () => store.refresh(),
                child: const Text('从 Todo 服务刷新'),
              ),
              const SizedBox(height: 16),
              Text(
                '前台每 30 秒读取一次，后台暂停。后台同步与消息提醒将在 A6 提供。',
                style: p.AppTextStyle.footnote.of(context),
              ),
              const SizedBox(height: 16),
              p.TextButton(
                onPressed: store.writing
                    ? null
                    : () async {
                        if (await confirmServiceAction(
                          context,
                          title: '退出登录',
                          message:
                              '清除本机当前会话和任务快照，返回登录页后可更改服务地址。未提交草稿及待确认请求会保留。',
                          action: '退出并返回登录',
                        )) {
                          await store.logout();
                        }
                      },
                child: const Text('退出登录 / 切换服务地址'),
              ),
            ],
          ),
        ),
      );
    },
  );
}
