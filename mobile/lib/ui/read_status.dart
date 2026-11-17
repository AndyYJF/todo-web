import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart' as p;

import '../data/remote_tasks.dart';
import '../data/task.dart';
import 'task_widgets.dart';
import 'write_notice.dart';

class ReadStatus extends StatelessWidget {
  const ReadStatus({super.key, required this.store});
  final RemoteTaskStore store;
  @override
  Widget build(BuildContext context) {
    final colors = p.Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StatusPill(
          label: store.refreshing
              ? '正在读取'
              : store.cached
              ? '本机缓存 · 联网刷新后可提交'
              : '服务端数据',
        ),
        const SizedBox(height: 8),
        Text(
          '最近读取：${readTimeLabel(store.readAt)}',
          style: p.AppTextStyle.caption1
              .of(context)
              .copyWith(color: colors.onSurfaceVariant),
        ),
        if (store.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              store.error!,
              style: p.AppTextStyle.footnote
                  .of(context)
                  .copyWith(color: colors.error),
            ),
          ),
        if (store.storageError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              store.storageError!,
              style: p.AppTextStyle.footnote
                  .of(context)
                  .copyWith(color: colors.error),
            ),
          ),
        WriteNotice(store: store),
      ],
    );
  }
}
