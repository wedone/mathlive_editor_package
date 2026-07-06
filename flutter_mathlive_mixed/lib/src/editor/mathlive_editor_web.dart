// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../config/mathlive_channels.dart';
import 'mathlive_editor_html_patch.dart';

Widget mathLiveMixedWebEditorBody({
  required bool isDark,
  required void Function(String latex) onLatex,
  required void Function(void Function() triggerExportFromHost) onExporterReady,
  required void Function(bool success) onWebEditorReady,
  required Color backgroundColor,
  String? initialLatex,
  void Function(double chromeHeight)? onEditorChromeHeight,
  TextStyle? loadingTextStyle,
  Color? accentColor,
}) {
  return _MathLiveMixedWebHost(
    isDark: isDark,
    onLatex: onLatex,
    onExporterReady: onExporterReady,
    onWebEditorReady: onWebEditorReady,
    backgroundColor: backgroundColor,
    initialLatex: initialLatex,
    onEditorChromeHeight: onEditorChromeHeight,
  );
}

class _MathLiveMixedWebHost extends StatefulWidget {
  const _MathLiveMixedWebHost({
    required this.isDark,
    required this.onLatex,
    required this.onExporterReady,
    required this.onWebEditorReady,
    required this.backgroundColor,
    this.initialLatex,
    this.onEditorChromeHeight,
  });

  final bool isDark;
  final void Function(String latex) onLatex;
  final void Function(void Function() triggerExportFromHost) onExporterReady;
  final void Function(bool success) onWebEditorReady;
  final Color backgroundColor;
  final String? initialLatex;
  final void Function(double chromeHeight)? onEditorChromeHeight;

  @override
  State<_MathLiveMixedWebHost> createState() => _MathLiveMixedWebHostState();
}

class _MathLiveMixedWebHostState extends State<_MathLiveMixedWebHost> {
  static int _nextId = 0;
  late final String _viewType = 'mathlive-mixed-editor-${_nextId++}';
  late final String _rootId = '$_viewType-root';

  StreamSubscription<html.MessageEvent>? _sub;
  bool _readyNotified = false;
  bool _loadFailed = false;

  static Completer<void>? _mathLiveCdnCompleter;
  static bool _editorStylesInjected = false;

  @override
  void initState() {
    super.initState();
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) {
      final html.DivElement host = html.DivElement()
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.overflow = 'hidden';
      unawaited(_bootstrapHost(host));
      return host;
    });
    _sub = html.window.onMessage.listen(_onWindowMessage);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onExporterReady(triggerExport);
    });
  }

  Future<void> _ensureMathLiveCdnLoaded() async {
    if (_mathLiveCdnCompleter != null) {
      return _mathLiveCdnCompleter!.future;
    }
    _mathLiveCdnCompleter = Completer<void>();
    try {
      // CSS 仍从 CDN 加载（字体路径正常）
      if (html.document.querySelector('link[data-mathlive-mixed-cdn-css]') ==
          null) {
        final html.LinkElement link = html.LinkElement()
          ..rel = 'stylesheet'
          ..href =
              'https://cdn.jsdelivr.net/npm/mathlive@0.101.2/dist/mathlive-static.css'
          ..setAttribute('data-mathlive-mixed-cdn-css', '1');
        html.document.head!.append(link);
      }
      if (html.document.querySelector('script[data-mathlive-mixed-local-js]') !=
          null) {
        if (!_mathLiveCdnCompleter!.isCompleted) {
          _mathLiveCdnCompleter!.complete();
        }
        return _mathLiveCdnCompleter!.future;
      }
      // JS 从本地 assets 加载（含 fixedRows 等源码级改动，内联执行）
      final String jsCode = await rootBundle.loadString(kMathLiveJsAsset);
      final html.ScriptElement script = html.ScriptElement()
        ..text = jsCode
        ..setAttribute('data-mathlive-mixed-local-js', '1');
      html.document.head!.append(script);
      // 内联脚本同步执行，添加到 DOM 后即可用
      if (!_mathLiveCdnCompleter!.isCompleted) {
        _mathLiveCdnCompleter!.complete();
      }
    } catch (e, st) {
      if (_mathLiveCdnCompleter != null &&
          !_mathLiveCdnCompleter!.isCompleted) {
        _mathLiveCdnCompleter!.completeError(e, st);
      }
    }
    return _mathLiveCdnCompleter!.future;
  }

  void _ensureEditorStylesInjected(String fullDoc) {
    if (_editorStylesInjected) {
      return;
    }
    final RegExpMatch? m =
        RegExp(r'<style>([\s\S]*?)</style>', multiLine: true).firstMatch(fullDoc);
    if (m == null) {
      return;
    }
    final html.StyleElement style = html.StyleElement()
      ..text = m.group(1)!
      ..setAttribute('data-mathlive-mixed-editor-inline', '1');
    html.document.head!.append(style);
    _editorStylesInjected = true;
  }

  Future<void> _bootstrapHost(html.DivElement host) async {
    try {
      await _ensureMathLiveCdnLoaded();
      String doc = patchMathLiveEditorHtml(
        await rootBundle.loadString(kMathLiveEditorHtmlAsset),
        rootAndClientId: _rootId,
      );
      _ensureEditorStylesInjected(doc);

      final RegExpMatch? bodyMatch = RegExp(
        r'<body[^>]*>([\s\S]*)</body>',
        multiLine: true,
        caseSensitive: false,
      ).firstMatch(doc);
      final String bodyChunk = bodyMatch?.group(1) ?? '';
      final int scriptOpen = bodyChunk.indexOf('<script>');
      final String bodyHtml =
          scriptOpen >= 0 ? bodyChunk.substring(0, scriptOpen) : bodyChunk;
      final RegExpMatch? scriptMatch =
          RegExp(r'<script>([\s\S]*)</script>').firstMatch(bodyChunk);
      final String scriptText = scriptMatch?.group(1) ?? '';

      host.setInnerHtml(
        bodyHtml,
        treeSanitizer: html.NodeTreeSanitizer.trusted,
      );
      host.append(html.ScriptElement()..text = scriptText);

      if (_loadFailed || _readyNotified) {
        return;
      }
      _readyNotified = true;
      Future<void>.delayed(const Duration(milliseconds: 150), () {
        if (!mounted || _loadFailed) {
          return;
        }
        _postTheme();
        _postSetLatexIfAny();
        widget.onWebEditorReady(true);
        Future<void>.delayed(const Duration(milliseconds: 400), () {
          if (!mounted || _loadFailed) {
            return;
          }
          _postSetLatexIfAny();
        });
        Future<void>.delayed(const Duration(milliseconds: 900), () {
          if (!mounted || _loadFailed) {
            return;
          }
          _postSetLatexIfAny();
        });
      });
    } catch (_) {
      _loadFailed = true;
      if (mounted) {
        widget.onWebEditorReady(false);
      }
    }
  }

  void _onWindowMessage(html.MessageEvent event) {
    final Object? data = event.data;
    if (data is! Map) {
      return;
    }
    final Map<dynamic, dynamic> map = data;
    if (map['channel'] != MathLiveMixedChannels.fromEditor) {
      return;
    }
    if (map['clientId'] != _rootId) {
      return;
    }
    final Object? latex = map['latex'];
    if (latex != null) {
      widget.onLatex('$latex');
    }
    final Object? editorHeight = map['editorHeight'];
    if (editorHeight != null && widget.onEditorChromeHeight != null) {
      final double? h = editorHeight is num
          ? editorHeight.toDouble()
          : double.tryParse('$editorHeight');
      if (h != null && h.isFinite && h > 0) {
        widget.onEditorChromeHeight!(h);
      }
    }
  }

  void _postTheme() {
    html.window.postMessage(
      <String, Object?>{
        'channel': MathLiveMixedChannels.toEditor,
        'clientId': _rootId,
        'cmd': 'theme',
        'dark': widget.isDark,
      },
      '*',
    );
  }

  void _postSetLatexIfAny() {
    final String t = widget.initialLatex?.trim() ?? '';
    if (t.isEmpty) {
      return;
    }
    html.window.postMessage(
      <String, Object?>{
        'channel': MathLiveMixedChannels.toEditor,
        'clientId': _rootId,
        'cmd': 'setLatex',
        'latex': t,
      },
      '*',
    );
  }

  void triggerExport() {
    html.window.postMessage(
      <String, Object?>{
        'channel': MathLiveMixedChannels.toEditor,
        'clientId': _rootId,
        'cmd': 'export',
      },
      '*',
    );
  }

  @override
  void didUpdateWidget(covariant _MathLiveMixedWebHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isDark != widget.isDark && _readyNotified && !_loadFailed) {
      _postTheme();
    }
    if (oldWidget.initialLatex != widget.initialLatex &&
        _readyNotified &&
        !_loadFailed) {
      Future<void>.delayed(const Duration(milliseconds: 80), _postSetLatexIfAny);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: widget.backgroundColor,
      child: HtmlElementView(viewType: _viewType),
    );
  }
}
