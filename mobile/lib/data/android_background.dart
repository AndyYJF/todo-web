import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AndroidBackground extends ChangeNotifier {
  static const _channel = MethodChannel('todo/background');
  Map<String, dynamic> status = {};
  Map<String, dynamic>? pendingTap;
  String? error;
  bool _disposed = false, _attached = false;
  bool get enabled => status['enabled'] == true;
  bool get campus => status['campus'] == true;
  bool get deadline => status['deadline'] == true;
  bool get sessionInvalid => status['sessionInvalid'] == true;
  Future<T?> _call<T>(String method, [Object? arguments]) async {
    try {
      final result = await _channel.invokeMethod<T>(method, arguments);
      error = null;
      return result;
    } on PlatformException {
      error = '后台任务暂时不可用，请稍后重试';
      return null;
    } on MissingPluginException {
      error = '此构建不支持 Android 后台任务';
      return null;
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> attach(String path, {bool local = false}) async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'notificationTap') await _tap();
      if (call.method == 'backgroundChanged') await refreshStatus();
    });
    final value = await _call<Map>('attach', {'path': path, 'local': local});
    if (value != null) {
      status = Map<String, dynamic>.from(value);
      _attached = true;
    }
    await _tap();
    _notify();
  }

  Future<void> _tap() async {
    final tap = await _call<Map>('consumeTap');
    if (tap != null) {
      pendingTap = Map<String, dynamic>.from(tap);
      _notify();
    }
  }

  Map<String, dynamic>? takeTap() {
    final value = pendingTap;
    pendingTap = null;
    return value;
  }

  Future<void> stateChanged() async {
    if (!_attached) return;
    final value = await _call<Map>('stateChanged');
    if (value != null) {
      final next = Map<String, dynamic>.from(value);
      if (!mapEquals(next, status)) {
        status = next;
        _notify();
      }
    }
  }

  Future<void> refreshStatus() async {
    if (!_attached) return;
    final value = await _call<Map>('status');
    if (value != null) status = Map<String, dynamic>.from(value);
    _notify();
  }

  Future<void> setOptions({bool? enabled, bool? campus, bool? deadline}) async {
    final value = await _call<Map>('options', {
      'enabled': ?enabled,
      'campus': ?campus,
      'deadline': ?deadline,
    });
    if (value != null) status = Map<String, dynamic>.from(value);
    _notify();
  }

  Future<void> requestNotifications() async {
    await _call<bool>('requestNotifications');
    await refreshStatus();
  }

  Future<void> openNotificationSettings() async {
    await _call<void>('openNotificationSettings');
  }

  Future<void> openExactSettings() async {
    await _call<void>('openExactSettings');
  }

  Future<void> openBatterySettings() async {
    await _call<void>('openBatterySettings');
  }

  Future<void> runNow() async {
    await _call<void>('runNow');
    await refreshStatus();
  }

  Future<Map<String, dynamic>?> snapshot() async {
    final value = await _call<Map>('snapshot');
    return value == null ? null : Map<String, dynamic>.from(value);
  }

  @override
  void dispose() {
    _disposed = true;
    _channel.setMethodCallHandler(null);
    super.dispose();
  }
}
