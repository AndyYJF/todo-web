import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart' as p;

import '../data/remote_tasks.dart';
import '../data/task_write.dart';
import 'task_widgets.dart';
import 'todo_motion.dart';

class WriteNotice extends StatelessWidget {
  const WriteNotice({super.key, required this.store});
  final RemoteTaskStore store;
  @override
  Widget build(BuildContext context) {
    final operation = store.pending;
    if (operation == null) {
      if (store.writeError == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(
          store.writeError!,
          style: p.AppTextStyle.footnote
              .of(context)
              .copyWith(color: p.Theme.of(context).colorScheme.error),
        ),
      );
    }
    final sameOrigin = operation.origin == store.origin;
    final candidates = store.createCandidates;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: p.Card(
        inert: true,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              store.writing ? '正在提交，请勿重复操作' : '提交结果待确认',
              style: p.AppTextStyle.headline.of(context),
            ),
            const SizedBox(height: 8),
            Text(
              store.writing
                  ? '收到服务端结果后会更新任务。'
                  : sameOrigin
                  ? '先重新读取并核对结果。新建任务不会自动重发。'
                  : '请登录原站点核对：${operation.origin}',
              style: p.AppTextStyle.footnote.of(context),
            ),
            if (!store.writing && sameOrigin && store.authenticated)
              p.TextButton(
                onPressed: store.refreshing ? null : () => store.refresh(),
                child: const Text('重新读取确认'),
              ),
            if (!store.writing &&
                operation.kind == WriteKind.create &&
                sameOrigin) ...[
              if (candidates.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('暂未发现匹配的新任务，原请求仍可能在处理。'),
                ),
              for (final task in candidates.take(3))
                p.TextButton(
                  onPressed: () => store.confirmCreated(task.id),
                  child: Text(
                    '确认是这条任务：${task.title}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            if (!store.writing)
              p.TextButton(
                onPressed: () => _abandon(context),
                child: const Text('已核对，结束本次结果确认'),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _abandon(BuildContext context) async {
    final confirmed = await showTodoFormSheet<bool>(
      context: context,
      builder: (context) => p.PrismScaffold(
        bar: todoBar(
          context,
          '结束结果确认',
          actions: [
            p.TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
          ],
        ),
        body: Builder(
          builder: (context) => Padding(
            padding: EdgeInsets.fromLTRB(24, context.appBarInset + 20, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('此操作不会重发请求，草稿会保留。原请求仍可能在服务端生效，再次提交前请核对任务列表。'),
                const SizedBox(height: 20),
                p.FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('保留草稿并结束确认'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (confirmed == true) await store.abandonPending();
  }
}
