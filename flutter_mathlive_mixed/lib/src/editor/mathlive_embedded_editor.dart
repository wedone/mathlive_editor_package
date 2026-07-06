import 'dart:async';
import 'dart:convert';
import 'dart:math' show max;

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData, rootBundle;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../config/mathlive_channels.dart';
import '../config/mathlive_mixed_theme.dart';
import 'mathlive_editor_html_patch.dart';
import 'mathlive_editor_stub.dart'
    if (dart.library.html) 'mathlive_editor_web.dart'
    as mathlive_platform;

/// MathLive editor in a fixed-height box; debounced [onLatexChanged].
class MathLiveEmbeddedEditor extends StatefulWidget {
  const MathLiveEmbeddedEditor({
    super.key,
    required this.isDark,
    this.initialLatex,
    required this.onLatexChanged,
    this.onInsertFormula,
    this.height = 320,
    this.latexSnapshot,
    this.theme = MathLiveMixedTheme.defaults,
    this.loadingTextStyle,
  });

  final bool isDark;
  final String? initialLatex;
  final ValueChanged<String> onLatexChanged;

  /// 当用户通过自定义 command（insertInline/insertBlock）请求插入公式时回调。
  ///
  /// [latex] 为 MathLive 编辑器中的 LaTeX 内容，
  /// [mode] 为 'inline'（行内，$...$）或 'block'（行间，$$...$$）。
  final void Function(String latex, String mode)? onInsertFormula;
  final double height;
  final ValueNotifier<String>? latexSnapshot;
  final MathLiveMixedTheme theme;
  final TextStyle? loadingTextStyle;

  @override
  State<MathLiveEmbeddedEditor> createState() => _MathLiveEmbeddedEditorState();
}

class _MathLiveEmbeddedEditorState extends State<MathLiveEmbeddedEditor> {
  WebViewController? _controller;
  Timer? _debounce;
  Timer? _webPoll;
  void Function()? _webTriggerExport;
  double _webChromeHeight = 0;
  double _reportedHeight = 0;
  bool _loading = true;
  String? _error;
  bool _ready = false;

  Color get _bg => widget.theme.editorBackground(widget.isDark);
  Color get _fg => widget.theme.editorForeground(widget.isDark);

  TextStyle get _loadingStyle =>
      widget.loadingTextStyle ??
      TextStyle(fontSize: 13, color: _fg.withOpacity( 0.85));

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _loading = true;
      return;
    }
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(_bg)
      ..addJavaScriptChannel(
        MathLiveMixedChannels.latexSyncJsChannel,
        onMessageReceived: (JavaScriptMessage message) {
          if (!mounted) return;
          final String latex = message.message;
          widget.latexSnapshot?.value = latex;
          _debounce?.cancel();
          _debounce = Timer(const Duration(milliseconds: 280), () {
            if (!mounted) return;
            widget.onLatexChanged(latex);
          });
        },
      )
      ..addJavaScriptChannel(
        MathLiveMixedChannels.paste,
        onMessageReceived: (JavaScriptMessage message) async {
          final ClipboardData? data = await Clipboard.getData('text/plain');
          if (data?.text != null) {
            await _controller?.runJavaScript(
              'mlMixedPasteText(${jsonEncode(data!.text)})',
            );
          }
        },
      )
      ..addJavaScriptChannel(
        MathLiveMixedChannels.heightSync,
        onMessageReceived: (JavaScriptMessage message) {
          if (!mounted) return;
          final double? h = double.tryParse(message.message);
          if (h != null && h.isFinite && h > 0 && h != _reportedHeight) {
            setState(() => _reportedHeight = h);
          }
        },
      )
      ..addJavaScriptChannel(
        MathLiveMixedChannels.latexInsertJsChannel,
        onMessageReceived: (JavaScriptMessage message) {
          if (!mounted) return;
          try {
            final data = jsonDecode(message.message) as Map<String, dynamic>;
            final mode = data['mode'] as String? ?? 'inline';
            final latex = data['latex'] as String? ?? '';
            if (latex.trim().isNotEmpty) {
              widget.onInsertFormula?.call(latex, mode);
            }
          } catch (_) {}
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) {
              setState(() {
                _loading = true;
                _error = null;
              });
            }
          },
          onPageFinished: (_) async {
            if (!mounted) return;
            setState(() {
              _loading = false;
              _ready = true;
            });
            await _applyTheme();
            await _injectInitialLatex();
            await _attachLiveSync();
          },
          onWebResourceError: (WebResourceError error) {
            if (error.isForMainFrame == false) return;
            if (mounted) {
              setState(() {
                _loading = false;
                _error = error.description;
              });
            }
          },
        ),
      );
    unawaited(_bootstrap());
  }

  Future<void> _tunePlatform() async {
    final WebViewController? c = _controller;
    if (c == null) return;
    try {
      await c.enableZoom(false);
    } catch (_) {}
    if (defaultTargetPlatform != TargetPlatform.android) return;
    if (c.platform is! AndroidWebViewController) return;
    final AndroidWebViewController android =
        c.platform as AndroidWebViewController;
    try {
      await android.setMediaPlaybackRequiresUserGesture(false);
    } catch (_) {}
  }

  Future<void> _bootstrap() async {
    await _tunePlatform();
    final WebViewController? c = _controller;
    if (!mounted || c == null) return;
    try {
      final String html = patchMathLiveEditorHtml(
        await rootBundle.loadString(kMathLiveEditorHtmlAsset),
      );
      // 内联本地构建的 JS（含 fixedRows），CSS 仍从 CDN 加载（字体路径正常）
      final String js = await rootBundle.loadString(kMathLiveJsAsset);
      final String htmlWithLocalJs = inlineLocalMathLiveJs(html, js);
      await c.loadHtmlString(
        htmlWithLocalJs,
        baseUrl: 'https://cdn.jsdelivr.net/npm/mathlive@0.101.2/dist/',
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load math editor';
        });
      }
    }
  }

  Future<void> _applyTheme() async {
    final WebViewController? c = _controller;
    if (c == null) return;
    try {
      await c.runJavaScript(
        'try{mlMixedSetTheme(${widget.isDark ? 'true' : 'false'});}catch(e){}',
      );
    } catch (_) {}
  }

  Future<void> _injectInitialLatex() async {
    final String t = widget.initialLatex?.trim() ?? '';
    if (t.isEmpty) return;
    final WebViewController? c = _controller;
    if (c == null) return;
    for (final Duration d in <Duration>[
      const Duration(milliseconds: 50),
      const Duration(milliseconds: 200),
      const Duration(milliseconds: 500),
      const Duration(milliseconds: 900),
    ]) {
      await Future<void>.delayed(d);
      if (!mounted) return;
      try {
        await c.runJavaScript(
          'try{mlMixedSetLatex(${jsonEncode(t)});}catch(e){}',
        );
      } catch (_) {}
    }
  }

  Future<void> _attachLiveSync() async {
    final WebViewController? c = _controller;
    if (c == null) return;
    try {
      await c.runJavaScript(r'''
(function(){
  var mf = document.getElementById('mf');
  if (!mf || mf.dataset.mlMixedLiveSync === '1') return;
  mf.dataset.mlMixedLiveSync = '1';
  function push() {
    try {
      if (typeof mlMixedExportLatex === 'function') mlMixedExportLatex();
    } catch(e) {}
  }
  mf.addEventListener('input', function() {
    clearTimeout(mf._mlMixedLiveT);
    mf._mlMixedLiveT = setTimeout(push, 300);
  });
  push();
})();
''');
    } catch (_) {}
  }

  void _onLatexFromWebDebounced(String latex) {
    widget.latexSnapshot?.value = latex;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), () {
      if (!mounted) return;
      widget.onLatexChanged(latex);
    });
  }

  @override
  void didUpdateWidget(covariant MathLiveEmbeddedEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isDark != widget.isDark && _ready && !kIsWeb) {
      unawaited(_applyTheme());
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _webPoll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      final double screenCap = MediaQuery.sizeOf(context).height * 0.92;
      final double webH =
          max(widget.height, _webChromeHeight).clamp(widget.height, screenCap);
      return SizedBox(
        height: webH,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              mathlive_platform.mathLiveMixedWebEditorBody(
                isDark: widget.isDark,
                backgroundColor: _bg,
                initialLatex: widget.initialLatex,
                onLatex: _onLatexFromWebDebounced,
                onEditorChromeHeight: (double h) {
                  if (!mounted) return;
                  setState(() => _webChromeHeight = h);
                },
                onExporterReady: (void Function() fn) {
                  _webTriggerExport = fn;
                  _webPoll?.cancel();
                  _webPoll = Timer.periodic(
                    const Duration(milliseconds: 500),
                    (_) => _webTriggerExport?.call(),
                  );
                },
                onWebEditorReady: (bool success) {
                  if (!mounted) return;
                  setState(() {
                    _loading = false;
                    _ready = success;
                    _error = success ? null : 'Could not load math editor';
                  });
                },
              ),
              if (_loading) _loadingOverlay(),
            ],
          ),
        ),
      );
    }

    // Dynamic height: use HTML-reported height when available, fallback to widget.height
    final double effectiveHeight =
        _reportedHeight > 0 ? _reportedHeight : widget.height;

    return SizedBox(
      height: effectiveHeight,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          ColoredBox(
            color: _bg,
            child: WebViewWidget(controller: _controller!),
          ),
          if (_loading) _loadingOverlay(),
          if (_error != null && !_loading) _errorOverlay(),
        ],
      ),
    );
  }

  Widget _loadingOverlay() {
    return ColoredBox(
      color: _bg.withOpacity( 0.88),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            CircularProgressIndicator(color: widget.theme.accent),
            const SizedBox(height: 12),
            Text('Loading MathLive…', style: _loadingStyle),
          ],
        ),
      ),
    );
  }

  Widget _errorOverlay() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: _fg)),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () {
                setState(() {
                  _error = null;
                  _loading = true;
                });
                unawaited(_bootstrap());
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
