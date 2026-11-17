import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:prism_ui/prism_ui.dart' as p;

import '../data/remote_tasks.dart';
import '../features/login_page.dart';
import '../ui/task_widgets.dart';
import '../features/home_shell.dart';
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
    unawaited(_store.initialize());
  }

  void _authChanged() {
    if (_wasAuthenticated && !_store.authenticated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _navigator.currentState?.popUntil((route) => route.isFirst);
        }
      });
    }
    _wasAuthenticated = _store.authenticated;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _store.setForeground(state == AppLifecycleState.resumed);
    if (state == AppLifecycleState.resumed && _store.authenticated) {
      unawaited(_store.refresh());
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
              themeMode: _mode,
              onThemeChanged: (mode) => _store.setTheme(mode.name),
            ),
    ),
  );
}
