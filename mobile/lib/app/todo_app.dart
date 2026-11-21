import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:prism_ui/prism_ui.dart' as p;

import '../data/remote_tasks.dart';
import '../data/planner_client.dart';
import '../features/planner/planner_page.dart';
import '../features/login_page.dart';
import '../ui/task_widgets.dart';
import '../features/home_shell.dart';
import '../features/task_detail.dart';
import '../ui/todo_motion.dart';
import '../ui/todo_localizations.dart';

class TodoApp extends StatefulWidget {
  const TodoApp({super.key, required this.store});
  final RemoteTaskStore store;
  @override
  State<TodoApp> createState() => _TodoAppState();
}

class _TodoAppState extends State<TodoApp> with WidgetsBindingObserver {
  late final _store = widget.store;
  final _navigator = GlobalKey<NavigatorState>();
  bool _wasAuthenticated = false;
  PlannerClient? _planner;
  PlannerClient get _activePlanner {
    if (_planner?.origin != _store.origin) _planner = PlannerClient(_store);
    return _planner!;
  }

  p.ThemeMode get _mode => switch (_store.theme) {
    'light' => p.ThemeMode.light,
    'dark' => p.ThemeMode.dark,
    _ => p.ThemeMode.system,
  };
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _store.setForeground(
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
    );
    _store.addListener(_authChanged);
    _store.background?.addListener(_openNotification);
    unawaited(_store.initialize());
  }

  void _authChanged() {
    if (_wasAuthenticated && !_store.authenticated) {
      _planner = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _navigator.currentState?.popUntil((route) => route.isFirst);
        }
      });
    }
    _wasAuthenticated = _store.authenticated;
    _openNotification();
  }

  bool _openingNotification = false;
  void _openNotification() {
    if (_openingNotification || !_store.ready || !_store.authenticated) return;
    final background = _store.background;
    if (background?.pendingTap == null) return;
    final tap = background!.takeTap()!;
    final date = tap['date'] as String?;
    final id = tap['id'] as int?;
    if (tap['origin'] != _store.origin || (date == null && id == null)) return;
    _openingNotification = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        if (id != null) await _store.resume();
        if (mounted && _store.authenticated && tap['origin'] == _store.origin) {
          final context = _navigator.currentContext;
          if (context != null && context.mounted) {
            _navigator.currentState?.push(
              todoPageRoute<void>(
                context,
                (_) => date != null
                    ? PlannerPage(client: _activePlanner, initialDate: date)
                    : TaskDetail(store: _store, id: id!),
              ),
            );
          }
        }
      } finally {
        _openingNotification = false;
        if (mounted) _openNotification();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _store.setForeground(state == AppLifecycleState.resumed);
    if (state == AppLifecycleState.resumed && _store.authenticated) {
      unawaited(_store.resume());
    }
  }

  late final _light = p.ThemeData(
    colorScheme: p.ColorScheme.fromSeed(
      seedColor: const Color(0xFF007AFF),
      style: p.ColorStyle.vivid,
    ),
  );
  late final _darkScheme = p.ColorScheme.fromSeed(
    seedColor: const Color(0xFF007AFF),
    brightness: Brightness.dark,
    style: p.ColorStyle.vivid,
  );
  late final _dark = p.ThemeData(
    colorScheme: _darkScheme,
    elevatedColorScheme: _darkScheme.elevated,
  );
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _store.removeListener(_authChanged);
    _store.background?.removeListener(_openNotification);
    _store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _store,
    builder: (context, _) => p.PrismApp(
      navigatorKey: _navigator,
      title: 'Todo',
      theme: _light,
      darkTheme: _dark,
      themeMode: _mode,
      debugShowCheckedModeBanner: false,
      liquidGlass: p.LiquidGlassQuality.standard,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: const [
        TodoUiLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      builder: (context, child) => LayoutBuilder(
        builder: (context, constraints) {
          final dark = p.Theme.of(context).brightness == Brightness.dark;
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle(
              statusBarColor: const Color(0x00000000),
              statusBarIconBrightness: dark
                  ? Brightness.light
                  : Brightness.dark,
              systemNavigationBarColor: const Color(0x00000000),
              systemNavigationBarIconBrightness: dark
                  ? Brightness.light
                  : Brightness.dark,
            ),
            child: p.ViewScope(
              size: constraints.biggest,
              isMobile: constraints.maxWidth < 600,
              child: child!,
            ),
          );
        },
      ),
      home: !_store.ready
          ? Builder(
              builder: (context) => p.PrismScaffold(
                bar: todoBar(context, 'Todo'),
                body: const Center(child: p.ActivityIndicator()),
              ),
            )
          : !_store.authenticated
          ? LoginPage(store: _store)
          : HomeShell(
              store: _store,
              planner: _activePlanner,
              themeMode: _mode,
              onThemeChanged: (mode) => _store.setTheme(mode.name),
            ),
    ),
  );
}
