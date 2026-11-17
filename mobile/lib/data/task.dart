DateTime businessNow() => DateTime.now().toUtc().add(const Duration(hours: 8));

DateTime? parseBusinessDate(Object? value) {
  if (value == null) return null;
  if (value is! String) throw const FormatException('日期格式错误');
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})(?::(\d{2}))?$',
  ).firstMatch(value);
  if (match == null) throw const FormatException('日期格式错误');
  final parts = [for (var i = 1; i <= 6; i++) int.parse(match[i] ?? '0')];
  final result = DateTime.utc(
    parts[0],
    parts[1],
    parts[2],
    parts[3],
    parts[4],
    parts[5],
  );
  if (result.year != parts[0] ||
      result.month != parts[1] ||
      result.day != parts[2] ||
      result.hour != parts[3] ||
      result.minute != parts[4] ||
      result.second != parts[5]) {
    throw const FormatException('日期范围错误');
  }
  return result;
}

String? businessDateString(DateTime? value) {
  if (value == null) return null;
  String p(int n) => n.toString().padLeft(2, '0');
  return '${value.year}-${p(value.month)}-${p(value.day)} ${p(value.hour)}:${p(value.minute)}';
}

bool isTodayTask(TodoTask task) {
  final now = businessNow();
  return !task.done &&
      (task.dueAt == null ||
          task.dueAt!.isBefore(DateTime.utc(now.year, now.month, now.day + 1)));
}

class TodoTask {
  const TodoTask({
    required this.id,
    required this.title,
    this.note = '',
    this.project = '',
    this.priority = 'normal',
    this.startAt,
    this.dueAt,
    this.done = false,
    this.pinned = false,
    this.quick = false,
    this.urgent,
    this.important,
    this.externalId,
    this.externalRev,
    this.doneAt,
    this.createdAt,
    this.updatedAt,
  });
  final int id;
  final String title, note, project, priority;
  final DateTime? startAt, dueAt, doneAt, createdAt, updatedAt;
  final bool done, pinned, quick;
  final bool? urgent, important;
  final String? externalId;
  final int? externalRev;

  factory TodoTask.fromJson(Map<String, dynamic> json) {
    bool flag(String key) {
      final value = json[key];
      if (value != 0 && value != 1) throw FormatException('任务字段错误：$key');
      return value == 1;
    }

    bool? axis(String key) => json[key] == null ? null : flag(key);
    String text(String key) {
      final value = json[key];
      if (value is! String) throw FormatException('任务字段错误：$key');
      return value;
    }

    final id = json['id'];
    if (id is! int || id <= 0) throw const FormatException('任务 ID 错误');
    final priority = text('priority');
    if (!['low', 'normal', 'high'].contains(priority)) {
      throw const FormatException('优先级错误');
    }
    return TodoTask(
      id: id,
      title: text('title'),
      note: text('note'),
      project: text('project'),
      priority: priority,
      done: flag('done'),
      pinned: flag('pinned'),
      quick: flag('quick'),
      urgent: axis('urgent'),
      important: axis('important'),
      startAt: parseBusinessDate(json['startAt']),
      dueAt: parseBusinessDate(json['dueAt']),
      doneAt: parseBusinessDate(json['doneAt']),
      createdAt: parseBusinessDate(json['createdAt']),
      updatedAt: parseBusinessDate(json['updatedAt']),
      externalId: json['externalId'] as String?,
      externalRev: json['externalRev'] as int?,
    );
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'note': note,
    'project': project,
    'priority': priority,
    'done': done ? 1 : 0,
    'pinned': pinned ? 1 : 0,
    'quick': quick ? 1 : 0,
    'urgent': urgent == null
        ? null
        : urgent!
        ? 1
        : 0,
    'important': important == null
        ? null
        : important!
        ? 1
        : 0,
    'startAt': businessDateString(startAt),
    'dueAt': businessDateString(dueAt),
    'doneAt': businessDateString(doneAt),
    'createdAt': businessDateString(createdAt),
    'updatedAt': businessDateString(updatedAt),
    'externalId': externalId,
    'externalRev': externalRev,
  };
  TodoTask copyWith({
    String? title,
    String? note,
    String? project,
    String? priority,
    DateTime? dueAt,
    bool clearDue = false,
    bool? done,
    bool? pinned,
    bool? urgent,
    bool? important,
  }) => TodoTask(
    id: id,
    title: title ?? this.title,
    note: note ?? this.note,
    project: project ?? this.project,
    priority: priority ?? this.priority,
    dueAt: clearDue ? null : dueAt ?? this.dueAt,
    done: done ?? this.done,
    pinned: pinned ?? this.pinned,
    urgent: urgent ?? this.urgent,
    important: important ?? this.important,
    startAt: startAt,
    doneAt: doneAt,
    quick: quick,
    externalId: externalId,
    externalRev: externalRev,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

String dueLabel(DateTime? date) {
  if (date == null) return '未设日期';
  final now = businessNow();
  final diff = DateTime.utc(
    date.year,
    date.month,
    date.day,
  ).difference(DateTime.utc(now.year, now.month, now.day)).inDays;
  final label = switch (diff) {
    0 => '今天',
    1 => '明天',
    -1 => '昨天',
    _ => '${date.month}月${date.day}日',
  };
  return '$label ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

String readTimeLabel(DateTime? utc) => utc == null
    ? '尚未读取'
    : businessDateString(utc.toUtc().add(const Duration(hours: 8)))!;
