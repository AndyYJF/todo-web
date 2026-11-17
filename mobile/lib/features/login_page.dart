import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:prism_ui/prism_ui.dart' as p;
import 'package:prism_ui/icons/icons.dart';

import '../data/remote_tasks.dart';
import '../ui/task_widgets.dart';
import '../ui/todo_glyphs.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.store});
  final RemoteTaskStore store;
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  late final _server = TextEditingController(text: widget.store.origin);
  final _password = TextEditingController();
  @override
  void dispose() {
    _server.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_password.text.isEmpty || widget.store.signingIn) return;
    final password = _password.text;
    _password.clear();
    FocusManager.instance.primaryFocus?.unfocus();
    await widget.store.login(_server.text, password);
  }

  @override
  Widget build(BuildContext context) => p.PrismScaffold(
    bar: todoBar(context, 'Todo'),
    body: Builder(
      builder: (context) => ListView(
        padding: EdgeInsets.fromLTRB(24, context.appBarInset + 24, 24, 32),
        children: [
          Center(
            child: Container(
              width: 76,
              height: 76,
              decoration: ShapeDecoration(
                color: p.Theme.of(context).colorScheme.primary
                    .withValues(alpha: .12),
                shape: p.AppShape.xxl,
              ),
              child: Center(
                child: GlyphIcon(
                  TodoGlyphs.tasks,
                  size: 36,
                  color: p.Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '连接你的待办',
            style: p.AppTextStyle.title1.of(context, emphasized: true),
          ),
          const SizedBox(height: 10),
          Text(
            '使用网站的登录密码。会话保存在本机，密码不会保存。',
            style: p.AppTextStyle.callout.of(context),
          ),
          const SectionHeading('服务地址'),
          p.TextField(
            controller: _server,
            enabled: !widget.store.signingIn,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const p.InputDecoration(
              hintText: 'https://todo.fei.cx',
            ),
          ),
          const SectionHeading('登录密码'),
          p.TextField(
            controller: _password,
            enabled: !widget.store.signingIn,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _login(),
            decoration: const p.InputDecoration(hintText: '输入网站密码'),
          ),
          if (widget.store.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                widget.store.error!,
                style: TextStyle(color: p.Theme.of(context).colorScheme.error),
              ),
            ),
          if (widget.store.storageError != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(widget.store.storageError!),
            ),
          const SizedBox(height: 24),
          p.FilledButton(
            onPressed: widget.store.signingIn ? null : _login,
            child: widget.store.signingIn
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: p.ActivityIndicator(),
                  )
                : const Text('登录'),
          ),
          const SizedBox(height: 22),
          const StatusPill(label: 'A2 · 真实数据只读预览'),
        ],
      ),
    ),
  );
}
