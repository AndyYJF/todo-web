import 'task.dart';

const taskInputKeys = [
  'title',
  'note',
  'project',
  'priority',
  'startAt',
  'dueAt',
  'quick',
  'pinned',
];
Map<String, dynamic> taskInput(TodoTask task) => {
  'title': task.title,
  'note': task.note,
  'project': task.project,
  'priority': task.priority,
  'startAt': businessDateString(task.startAt),
  'dueAt': businessDateString(task.dueAt),
  'quick': task.quick,
  'pinned': task.pinned,
};

class TaskDraft {
  TaskDraft({
    required this.key,
    required this.origin,
    required this.taskId,
    required Map<String, dynamic> base,
    required Map<String, dynamic> values,
  }) : base = Map.unmodifiable(base),
       values = Map.unmodifiable(values);
  factory TaskDraft.open(String origin, TodoTask? task) {
    final values = task == null
        ? <String, dynamic>{
            'title': '',
            'note': '',
            'project': '',
            'priority': 'normal',
            'startAt': null,
            'dueAt': null,
            'quick': false,
            'pinned': false,
          }
        : taskInput(task);
    return TaskDraft(
      key: DateTime.now().microsecondsSinceEpoch.toString(),
      origin: origin,
      taskId: task?.id,
      base: values,
      values: values,
    );
  }
  final String key, origin;
  final int? taskId;
  final Map<String, dynamic> base, values;
  bool get hasChanges => taskId == null
      ? values['title'].toString().isNotEmpty ||
            values['note'].toString().isNotEmpty ||
            taskInputKeys.any((k) => values[k] != base[k])
      : taskInputKeys.any((k) => values[k] != base[k]);
  TaskDraft withValues(Map<String, dynamic> input) => TaskDraft(
    key: key,
    origin: origin,
    taskId: taskId,
    base: base,
    values: input,
  );
  Map<String, dynamic> payload() {
    final result = <String, dynamic>{};
    for (final key in taskInputKeys) {
      if (taskId != null && values[key] == base[key]) continue;
      var value = values[key];
      if (key == 'title' || key == 'project') value = (value as String).trim();
      if (key == 'startAt' || key == 'dueAt') {
        final text = (value as String?)?.trim();
        value = text == null || text.isEmpty
            ? null
            : businessDateString(parseBusinessDate(text));
      }
      result[key] = value;
    }
    if ((result['title'] is String && (result['title'] as String).isEmpty) ||
        values['title'].toString().trim().isEmpty) {
      throw const FormatException('请填写任务标题');
    }
    return result;
  }

  Map<String, dynamic> toJson() => {
    'key': key,
    'origin': origin,
    'taskId': taskId,
    'base': base,
    'values': values,
  };
  factory TaskDraft.fromJson(Map<String, dynamic> json) => TaskDraft(
    key: json['key'] as String,
    origin: json['origin'] as String,
    taskId: json['taskId'] as int?,
    base: Map<String, dynamic>.from(json['base'] as Map),
    values: Map<String, dynamic>.from(json['values'] as Map),
  );
}

enum WriteKind { create, patch, delete }

enum WriteState { confirmed, rejected, pending }

class WriteOutcome {
  const WriteOutcome(this.state, this.message, {this.task});
  final WriteState state;
  final String message;
  final TodoTask? task;
  bool get succeeded => state == WriteState.confirmed;
}

class PendingWrite {
  PendingWrite({
    required this.origin,
    required this.kind,
    required this.taskId,
    required this.payload,
    required this.beforeIds,
    required this.sentAt,
    this.draftKey,
  });
  final String origin;
  final WriteKind kind;
  final int? taskId;
  final Map<String, dynamic> payload;
  final Set<int> beforeIds;
  final DateTime sentAt;
  final String? draftKey;
  bool matches(TodoTask task) {
    final values = task.toJson();
    return payload.entries.every((entry) {
      final expected = entry.value is bool
          ? (entry.value as bool ? 1 : 0)
          : entry.value;
      return values[entry.key] == expected;
    });
  }

  Map<String, dynamic> toJson() => {
    'origin': origin,
    'kind': kind.name,
    'taskId': taskId,
    'payload': payload,
    'beforeIds': beforeIds.toList(),
    'sentAt': sentAt.toUtc().toIso8601String(),
    'draftKey': draftKey,
  };
  factory PendingWrite.fromJson(Map<String, dynamic> json) => PendingWrite(
    origin: json['origin'] as String,
    kind: WriteKind.values.byName(json['kind'] as String),
    taskId: json['taskId'] as int?,
    payload: Map<String, dynamic>.from(json['payload'] as Map),
    beforeIds: (json['beforeIds'] as List).cast<int>().toSet(),
    sentAt: DateTime.parse(json['sentAt'] as String).toUtc(),
    draftKey: json['draftKey'] as String?,
  );
}
