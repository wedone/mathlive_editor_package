# mathlive_studio 包架构分析与自定义能力

## 一、包概览

`mathlive_studio` 是一个 Flutter 包，用于在 Flutter 中渲染和编辑**混合内容**（纯文本 + `\(...\)` 包裹的内联 LaTeX 数学公式）。基于 MathLive 0.101.2 实现，支持 Android、iOS 和 Web。

### 核心架构

```
┌─────────────────────────────────────────────────────────────┐
│  Flutter 宿主应用（如 zulip-flutter）                         │
│    └─ MathLiveEmbeddedEditor(isDark: true, theme: ...)      │
│         │                                                   │
│         │  Dart → JS: runJavaScript() / 占位符替换            │
│         │  JS → Dart: JavaScriptChannel / postMessage        │
│         ▼                                                   │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  WebView / iframe                                    │    │
│  │    └─ mathlive_editor.html（HTML + CSS + JS）         │    │
│  │         │                                            │    │
│  │         │  完整的 MathLive JS 运行环境                   │    │
│  │         │  可调用所有 MathLive API                      │    │
│  │         ▼                                            │    │
│  │    ┌─────────────────────────────────────────────┐   │    │
│  │    │  MathLive JS Library（CDN: mathlive@0.101.2）│   │    │
│  │    │    <math-field> / <math-virtual-keyboard>    │   │    │
│  │    │    mathVirtualKeyboard.layouts / .container  │   │    │
│  │    │    mf.setValue / .getValue / .smartMode ...  │   │    │
│  │    └─────────────────────────────────────────────┘   │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

**关键理解**：HTML 模板运行在 WebView 内，加载了完整的 `mathlive.min.js`，拥有 MathLive 的**全部能力**。你在 HTML 的 `<script>` 中可以直接调用任何 MathLive API。

### 目录结构

```
flutter_mathlive_mixed/
├── assets/mathlive/
│   └── mathlive_editor.html          # ★ 编辑器 HTML 模板（含 JS）—— UI/交互自定义的主战场
├── lib/
│   ├── mathlive_studio.dart          # 主入口（导出核心 Widget）
│   ├── utils.dart                    # 工具函数导出
│   └── src/
│       ├── config/
│       │   ├── mathlive_channels.dart    # postMessage 通道名常量
│       │   └── mathlive_mixed_theme.dart # 主题配置类
│       ├── editor/
│       │   ├── mathlive_embedded_editor.dart  # 内联编辑器 Widget
│       │   ├── mathlive_editor_page.dart      # 全屏编辑器页面
│       │   ├── mathlive_editor_html_patch.dart # HTML 占位符替换
│       │   ├── mathlive_editor_web.dart       # Web 平台实现
│       │   └── mathlive_editor_stub.dart      # 非 Web 平台 stub
│       ├── preview/
│       │   ├── mathlive_mixed_preview.dart    # 预览 Widget（跨平台入口）
│       │   ├── mathlive_mixed_preview_html.dart # 预览 HTML 构建器
│       │   ├── mathlive_mixed_preview_io.dart   # IO 平台（WebView）
│       │   └── mathlive_mixed_preview_web.dart  # Web 平台（iframe）
│       ├── fallback/
│       │   ├── inline_tex_mixed_text.dart     # 轻量级回退渲染
│       │   └── simple_latex_inline.dart       # 简单 LaTeX 内联渲染
│       └── utils/
│           ├── math_normalize.dart            # LaTeX 规范化
│           └── math_import_converter.dart     # 纯文本→LaTeX 转换
```

---

## 二、自定义 MathLive 的两种方式

### 方式 1：修改 HTML 模板（推荐用于 UI 和交互自定义）

**改哪个文件**：`assets/mathlive/mathlive_editor.html`

**能做什么**：MathLive 的**所有** API 都可以在 HTML 的 `<script>` 中直接使用，包括但不限于：
- `mathVirtualKeyboard.layouts = [...]` — 自定义键盘布局（含 `fixedRows`、`variants`、`shift` 等）
- `<math-field>` 的所有属性（`smart-mode`、`virtual-keyboard-mode`、`math-mode-space` 等）
- `<math-virtual-keyboard>` 的所有配置
- CSS 变量和 `::part()` 伪元素
- `mf.executeCommand()` 执行任何 MathLive 命令
- `mf.setValue()` / `mf.getValue()` 读写公式
- 事件监听（`input`、`focusin`、`focusout`、`mode-change` 等）
- `mathVirtualKeyboard.show()` / `hide()` / `.visible`
- `mf.menuItems` 自定义右键菜单
- `mf.computeEngine` 计算引擎

**本质**：HTML 模板 = 一个完整的 MathLive 宿主页面，和 `d:\vc\mathlive\examples\scrollable-keyboard\index.html` 是同一层级的东西，拥有完全相同的能力。

**示例**：在 `mlMixedAttachVirtualKeyboard()` 中添加自定义布局

```js
function mlMixedAttachVirtualKeyboard() {
  if (typeof mathVirtualKeyboard === 'undefined') return;
  
  // ★ 直接在 JS 中设置，无需 Dart API
  mathVirtualKeyboard.layouts = [
    {
      label: '常用',
      layers: [{
        rows: [ /* 自定义按键行 */ ],
        fixedRows: [ /* 固定行（如 +−×÷ = shift backspace left right return）*/ ],
      }],
    },
    'numeric', 'symbols', 'alphabetic', 'greek'
  ];
  
  // ... 原有 container 绑定和 geometrychange 监听不变
}
```

**局限性**：修改后行为**硬编码**在包里，所有使用该包的应用行为一致，无法从 Flutter 侧动态控制。

### 方式 2：扩展 Dart API（用于需要 Flutter 侧动态控制的场景）

**改哪些文件**：
1. Dart Widget（如 `mathlive_embedded_editor.dart`）— 新增参数
2. HTML 模板（`mathlive_editor.html`）— 新增占位符或 JS 函数
3. 可能改 `mathlive_editor_html_patch.dart` — 新增占位符替换

**什么时候需要**：当你需要**从 Flutter 代码动态控制** MathLive 行为时，例如：
- 用户在 Flutter 设置界面切换键盘布局
- 根据用户角色（学生/教师）显示不同的 math-field 属性
- 运行时切换 `smartMode`、`locale`
- 需要把 MathLive 的事件（如 `focusin`）传回 Flutter

**实现模式**：

```
Flutter 参数 → runJavaScript("mlMixedSetXxx(value)") → JS 函数 → MathLive API
```

或：

```
Flutter 参数 → patchMathLiveEditorHtml 占位符替换 → HTML 中直接使用值
```

### 两种方式的选择标准

| 场景 | 用方式 1（改 HTML） | 用方式 2（扩展 Dart API） |
|------|-------------------|------------------------|
| 自定义键盘布局 | ✅ 直接在 HTML 写 `layouts = [...]` | 仅当需要 Flutter 侧切换布局时 |
| 修改 `<math-field>` CSS | ✅ 直接改 HTML 的 `<style>` | ❌ CSS 不适合通过 API 传 |
| 添加 `fixedRows` | ✅ 直接在 layouts 对象中添加 | 仅当需要 Flutter 侧配置时 |
| 隐藏/显示键盘切换按钮 | ✅ 改 CSS `::part()` | ❌ |
| 切换 `smartMode` | ✅ 在 HTML 中硬编码 | 需要运行时切换时才扩展 API |
| 设置 `locale` | ✅ 在 HTML 中硬编码 | 需要运行时切换语言时才扩展 API |
| 监听 `focusin`/`focusout` | ✅ 在 HTML 的 JS 中写 | 需要通知 Flutter 时才扩展 API |
| 自定义右键菜单 | ✅ 在 HTML 的 JS 中写 | 仅当需要 Flutter 侧配置菜单项时 |

**简单原则**：如果自定义内容在运行时不变，改 HTML；如果需要 Flutter 侧动态控制，扩展 Dart API。

---

## 三、公开 API 全景

### 3.1 Widget 层

| Widget | 用途 | 构造函数参数 |
|--------|------|-------------|
| `MathLiveMixedPreview` | 只读预览混合文本 | `previewText`, `isDark`, `backgroundColor`, `baseStyle`, `maxViewportHeight`, `expandToContent`, `displayOnly`, `clipOverflow`, `preventShrinkingReportedHeight` |
| `MathLiveEmbeddedEditor` | 固定高度内联编辑器 | `isDark`, `initialLatex`, `onLatexChanged`, `height`, `latexSnapshot`, `theme`, `loadingTextStyle` |
| `MathLiveEditorPage` | 全屏编辑器页面 | `isDark`, `initialLatex`, `theme`, `title`, `onEmptyLatex` |
| `InlineTexMixedText` | 轻量级回退渲染（无需 WebView） | `source`, `style` |

### 3.2 主题层

```dart
class MathLiveMixedTheme {
  const MathLiveMixedTheme({
    this.editorBackgroundLight = Colors.white,
    this.editorBackgroundDark = const Color(0xFF141922),
    this.editorForegroundLight = const Color(0xFF0F172A),
    this.editorForegroundDark = const Color(0xFFE2E8F0),
    this.accent = const Color(0xFF2563EB),
  });
}
```

**5 个颜色字段**，控制编辑器亮/暗模式下的背景色、前景色和强调色。

### 3.3 工具函数层

| 函数 | 用途 | 参数 |
|------|------|------|
| `buildMathLiveMixedPreviewHtml()` | 构建预览 HTML（高级用法） | `source`, `isDark`, `backgroundColor`, `textColor`, `fontSizePx`, `fontFamily`, `lineHeight`, `fontWeight`, `letterSpacing`, `embedWithoutScroll`, `clipRootOverflow`, `disableTextInteraction`, `webParentPostMessageId` |
| `parsePreviewParts()` | 拆分混合文本为文本/数学片段 | `source` |
| `buildSimpleLatexInline()` | 轻量级 LaTeX 渲染 | `tex`, `style` |
| `textUsesMathLivePreview()` | 判断文本是否含数学公式 | `text` |
| `normalizeInlineMath()` | 规范化定界符 | `input` |
| `normalizeLatexForFlutterMath()` | `\placeholder` → `\square` | `tex` |
| `convertOuterPlainTextToMathliveLatex()` | 纯文本→LaTeX | `raw` |
| `patchMathLiveEditorHtml()` | HTML 占位符替换 | `raw`, `rootAndClientId` |

---

## 四、参数传递链路

### 4.1 编辑器参数传递（以 `isDark` 为例）

```
Flutter Widget (MathLiveEmbeddedEditor.isDark)
    │
    ├─→ Dart: _applyTheme() → runJavaScript("mlMixedSetTheme(true)")
    │       └─→ JS: mlMixedSetTheme(dark) → 切换 body/.mathlive-mixed-root 的 theme-dark class
    │               └─→ CSS: .theme-dark math-field { background: #1e2532; color: #e2e8f0; }
    │
    └─→ Dart: theme.editorBackground(isDark) → WebView 背景色
```

### 4.2 `initialLatex` 传递

```
Flutter Widget (MathLiveEmbeddedEditor.initialLatex)
    │
    └─→ Dart: _injectInitialLatex() → 多次延迟重试 runJavaScript("mlMixedSetLatex('...')")
            └─→ JS: mlMixedSetLatex(latex) → mf.setValue(latex, {format: 'latex'})
                    └─→ MathLive: <math-field> 渲染公式
```

### 4.3 `onLatexChanged` 回调（反向传递）

```
MathLive <math-field> input 事件
    │
    └─→ JS: mlMixedExportLatex() → postMessage({channel: 'MathLiveMixed', latex: '...'})
            └─→ Flutter: JavaScriptChannel('FlutterLatexSync').onMessageReceived
                    └─→ Dart: 280ms 防抖 → widget.onLatexChanged(latex)
```

### 4.4 预览参数传递

```
Flutter Widget (MathLiveMixedPreview.baseStyle)
    │
    └─→ Dart: 提取 fontSize/fontFamily/color/height/fontWeight/letterSpacing
            └─→ buildMathLiveMixedPreviewHtml() → 生成完整 HTML 字符串（含 CSS）
                    └─→ WebView/iframe 加载 HTML → MathLive 渲染
```

**关键区别**：预览组件是**一次性生成 HTML**，编辑器是**动态通信**。

---

## 五、MathLive API 可用性分析

### 5.1 HTML 模板中已使用的 MathLive API

| MathLive API | 使用位置 | 用途 |
|-------------|---------|------|
| `<math-field>` Web Component | mathlive_editor.html | 编辑器核心 |
| `<math-virtual-keyboard>` | mathlive_editor.html | 虚拟键盘 |
| `mathVirtualKeyboard.container` | mathlive_editor.html | 键盘容器绑定 |
| `mathVirtualKeyboard.visible` | mathlive_editor.html | 键盘显隐控制 |
| `mathVirtualKeyboard.show()/hide()` | mathlive_editor.html | 键盘显隐方法 |
| `mathVirtualKeyboard.boundingRect.height` | mathlive_editor.html | 键盘高度（同步给 Flutter） |
| `mathVirtualKeyboard.addEventListener('geometrychange')` | mathlive_editor.html | 监听键盘尺寸变化 |
| `mf.setValue(latex, {format: 'latex'})` | mathlive_editor.html | 设置 LaTeX 内容 |
| `mf.getValue('latex')` | mathlive_editor.html | 获取 LaTeX 内容 |
| `mf.executeCommand()` | mathlive_editor.html | 执行命令（如 addRowAfter） |
| `mf.mathVirtualKeyboardPolicy = 'manual'` | mathlive_editor.html | 手动控制键盘 |
| `mf.readOnly = true` | mathlive_mixed_preview_html.dart | 预览模式只读 |
| `mf.mathVirtualKeyboardPolicy = 'off'` | mathlive_mixed_preview_html.dart | 预览模式关闭键盘 |
| `::part(menu-toggle)` / `::part(virtual-keyboard-toggle)` | mathlive_editor.html | 隐藏原生切换按钮 |

### 5.2 可直接在 HTML 中使用但尚未使用的 MathLive API

以下 API 均可在 `mathlive_editor.html` 的 `<script>` 中直接调用，**无需扩展 Dart API**：

| MathLive API | 说明 | 自定义类型 |
|-------------|------|-----------|
| `mathVirtualKeyboard.layouts = [...]` | 自定义键盘布局（含 `rows`、`fixedRows`、`variants`、`shift`） | UI/交互 |
| `mf.smartMode = true` | 智能模式（自动识别输入类型） | 行为 |
| `mf.keybindings = [...]` | 自定义键盘快捷键 | 行为 |
| `mf.locale = 'zh-CN'` | 本地化（影响菜单文字等） | 行为 |
| `mf.placeholder = '...'` | 占位符文本 | UI |
| `mf.menuItems = [...]` | 自定义右键菜单 | UI/交互 |
| `mf.computeEngine` | 计算引擎（实时计算/验证） | 功能 |
| `mf.selection` | 选区信息 | 状态查询 |
| `mf.insert()` | 程序化插入 LaTeX | 功能 |
| `mf.focus()` / `mf.blur()` / `mf.hasFocus()` | 焦点控制 | 状态 |
| `mf.getValue('ascii-math')` | 多格式导出 | 功能 |
| `mf.getValue('spoken-text')` | 语音文本（无障碍） | 功能 |
| `mf.addEventListener('focusin')` | 聚焦事件 | 事件 |
| `mf.addEventListener('focusout')` | 失焦事件 | 事件 |
| `mf.addEventListener('mode-change')` | 输入模式切换事件 | 事件 |
| `mf.addEventListener('move-out')` | 光标移出边界事件 | 事件 |
| CSS 变量（`--primary`、`--caret-color`、`--selection-color` 等） | 视觉定制 | UI |
| `::part(content)` / `::part(container)` / `::part(keyboard-sink)` | math-field 内部元素样式 | UI |

### 5.3 "已暴露" vs "未暴露" 的真正含义

| 术语 | 含义 | 配置方式 | 灵活性 |
|------|------|---------|--------|
| **已暴露** | Dart Widget 提供了参数，Flutter 开发者可以在 Dart 代码中配置 | 写 Dart 代码（如 `isDark: true`） | 任何使用包的 Flutter 应用都可以自由配置 |
| **未暴露** | Dart Widget 没有提供参数，但 **HTML 中仍然可以直接使用** | 编辑 `mathlive_editor.html` | 只有修改包源码才能配置，改完后所有使用该包的应用行为一致 |

**重要**："未暴露"≠"不能用"。"未暴露"只意味着你不能从 Flutter 侧动态配置，但在 HTML 模板里直接写是完全可以的。

**举例**：
- `isDark` 已暴露 → 你可以在 Flutter 代码中写 `MathLiveEmbeddedEditor(isDark: true)`
- `layouts` 未暴露 → 你不能在 Flutter 代码中写 `MathLiveEmbeddedEditor(keyboardLayouts: [...])`，但你可以直接在 `mathlive_editor.html` 中写 `mathVirtualKeyboard.layouts = [...]`

---

## 六、当前设计的优缺点

### 6.1 优点

1. **封装良好**：Flutter 开发者无需了解 MathLive 的 Web Component API，通过 Dart 参数即可使用
2. **跨平台一致**：IO 平台（WebView）和 Web 平台（iframe）提供统一 API
3. **通信协议清晰**：postMessage 通道名集中管理（`MathLiveMixedChannels`）
4. **占位符机制**：`patchMathLiveEditorHtml()` 支持多实例共存（通过 `rootAndClientId`）
5. **防抖设计**：`onLatexChanged` 有 280ms 防抖，避免频繁回调
6. **回退方案**：`InlineTexMixedText` 提供无需 WebView 的轻量级渲染

### 6.2 缺点/限制

1. **Dart API 参数有限**：只暴露了 `isDark`、`theme`、`initialLatex` 等基础参数，MathLive 的大量能力未通过 Dart 参数暴露
2. **键盘布局使用默认值**：`mathVirtualKeyboard.layouts` 在 JS 中未设置，使用 MathLive 默认布局
3. **参数传递单向为主**：大部分参数从 Dart → JS，反向只有 `onLatexChanged` 和高度同步
4. **主题字段有限**：`MathLiveMixedTheme` 只有 5 个颜色字段，无法自定义字体、间距、边框等
5. **MathLive 版本锁定**：HTML 中硬编码 `mathlive@0.101.2`，升级需改源码
6. **网络依赖**：MathLive JS/CSS 从 jsDelivr CDN 加载，首次渲染需联网

---

## 七、自定义能力矩阵

| 自定义项 | 改 HTML 即可 | 需扩展 Dart API | 当前文件 | 改动位置 |
|---------|:-----------:|:--------------:|---------|---------|
| **虚拟键盘布局（layouts、fixedRows、variants）** | ✅ | 仅当需 Flutter 侧切换时 | mathlive_editor.html | JS: `mlMixedAttachVirtualKeyboard()` |
| **`<math-field>` CSS 样式** | ✅ | ❌ | mathlive_editor.html | CSS `<style>` |
| **`<math-field>` 属性（smart-mode、locale 等）** | ✅ | 仅当需运行时切换时 | mathlive_editor.html | HTML 标签属性 / JS |
| **键盘显隐行为（默认显示/手动切换）** | ✅ | 仅当需 Flutter 侧控制时 | mathlive_editor.html | JS: `mathVirtualKeyboard.show()` |
| **CSS 变量（`--primary`、`--caret-color` 等）** | ✅ | ❌ | mathlive_editor.html | CSS |
| **`::part()` 伪元素样式** | ✅ | ❌ | mathlive_editor.html | CSS |
| **右键菜单（menuItems）** | ✅ | 仅当需 Flutter 侧配置时 | mathlive_editor.html | JS |
| **快捷键映射（keybindings）** | ✅ | 仅当需 Flutter 侧配置时 | mathlive_editor.html | JS |
| **MathLive 版本/CDN 源** | ✅ | ❌ | mathlive_editor.html | `<script src="...">` |
| **编辑器颜色主题** | ✅ | ✅ 已暴露 | mathlive_mixed_theme.dart | Dart 参数 |
| **编辑器高度** | ✅ | ✅ 已暴露 | mathlive_embedded_editor.dart | Dart 参数 |
| **初始 LaTeX 内容** | ✅ | ✅ 已暴露 | mathlive_embedded_editor.dart | Dart 参数 |
| **预览文本样式** | ✅ | ✅ 已暴露 | mathlive_mixed_preview.dart | Dart 参数 |
| **onFocusChanged 回调** | ❌ | ✅ 需扩展 | mathlive_embedded_editor.dart + HTML | 新增 JS→Dart 通道 |
| **运行时切换 layouts** | ❌ | ✅ 需扩展 | mathlive_embedded_editor.dart + HTML | 新增 Dart→JS 函数 |
| **多格式导出（ASCII Math 等）** | ❌ | ✅ 需扩展 | mathlive_embedded_editor.dart + HTML | 新增 JS→Dart 通道 |
| **计算引擎** | ❌ | ✅ 需扩展 | mathlive_embedded_editor.dart + HTML | 新增 JS→Dart 通道 |

---

## 八、下一步行动建议

### 8.1 UI/交互自定义（改 HTML 即可）

这些只需要修改 `mathlive_editor.html`，不需要改 Dart 代码：

1. **自定义虚拟键盘布局**：在 `mlMixedAttachVirtualKeyboard()` 中设置 `mathVirtualKeyboard.layouts`（含 `fixedRows`、`variants`、`shift`、中文 label 等）
2. **修改 `<math-field>` CSS**：边框、聚焦样式、字号、padding 等
3. **键盘显隐行为**：是否默认显示、触发方式等
4. **`<math-field>` 属性**：`smart-mode`、`locale`、`placeholder` 等
5. **CSS 变量和 `::part()`**：颜色、光标、选区等视觉定制

### 8.2 需要扩展 Dart API 的场景

当需要**从 Flutter 侧动态控制**时才需要：

1. **新增 `keyboardLayouts` 参数**：让宿主可传入自定义布局（JSON 字符串）
2. **新增 `mathFieldOptions` 参数**：让宿主可设置 `<math-field>` 的属性
3. **新增 `onFocusChanged` 回调**：让宿主可监听聚焦状态（需新增 JS→Dart 通道）
4. **扩展 `MathLiveMixedTheme`**：添加更多样式字段
5. **新增事件通道**：`mode-change`、`move-out`、`selection-change` 等

### 8.3 底层功能自定义（如 fixedRows 滚动键盘）

`fixedRows` 是 `mathVirtualKeyboard.layouts` 中的配置项，属于 MathLive JS 层面的功能。实现路径：

1. **改 HTML 即可实现功能**：在 `mathlive_editor.html` 的 layouts 定义中添加 `fixedRows` 字段
2. **如果要让 Flutter 侧控制**：需要扩展 Dart API（新增参数 → 占位符替换或 `runJavaScript` 传递）

---

## 九、关键文件索引

| 文件 | 用途 | 何时修改 |
|------|------|---------|
| `assets/mathlive/mathlive_editor.html` | 编辑器 HTML 模板（含 CSS + JS） | **UI/交互/行为自定义的主文件** |
| `lib/src/editor/mathlive_embedded_editor.dart` | 内联编辑器 Widget | 需要新增 Dart 参数时 |
| `lib/src/editor/mathlive_editor_page.dart` | 全屏编辑器页面 | 需要新增 Dart 参数时 |
| `lib/src/editor/mathlive_editor_html_patch.dart` | HTML 占位符替换 | 需要新增占位符时 |
| `lib/src/config/mathlive_mixed_theme.dart` | 主题配置 | 需要扩展主题字段时 |
| `lib/src/config/mathlive_channels.dart` | 通信通道名 | 需要新增 JS↔Dart 通道时 |
| `lib/src/preview/mathlive_mixed_preview_html.dart` | 预览 HTML 构建器 | 需要自定义预览渲染时 |

---

## 十、总结

**核心结论**：修改 `mathlive_editor.html` 即可使用 MathLive 的**全部** API，包括 `layouts`、`fixedRows`、`smartMode`、`locale`、CSS 变量、`::part()` 等。不需要扩展 Dart API。

**何时需要扩展 Dart API**：只有当你需要**从 Flutter 代码动态控制**这些功能时（如运行时切换布局、监听事件回传 Flutter），才需要新增 Dart 参数和通信通道。

**推荐策略**：
1. **UI/交互自定义**→ 直接改 `mathlive_editor.html`
2. **需要 Flutter 侧动态控制** → 扩展 Dart API（新增参数 + JS 通信）
3. **底层功能（如 fixedRows）** → 先在 HTML 中实现功能，后续按需暴露 Dart 参数
