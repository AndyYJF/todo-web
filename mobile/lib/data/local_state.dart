import 'dart:convert';
import 'dart:io';

class LocalStateFile {
  LocalStateFile(this.directory);
  final Directory directory;
  Future<void> _writes = Future.value();
  File get _file => File('${directory.path}/todo-state.json');

  Future<Map<String, dynamic>?> read() async {
    if (!await _file.exists()) return null;
    return Map<String, dynamic>.from(
      jsonDecode(await _file.readAsString()) as Map,
    );
  }

  Future<void> save(Map<String, dynamic> state) {
    final content = jsonEncode(state);
    final write = _writes.catchError((Object _) {}).then((_) async {
      await directory.create(recursive: true);
      final temporary = File('${_file.path}.tmp');
      await temporary.writeAsString(content, flush: true);
      await temporary.rename(_file.path);
    });
    _writes = write;
    return write;
  }
}
