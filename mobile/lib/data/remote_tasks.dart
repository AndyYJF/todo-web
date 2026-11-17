import 'dart:async';

import 'package:flutter/foundation.dart';

import 'local_state.dart';
import 'task.dart';
import 'todo_api.dart';

class RemoteTaskStore extends ChangeNotifier {
  RemoteTaskStore(this.storage, {this.allowLocalHttp = false});
  final LocalStateFile storage;
  final bool allowLocalHttp;
  TodoApi _api = TodoApi(Uri.parse(defaultOrigin));
  bool ready = false,
      authenticated = false,
      signingIn = false,
      refreshing = false;
  bool cached = false;
  String? error, campusReadError, storageError;
  String theme = 'system';
  DateTime? readAt;
  CampusStatus? campus;
  List<TodoTask> _tasks = [];
  List<String> _projects = [];
  int _generation = 0;
  Future<void>? _inFlight;
  bool _disposed = false;
  String get origin => _api.origin.toString();
  List<TodoTask> get tasks => List.unmodifiable(_tasks);
  List<TodoTask> get today => _tasks.where(isTodayTask).toList();
  List<String> get projects => List.unmodifiable(_projects);
  TodoTask? task(int id) {
    for (final task in _tasks) {
      if (task.id == id) return task;
    }
    return null;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() async {
    try {
      final state = await storage.read();
      if (state != null) {
        if (state['schema'] != 1) throw const FormatException('本地数据版本不兼容');
        final site = normalizeOrigin(
          state['origin'] as String,
          allowLocalHttp: allowLocalHttp,
        );
        _api.close();
        _api = TodoApi(site);
        if (['system', 'light', 'dark'].contains(state['theme'])) {
          theme = state['theme'] as String;
        }
        final sessionJson = state['session'];
        if (sessionJson != null) {
          final session = TodoSession.fromJson(
            Map<String, dynamic>.from(sessionJson as Map),
          );
          if (session.valid) {
            _api.session = session;
            authenticated = true;
            final snapshot = state['snapshot'];
            if (snapshot is Map && snapshot['origin'] == origin) {
              _tasks = (snapshot['tasks'] as List)
                  .map(
                    (r) =>
                        TodoTask.fromJson(Map<String, dynamic>.from(r as Map)),
                  )
                  .toList();
              if (_tasks.map((t) => t.id).toSet().length != _tasks.length) {
                throw const FormatException('缓存任务 ID 重复');
              }
              _projects = (snapshot['projects'] as List)
                  .cast<String>()
                  .toList();
              readAt = DateTime.parse(snapshot['readAt'] as String).toUtc();
              campus = snapshot['campus'] == null
                  ? null
                  : CampusStatus.fromJson(
                      Map<String, dynamic>.from(snapshot['campus'] as Map),
                    );
              cached = true;
            }
          } else {
            error = '会话已过期，请重新登录';
          }
        }
      }
    } catch (_) {
      authenticated = false;
      _api.session = null;
      _clearSnapshot();
      error = '本地会话或缓存无法读取，请重新登录';
    }
    ready = true;
    _notify();
    if (authenticated) {
      unawaited(refresh());
    } else {
      await _persist();
    }
  }

  void _clearSnapshot() {
    _tasks = [];
    _projects = [];
    readAt = null;
    campus = null;
    cached = false;
    campusReadError = null;
  }

  Future<void> _persist() async {
    final state = <String, dynamic>{
      'schema': 1,
      'origin': origin,
      'theme': theme,
      'session': authenticated ? _api.session?.toJson() : null,
      'snapshot': authenticated && readAt != null
          ? {
              'origin': origin,
              'tasks': _tasks.map((t) => t.toJson()).toList(),
              'projects': _projects,
              'readAt': readAt!.toUtc().toIso8601String(),
              'campus': campus?.toJson(),
            }
          : null,
    };
    try {
      await storage.save(state);
      storageError = null;
    } catch (_) {
      storageError = '本机保存失败，重启后可能需要重新登录';
    }
    _notify();
  }

  Future<bool> login(String server, String password) async {
    if (signingIn) return false;
    Uri site;
    try {
      site = normalizeOrigin(server, allowLocalHttp: allowLocalHttp);
    } on FormatException catch (e) {
      error = e.message;
      _notify();
      return false;
    }
    final generation = ++_generation;
    signingIn = true;
    authenticated = false;
    refreshing = false;
    _inFlight = null;
    _clearSnapshot();
    error = null;
    _api.close();
    final api = TodoApi(site);
    _api = api;
    _notify();
    await _persist();
    try {
      await api.login(password);
      if (generation != _generation || _disposed) return false;
      authenticated = true;
      await _persist();
      unawaited(refresh());
      return true;
    } catch (e) {
      if (generation == _generation) error = _message(e);
      return false;
    } finally {
      if (generation == _generation) {
        signingIn = false;
        _notify();
      }
    }
  }

  Future<void> refresh() {
    if (!authenticated || _disposed) return Future.value();
    return _inFlight ??= _read(_generation, _api);
  }

  Future<(T?, Object?)> _readResult<T>(Future<T> read) async {
    try {
      return (await read, null);
    } catch (e) {
      return (null, e);
    }
  }

  Future<void> _read(int generation, TodoApi api) async {
    refreshing = true;
    _notify();
    try {
      final taskFuture = _readResult(api.tasks());
      final projectFuture = _readResult(api.projects());
      final campusFuture = _readResult(api.campus());
      final taskResult = await taskFuture;
      final projectResult = await projectFuture;
      final campusResult = await campusFuture;
      if (generation != _generation || _disposed) return;
      final failures = [taskResult.$2, projectResult.$2, campusResult.$2];
      if (failures.any((e) => e is ApiFailure && e.unauthorized)) {
        await _expire();
        return;
      }
      if (taskResult.$2 != null) throw taskResult.$2!;
      _tasks = taskResult.$1!;
      _projects =
          projectResult.$1 ??
          (_tasks
              .map((t) => t.project)
              .where((p) => p.isNotEmpty)
              .toSet()
              .toList()
            ..sort());
      campusReadError = campusResult.$2 == null
          ? null
          : _message(campusResult.$2!);
      if (campusResult.$2 == null) campus = campusResult.$1;
      readAt = DateTime.now().toUtc();
      cached = false;
      error = projectResult.$2 == null ? null : '任务已更新，项目列表读取失败';
      await _persist();
    } catch (e) {
      if (generation == _generation && !_disposed) {
        if (e is ApiFailure && e.unauthorized) {
          await _expire();
        } else {
          error = _message(e);
          cached = readAt != null;
        }
      }
    } finally {
      if (generation == _generation) {
        refreshing = false;
        _inFlight = null;
        _notify();
      }
    }
  }

  String _message(Object error) =>
      error is ApiFailure ? error.message : '服务返回的数据无法解析，已保留最近的任务快照';
  Future<void> _expire() async {
    ++_generation;
    _inFlight = null;
    refreshing = false;
    authenticated = false;
    _api.session = null;
    _clearSnapshot();
    error = '会话已失效，请重新登录';
    _notify();
    await _persist();
  }

  Future<void> logout() async {
    final oldApi = _api;
    ++_generation;
    _inFlight = null;
    refreshing = false;
    signingIn = false;
    authenticated = false;
    _clearSnapshot();
    error = null;
    _api = TodoApi(oldApi.origin);
    _notify();
    final remote = () async {
      try {
        await oldApi.logout();
      } catch (_) {
      } finally {
        oldApi.close();
      }
    }();
    await _persist();
    unawaited(remote);
  }

  Future<void> setTheme(String value) async {
    if (!['system', 'light', 'dark'].contains(value)) return;
    theme = value;
    _notify();
    await _persist();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _api.close();
    super.dispose();
  }
}
