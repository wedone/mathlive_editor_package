/// Replaces placeholders in [assets/mathlive/mathlive_editor.html] after load.
String patchMathLiveEditorHtml(String raw, {String? rootAndClientId}) {
  final String id = rootAndClientId ?? 'mathlive-mixed-root';
  return raw
      .replaceAll('MATHLIVE_MIXED_ROOT_ID', id)
      .replaceAll('___MATHLIVE_MIXED_CLIENT___', id);
}

/// Package asset path for [rootBundle.loadString].
const String kMathLiveEditorHtmlAsset =
    'packages/mathlive_studio/assets/mathlive/mathlive_editor.html';

/// 本地构建的 MathLive JS（含 fixedRows 等源码级改动）的资源路径。
const String kMathLiveJsAsset =
    'packages/mathlive_studio/assets/mathlive/mathlive.min.js';

/// 将 HTML 中引用 CDN 的 `<script src="...mathlive.min.js">` 替换为内联本地 JS。
///
/// CSS 仍从 CDN 加载（字体路径正常），仅替换 JS 以获得 fixedRows 等本地构建特性。
/// 同时移除 CDN 的 `<script>` 标签，避免重复加载。
String inlineLocalMathLiveJs(String html, String jsCode) {
  // 转义 JS 中可能存在的 </script>，防止 HTML 解析提前闭合
  final safeJs = jsCode.replaceAll('</script>', r'<\/script>');
  // 匹配 CDN 的 mathlive.min.js <script> 标签
  final pattern = RegExp(
    r'<script\s+src="[^"]*mathlive\.min\.js"[^>]*>\s*</script>',
    caseSensitive: false,
  );
  return html.replaceFirst(pattern, '<script>$safeJs</script>');
}
