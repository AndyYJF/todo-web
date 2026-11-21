import 'dart:io';

import 'local_state.dart';
import 'planner_models.dart';
import 'remote_tasks.dart';
import 'todo_api.dart';

/// Keeps only recent day snapshots and one local work draft, bound to the site.
class PlannerClient {
  PlannerClient(this.store)
    : origin = store.origin,
      file = LocalStateFile(
        Directory('${store.storage.directory.path}/planner'),
      );
  final RemoteTaskStore store;
  final String origin;
  final LocalStateFile file;
  final _days = <String, Map<String, dynamic>>{};
  Map<String, dynamic>? draft;
  Map<String, dynamic>? importAttempt;
  bool _loaded = false;

  bool get _current => store.authenticated && store.origin == origin;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final state = await file.read();
      if (!_current || state == null || state['origin'] != origin) return;
      final days = (state['days'] as List? ?? []).cast<Map<String, dynamic>>();
      for (final day in days) {
        final parsed = PlanDay.fromJson(day);
        _days[parsed.date] = day;
      }
      draft = state['draft'] as Map<String, dynamic>?;
    } catch (_) {
      _days.clear();
    }
  }

  PlanDay? cached(String date) {
    final data = _days[date];
    return _current && data != null ? PlanDay.fromJson(data) : null;
  }

  Future<void> _save() async {
    if (!_current) return;
    try {
      await file.save({
        'origin': origin,
        'days': _days.values.toList(),
        'draft': draft,
      });
    } catch (_) {
      /* The in-memory copy stays usable. */
    }
  }

  Future<void> saveDraft(Map<String, dynamic>? value) async {
    draft = value;
    await _save();
  }

  Future<PlanDay> loadDay(
    String? date, {
    required bool Function() isCurrent,
  }) async {
    final Map<String, dynamic> data;
    try {
      data = await store.plannerRequest(PlannerResource.day, date: date);
    } on ApiFailure catch (error) {
      if (error.statusCode == 410 &&
          date != null &&
          _days.remove(date) != null) {
        await _save();
      }
      rethrow;
    }
    final day = PlanDay.fromJson(data);
    if (date == null) return day;
    if (day.date != date) throw const ApiFailure('服务返回了其他日期');
    final existing = cached(date);
    if (isCurrent() &&
        (existing == null || existing.revision <= day.revision)) {
      _days.remove(date);
      _days[date] = data;
      while (_days.length > 3) {
        _days.remove(_days.keys.first);
      }
      await _save();
    }
    return day;
  }

  Future<PlanHistory> loadHistory({String? before}) async {
    final data = await store.plannerRequest(
      PlannerResource.history,
      before: before,
    );
    final page = PlanHistory.fromJson(data);
    final first = page.earliestDate;
    final count = _days.length;
    _days.removeWhere(
      (date, cached) => first == null
          ? cached['archived'] == true
          : date.compareTo(first) < 0,
    );
    if (_days.length != count) await _save();
    return page;
  }

  Future<Map<String, dynamic>> schoolWeek(String date) =>
      store.plannerRequest(PlannerResource.academicCalendar, date: date);
  Future<Map<String, dynamic>> write(Map<String, dynamic> body) =>
      store.plannerRequest(PlannerResource.day, body: body);
  Future<Map<String, dynamic>> timetable(Map<String, dynamic> body) =>
      store.plannerRequest(PlannerResource.timetable, body: body);
}
