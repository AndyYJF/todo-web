import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart' as p;

import '../../data/planner_client.dart';
import '../../data/planner_models.dart';
import '../../data/task.dart';
import '../../data/todo_api.dart';
import '../../ui/task_widgets.dart';
import 'planner_controls.dart';

class PlannerReminderSettings extends StatefulWidget {
  const PlannerReminderSettings({super.key, required this.client});
  final PlannerClient client;

  @override
  State<PlannerReminderSettings> createState() =>
      _PlannerReminderSettingsState();
}

class _PlannerReminderSettingsState extends State<PlannerReminderSettings> {
  final _time = TextEditingController(text: '21:30');
  Map<String, dynamic>? _settings;
  int _received = 0;
  bool _enabled = false, _busy = false;
  String? _message, _error;

  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void dispose() {
    _time.dispose();
    super.dispose();
  }

  void _update(Map<String, dynamic> data, {bool keepEdits = false}) {
    _settings = data;
    _received = DateTime.now().millisecondsSinceEpoch;
    if (!keepEdits) {
      _time.text = data['time'] as String;
      _enabled = data['enabled'] as bool;
    }
  }

  Future<void> _read() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      final settings = await widget.client.reminder();
      if (mounted) setState(() => _update(settings));
    } on ApiFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    final settings = _settings;
    final pending = widget.client.reminderAttempt;
    final time = _time.text.trim();
    if (pending == null) {
      if (settings == null) return;
      if (!RegExp(r'^(0[0-9]|1[0-9]|2[0-3]):[0-5][0-9]$').hasMatch(time)) {
        setState(() => _error = '请填写 24 小时制的 HH:mm 时间');
        return;
      }
    }
    final body =
        pending ??
        {
          'enabled': _enabled,
          'time': time,
          'baseVersion': settings!['revision'],
          'issuedAt':
              (settings['serverTime'] as int) +
              DateTime.now().millisecondsSinceEpoch -
              _received,
          'operationId': newPlannerOperation(),
        };
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    widget.client.reminderAttempt = body;
    final background = widget.client.store.background;
    try {
      final result = await widget.client.reminder(body: body);
      widget.client.reminderAttempt = null;
      if (!mounted) return;
      setState(() {
        _update(result);
        _message = '提醒设置已同步';
      });
      if (result['enabled'] == true &&
          background?.status['notificationsAllowed'] != true) {
        await background?.requestNotifications();
      }
    } on ApiFailure catch (error) {
      if (!error.uncertain) widget.client.reminderAttempt = null;
      if (!mounted) return;
      setState(() {
        if (error is PlannerApiFailure &&
            error.code == 'settings_conflict' &&
            error.current != null) {
          final current = error.current!;
          _update(current, keepEdits: true);
          _error =
              '另一端已改为 ${current['enabled'] == true ? '开启' : '关闭'} · ${current['time']}。请核对后再保存。';
        } else {
          _error = error.uncertain ? '保存结果待确认，可重试原操作。' : error.message;
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final background = widget.client.store.background!;
    final pending = widget.client.reminderAttempt;
    final enabled = (pending?['enabled'] as bool?) ?? _enabled;
    final locked = _busy || pending != null || _settings == null;
    return p.PrismScaffold(
      bar: todoBar(context, '规划提醒', back: true),
      body: Builder(
        builder: (context) => ListView(
          padding: EdgeInsets.fromLTRB(16, context.appBarInset + 16, 16, 28),
          children: [
            if (_error != null) PlannerNotice(_error!, error: true),
            if (_message != null) PlannerNotice(_message!),
            if (_busy && _settings == null && pending == null)
              const Center(child: p.ActivityIndicator()),
            p.Card(
              inert: true,
              padding: EdgeInsets.zero,
              child: p.ListRow(
                title: const Text('每日规划提醒'),
                subtitle: const Text('点按通知，打开当晚对应的安排'),
                trailing: p.Switch(
                  value: enabled,
                  onChanged: (value) {
                    if (!locked) setState(() => _enabled = value);
                  },
                ),
              ),
            ),
            const SectionHeading('提醒时间（UTC+8）'),
            p.TextField(
              controller: _time,
              enabled: !locked,
              keyboardType: TextInputType.datetime,
              decoration: const p.InputDecoration(hintText: 'HH:mm'),
            ),
            const SizedBox(height: 12),
            p.FilledButton(
              onPressed: _busy || (_settings == null && pending == null)
                  ? null
                  : _save,
              child: Text(pending != null ? '重试原操作' : '保存提醒'),
            ),
            p.TextButton(
              onPressed: _busy || pending != null ? null : _read,
              child: const Text('读取服务端设置'),
            ),
            ListenableBuilder(
              listenable: background,
              builder: (context, _) {
                final status = background.status;
                final next = status['plannerNextAt'] as int? ?? 0;
                final allowed = status['notificationsAllowed'] == true;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (next > 0)
                      PlannerNotice(
                        '本机下次提醒 ${readTimeLabel(DateTime.fromMillisecondsSinceEpoch(next, isUtc: true))}',
                      ),
                    if (!allowed)
                      p.TextButton(
                        onPressed: background.requestNotifications,
                        child: const Text('允许消息通知'),
                      ),
                    p.TextButton(
                      onPressed: background.openNotificationSettings,
                      child: const Text('系统通知设置'),
                    ),
                    if (status['exactAllowed'] != true) ...[
                      const PlannerNotice('Android 可能延后提醒。'),
                      p.TextButton(
                        onPressed: background.openExactSettings,
                        child: const Text('设置准时提醒权限'),
                      ),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
