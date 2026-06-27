# mathlive_studio

Render and edit **mixed content** in Flutter: normal text plus inline math written as LaTeX inside `\(...\)`, powered by [MathLive](https://mathlive.io/) **0.110.0**.

Works on **Android, iOS, and Web** (mobile/desktop use a WebView; web uses iframes / platform views).

## Features

| Feature | Widget / API |
|--------|----------------|
| Read-only preview | `MathLiveMixedPreview` |
| Inline editor (fixed height) | `MathLiveEmbeddedEditor` |
| Full-screen editor | `MathLiveEditorPage` |
| Detect math in a string | `textUsesMathLivePreview()` |
| Normalize LaTeX / delimiters | `normalizeInlineMath()`, `normalizeLatexForFlutterMath()` |
| Lightweight fallback (no WebView) | `InlineTexMixedText`, `buildSimpleLatexInline()` |

Host apps do **not** need to declare MathLive assets in their own `pubspec.yaml` — they are bundled in this package.

## Installation

### pub.dev (recommended)

```yaml
dependencies:
  mathlive_studio: ^0.1.1
```

```bash
flutter pub get
```

### Git

```yaml
dependencies:
  mathlive_studio:
    git:
      url: https://github.com/RohanPardule/mathlive_editor_package.git
      path: flutter_mathlive_mixed
      ref: main
```

### Local path (monorepo)

```yaml
dependencies:
  mathlive_studio:
    path: ../flutter_mathlive_mixed
```

## Text format

Store user-facing content as plain text with **inline math** wrapped in delimiters:

```text
The area of a circle is \(A = \pi r^2\) where \(r\) is the radius.
```

- **Preview** expects this mixed format (`\(...\)` for each formula).
- **Editor** exports **inner LaTeX only** (e.g. `\frac{1}{2}`) from `MathLiveEmbeddedEditor` / `MathLiveEditorPage`; wrap with `\(` `\)` yourself when building preview strings.

## Quick start

```dart
import 'package:flutter/material.dart';
import 'package:mathlive_studio/mathlive_studio.dart';
import 'package:mathlive_studio/utils.dart';
```

### Preview

```dart
MathLiveMixedPreview(
  previewText: r'Solve \(x^2 + 1 = 0\) for real \(x\).',
  isDark: Theme.of(context).brightness == Brightness.dark,
  backgroundColor: Colors.transparent,
  baseStyle: Theme.of(context).textTheme.bodyMedium!,
  expandToContent: true,   // chat-style: height follows content
  displayOnly: true,     // no text selection inside WebView
)
```

### Choose preview vs plain text

```dart
final TextStyle style = Theme.of(context).textTheme.bodyMedium!;

Widget buildBody(String text) {
  if (textUsesMathLivePreview(text)) {
    return MathLiveMixedPreview(
      previewText: text,
      isDark: false,
      backgroundColor: Colors.white,
      baseStyle: style,
    );
  }
  return InlineTexMixedText(source: text, style: style);
}
```

### Embedded editor + live preview

```dart
String latex = r'\frac{1}{2}';

Column(
  children: [
    MathLiveEmbeddedEditor(
      isDark: false,
      initialLatex: latex,
      height: 300,
      onLatexChanged: (value) => setState(() => latex = value),
    ),
    const SizedBox(height: 12),
    MathLiveMixedPreview(
      previewText: r'\(' + latex + r'\)',
      isDark: false,
      backgroundColor: Colors.grey.shade100,
      baseStyle: const TextStyle(fontSize: 15),
      expandToContent: true,
      displayOnly: true,
    ),
  ],
)
```

### Full-screen editor

```dart
final String? latex = await MathLiveEditorPage.open(
  context,
  isDark: false,
  initialLatex: r'x^2+1',
);
if (latex != null) {
  // use inner LaTeX
}
```

## `MathLiveMixedPreview` options

| Parameter | Use when |
|-----------|----------|
| `expandToContent: true` | Chat bubbles, detail screens — WebView height tracks math layout |
| `displayOnly: true` | Read-only; disables selection / copy UI in the WebView |
| `clipOverflow: true` | List cards — fixed `maxViewportHeight`, clip excess (no inner scroll) |
| `maxViewportHeight` | Cap height (defaults to ~45% of screen if omitted) |
| `preventShrinkingReportedHeight: true` | Reduces web height flicker when content grows in scrollable parents |
| `baseStyle` | Font family, size, color passed into the HTML layer |

**List card (short teaser):**

```dart
MathLiveMixedPreview(
  previewText: snippet,
  isDark: isDark,
  backgroundColor: cardColor,
  baseStyle: bodyStyle,
  maxViewportHeight: 72,
  clipOverflow: true,
)
```

## Theming

Optional chrome colors for editors:

```dart
const theme = MathLiveMixedTheme(
  accent: Color(0xFF2563EB),
);

MathLiveEmbeddedEditor(
  isDark: isDark,
  theme: theme,
  onLatexChanged: (_) {},
)
```

Preview colors come from your `baseStyle` and `backgroundColor` — no app-specific theme types required.

## Platform notes

### Network

MathLive **JS/CSS** load from **jsDelivr** over HTTPS at runtime. Devices need internet for first render unless you customize the HTML to use only bundled assets.

### Android

- `webview_flutter` + `webview_flutter_android`
- Default Flutter apps already include `INTERNET`.

### iOS

- `WKWebView` via `webview_flutter`
- HTTPS CDN works with default App Transport Security.

### Web

- Preview: blob URL iframe + `postMessage` height sync
- Editor: MathLive runs in a host `HtmlElementView` so the virtual keyboard works
- If your Flutter SDK is &lt; 3.22, pin `webview_flutter_web: 0.2.3+2` in the **app** `pubspec.yaml`

## Example app

From the [repository](https://github.com/RohanPardule/mathlive_editor_package):

```bash
cd flutter_mathlive_mixed/example
flutter pub get
flutter run -d chrome
flutter run   # iOS / Android
```

Tabs demonstrate preview toggles and an embedded editor with live preview.

## API exports

```dart
// package:mathlive_studio/mathlive_studio.dart
MathLiveMixedPreview
MathLiveEmbeddedEditor
MathLiveEditorPage
MathLiveMixedTheme
InlineTexMixedText
buildSimpleLatexInline
parsePreviewParts
buildMathLiveMixedPreviewHtml  // advanced: custom HTML host

// package:mathlive_studio/utils.dart
textUsesMathLivePreview
normalizeInlineMath
normalizeLatexForFlutterMath
convertOuterPlainTextToMathliveLatex
```

## Issues & contributing

- [Bug reports / features](https://github.com/RohanPardule/mathlive_editor_package/issues)
- [Source](https://github.com/RohanPardule/mathlive_editor_package/tree/main/flutter_mathlive_mixed)

## License

- **This package (Dart):** MIT — see [LICENSE](LICENSE).
- **MathLive** (CDN / bundled assets): subject to the [MathLive license](https://github.com/arnog/mathlive); review before commercial redistribution.
