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
}
