import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:prism_ui/prism_ui.dart' as p;

import '../data/demo_tasks.dart';
import '../features/home_shell.dart';
import '../ui/todo_localizations.dart';

class TodoApp extends StatefulWidget {
  const TodoApp({super.key});
  @override
  State<TodoApp> createState() => _TodoAppState();
}

class _TodoAppState extends State<TodoApp> {
  final _store = DemoTaskStore();
  p.ThemeMode _mode = p.ThemeMode.system;
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
    _store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => p.PrismApp(
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
            statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
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
    home: HomeShell(
      store: _store,
      themeMode: _mode,
      onThemeChanged: (mode) => setState(() => _mode = mode),
    ),
  );
}
