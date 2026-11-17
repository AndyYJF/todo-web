import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart' as p;

import '../data/android_background.dart';
import '../data/task.dart';
import 'task_widgets.dart';

class BackgroundSettings extends StatelessWidget {
  const BackgroundSettings({super.key, required this.background});
  final AndroidBackground background;
  String time(Object? value) => value is int && value > 0
      ? readTimeLabel(DateTime.fromMillisecondsSinceEpoch(value, isUtc: true))
      : '尚未执行';
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: background,
    builder: (context, _) {
      final state = background.status;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeading('后台同步与提醒'),
          p.Card(
            inert: true,
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                p.ListRow(
                  title: const Text('后台同步'),
                  subtitle: const Text('约每 30 分钟读取 Todo 服务'),
                  trailing: p.Switch(
                    value: background.enabled,
                    onChanged: (v) => background.setOptions(enabled: v),
                  ),
                ),
                p.ListRow(
                  title: const Text('新校园任务提醒'),
                  subtitle: const Text('首次启用不提醒已有任务'),
                  trailing: p.Switch(
                    value: background.campus,
                    onChanged: (v) async {
                      if (v) await background.requestNotifications();
                      await background.setOptions(campus: v);
                    },
                  ),
                ),
                p.ListRow(
                  title: const Text('截止时提醒'),
                  subtitle: const Text('已完成或删除后取消本机提醒'),
                  trailing: p.Switch(
                    value: background.deadline,
                    onChanged: (v) async {
                      if (v) await background.requestNotifications();
                      await background.setOptions(deadline: v);
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          p.Card(
            inert: true,
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  state['notificationsAllowed'] == true
                      ? '消息通知已允许'
                      : '消息通知尚未允许',
                  style: p.AppTextStyle.headline.of(context),
                ),
                if (state['notificationsAllowed'] != true)
                  p.TextButton(
                    onPressed: background.requestNotifications,
                    child: const Text('允许消息通知'),
                  ),
                p.TextButton(
                  onPressed: background.openNotificationSettings,
                  child: const Text('系统通知设置'),
                ),
                Text(
                  state['exactAllowed'] == true
                      ? '准时提醒权限已允许'
                      : '未允许准时提醒，系统可能延后通知',
                ),
                if (state['exactAllowed'] != true)
                  p.TextButton(
                    onPressed: background.openExactSettings,
                    child: const Text('设置准时提醒权限'),
                  ),
                const SizedBox(height: 12),
                Text('最近尝试：${time(state['lastAttempt'])}'),
                Text('最近成功：${time(state['lastSuccess'])}'),
                Text('已安排 ${state['scheduledAlarms'] ?? 0} 个到期提醒'),
                if (state['message'] is String)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(state['message'] as String),
                  ),
                if (background.error != null)
                  Text(
                    background.error!,
                    style: TextStyle(
                      color: p.Theme.of(context).colorScheme.error,
                    ),
                  ),
                const SizedBox(height: 12),
                p.FilledButton(
                  onPressed:
                      background.enabled &&
                          state['running'] != true &&
                          !background.sessionInvalid
                      ? background.runNow
                      : null,
                  child: Text(state['running'] == true ? '正在后台读取' : '立即后台读取一次'),
                ),
                p.TextButton(
                  onPressed: background.refreshStatus,
                  child: const Text('刷新后台状态'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '后台只读取 Todo API，不触发校园上游同步。通知仅显示任务标题，不含备注和图片。省电、网络或强行停止可能延后/停止系统任务；重新打开 App 后恢复。',
            style: p.AppTextStyle.footnote.of(context),
          ),
          p.TextButton(
            onPressed: background.openBatterySettings,
            child: const Text('查看系统电池与后台限制'),
          ),
        ],
      );
    },
  );
}
