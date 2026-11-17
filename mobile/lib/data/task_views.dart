import 'task.dart';

DateTime taskDay(DateTime value) =>
    DateTime.utc(value.year, value.month, value.day);
bool taskOnDay(TodoTask task, DateTime day) {
  final first = task.startAt ?? task.dueAt, last = task.dueAt ?? task.startAt;
  if (first == null || last == null) return false;
  final a = taskDay(first), b = taskDay(last), target = taskDay(day);
  final start = a.isBefore(b) ? a : b, end = a.isBefore(b) ? b : a;
  return !target.isBefore(start) && !target.isAfter(end);
}

String quadrantLabel(bool? urgent, bool? important) {
  if (urgent == null || important == null) return '未分类';
  return important
      ? urgent
            ? '马上做'
            : '计划做'
      : urgent
      ? '快速处理'
      : '可以缓缓';
}

const quadrantChoices = <(String, String, bool?, bool?)>[
  ('马上做', '重要且紧急', true, true),
  ('计划做', '重要不紧急', false, true),
  ('快速处理', '紧急不重要', true, false),
  ('可以缓缓', '不重要不紧急', false, false),
  ('未分类', '清除两个分类标记', null, null),
];
List<String> projectNames(List<TodoTask> tasks, List<String> projects) =>
    ({...projects, ...tasks.map((t) => t.project)}.toList()..sort(
      (a, b) => a.isEmpty
          ? (b.isEmpty ? 0 : 1)
          : b.isEmpty
          ? -1
          : a.compareTo(b),
    ));
