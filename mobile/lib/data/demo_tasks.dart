import 'package:flutter/foundation.dart';

DateTime businessNow() => DateTime.now().toUtc().add(const Duration(hours: 8));

bool isTodayTask(DemoTask task) {
  final now = businessNow();
  final end = DateTime.utc(now.year, now.month, now.day + 1);
  return !task.done && (task.dueAt == null || task.dueAt!.isBefore(end));
}

class DemoTask {
  const DemoTask({
    required this.id,
    required this.title,
    this.note = '',
    this.project = '',
    this.priority = 'normal',
    this.dueAt,
    this.done = false,
    this.pinned = false,
    this.urgent,
    this.important,
  });
  final int id;
  final String title;
  final String note;
  final String project;
  final String priority;
  final DateTime? dueAt;
  final bool done;
  final bool pinned;
  final bool? urgent;
  final bool? important;
  DemoTask copyWith({
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
  }) => DemoTask(
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
  );
}

class DemoTaskStore extends ChangeNotifier {
  DemoTaskStore() {
    final now = businessNow();
    final day = DateTime.utc(now.year, now.month, now.day);
    _tasks = [
      DemoTask(
        id: 1,
        title: '把今天留给真正重要的事',
        note: '写下你想推进的一件事。这里的任务只是演示，修改只保留在本次打开期间。',
        project: '个人',
        pinned: true,
        urgent: true,
        important: true,
        dueAt: day.add(const Duration(hours: 20)),
        priority: 'high',
      ),
      DemoTask(
        id: 2,
        title: '整理课程笔记与本周复习提纲',
        note: '把散落的想法整理成清晰的步骤。先完成最关键的部分，给自己留一点余裕。',
        project: '学习',
        urgent: false,
        important: true,
        dueAt: day.add(const Duration(hours: 18)),
      ),
      DemoTask(
        id: 3,
        title: '确认校园活动报名信息',
        note: '检查时间、地点和需要准备的材料。',
        project: '校园',
        urgent: true,
        important: false,
        dueAt: day.subtract(const Duration(hours: 4)),
        priority: 'high',
      ),
      const DemoTask(
        id: 4,
        title: '读几页一直想读的书 📖',
        project: '生活',
        urgent: false,
        important: false,
      ),
      DemoTask(
        id: 5,
        title: '准备下周的小组讨论',
        project: '学习',
        urgent: false,
        important: true,
        dueAt: day.add(const Duration(days: 3, hours: 14)),
      ),
      const DemoTask(
        id: 6,
        title: '记录一个还没分类的新想法',
        note: '未分类任务可以在四象限页面集中查看。',
        project: '个人',
      ),
      DemoTask(
        id: 7,
        title: '完成一件很小却值得开心的事',
        project: '生活',
        done: true,
        urgent: false,
        important: false,
        dueAt: day.add(const Duration(hours: 10)),
      ),
    ];
  }
  late List<DemoTask> _tasks;
  int _nextId = 8;
  List<DemoTask> get tasks => List.unmodifiable(_tasks);
  DemoTask? task(int id) {
    for (final t in _tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  List<DemoTask> get today => _tasks.where(isTodayTask).toList();

  void save(DemoTask task) {
    _tasks = _tasks.map((t) => t.id == task.id ? task : t).toList();
    notifyListeners();
  }

  void add({
    required String title,
    required String note,
    required String project,
    required String priority,
    DateTime? dueAt,
  }) {
    _tasks = [
      DemoTask(
        id: _nextId++,
        title: title,
        note: note,
        project: project,
        priority: priority,
        dueAt: dueAt,
      ),
      ..._tasks,
    ];
    notifyListeners();
  }

  void toggle(int id) {
    final t = task(id);
    if (t != null) save(t.copyWith(done: !t.done));
  }

  void remove(int id) {
    _tasks = _tasks.where((t) => t.id != id).toList();
    notifyListeners();
  }
}

String dueLabel(DateTime? date) {
  if (date == null) return '未设日期';
  final now = businessNow();
  final day = DateTime.utc(now.year, now.month, now.day);
  final target = DateTime.utc(date.year, date.month, date.day);
  final diff = target.difference(day).inDays;
  final label = switch (diff) {
    0 => '今天',
    1 => '明天',
    -1 => '昨天',
    _ => '${date.month}月${date.day}日',
  };
  return '$label ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}
