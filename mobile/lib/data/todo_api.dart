import 'dart:io';

import 'package:dio/dio.dart';

import 'task.dart';

const defaultOrigin = 'https://todo.fei.cx';

Uri normalizeOrigin(String input, {bool allowLocalHttp = false}) {
  final value = input.trim();
  final uri = Uri.tryParse(value.contains('://') ? value : 'https://$value');
  if (uri == null ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.path.isNotEmpty && uri.path != '/')) {
    throw const FormatException('请输入站点地址，例如 https://todo.fei.cx');
  }
  final local = ['localhost', '127.0.0.1', '::1'].contains(uri.host);
  if (uri.scheme != 'https' &&
      !(allowLocalHttp && local && uri.scheme == 'http')) {
    throw const FormatException('服务地址必须使用 HTTPS');
  }
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
  );
}

class ApiFailure implements Exception {
  const ApiFailure(
    this.message, {
    this.unauthorized = false,
    this.uncertain = false,
    this.statusCode,
  });
  final String message;
  final bool unauthorized, uncertain;
  final int? statusCode;
  @override
  String toString() => message;
}

class TodoSession {
  const TodoSession(this.value, this.expiresAt);
  final String value;
  final DateTime expiresAt;
  bool get valid =>
      value.isNotEmpty && expiresAt.isAfter(DateTime.now().toUtc());
  Map<String, dynamic> toJson() => {
    'value': value,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
  };
  factory TodoSession.fromJson(Map<String, dynamic> json) => TodoSession(
    json['value'] as String,
    DateTime.parse(json['expiresAt'] as String).toUtc(),
  );
}

class CampusStatus {
  const CampusStatus({
    required this.at,
    required this.total,
    required this.added,
    required this.updated,
    required this.completed,
    this.error,
  });
  final DateTime at;
  final int total, added, updated, completed;
  final String? error;
  factory CampusStatus.fromJson(Map<String, dynamic> json) => CampusStatus(
    at: parseBusinessDate(json['at'])!,
    total: json['total'] as int,
    added: json['added'] as int,
    updated: json['updated'] as int,
    completed: json['completed'] as int,
    error: json['error'] as String?,
  );
  Map<String, dynamic> toJson() => {
    'at': businessDateString(at),
    'total': total,
    'added': added,
    'updated': updated,
    'completed': completed,
    if (error != null) 'error': error,
  };
}

class TodoApi {
  TodoApi(this.origin)
    : _dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 12),
          receiveTimeout: const Duration(seconds: 20),
          sendTimeout: const Duration(seconds: 12),
          followRedirects: false,
          maxRedirects: 0,
          validateStatus: (status) => status != null,
        ),
      );
  final Uri origin;
  final Dio _dio;
  TodoSession? session;

  Future<Response<dynamic>> _request(
    String path, {
    String method = 'GET',
    Object? data,
    Map<String, dynamic>? query,
    bool authenticated = true,
    bool mutation = false,
  }) async {
    final headers = <String, dynamic>{'Accept': 'application/json'};
    if (authenticated) {
      if (session?.valid != true) {
        throw const ApiFailure('会话已失效，请重新登录', unauthorized: true);
      }
      final cookie = Cookie('todo_session', session!.value);
      headers[HttpHeaders.cookieHeader] = '${cookie.name}=${cookie.value}';
    }
    try {
      final response = await _dio.request<dynamic>(
        origin.resolve(path).toString(),
        data: data,
        queryParameters: query,
        options: Options(method: method, headers: headers),
      );
      final status = response.statusCode!;
      if (status >= 300 && status < 400) {
        throw ApiFailure('服务地址发生跳转，请核对站点地址', uncertain: mutation);
      }
      if (status == 401) {
        throw ApiFailure(
          authenticated ? '会话已失效，请重新登录' : '密码错误',
          unauthorized: authenticated,
          statusCode: status,
        );
      }
      if (status < 200 || status >= 300) {
        throw ApiFailure(
          '服务请求失败（HTTP $status）',
          statusCode: status,
          uncertain: mutation && (status >= 500 || status == 408),
        );
      }
      if (response.data is! Map) {
        throw ApiFailure('服务返回的数据格式不正确', uncertain: mutation);
      }
      return response;
    } on DioException catch (e) {
      final uncertain =
          mutation &&
          ![
            DioExceptionType.connectionTimeout,
            DioExceptionType.badCertificate,
          ].contains(e.type);
      throw ApiFailure(
        uncertain
            ? '提交结果待确认，请先重新读取，避免重复提交'
            : switch (e.type) {
                DioExceptionType.connectionTimeout ||
                DioExceptionType.sendTimeout ||
                DioExceptionType.receiveTimeout => '连接超时，已保留最近的任务快照',
                DioExceptionType.badCertificate => '服务器证书校验失败',
                _ => '无法连接服务，请检查网络或站点地址',
              },
        uncertain: uncertain,
      );
    }
  }

  Future<TodoSession> login(String password) async {
    final response = await _request(
      '/api/login',
      method: 'POST',
      data: {'password': password},
      authenticated: false,
    );
    for (final value
        in response.headers[HttpHeaders.setCookieHeader] ?? <String>[]) {
      final cookie = Cookie.fromSetCookieValue(value);
      if (cookie.name != 'todo_session') continue;
      final domain = cookie.domain
          ?.replaceFirst(RegExp(r'^\.'), '')
          .toLowerCase();
      if (domain != null && domain != origin.host.toLowerCase()) continue;
      if (cookie.path != null && cookie.path != '/') continue;
      final expires = cookie.maxAge != null
          ? DateTime.now().toUtc().add(Duration(seconds: cookie.maxAge!))
          : cookie.expires;
      if (expires == null) throw const ApiFailure('服务未提供会话有效期');
      final result = TodoSession(cookie.value, expires.toUtc());
      if (!result.valid) throw const ApiFailure('服务返回了已过期的会话');
      session = result;
      return result;
    }
    throw const ApiFailure('登录响应缺少会话 Cookie');
  }

  Future<List<TodoTask>> tasks() async {
    final data =
        (await _request('/api/tasks', query: {'view': 'all'})).data as Map;
    final rows = data['tasks'] as List;
    final result = rows
        .map((r) => TodoTask.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
    if (result.map((t) => t.id).toSet().length != result.length) {
      throw const FormatException('任务 ID 重复');
    }
    return result;
  }

  Future<List<String>> projects() async {
    final data =
        (await _request('/api/tasks', query: {'meta': 'projects'})).data as Map;
    return (data['projects'] as List).cast<String>().toList();
  }

  Future<CampusStatus?> campus() async {
    final data = (await _request('/api/sync')).data as Map;
    return data['last'] == null
        ? null
        : CampusStatus.fromJson(Map<String, dynamic>.from(data['last'] as Map));
  }

  TodoTask _taskResponse(Response<dynamic> response, {bool mutation = false}) {
    try {
      return TodoTask.fromJson(
        Map<String, dynamic>.from((response.data as Map)['task'] as Map),
      );
    } catch (_) {
      throw ApiFailure('服务返回的任务无法解析', uncertain: mutation);
    }
  }

  Future<TodoTask?> task(int id) async {
    try {
      return _taskResponse(await _request('/api/tasks/$id'));
    } on ApiFailure catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<TodoTask> createTask(Map<String, dynamic> input) async {
    final response = await _request(
      '/api/tasks',
      method: 'POST',
      data: input,
      mutation: true,
    );
    if (response.statusCode != 201) {
      throw const ApiFailure('新建响应异常，请先核对结果', uncertain: true);
    }
    return _taskResponse(response, mutation: true);
  }

  Future<TodoTask> patchTask(int id, Map<String, dynamic> patch) async =>
      _taskResponse(
        await _request(
          '/api/tasks/$id',
          method: 'PATCH',
          data: patch,
          mutation: true,
        ),
        mutation: true,
      );
  Future<void> deleteTask(int id) async {
    final response = await _request(
      '/api/tasks/$id',
      method: 'DELETE',
      mutation: true,
    );
    if ((response.data as Map)['ok'] != true) {
      throw const ApiFailure('删除响应异常，请先核对结果', uncertain: true);
    }
  }

  Future<void> logout() async {
    await _request('/api/logout', method: 'POST');
  }

  void close() => _dio.close(force: true);
}
