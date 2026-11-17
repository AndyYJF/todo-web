import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart' as p;
import 'package:prism_ui/icons/icons.dart';

import '../data/task.dart';

class DemoBadge extends StatelessWidget {
  const DemoBadge({super.key});
  @override
  Widget build(BuildContext context) => const StatusPill(label: '演示数据 · 仅本次会话');
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, this.color});
  final String label;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final scheme = p.Theme.of(context).colorScheme;
    final accent = color ?? scheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: ShapeDecoration(
        color: accent.withValues(alpha: 0.1),
        shape: p.AppShape.full,
      ),
      child: Text(
        label,
        style: p.AppTextStyle.caption1
            .of(context, emphasized: true)
            .copyWith(color: accent),
      ),
    );
  }
}

class SectionHeading extends StatelessWidget {
  const SectionHeading(this.title, {super.key, this.trailing});
  final String title;
  final String? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 20, 4, 12),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: p.AppTextStyle.title3.of(context, emphasized: true),
          ),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: p.AppTextStyle.footnote
                .of(context)
                .copyWith(
                  color: p.Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
      ],
    ),
  );
}

class TaskTile extends StatelessWidget {
  const TaskTile({
    super.key,
    required this.task,
    required this.onOpen,
    required this.onToggle,
  });
  final TodoTask task;
  final VoidCallback onOpen;
  final VoidCallback? onToggle;
  @override
  Widget build(BuildContext context) {
    final colors = p.Theme.of(context).colorScheme;
    final today = businessNow();
    final overdue =
        !task.done && task.dueAt != null && task.dueAt!.isBefore(today);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: p.ElasticPress(
        enabled: !MediaQuery.disableAnimationsOf(context),
        child: p.Card(
          padding: const EdgeInsets.fromLTRB(2, 12, 14, 12),
          onPressed: onOpen,
          child: Row(
            children: [
              Semantics(
                label: onToggle == null
                    ? (task.done ? '已完成' : '未完成')
                    : task.done
                    ? '标为未完成'
                    : '完成任务',
                child: p.Checkbox(
                  value: task.done,
                  isCircle: true,
                  onChanged: onToggle == null ? null : (_) => onToggle!(),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: p.AppTextStyle.callout
                          .of(context, emphasized: !task.done)
                          .copyWith(
                            color: task.done
                                ? colors.onSurfaceVariant
                                : colors.onSurface,
                            decoration: task.done
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                    ),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (task.pinned)
                          GlyphIcon(
                            Glyphs.pin,
                            size: 12,
                            color: colors.primary,
                          ),
                        Text(
                          task.project.isEmpty ? '个人任务' : task.project,
                          style: p.AppTextStyle.caption1
                              .of(context)
                              .copyWith(color: colors.onSurfaceVariant),
                        ),
                        Text(
                          overdue
                              ? '逾期 · ${dueLabel(task.dueAt)}'
                              : dueLabel(task.dueAt),
                          style: p.AppTextStyle.caption1
                              .of(context)
                              .copyWith(
                                color: overdue
                                    ? colors.error
                                    : colors.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              GlyphIcon(
                Glyphs.chevronForward,
                size: 15,
                color: colors.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class EmptyTasks extends StatelessWidget {
  const EmptyTasks({super.key, required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => p.Card(
    padding: const EdgeInsets.all(28),
    child: Column(
      children: [
        GlyphIcon(
          Glyphs.check,
          size: 32,
          color: p.Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 12),
        Text(
          message,
          textAlign: TextAlign.center,
          style: p.AppTextStyle.callout.of(context),
        ),
      ],
    ),
  );
}

PreferredSizeWidget todoBar(
  BuildContext context,
  String title, {
  List<Widget> actions = const [],
  bool back = false,
}) {
  final compact = p.ScaffoldSurface.of(context).isCompact;
  final height = compact ? p.sheetToolbarHeight : 70.0;
  return PreferredSize(
    preferredSize: Size.fromHeight(height),
    child: p.AppBar(
      title: Text(title),
      titleTextStyle:
          (compact ? p.AppTextStyle.title3 : p.AppTextStyle.largeTitle).of(
            context,
            emphasized: true,
          ),
      toolbarHeight: height,
      leading: back
          ? p.IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const GlyphIcon(Glyphs.chevronBack),
              tooltip: '返回',
            )
          : null,
      actions: actions,
    ),
  );
}
