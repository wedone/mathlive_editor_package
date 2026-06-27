import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../config/mathlive_channels.dart';
import '../config/mathlive_mixed_theme.dart';
import 'mathlive_editor_html_patch.dart';
import 'mathlive_editor_stub.dart'
    if (dart.library.html) 'mathlive_editor_web.dart'
    as mathlive_platform;

/// Full-screen MathLive editor; pops with LaTeX on Insert.
class MathLiveEditorPage extends StatefulWidget {
  const MathLiveEditorPage({
    super.key,
    required this.isDark,
    this.initialLatex,
    this.theme = MathLiveMixedTheme.defaults,
    this.title = 'Math editor',
    this.onEmptyLatex,
  });

  final bool isDark;
  final String? initialLatex;
  final MathLiveMixedTheme theme;
  final String title;
  final VoidCallback? onEmptyLatex;

  static Future<String?> open(
    BuildContext context, {
    required bool isDark,
    String? initialLatex,
    MathLiveMixedTheme theme = MathLiveMixedTheme.defaults,
  }) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => MathLiveEditorPage(
          isDark: isDark,
          initialLatex: initialLatex,
          theme: theme,
        ),
      ),
    );
  }

  @override
  State<MathLiveEditorPage> createState() => _MathLiveEditorPageState();
}

class _MathLiveEditorPageState extends State<MathLiveEditorPage> {
  WebViewController? _controller;
  void Function()? _webTriggerExport;
  int _webSession = 0;
  bool _loading = true;
  String? _error;
  bool _ready = false;

  Color get _bg => widget.theme.editorBackground(widget.isDark);
  Color get _fg => widget.theme.editorForeground(widget.isDark);

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
        MathLiveMixedChannels.latexExportJsChannel,
        onMessageReceived: (JavaScriptMessage message) {
          if (!mounted) return;
          final String latex = message.message;
          if (latex.trim().isEmpty) {
            widget.onEmptyLatex?.call();
            _showEmptyError();
            return;
          }
          Navigator.of(context).pop<String>(latex);
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
            await _applyThemeToWebView();
            unawaited(_injectInitialLatexIntoWebView());
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
    unawaited(_bootstrapWebView());
  }

  void _showEmptyError() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Enter a formula first')),
    );
  }

  Future<void> _tunePlatformWebView() async {
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

  Future<void> _bootstrapWebView() async {
    await _tunePlatformWebView();
    final WebViewController? c = _controller;
    if (!mounted || c == null) return;
    try {
      final String html = patchMathLiveEditorHtml(
        await rootBundle.loadString(kMathLiveEditorHtmlAsset),
      );
      await c.loadHtmlString(
        html,
        baseUrl: 'https://cdn.jsdelivr.net/npm/mathlive@0.110.0/',
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

  Future<void> _applyThemeToWebView() async {
    final WebViewController? c = _controller;
    if (c == null) return;
    try {
      await c.runJavaScript(
        'try{mlMixedSetTheme(${widget.isDark ? 'true' : 'false'});}catch(e){}',
      );
    } catch (_) {}
  }

  Future<void> _injectInitialLatexIntoWebView() async {
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

  Future<void> _onInsert() async {
    if (!_ready) return;
    if (kIsWeb) {
      _webTriggerExport?.call();
      return;
    }
    try {
      await _controller?.runJavaScript('mlMixedExportLatex();');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not read formula')),
        );
      }
    }
  }

  void _onLatexFromWeb(String latex) {
    if (!mounted) return;
    if (latex.trim().isEmpty) {
      widget.onEmptyLatex?.call();
      _showEmptyError();
      return;
    }
    Navigator.of(context).pop<String>(latex);
  }

  @override
  void didUpdateWidget(covariant MathLiveEditorPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isDark != widget.isDark && _ready && !kIsWeb) {
      unawaited(_applyThemeToWebView());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: _fg,
        elevation: 0,
        title: Text(
          widget.title,
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: _fg),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: _loading || _error != null ? null : _onInsert,
            child: Text(
              'Insert',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: widget.theme.accent,
              ),
            ),
          ),
        ],
      ),
      body: kIsWeb ? _buildWebBody() : _buildIoBody(),
    );
  }

  Widget _buildWebBody() {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        KeyedSubtree(
          key: ValueKey<int>(_webSession),
          child: mathlive_platform.mathLiveMixedWebEditorBody(
            isDark: widget.isDark,
            backgroundColor: _bg,
            initialLatex: widget.initialLatex,
            onLatex: _onLatexFromWeb,
            onExporterReady: (void Function() fn) {
              _webTriggerExport = fn;
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
        ),
        if (_loading) _loadingOverlay(),
        if (_error != null && !_loading) _errorOverlay(retryWeb: true),
      ],
    );
  }

  Widget _buildIoBody() {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        ColoredBox(
          color: _bg,
          child: WebViewWidget(controller: _controller!),
        ),
        if (_loading) _loadingOverlay(),
        if (_error != null && !_loading) _errorOverlay(retryWeb: false),
      ],
    );
  }

  Widget _loadingOverlay() {
    return ColoredBox(
      color: _bg.withOpacity( 0.85),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            CircularProgressIndicator(color: widget.theme.accent),
            const SizedBox(height: 16),
            Text('Loading MathLive…', style: TextStyle(color: _fg.withOpacity( 0.8))),
          ],
        ),
      ),
    );
  }

  Widget _errorOverlay({required bool retryWeb}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.wifi_off_rounded, size: 48, color: _fg.withOpacity( 0.5)),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: _fg)),
            const SizedBox(height: 8),
            Text(
              'MathLive loads from the network. Check your connection and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: _fg.withOpacity( 0.7)),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () {
                setState(() {
                  if (retryWeb) {
                    _webSession++;
                    _webTriggerExport = null;
                  } else {
                    _error = null;
                    _loading = true;
                    unawaited(_bootstrapWebView());
                    return;
                  }
                  _error = null;
                  _loading = true;
                  _ready = false;
                });
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
