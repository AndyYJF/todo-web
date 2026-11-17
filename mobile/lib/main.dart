import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

import 'app/todo_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const TodoApp());
}
