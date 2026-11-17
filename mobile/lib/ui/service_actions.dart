import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart' as p;

import '../data/remote_tasks.dart';
import '../data/task_views.dart';
import 'task_widgets.dart';
import 'todo_motion.dart';

Future<bool> confirmServiceAction(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
}) async =>
    await showTodoFormSheet<bool>(
      context: context,
      builder: (context) => p.PrismScaffold(
        bar: todoBar(
          context,
          title,
          actions: [
            p.TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
          ],
        ),
        body: Builder(
          builder: (context) => ListView(
            shrinkWrap: true,
            padding: EdgeInsets.fromLTRB(24, context.appBarInset + 24, 24, 32),
            children: [
              Text(message, style: p.AppTextStyle.body.of(context)),
              const SizedBox(height: 24),
              p.FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(action),
              ),
            ],
          ),
        ),
      ),
    ) ??
    false;
Future<void> classifyTasks(
  BuildContext context,
  RemoteTaskStore store, {
  bool force = false,
}) async {
  final confirmed = await confirmServiceAction(
    context,
    title: force ? '重新分类全部' : '分类未分类任务',
    message: force
        ? '将重新分类全部未完成任务，覆盖已有象限，包括手动选择的结果。已完成任务不变。AI 不可用时由服务端规则兜底。'
        : '只分类未完成且尚未分类的任务，保留已有象限。AI 不可用时由服务端规则兜底。',
    action: force ? '确认重新分类' : '开始分类',
  );
  if (confirmed && context.mounted) await store.classifyTasks(force: force);
}

Future<void> syncCampus(BuildContext context, RemoteTaskStore store) async {
  if (await confirmServiceAction(
        context,
        title: '同步校园任务',
        message: '从校园上游获取最新任务并更新 Todo 服务，可能需要一分钟。普通刷新只读取 Todo 服务，不触发此操作。',
        action: '开始校园同步',
      ) &&
      context.mounted) {
    await store.syncCampus();
  }
}

Future<void> chooseQuadrant(
  BuildContext context,
  RemoteTaskStore store,
  int id,
) async {
  final choice = await showTodoFormSheet<int>(
    context: context,
    props: const p.SheetProps(detents: [.8]),
    builder: (context) => p.PrismScaffold(
      bar: todoBar(
        context,
        '选择象限',
        actions: [
          p.TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
      body: Builder(
        builder: (context) => ListView(
          padding: EdgeInsets.fromLTRB(20, context.appBarInset + 12, 20, 32),
          children: [
            for (var i = 0; i < quadrantChoices.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: p.Card(
                  onPressed: () => Navigator.of(context).pop(i),
                  child: p.ListRow(
                    title: Text(quadrantChoices[i].$1),
                    subtitle: Text(quadrantChoices[i].$2),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
  if (choice != null) {
    await store.patchTask(id, {
      'urgent': quadrantChoices[choice].$3,
      'important': quadrantChoices[choice].$4,
    });
  }
}
