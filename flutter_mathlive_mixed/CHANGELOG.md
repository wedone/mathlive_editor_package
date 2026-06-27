## 0.2.0

- Upgrade MathLive from 0.101.2 to 0.110.0 (XSS fix, virtual keyboard improvements, LaTeX mode Space completion, scientific notation support, and more).
- Update CDN paths to match 0.110.0 package layout (no `dist/` prefix).

## 0.1.2

- README: user-focused docs; removed internal publishing and Rodha migration sections.

## 0.1.1

- Sync repository URLs with GitHub; publish after `mathlive_studio` rename.

## 0.1.0

- Initial release as `mathlive_studio`: `MathLiveMixedPreview`, `MathLiveEmbeddedEditor`, `MathLiveEditorPage`.
- Utilities: `textUsesMathLivePreview`, `normalizeInlineMath`, `parsePreviewParts`.
- Fallback: `InlineTexMixedText`, `buildSimpleLatexInline`.
- MathLive 0.101.2 via jsDelivr; bundled `mathlive_editor.html`.
- Example app with Preview and Editor tabs.
