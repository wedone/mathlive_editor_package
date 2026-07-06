# mathlive\_studio

在 Flutter 中渲染和编辑**混合内容**：普通文本加内联数学公式（以 `\(...\)` 包裹的 LaTeX），基于 [MathLive](https://mathlive.io/) **0.101.2** 实现。

支持 **Android、iOS 和 Web**（移动端/桌面端使用 WebView；Web 端使用 iframe / platform views）。

## 功能特性

| 功能                  | Widget / API                                              |
| ------------------- | --------------------------------------------------------- |
| 只读预览                | `MathLiveMixedPreview`                                    |
| 内联编辑器（固定高度）         | `MathLiveEmbeddedEditor`                                  |
| 全屏编辑器               | `MathLiveEditorPage`                                      |
| 检测字符串中是否包含数学公式      | `textUsesMathLivePreview()`                               |
| 规范化 LaTeX / 分隔符     | `normalizeInlineMath()`, `normalizeLatexForFlutterMath()` |
| 轻量级回退方案（无需 WebView） | `InlineTexMixedText`, `buildSimpleLatexInline()`          |

宿主应用**无需**在其 `pubspec.yaml` 中声明 MathLive 资源——它们已打包在此包中。

## 安装

### pub.dev（推荐）

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

### 本地路径（monorepo）

```yaml
dependencies:
  mathlive_studio:
    path: ../flutter_mathlive_mixed
```

## 文本格式

将面向用户的内容存储为纯文本，其中**内联数学公式**用分隔符包裹：

```text
圆的面积是 \(A = \pi r^2\)，其中 \(r\) 是半径。
```

- **预览**组件期望这种混合格式（每个公式使用 `\(...\)`）。
- **编辑器**从 `MathLiveEmbeddedEditor` / `MathLiveEditorPage` 导出**仅内层 LaTeX**（例如 `\frac{1}{2}`）；构建预览字符串时，需自行用 `\(` `\)` 包裹。

## 快速开始

```dart
import 'package:flutter/material.dart';
import 'package:mathlive_studio/mathlive_studio.dart';
import 'package:mathlive_studio/utils.dart';
```

### 预览

```dart
MathLiveMixedPreview(
  previewText: r'求解 \(x^2 + 1 = 0\) 中实数 \(x\) 的值。',
  isDark: Theme.of(context).brightness == Brightness.dark,
  backgroundColor: Colors.transparent,
  baseStyle: Theme.of(context).textTheme.bodyMedium!,
  expandToContent: true,   // 聊天风格：高度跟随内容
  displayOnly: true,       // WebView 内禁止文本选择
)
```

### 选择预览还是纯文本

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

### 内联编辑器 + 实时预览

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

### 全屏编辑器

```dart
final String? latex = await MathLiveEditorPage.open(
  context,
  isDark: false,
  initialLatex: r'x^2+1',
);
if (latex != null) {
  // 使用内层 LaTeX
}
```

## `MathLiveMixedPreview` 选项

| 参数                                     | 使用场景                                       |
| -------------------------------------- | ------------------------------------------ |
| `expandToContent: true`                | 聊天气泡、详情页面——WebView 高度跟随数学公式布局              |
| `displayOnly: true`                    | 只读模式；禁用 WebView 中的选择/复制 UI                 |
| `clipOverflow: true`                   | 列表卡片——固定 `maxViewportHeight`，裁剪超出部分（无内部滚动） |
| `maxViewportHeight`                    | 最大高度限制（省略时默认为屏幕高度的约 45%）                   |
| `preventShrinkingReportedHeight: true` | 减少内容在可滚动父组件中增长时 web 高度闪烁                   |
| `baseStyle`                            | 传递给 HTML 层的字体族、大小、颜色                       |

**列表卡片（短摘要）：**

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

## 主题

编辑器的可选配色：

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

预览组件的颜色来自 `baseStyle` 和 `backgroundColor`——无需应用特定的主题类型。

## 平台说明

### 网络

MathLive **JS/CSS** 在运行时通过 HTTPS 从 **jsDelivr** 加载。除非您自定义 HTML 以仅使用打包资源，否则设备首次渲染时需要联网。

### Android

- `webview_flutter` + `webview_flutter_android`
- 默认 Flutter 应用已包含 `INTERNET` 权限。

### iOS

- 通过 `webview_flutter` 使用 `WKWebView`
- HTTPS CDN 在默认 App Transport Security 配置下正常工作。

### Web

- 预览：blob URL iframe + `postMessage` 高度同步
- 编辑器：MathLive 运行在宿主 `HtmlElementView` 中，以便虚拟键盘正常工作
- 如果您的 Flutter SDK 版本低于 3.22，请在**应用**的 `pubspec.yaml` 中锁定 `webview_flutter_web: 0.2.3+2`

## 示例应用

来自[仓库](https://github.com/RohanPardule/mathlive_editor_package)：

```bash
cd flutter_mathlive_mixed/example
flutter pub get
flutter run -d chrome
flutter run   # iOS / Android
```

标签页展示了预览切换和内联编辑器与实时预览的功能。

## API 导出

```dart
// package:mathlive_studio/mathlive_studio.dart
MathLiveMixedPreview
MathLiveEmbeddedEditor
MathLiveEditorPage
MathLiveMixedTheme
InlineTexMixedText
buildSimpleLatexInline
parsePreviewParts
buildMathLiveMixedPreviewHtml  // 高级用法：自定义 HTML 宿主

// package:mathlive_studio/utils.dart
textUsesMathLivePreview
normalizeInlineMath
normalizeLatexForFlutterMath
convertOuterPlainTextToMathliveLatex
```

## 问题反馈与贡献

- [Bug 报告 / 功能建议](https://github.com/RohanPardule/mathlive_editor_package/issues)
- [源代码](https://github.com/RohanPardule/mathlive_editor_package/tree/main/flutter_mathlive_mixed)

## 许可证

- **本包（Dart）：** MIT — 参见 [LICENSE](LICENSE)。
- **MathLive**（CDN / 打包资源）：遵循 [MathLive 许可证](https://github.com/arnog/mathlive)；商业分发前请审阅。

