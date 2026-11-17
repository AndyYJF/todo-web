import 'package:flutter/foundation.dart';

import 'task.dart';

class DemoTaskStore extends ChangeNotifier {
  DemoTaskStore() {
    final now = businessNow();
    final day = DateTime.utc(now.year, now.month, now.day);
    _tasks = [
      TodoTask(
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
      TodoTask(
        id: 2,
        title: '整理课程笔记与本周复习提纲',
        note: '把散落的想法整理成清晰的步骤。先完成最关键的部分，给自己留一点余裕。',
        project: '学习',
        urgent: false,
        important: true,
        dueAt: day.add(const Duration(hours: 18)),
      ),
      TodoTask(
        id: 3,
        title: '确认校园活动报名信息',
        note: '检查时间、地点和需要准备的材料。',
        project: '校园',
        urgent: true,
        important: false,
        dueAt: day.subtract(const Duration(hours: 4)),
        priority: 'high',
      ),
      const TodoTask(
        id: 4,
        title: '读几页一直想读的书 📖',
        project: '生活',
        urgent: false,
        important: false,
      ),
      TodoTask(
        id: 5,
        title: '准备下周的小组讨论',
        project: '学习',
        urgent: false,
        important: true,
        dueAt: day.add(const Duration(days: 3, hours: 14)),
      ),
      const TodoTask(
        id: 6,
        title: '记录一个还没分类的新想法',
        note: '未分类任务可以在四象限页面集中查看。',
        project: '个人',
      ),
      TodoTask(
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
  late List<TodoTask> _tasks;
  int _nextId = 8;
  List<TodoTask> get tasks => List.unmodifiable(_tasks);
  TodoTask? task(int id) {
    for (final t in _tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  List<TodoTask> get today => _tasks.where(isTodayTask).toList();

  void save(TodoTask task) {
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
      TodoTask(
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
