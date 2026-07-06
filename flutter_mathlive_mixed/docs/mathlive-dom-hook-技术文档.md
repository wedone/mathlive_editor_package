# MathLive DOM Hook 技术文档

## 一、什么是 DOM Hook 方法

DOM Hook（DOM 钩子）是一种**在不修改第三方库源码的前提下，通过操作库动态生成的 DOM 元素来注入自定义行为**的方法。

MathLive 在运行时会动态创建大量 DOM 元素（虚拟键盘、按键、变体面板等），这些元素带有特定的 CSS 类名（如 `ML__keyboard`、`MLK__scrollable-rows`）。我们利用这些类名作为"钩子"，通过 CSS 覆盖和 JS 事件拦截来定制行为。

### 核心思路

```
MathLive JS 渲染 → 生成带特定类名的 DOM → 我们用 CSS/JS "钩住"这些类名 → 注入自定义行为
```

### 适用场景

- 不方便直接修改 MathLive 源码（如使用 CDN 加载）
- MathLive 的公开 API 不足以实现需求
- 需要在 MathLive 渲染的 DOM 上叠加触摸交互逻辑

---

## 二、MathLive 内部 CSS 类名速查

MathLive 的 CSS 类名使用两种前缀，理解它们的命名规律是 Hook 的基础：

| 前缀 | 含义 | 示例 |
|------|------|------|
| `ML__` | MathLive 通用元素 | `ML__keyboard`、`ML__menu`、`ML__edit-toolbar` |
| `MLK__` | MathLive Keyboard 专属元素 | `MLK__plate`、`MLK__row`、`MLK__keycap` |

### 虚拟键盘 DOM 树结构

以下是 MathLive 渲染虚拟键盘后的完整 DOM 结构（使用 `fixedRows` 时）：

```
<body>
  └─ <div class="ML__keyboard is-visible">              ← 键盘根容器（position:fixed; bottom:0）
       └─ <div class="MLK__backdrop">                    ← 背景层
            └─ <div class="MLK__plate">                  ← 按键面板
                 └─ <div class="MLK__layer has-fixed-rows" id="layer_id">  ← 层（可切换）
                      ├─ <div class="MLK__toolbar">      ← 工具栏（布局切换标签等）
                      │    ├─ <div class="left">         ← 左侧：布局切换按钮
                      │    └─ <div class="ML__edit-toolbar right">  ← 右侧：撤销/重做等
                      ├─ <div class="MLK__rows MLK__scrollable-rows">  ← ★ 可滚动区域
                      │    ├─ <div class="MLK__row">     ← rows[0]
                      │    │    ├─ <div class="MLK__keycap">  ← 单个按键
                      │    │    ├─ <div class="separator">
                      │    │    └─ ...
                      │    ├─ <div class="MLK__row">     ← rows[1]
                      │    └─ ...                        ← rows[N]
                      └─ <div class="MLK__rows MLK__fixed-rows">     ← ★ 固定区域（不滚动）
                           └─ <div class="MLK__row">     ← fixedRows[0]
```

### 状态类名

| 类名 | 添加时机 | 添加者 |
|------|---------|--------|
| `is-visible` | 键盘/面板显示时 | MathLive `show()` |
| `is-pressed` | 按键被按下时 | MathLive `Gg(pointerdown)` |
| `is-active` | Shift 键激活 / variant 面板打开 | MathLive `Gg()` / `ys()` |
| `has-fixed-rows` | layer 包含 `fixedRows` 时 | MathLive `jg()` 渲染函数 |
| `is-visible`（variant） | variant 面板弹出时 | MathLive `ys()` |

---

## 三、本项目中的 DOM Hook 修改点

以下是 `mathlive_editor.html` 中所有 DOM Hook 修改点的索引：

### 修改点 #1：虚拟键盘外观（CSS 覆盖）

```css
body > .ML__keyboard.is-visible > .MLK__backdrop {
  box-shadow: none;
  border-top: none;
}
```

- **目标类**：`.ML__keyboard` / `.MLK__backdrop`
- **作用**：去掉键盘顶部的阴影和边框
- **风险**：低。纯视觉调整，不涉及交互逻辑

### 修改点 #2：fixedRows 滚动区域触摸行为（CSS 覆盖）

```css
.MLK__rows.MLK__scrollable-rows,
.MLK__rows.MLK__scrollable-rows .MLK__row,
.MLK__rows.MLK__scrollable-rows .MLK__row > div {
  touch-action: none;
}
```

- **目标类**：`.MLK__scrollable-rows` 及其子元素
- **作用**：禁用浏览器原生滚动，改由 JS 手动控制
- **原因**：`touch-action: pan-y` 会与 variant 面板的上划选择冲突
- **关联 JS**：`mlMixedFixScrollTouch()`

### 修改点 #3：自定义键盘布局（API 调用）

```js
mathVirtualKeyboard.layouts = [{
  label: '常用',
  layers: [{
    rows: [...],       // 可滚动行
    fixedRows: [...],  // 固定行（需要本地构建的 JS 支持）
  }]
}, 'numeric', 'symbols', 'greek'];
```

- **调用 API**：`mathVirtualKeyboard.layouts`（MathLive 公开 API）
- **作用**：配置 6 行可滚动 `rows` + 1 行固定 `fixedRows`
- **注意**：`fixedRows` 是源码级扩展，CDN 0.101.2 不支持，需本地构建

### 修改点 #4：触摸滚动事件拦截器（JS 事件拦截）

```js
scrollable.addEventListener('pointermove', function(e) {
  // variant 面板打开时不干预
  if (document.querySelector('.MLK__variant-panel.is-visible')) return;
  
  // 超过阈值 → 判定为滚动
  if (Math.abs(dy) > THRESHOLD) {
    isScrolling = true;
    // 移除 is-pressed 类，使 MathLive 的 pointerup 不触发命令
    scrollable.querySelector('.is-pressed')?.classList.remove('is-pressed');
  }
  
  // 阻止事件传播到 MathLive 的处理器
  e.preventDefault();
  e.stopPropagation();
  
  // 手动滚动（带 2x 增益）
  scrollable.scrollTop = startScrollTop - dy * SCROLL_GAIN;
}, { capture: true });
```

- **目标类**：`.MLK__scrollable-rows`
- **冲突类**：`.MLK__variant-panel.is-visible`
- **状态类**：`.is-pressed`
- **拦截阶段**：`capture: true`（先于 MathLive 的 bubble 阶段处理器）
- **关键技术点**：
  - 使用 `capture: true` 在 MathLive 之前接收事件
  - `stopPropagation()` 阻止事件到达 MathLive 的处理器
  - 移除 `is-pressed` 类而非派发 `pointercancel`（避免 WebView 停止 pointermove）

### 修改点 #5：键盘生命周期钩子（API 事件监听）

```js
mathVirtualKeyboard.addEventListener('geometrychange', function() {
  mlMixedNotifyHostChromeHeight();
  mlMixedFixScrollTouch();  // 重新绑定滚动事件
});
```

- **调用 API**：`mathVirtualKeyboard.addEventListener('geometrychange', ...)`
- **作用**：MathLive 重建键盘 DOM 后重新绑定事件监听器
- **原因**：`rebuild()` 会移除旧 DOM，之前绑定的事件监听器随之销毁

### 修改点 #6：右键菜单容器尺寸适配（CSS 覆盖）

```css
.ML__menu,
.ui-menu-container,
[role="menu"] {
  max-width: calc(100vw - 16px) !important;
  max-height: calc(100vh - 16px) !important;
  overflow: auto !important;
  box-sizing: border-box !important;
}
```

- **目标类**：`.ML__menu` / `.ui-menu-container` / `[role="menu"]`
- **作用**：限制菜单最大宽高，使其在窄屏 WebView 中不溢出
- **使用 `!important`**：需要覆盖 MathLive 内联样式

### 修改点 #7：菜单项文本换行（CSS 覆盖）

```css
.ML__menu [role="menuitem"],
[role="menu"] [role="menuitem"] {
  white-space: normal !important;
  word-break: break-word !important;
}
```

- **目标类**：`[role="menuitem"]`
- **作用**：允许菜单项文本自动换行，防止长文本（如中文标注）被截断
- **原因**：MathLive 默认 `white-space: nowrap`，中文文本会溢出

### 修改点 #8：触屏设备按键尺寸适配（CSS 变量覆盖）

```css
@media (pointer: coarse) {
  body {
    --keycap-height: 42px;
    --keycap-font-size: 17px;
    --keycap-gap: 4px;
    /* ... */
  }
}
```

- **目标**：通过 MathLive CSS 变量覆盖按键尺寸
- **作用**：在触屏设备上使用更小的按键高度，为 fixedRows 滚动留出更多空间
- **原理**：MathLive 内部使用 `var(--keycap-height)` 控制按键高度，覆盖这些变量即可全局调整

---

## 四、DOM Hook 的三种技术手段

### 手段 1：CSS 类覆盖

利用 CSS 的层叠优先级，覆盖 MathLive 内置样式。

```css
/* MathLive 内置 */
.MLK__rows.MLK__scrollable-rows { overflow-y: auto; }

/* 我们的覆盖（更具体的选择器 + !important） */
.MLK__rows.MLK__scrollable-rows .MLK__row > div {
  touch-action: none !important;
}
```

**技巧**：选择器越具体，优先级越高。必要时使用 `!important`。

### 手段 2：JS 事件拦截（capture 阶段）

DOM 事件传播分三个阶段：`capture → target → bubble`。MathLive 的处理器大多注册在 bubble 阶段。我们在 capture 阶段拦截，可以：

- `stopPropagation()`：阻止事件到达 MathLive 的处理器
- `preventDefault()`：阻止默认行为

```js
element.addEventListener('pointerdown', function(e) {
  // 在 MathLive 之前执行
  e.stopPropagation();  // 阻止 MathLive 的处理器
}, { capture: true });  // ← 关键：capture 阶段
```

### 手段 3：API 事件监听 + 重新绑定

MathLive 的 `rebuild()` 会销毁并重建 DOM。需要在 `geometrychange` 事件中重新绑定：

```js
mathVirtualKeyboard.addEventListener('geometrychange', function() {
  // DOM 已重建，重新绑定事件
  mlMixedFixScrollTouch();
});
```

---

## 五、MathLive 内部事件处理流程（逆向分析）

理解 MathLive 的内部事件流程是解决触摸冲突的关键。以下是逆向分析结果：

### pointerdown 流程

```
手指按下按键
  ↓
capture 阶段：
  我们的处理器（mlMixedFixScrollTouch）
  → 记录起始坐标和 scrollTop
  ↓
target 阶段：
  .MLK__layer 的处理器
  → e.preventDefault()  ← 阻止浏览器启动滚动手势
  ↓
bubble 阶段：
  .ML__keyboard 的 Gg() 函数
  → 添加 .is-pressed 类
  → 注册 pointerenter/pointerleave/pointerup 监听器
  → 如果有 variants：300ms 后弹出 variant 面板
  → e.preventDefault()
```

### pointerup 流程（正常点击）

```
手指抬起
  ↓
capture 阶段：
  我们的处理器
  → 如果 isScrolling：stopPropagation()，阻止后续处理
  → 如果 !isScrolling：放行，让 MathLive 处理
  ↓
bubble 阶段（仅 !isScrolling 时）：
  MathLive 的 Ms() 函数
  → 检查 .is-pressed 类是否存在
  → 存在：执行按键命令（insert/typedText 等）
  → 不存在：不执行任何操作
```

### variant 面板流程

```
长按按键 300ms
  ↓
MathLive 的 ys() 函数
  → 创建 .MLK__variant-panel
  → 添加 .is-visible 类
  → 添加 .is-active 到按键
  ↓
手指上划选择
  → pointerup 时检查选中的 variant 项
  → 执行对应的 insert 命令
```

---

## 六、踩坑记录

### 坑 1：`touch-action: pan-y` 与 variant 上划冲突

**现象**：设置了 `touch-action: pan-y` 后，variant 面板的上划选择失效，变成滚动键盘。

**原因**：`touch-action: pan-y` 让浏览器在 compositor 层直接处理垂直滚动，绕过了 JS 事件。浏览器无法区分"滚动键盘"和"选择 variant"。

**解决**：改用 `touch-action: none`，由 JS 手动控制滚动。variant 面板打开时不手动滚动，让 MathLive 正常处理上划选择。

### 坑 2：合成 `pointercancel` 导致 `pointermove` 停止

**现象**：在滚动开始时派发合成的 `pointercancel` 事件来取消按键按压，结果手指滑动只滚动了很小距离就停止。

**原因**：WebView 实现可能将合成的 `pointercancel` 视为真实取消信号，导致浏览器内部终止该 pointer 会话，后续 `pointermove` 不再派发。

**解决**：不派发 `pointercancel`，只移除 `is-pressed` CSS 类。MathLive 的 `pointerup` 处理器会检查 `r.classList.contains("is-pressed")`，如果不存在就不执行按键命令。

### 坑 3：`rebuild()` 销毁事件监听器

**现象**：切换键盘布局后，滚动功能失效。

**原因**：MathLive 的 `rebuild()` 会移除旧 DOM 并创建新 DOM，之前通过 `addEventListener` 绑定在旧 DOM 上的事件监听器随之销毁。

**解决**：在 `geometrychange` 事件回调中重新调用 `mlMixedFixScrollTouch()`。

### 坑 4：LaTeX 反斜杠转义

**现象**：键盘布局中 `'\frac'` 渲染为乱码。

**原因**：JavaScript 字符串中 `\f` 是换页符（form feed），不是字面反斜杠 + f。

**解决**：所有 LaTeX 命令中的反斜杠必须双写：`'\\frac'`。

---

## 七、如何新增一个 DOM Hook 修改

以"修改键盘按键的背景色"为例：

### 步骤 1：找到目标 CSS 类名

通过浏览器 DevTools 检查 MathLive 渲染后的 DOM：

```bash
# 在 Chrome DevTools Console 中执行
document.querySelector('.MLK__keycap')  // 找到按键元素
```

### 步骤 2：在 HTML 模板中添加 CSS 覆盖

在 `mathlive_editor.html` 的 `<style>` 标签中添加：

```css
/* ───── [DOM Hook 修改点 #N] 按键背景色 ───── */
/* 目标类：.MLK__keycap（MathLive 渲染的按键元素）
 * 作用：自定义按键背景色 */
.MLK__keycap {
  background: #f0f0f0 !important;
}
```

### 步骤 3：如需 JS 交互，添加事件拦截器

```js
/* ───── [DOM Hook 修改点 #N] 自定义按键交互 ───── */
function mlMixedFixKeycapStyle() {
  var keycaps = document.querySelectorAll('.MLK__keycap');
  keycaps.forEach(function(k) {
    if (k.dataset.mlMixedStyleFix === '1') return;
    k.dataset.mlMixedStyleFix = '1';
    // 添加自定义事件处理...
  });
}
```

### 步骤 4：在生命周期钩子中调用

```js
// 在 geometrychange 回调中重新调用
mathVirtualKeyboard.addEventListener('geometrychange', function() {
  mlMixedFixKeycapStyle();  // rebuild 后重新绑定
});
```

---

## 八、相关文件索引

| 文件 | 作用 |
|------|------|
| `assets/mathlive/mathlive_editor.html` | HTML 模板（所有 DOM Hook 修改的入口） |
| `lib/src/editor/mathlive_editor_html_patch.dart` | Dart 端 HTML 补丁（占位符替换 + JS 内联） |
| `lib/src/editor/mathlive_embedded_editor.dart` | IO 平台 WebView 编辑器 |
| `lib/src/editor/mathlive_editor_page.dart` | IO 平台全屏编辑器页面 |
| `lib/src/editor/mathlive_editor_web.dart` | Web 平台编辑器 |
| `assets/mathlive/mathlive.min.js` | 本地构建的 MathLive JS（含 fixedRows 源码级扩展） |
