import 'dart:convert';

import 'package:flutter/material.dart';

import '../config/mathlive_channels.dart';
import '../utils/math_normalize.dart';

/// Split mixed text into alternating plain text and inner-LaTeX segments.
List<Map<String, String>> parsePreviewParts(String source) {
  final String src = normalizeMentorEditorInlineMath(source);
  if (src.trim().isEmpty) {
    return <Map<String, String>>[];
  }
  final RegExp re = RegExp(r'\\\(([\s\S]*?)\\\)');
  if (!re.hasMatch(src)) {
    return <Map<String, String>>[<String, String>{'t': 'text', 's': src}];
  }
  final List<Map<String, String>> out = <Map<String, String>>[];
  int start = 0;
  for (final RegExpMatch m in re.allMatches(src)) {
    if (m.start > start) {
      final String plain = src.substring(start, m.start);
      if (plain.isNotEmpty) {
        out.add(<String, String>{'t': 'text', 's': plain});
      }
    }
    final String tex = m.group(1)!;
    out.add(<String, String>{
      't': 'math',
      's': normalizeLatexForFlutterMath(tex),
    });
    start = m.end;
  }
  if (start < src.length) {
    final String tail = src.substring(start);
    if (tail.isNotEmpty) {
      out.add(<String, String>{'t': 'text', 's': tail});
    }
  }
  return out;
}

String _cssRgb(Color c) => 'rgb(${c.red},${c.green},${c.blue})';

String _cssBackground(Color c) {
  if (c.alpha == 0) {
    return 'transparent';
  }
  if (c.alpha == 255) {
    return 'rgb(${c.red},${c.green},${c.blue})';
  }
  final double o = c.alpha / 255.0;
  return 'rgba(${c.red},${c.green},${c.blue},$o)';
}

String _cssFontFamily(String? family) {
  if (family == null || family.isEmpty) {
    return 'system-ui, -apple-system, sans-serif';
  }
  final String escaped = family.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
  return "'$escaped', system-ui, sans-serif";
}

/// Full HTML document: plain text spans + read-only [math-field] per formula.
String buildMathLiveMixedPreviewHtml({
  required String source,
  required bool isDark,
  required Color backgroundColor,
  required Color textColor,
  required double fontSizePx,
  String? fontFamily,
  double lineHeight = 1.45,
  int fontWeight = 400,
  double letterSpacing = 0,
  bool embedWithoutScroll = false,
  bool clipRootOverflow = false,
  bool disableTextInteraction = false,
  String? webParentPostMessageId,
}) {
  final List<Map<String, String>> parts = parsePreviewParts(source);
  if (parts.isEmpty) {
    return '';
  }
  final String partsJson = jsonEncode(parts);
  final String parentMsgIdJs = webParentPostMessageId == null
      ? 'null'
      : jsonEncode(webParentPostMessageId);
  final String bg = _cssBackground(backgroundColor);
  final String fg = _cssRgb(textColor);
  final String ff = _cssFontFamily(fontFamily);
  const String channel = MathLiveMixedChannels.previewHeight;

  final String htmlBodyBlock = embedWithoutScroll
      ? '''
    html {
      height: auto !important;
      min-height: 0;
      overflow: hidden !important;
      pointer-events: none;
    }
    body {
      margin: 0;
      padding: 0;
      min-height: 0;
      height: auto !important;
      overflow: hidden !important;
      background: $bg;
      color: $fg;
      pointer-events: none;
    }
    html::-webkit-scrollbar,
    body::-webkit-scrollbar {
      width: 0 !important;
      height: 0 !important;
      display: none;
    }
'''
      : '''
    html {
      height: 100%;
      min-height: 100%;
      overflow-x: hidden;
      overflow-y: auto;
      -webkit-overflow-scrolling: touch;
    }
    body {
      margin: 0;
      padding: 0;
      min-height: 100%;
      height: 100%;
      overflow-x: hidden;
      overflow-y: auto;
      background: $bg;
      color: $fg;
    }
    html::-webkit-scrollbar,
    body::-webkit-scrollbar {
      width: 4px;
    }
    html::-webkit-scrollbar-thumb,
    body::-webkit-scrollbar-thumb {
      background: rgba(148, 163, 184, 0.3);
      border-radius: 4px;
    }
''';

  final String rootTouchAction = embedWithoutScroll ? 'auto' : 'pan-y';
  final String rootPointerEvents = embedWithoutScroll ? 'none' : 'auto';
  final String rootOverflow = clipRootOverflow ? 'hidden' : 'visible';
  final String rootPaddingBottom = clipRootOverflow ? '6px' : '0';

  final String noSelectCss = disableTextInteraction
      ? '''
    #root, #root .text-span, math-field {
      -webkit-user-select: none !important;
      user-select: none !important;
      -webkit-touch-callout: none !important;
    }
'''
      : '';

  final String noSelectScript = disableTextInteraction
      ? '''
      function mlMixedNoTextUi(e) { e.preventDefault(); }
      document.addEventListener('contextmenu', mlMixedNoTextUi, true);
      document.addEventListener('selectstart', mlMixedNoTextUi, true);
      document.addEventListener('dragstart', mlMixedNoTextUi, true);
'''
      : '';

  return '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1" />
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/mathlive@0.110.0/mathlive-static.css" />
  <script src="https://cdn.jsdelivr.net/npm/mathlive@0.110.0/mathlive.min.js"></script>
  <style>
    $htmlBodyBlock
    $noSelectCss
    #root {
      box-sizing: border-box;
      padding: 0;
      padding-bottom: $rootPaddingBottom;
      font-family: $ff;
      font-size: ${fontSizePx}px;
      font-weight: $fontWeight;
      line-height: $lineHeight;
      letter-spacing: ${letterSpacing}px;
      white-space: pre-wrap;
      word-break: break-word;
      overflow-wrap: anywhere;
      width: 100%;
      overflow: $rootOverflow;
      touch-action: $rootTouchAction;
      pointer-events: $rootPointerEvents;
    }
    math-field {
      display: inline-block;
      vertical-align: middle;
      margin: 0 2px;
      border: none !important;
      outline: none !important;
      box-shadow: none !important;
      background: transparent !important;
      color: inherit;
      font-size: 1.05em;
      font-weight: inherit;
      min-width: 1em;
    }
    math-field:focus { outline: none !important; }
    .text-span { display: inline; }
  </style>
</head>
<body>
  <div id="root" class="mathlive-mixed-root"></div>
  <script>
    (function () {
      $noSelectScript
      var parts = $partsJson;
      var root = document.getElementById('root');
      var parentMsgId = $parentMsgIdJs;

      function reportHeight() {
        function measureAndPost() {
          var h = 40;
          if (root) {
            h = Math.max(root.scrollHeight, root.offsetHeight, 40);
            try {
              var r = root.getBoundingClientRect();
              h = Math.max(h, Math.ceil(r.height));
              var fields = root.querySelectorAll('math-field');
              for (var i = 0; i < fields.length; i++) {
                var br = fields[i].getBoundingClientRect();
                var relBottom = br.bottom - r.top;
                h = Math.max(h, Math.ceil(relBottom));
              }
            } catch (e0) {}
          } else {
            h = Math.max(document.documentElement.scrollHeight, document.body.scrollHeight, 40);
          }
          h = Math.ceil(h) + 12;
          try {
            if (typeof ${MathLiveMixedChannels.previewHeightJsChannel} !== 'undefined' && ${MathLiveMixedChannels.previewHeightJsChannel}.postMessage) {
              ${MathLiveMixedChannels.previewHeightJsChannel}.postMessage(String(h));
            }
          } catch (e1) {}
          try {
            if (window.parent && window.parent !== window) {
              var payload = { channel: '$channel', height: h };
              if (parentMsgId !== null && parentMsgId !== undefined) {
                payload.id = parentMsgId;
              }
              window.parent.postMessage(payload, '*');
            }
          } catch (e2) {}
        }
        requestAnimationFrame(function () {
          requestAnimationFrame(measureAndPost);
        });
      }

      var roTicking = false;
      function scheduleReportFromResize() {
        if (roTicking) return;
        roTicking = true;
        requestAnimationFrame(function () {
          roTicking = false;
          reportHeight();
        });
      }

      function build() {
        if (!root) return;
        root.innerHTML = '';
        parts.forEach(function (p) {
          if (p.t === 'text') {
            var span = document.createElement('span');
            span.className = 'text-span';
            span.textContent = p.s;
            root.appendChild(span);
          } else if (p.t === 'math') {
            var mf = document.createElement('math-field');
            mf.setAttribute('read-only', '');
            try { mf.readOnly = true; } catch (e) {}
            try { mf.mathVirtualKeyboardPolicy = 'off'; } catch (e2) {}
            try {
              mf.setValue(p.s, { format: 'latex' });
            } catch (e3) {
              mf.textContent = p.s;
            }
            root.appendChild(mf);
          }
        });
        setTimeout(reportHeight, 40);
        setTimeout(reportHeight, 150);
        setTimeout(reportHeight, 400);
        setTimeout(reportHeight, 800);
        setTimeout(reportHeight, 1400);
        setTimeout(reportHeight, 2200);
        try {
          if (typeof ResizeObserver !== 'undefined') {
            new ResizeObserver(scheduleReportFromResize).observe(root);
          }
        } catch (eRo) {}
      }

      if (typeof customElements !== 'undefined' && customElements.whenDefined) {
        customElements.whenDefined('math-field').then(build).catch(build);
      } else {
        build();
      }
    })();
  </script>
</body>
</html>
''';
}
