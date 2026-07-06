/// postMessage / JavaScript channel names for MathLive mixed editor and preview.
abstract final class MathLiveMixedChannels {
  static const String fromEditor = 'MathLiveMixed';
  static const String toEditor = 'MathLiveMixedHost';
  static const String previewHeight = 'MathLiveMixedPreview';
  static const String paste = 'MathLiveMixedPaste';

  static const String previewHeightJsChannel = 'FlutterPreviewHeight';
  static const String latexSyncJsChannel = 'FlutterLatexSync';
  static const String latexExportJsChannel = 'FlutterLatex';
  static const String heightSync = 'FlutterEditorHeight';

  /// 用于「插入公式」自定义命令（行内/行间）的 JS→Dart 通道。
  ///
  /// JS 侧通过 `FlutterLatexInsert.postMessage(jsonString)` 发送
  /// `{mode: 'inline'|'block', latex: '...'}` 格式的 JSON 字符串。
  static const String latexInsertJsChannel = 'FlutterLatexInsert';
}
