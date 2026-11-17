import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

import 'app/todo_app.dart';

import 'package:path_provider/path_provider.dart';

import 'data/local_state.dart';
import 'data/remote_tasks.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  final directory = await getApplicationSupportDirectory();
  runApp(TodoApp(store: RemoteTaskStore(LocalStateFile(directory))));
}
