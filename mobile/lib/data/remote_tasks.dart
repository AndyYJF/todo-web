import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'local_state.dart';
import 'android_background.dart';
import 'task.dart';
import 'task_write.dart';
import 'todo_api.dart';

class RemoteTaskStore extends ChangeNotifier {
  RemoteTaskStore(this.storage, {this.allowLocalHttp = false, this.background});
  final AndroidBackground? background;
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
  int _generation = 0, _writeGeneration = 0, _readRequest = 0;
  bool writing = false, _foreground = false;
  Timer? _poll;
  TaskDraft? draft;
  PendingWrite? pending;
  String? writeError, lastCompletedDraftKey, serviceMessage;
  ClassifyResult? lastClassification;
  DateTime? get sessionExpiresAt => _api.session?.expiresAt;
  TaskDraft? get activeDraft => draft?.origin == origin ? draft : null;
  bool get canWrite =>
      authenticated &&
      readAt != null &&
      !cached &&
      !writing &&
      pending == null &&
      !_disposed;
  List<TodoTask> get createCandidates {
    final operation = pending;
    if (operation == null ||
        operation.origin != origin ||
        operation.kind != WriteKind.create ||
        cached ||
        readAt == null ||
        readAt!.isBefore(operation.sentAt)) {
      return [];
    }
    return _tasks
        .where(
          (t) => !operation.beforeIds.contains(t.id) && operation.matches(t),
        )
        .toList();
  }

  void setForeground(bool value) {
    _foreground = value;
    _syncPolling();
  }

  void _syncPolling() {
    if (_foreground && ready && authenticated && !_disposed) {
      _poll ??= Timer.periodic(const Duration(seconds: 30), (_) {
        if (!writing) unawaited(refresh());
      });
    } else {
      _poll?.cancel();
      _poll = null;
    }
  }

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
        _writeGeneration = state['writeGeneration'] as int? ?? 0;
        final site = normalizeOrigin(
          state['origin'] as String,
          allowLocalHttp: allowLocalHttp,
        );
        _api.close();
        _api = TodoApi(site);
        if (['system', 'light', 'dark'].contains(state['theme'])) {
          theme = state['theme'] as String;
        }
        if (state['draft'] != null) {
          draft = TaskDraft.fromJson(
            Map<String, dynamic>.from(state['draft'] as Map),
          );
        }
        if (state['pending'] != null) {
          pending = PendingWrite.fromJson(
            Map<String, dynamic>.from(state['pending'] as Map),
          );
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
    if (background != null) {
      await background!.attach(
        '${storage.directory.path}/todo-state.json',
        local: allowLocalHttp,
      );
      if (authenticated && background!.sessionInvalid) await _expire();
      await _importBackground();
    }
    ready = true;
    _syncPolling();
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
    serviceMessage = null;
    lastClassification = null;
  }

  Future<bool> _persist() async {
    final state = <String, dynamic>{
      'schema': 1,
      'revision': DateTime.now().microsecondsSinceEpoch,
      'writeGeneration': _writeGeneration,
      'origin': origin,
      'theme': theme,
      'draft': draft?.toJson(),
      'pending': pending?.toJson(),
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
      await background?.stateChanged();
      storageError = null;
      _notify();
      return true;
    } catch (_) {
      storageError = '本机保存失败，重启后可能需要重新登录';
      _notify();
      return false;
    }
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
    writing = false;
    authenticated = false;
    _syncPolling();
    refreshing = false;
    _inFlight = null;
    _clearSnapshot();
    error = null;
    _api.close();
    final api = TodoApi(site);
    _api = api;
    if (draft?.origin != origin) draft = null;
    _notify();
    await _persist();
    try {
      await api.login(password);
      if (generation != _generation || _disposed) return false;
      authenticated = true;
      _syncPolling();
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

  Future<void> resume() async {
    await background?.refreshStatus();
    if (authenticated && background?.sessionInvalid == true) {
      await _expire();
      return;
    }
    await _importBackground();
    await refresh();
  }

  Future<void> _importBackground() async {
    if (background == null || !authenticated || writing || pending != null) {
      return;
    }
    final auth = _generation, write = _writeGeneration;
    try {
      final snapshot = await background!.snapshot();
      if (snapshot == null ||
          snapshot['origin'] != origin ||
          auth != _generation ||
          write != _writeGeneration ||
          writing ||
          pending != null) {
        return;
      }
      final at = DateTime.parse(snapshot['readAt'] as String).toUtc();
      if (readAt != null && !at.isAfter(readAt!)) return;
      final rows = (jsonDecode(snapshot['tasksJson'] as String) as List)
          .map((r) => TodoTask.fromJson(Map<String, dynamic>.from(r as Map)))
          .toList();
      if (rows.map((t) => t.id).toSet().length != rows.length) return;
      ++_readRequest;
      _inFlight = null;
      refreshing = false;
      _tasks = rows;
      _projects =
          rows.map((t) => t.project).where((p) => p.isNotEmpty).toSet().toList()
            ..sort();
      readAt = at;
      cached = true;
      await _persist();
      _notify();
    } catch (_) {
      /* Keep the existing cache if the background snapshot is unreadable. */
    }
  }

  Future<void> refresh() {
    if (!authenticated || _disposed || writing) return Future.value();
    return _inFlight ??= _read(
      _generation,
      _writeGeneration,
      ++_readRequest,
      _api,
    );
  }

  Future<(T?, Object?)> _readResult<T>(Future<T> read) async {
    try {
      return (await read, null);
    } catch (e) {
      return (null, e);
    }
  }

  bool _currentRead(int auth, int write, int request) =>
      auth == _generation &&
      write == _writeGeneration &&
      request == _readRequest &&
      !writing &&
      !_disposed;
  Future<void> _read(int auth, int write, int request, TodoApi api) async {
    refreshing = true;
    _notify();
    try {
      final taskFuture = _readResult(api.tasks());
      final projectFuture = _readResult(api.projects());
      final campusFuture = _readResult(api.campus());
      final taskResult = await taskFuture;
      final projectResult = await projectFuture;
      final campusResult = await campusFuture;
      if (!_currentRead(auth, write, request)) return;
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
      _reconcilePending();
      await _persist();
    } catch (e) {
      if (_currentRead(auth, write, request)) {
        if (e is ApiFailure && e.unauthorized) {
          await _expire();
        } else {
          error = _message(e);
          cached = readAt != null;
        }
      }
    } finally {
      if (auth == _generation && request == _readRequest) {
        refreshing = false;
        _inFlight = null;
        _notify();
      }
    }
  }

  Future<void> saveDraft(TaskDraft? value) async {
    if (value != null && value.origin != origin) return;
    draft = value?.hasChanges == true ? value : null;
    _notify();
    await _persist();
  }

  Future<TodoTask?> loadTaskForEdit(int id) async {
    final auth = _generation, write = _writeGeneration;
    try {
      final result = await _api.task(id);
      if (auth != _generation || write != _writeGeneration || _disposed) {
        throw const ApiFailure('会话或任务状态已变化，请重新打开编辑');
      }
      return result;
    } on ApiFailure catch (e) {
      if (auth == _generation && e.unauthorized) await _expire();
      rethrow;
    }
  }

  void _completePending(PendingWrite operation) {
    if (operation.draftKey != null) {
      lastCompletedDraftKey = operation.draftKey;
      if (draft?.key == operation.draftKey) draft = null;
    }
    if (identical(pending, operation)) pending = null;
    writeError = null;
  }

  void _reconcilePending() {
    final operation = pending;
    if (operation == null ||
        operation.origin != origin ||
        readAt == null ||
        readAt!.isBefore(operation.sentAt)) {
      return;
    }
    var resolved =
        operation.kind == WriteKind.delete && task(operation.taskId!) == null;
    if (operation.kind == WriteKind.patch) {
      final current = task(operation.taskId!);
      resolved = current != null && operation.matches(current);
    }
    if (resolved) _completePending(operation);
  }

  Future<bool> confirmCreated(int id) async {
    final operation = pending;
    if (operation == null || !createCandidates.any((t) => t.id == id)) {
      return false;
    }
    _completePending(operation);
    _notify();
    await _persist();
    return true;
  }

  Future<void> abandonPending() async {
    if (writing) return;
    pending = null;
    writeError = null;
    _notify();
    await _persist();
  }

  Future<WriteOutcome> classifyTasks({bool force = false}) =>
      _mutate(WriteKind.classify, null, {'force': force});
  Future<WriteOutcome> syncCampus() =>
      _mutate(WriteKind.campusSync, null, const {});
  Future<Uint8List> image(String source) async {
    final generation = _generation;
    try {
      final bytes = await _api.image(source);
      if (generation != _generation || _disposed) {
        throw const ApiFailure('会话已变化，请重新打开图片');
      }
      return bytes;
    } on ApiFailure catch (e) {
      if (generation == _generation && e.unauthorized) await _expire();
      rethrow;
    }
  }

  Future<WriteOutcome> createTask(
    Map<String, dynamic> input, {
    String? draftKey,
  }) => _mutate(WriteKind.create, null, input, draftKey: draftKey);
  Future<WriteOutcome> patchTask(
    int id,
    Map<String, dynamic> patch, {
    String? draftKey,
  }) => _mutate(WriteKind.patch, id, patch, draftKey: draftKey);
  Future<WriteOutcome> deleteTask(int id) =>
      _mutate(WriteKind.delete, id, const {});
  Future<WriteOutcome> _mutate(
    WriteKind kind,
    int? id,
    Map<String, dynamic> fields, {
    String? draftKey,
  }) async {
    if (!canWrite) {
      final message = !authenticated
          ? '请先登录，草稿已保留'
          : pending != null
          ? '请先核对上一笔待确认提交'
          : writing
          ? '正在提交，请勿重复操作'
          : readAt == null
          ? '尚未取得服务端快照，请联网刷新后提交'
          : '当前为缓存，请联网刷新后再提交';
      writeError = message;
      _notify();
      return WriteOutcome(WriteState.rejected, message);
    }
    final auth = _generation, api = _api;
    writing = true;
    writeError = null;
    serviceMessage = null;
    ++_writeGeneration;
    ++_readRequest;
    _inFlight = null;
    refreshing = false;
    final operation = PendingWrite(
      origin: origin,
      kind: kind,
      taskId: id,
      payload: Map.unmodifiable(fields),
      beforeIds: _tasks.map((t) => t.id).toSet(),
      sentAt: DateTime.now().toUtc(),
      draftKey: draftKey,
    );
    pending = operation;
    _notify();
    if (!await _persist() || auth != _generation || _disposed) {
      if (identical(pending, operation)) pending = null;
      if (auth == _generation) {
        writing = false;
        ++_writeGeneration;
      }
      _notify();
      await _persist();
      return const WriteOutcome(
        WriteState.rejected,
        '提交尚未发出，本机记录或会话状态发生变化，草稿已保留',
      );
    }
    WriteOutcome outcome;
    try {
      TodoTask? saved;
      ClassifyResult? classification;
      CampusSyncResult? campusResult;
      switch (kind) {
        case WriteKind.create:
          saved = await api.createTask(fields);
        case WriteKind.patch:
          saved = fields.isEmpty ? task(id!) : await api.patchTask(id!, fields);
        case WriteKind.delete:
          await api.deleteTask(id!);
        case WriteKind.classify:
          classification = await api.classifyTasks(
            force: fields['force'] == true,
          );
        case WriteKind.campusSync:
          campusResult = await api.syncCampus();
      }
      if (auth != _generation || _disposed) {
        return const WriteOutcome(WriteState.pending, '会话已变化，请重新登录后核对提交结果');
      }
      if (kind == WriteKind.delete) {
        _tasks = _tasks.where((t) => t.id != id).toList();
      } else if (saved != null) {
        _tasks = [saved, ..._tasks.where((t) => t.id != saved!.id)];
      }
      _completePending(operation);
      if (classification != null) {
        lastClassification = classification;
        serviceMessage = classification.message;
      }
      if (campusResult != null) {
        serviceMessage = campusResult.message;
        if (campusResult.error != null) writeError = serviceMessage;
      }
      outcome = WriteOutcome(
        campusResult?.error != null
            ? WriteState.rejected
            : WriteState.confirmed,
        serviceMessage ?? (kind == WriteKind.delete ? '已删除' : '已保存'),
        task: saved,
      );
    } on ApiFailure catch (e) {
      if (auth != _generation || _disposed) {
        return const WriteOutcome(WriteState.pending, '会话已变化，请重新登录后核对提交结果');
      }
      if (e.unauthorized) {
        pending = null;
        writeError = e.message;
        await _expire();
        return WriteOutcome(WriteState.rejected, e.message);
      }
      if (e.statusCode == 404 && kind == WriteKind.delete) {
        _tasks = _tasks.where((t) => t.id != id).toList();
        _completePending(operation);
        outcome = const WriteOutcome(WriteState.confirmed, '服务端任务已不存在');
      } else {
        if (!e.uncertain) pending = null;
        if (e.statusCode == 404) {
          _tasks = _tasks.where((t) => t.id != id).toList();
        }
        writeError = e.statusCode == 404 ? '任务已在其他端删除，草稿已保留，不会自动重建' : e.message;
        outcome = WriteOutcome(
          e.uncertain ? WriteState.pending : WriteState.rejected,
          writeError!,
        );
      }
    } catch (_) {
      writeError = '提交响应无法确认，请重新读取核对，勿重复提交';
      outcome = WriteOutcome(WriteState.pending, writeError!);
    } finally {
      if (auth == _generation) {
        writing = false;
        ++_writeGeneration;
        ++_readRequest;
        _inFlight = null;
        refreshing = false;
        _notify();
        await _persist();
      }
    }
    if (auth == _generation && authenticated) await refresh();
    if (outcome.state == WriteState.pending && pending == null) {
      return WriteOutcome(
        WriteState.confirmed,
        '已核对服务端当前状态',
        task: id == null ? null : task(id),
      );
    }
    return outcome;
  }

  String _message(Object error) =>
      error is ApiFailure ? error.message : '服务返回的数据无法解析，已保留最近的任务快照';
  Future<Map<String, dynamic>> plannerRequest(
    PlannerResource resource, {
    String? date,
    Map<String, dynamic>? body,
  }) async {
    final api = _api, generation = _generation;
    try {
      final data = await api.plannerRequest(resource, date: date, body: body);
      if (_disposed || generation != _generation) {
        throw const ApiFailure('当前登录会话已更换');
      }
      return data;
    } on ApiFailure catch (error) {
      if (!_disposed && generation == _generation && error.unauthorized) {
        await _expire();
      }
      rethrow;
    }
  }

  Future<void> _expire() async {
    ++_generation;
    _inFlight = null;
    refreshing = false;
    authenticated = false;
    writing = false;
    _syncPolling();
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
    writing = false;
    authenticated = false;
    _syncPolling();
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
    _poll?.cancel();
    ++_generation;
    _api.close();
    background?.dispose();
    super.dispose();
  }
}
