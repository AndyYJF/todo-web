import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:prism_ui/prism_ui.dart' as p;
import 'package:prism_ui/icons/icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/remote_tasks.dart';
import '../data/todo_api.dart';
import 'task_widgets.dart';
import 'todo_motion.dart';

String nativeNoteMarkdown(String source) => source
    .split('\n')
    .map((line) {
      final match = RegExp(r'^\s*图片[：:]\s*(https?://\S+)\s*$').firstMatch(line);
      return match == null ? line : '![校园图片](<${match[1]}>)';
    })
    .join('\n');

class RichNote extends StatefulWidget {
  const RichNote({super.key, required this.store, required this.text});
  final RemoteTaskStore store;
  final String text;
  @override
  State<RichNote> createState() => _RichNoteState();
}

class _RichNoteState extends State<RichNote> {
  final _links = <TapGestureRecognizer>[];
  String? _error;
  @override
  void dispose() {
    for (final link in _links) {
      link.dispose();
    }
    super.dispose();
  }

  Future<void> _open(String value) async {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      setState(() => _error = '只支持打开 HTTP/HTTPS 链接');
      return;
    }
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
          mounted) {
        setState(() => _error = '无法打开此链接');
      }
    } catch (_) {
      if (mounted) setState(() => _error = '无法打开此链接');
    }
  }

  @override
  Widget build(BuildContext context) {
    for (final link in _links) {
      link.dispose();
    }
    _links.clear();
    final nodes = md.Document(
      extensionSet: md.ExtensionSet.gitHubFlavored,
      encodeHtml: false,
    ).parseLines(nativeNoteMarkdown(widget.text).split('\n'));
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.text.isEmpty) const Text('暂无备注'),
          for (final node in nodes) _block(context, node, constraints.maxWidth),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: p.Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    );
  }

  Widget _block(BuildContext context, md.Node node, double width) {
    if (node is md.Element && (node.tag == 'ul' || node.tag == 'ol')) {
      var number = int.tryParse(node.attributes['start'] ?? '') ?? 1;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final child in node.children ?? <md.Node>[])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 28,
                    child: Text(node.tag == 'ol' ? '${number++}.' : '•'),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final part
                            in (child is md.Element
                                ? ((child.children ?? <md.Node>[]).any(
                                        (n) =>
                                            n is md.Element &&
                                            [
                                              'p',
                                              'ul',
                                              'ol',
                                              'blockquote',
                                              'pre',
                                            ].contains(n.tag),
                                      )
                                      ? child.children!
                                      : [child])
                                : [child]))
                          _block(context, part, width - 28),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    }
    if (node is md.Element && node.tag == 'blockquote') {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              width: 3,
              color: p.Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final child in node.children ?? <md.Node>[])
              _block(context, child, width - 24),
          ],
        ),
      );
    }
    if (node is md.Element && node.tag == 'hr') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Container(
          height: 1,
          color: p.Theme.of(context).colorScheme.onSurfaceVariant
              .withValues(alpha: .2),
        ),
      );
    }
    if (node is md.Element && node.tag == 'pre') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Text(
            node.textContent,
            style: p.AppTextStyle.footnote
                .of(context)
                .copyWith(fontFamily: 'monospace'),
          ),
        ),
      );
    }
    final heading =
        node is md.Element && RegExp(r'^h[1-6]$').hasMatch(node.tag);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text.rich(
        _inline(context, node, width),
        style: heading
            ? p.AppTextStyle.title3.of(context, emphasized: true)
            : p.AppTextStyle.body.of(context),
      ),
    );
  }

  InlineSpan _inline(
    BuildContext context,
    md.Node node,
    double width, {
    TapGestureRecognizer? link,
  }) {
    if (node is md.Text) return TextSpan(text: node.text, recognizer: link);
    final element = node as md.Element;
    if (element.tag == 'br') return const TextSpan(text: '\n');
    if (element.tag == 'img') {
      return WidgetSpan(
        child: NoteImage(
          key: ValueKey(element.attributes['src']),
          store: widget.store,
          source: element.attributes['src'] ?? '',
          width: width,
        ),
      );
    }
    if (element.tag == 'input') {
      return TextSpan(
        text: element.attributes.containsKey('checked') ? '☑ ' : '☐ ',
      );
    }
    final recognizer = element.tag == 'a'
        ? (TapGestureRecognizer()
            ..onTap = () => _open(element.attributes['href'] ?? ''))
        : link;
    if (element.tag == 'a' && recognizer != null) _links.add(recognizer);
    return TextSpan(
      recognizer: recognizer,
      style: TextStyle(
        fontWeight: ['strong', 'b'].contains(element.tag)
            ? FontWeight.bold
            : null,
        fontStyle: ['em', 'i'].contains(element.tag) ? FontStyle.italic : null,
        fontFamily: element.tag == 'code' ? 'monospace' : null,
        decoration: element.tag == 'a'
            ? TextDecoration.underline
            : element.tag == 'del'
            ? TextDecoration.lineThrough
            : null,
        color: element.tag == 'a'
            ? p.Theme.of(context).colorScheme.primary
            : null,
      ),
      children: [
        for (final child in element.children ?? <md.Node>[])
          _inline(context, child, width, link: recognizer),
      ],
    );
  }
}

class NoteImage extends StatefulWidget {
  const NoteImage({
    super.key,
    required this.store,
    required this.source,
    required this.width,
  });
  final RemoteTaskStore store;
  final String source;
  final double width;
  @override
  State<NoteImage> createState() => _NoteImageState();
}

class _NoteImageState extends State<NoteImage> {
  late Future<Uint8List> _image = widget.store.image(widget.source);
  @override
  void didUpdateWidget(NoteImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source || oldWidget.store != widget.store) {
      _image = widget.store.image(widget.source);
    }
  }

  Widget _failed(String message) => SizedBox(
    width: widget.width,
    child: p.Card(
      inert: true,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text(message),
          p.TextButton(
            onPressed: () =>
                setState(() => _image = widget.store.image(widget.source)),
            child: const Text('重试图片'),
          ),
        ],
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: _image,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return _failed(
          snapshot.error is ApiFailure
              ? (snapshot.error as ApiFailure).message
              : '图片暂时无法加载',
        );
      }
      if (!snapshot.hasData) {
        return SizedBox(
          width: widget.width,
          height: 120,
          child: const Center(child: p.ActivityIndicator()),
        );
      }
      final bytes = snapshot.data!;
      return SizedBox(
        width: widget.width,
        child: p.Card(
          onPressed: () => Navigator.of(context).push(
            todoPageRoute<void>(
              context,
              (_) => p.PrismScaffold(
                bar: todoBar(context, '查看图片', back: true),
                body: InteractiveViewer(
                  minScale: 1,
                  maxScale: 5,
                  child: Center(
                    child: Image.memory(
                      bytes,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const Text('图片格式无法显示'),
                    ),
                  ),
                ),
              ),
            ),
          ),
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: Image.memory(
                  bytes,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => _failed('图片格式无法显示'),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const GlyphIcon(Glyphs.search, size: 14),
                  const SizedBox(width: 6),
                  Text('查看图片', style: p.AppTextStyle.caption1.of(context)),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}
