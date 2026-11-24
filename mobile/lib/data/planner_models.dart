import 'dart:math' as math;

import 'task.dart';

String plannerDate(DateTime date) => date.toIso8601String().substring(0, 10);
String plannerShift(String date, int days) =>
    plannerDate(DateTime.parse('${date}T00:00:00Z').add(Duration(days: days)));
String plannerToday() => plannerDate(businessNow());

enum PlanStatus {
  pending('未记录'),
  done('已完成'),
  unfinished('未完成');

  const PlanStatus(this.label);
  final String label;

  static PlanStatus decode(Object? input) =>
      values.firstWhere((value) => value.name == input, orElse: () => pending);
}

class PlanItem {
  PlanItem.fromJson(Map data)
    : id = data['id'] as String,
      version = data['version'] as int,
      title = data['title'] as String,
      status = PlanStatus.decode(data['status']),
      note = data['note'] as String,
      startTime = data['startTime'] as String?,
      endTime = data['endTime'] as String?,
      todoId = data['todoId'] as int?;
  final String id, title, note;
  final PlanStatus status;
  final int version;
  final String? startTime, endTime;
  final int? todoId;
  Map<String, dynamic> toJson() => {'id': id, 'version': version, ...fields()};
  Map<String, dynamic> fields() => {
    'title': title,
    'note': note,
    'startTime': startTime,
    'endTime': endTime,
    'todoId': todoId,
    'status': status.name,
  };
}

class PlanCourse {
  PlanCourse.fromJson(Map data)
    : title = data['title'] as String,
      location = data['location'] as String,
      startsAt = data['startsAt'] as String,
      endsAt = data['endsAt'] as String,
      allDay = data['allDay'] as bool;
  final String title, location, startsAt, endsAt;
  final bool allDay;
}

class PlanDay {
  PlanDay.fromJson(Map data)
    : date = data['date'] as String,
      today = data['today'] as String,
      openFrom = data['openFrom'] as String,
      revision = data['revision'] as int,
      serverTime = data['serverTime'] as int,
      archived = data['archived'] as bool,
      courses = (data['courses'] as List)
          .cast<Map>()
          .map(PlanCourse.fromJson)
          .toList(),
      items = (data['items'] as List)
          .cast<Map>()
          .map(PlanItem.fromJson)
          .toList();
  final String date, today, openFrom;
  final int revision, serverTime;
  final bool archived;
  final List<PlanCourse> courses;
  final List<PlanItem> items;
}

class PlanHistory {
  PlanHistory.fromJson(Map<String, dynamic> data)
    : items = (data['items'] as List)
          .cast<Map>()
          .map(PlanHistoryDay.fromJson)
          .toList(),
      nextBefore = data['nextBefore'] as String?,
      earliestDate = data['earliestDate'] as String?,
      bytes = data['bytes'] as int,
      limitBytes = data['limitBytes'] as int;
  final List<PlanHistoryDay> items;
  final String? nextBefore, earliestDate;
  final int bytes, limitBytes;
}

class PlanHistoryDay {
  PlanHistoryDay.fromJson(Map data)
    : date = data['date'] as String,
      doneCount = data['doneCount'] as int,
      itemCount = data['itemCount'] as int;
  final String date;
  final int doneCount, itemCount;
}

class PlanInterval {
  const PlanInterval(
    this.start,
    this.end, {
    this.course,
    this.item,
    this.overlap = false,
  });
  final int start, end;
  final PlanCourse? course;
  final PlanItem? item;
  final bool overlap;
  bool get isGap => course == null && item == null;
}

int _minutes(String value) =>
    int.parse(value.substring(0, 2)) * 60 + int.parse(value.substring(3, 5));

String plannerTime(int minutes) {
  String pad(int value) => value.toString().padLeft(2, '0');
  return '${pad(minutes ~/ 60)}:${pad(minutes % 60)}';
}

List<PlanInterval> plannerTimeline(PlanDay day, {String? excludeItemId}) {
  final courses = [
    for (final course in day.courses.where((course) => !course.allDay))
      PlanInterval(
        course.startsAt.substring(0, 10).compareTo(day.date) < 0
            ? 0
            : _minutes(course.startsAt.substring(11, 16)),
        course.endsAt.substring(0, 10).compareTo(day.date) > 0
            ? 1440
            : _minutes(course.endsAt.substring(11, 16)),
        course: course,
      ),
  ];
  final booked = [...courses];
  for (final item in day.items) {
    if (item.id == excludeItemId ||
        item.startTime == null ||
        item.endTime == null) {
      continue;
    }
    final start = _minutes(item.startTime!), end = _minutes(item.endTime!);
    booked.add(
      PlanInterval(
        start,
        end,
        item: item,
        overlap: courses.any(
          (course) => start < course.end && course.start < end,
        ),
      ),
    );
  }
  booked.sort(
    (a, b) => a.start == b.start
        ? a.end.compareTo(b.end)
        : a.start.compareTo(b.start),
  );
  var freeFrom = 8 * 60;
  const freeUntil = 22 * 60;
  final entries = <PlanInterval>[];
  for (final block in booked) {
    final end = math.min(block.start, freeUntil);
    if (end - freeFrom >= 15) entries.add(PlanInterval(freeFrom, end));
    entries.add(block);
    freeFrom = math.max(freeFrom, block.end);
  }
  if (freeUntil - freeFrom >= 15) {
    entries.add(PlanInterval(freeFrom, freeUntil));
  }
  return entries;
}

String newPlannerOperation() {
  final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final text = bytes
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${text.substring(0, 8)}-${text.substring(8, 12)}-${text.substring(12, 16)}-${text.substring(16, 20)}-${text.substring(20)}';
}

final _random = math.Random.secure();
