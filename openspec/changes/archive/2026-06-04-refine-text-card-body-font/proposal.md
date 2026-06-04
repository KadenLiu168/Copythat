## Why

The recent text card density improvement is working, but the text preview can still become more useful for quick scanning. The current preview body still uses the app-wide preferred font path, which may choose a code-oriented face and does not always give the best readability for mixed Chinese and English clipboard text.

## What Changes

- Refine only the text card body preview typography.
- Use a smaller, more readable system text face for text preview content so mixed Chinese and English text scans naturally on macOS.
- Increase text preview density slightly while preserving comfortable readability.
- Keep the existing selected-card scale and raised positioning behavior unchanged.
- Keep card size, timeline layout, header typography, source icon treatment, and non-text card previews unchanged.

## Non-goals

- Do not add a user-facing font or density setting.
- Do not introduce or bundle a new font dependency.
- Do not detect code snippets and switch fonts dynamically.
- Do not change clipboard capture, search, pinning, paste, or persistence behavior.
- Do not alter selected-card motion, card dimensions, or panel layout.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `panel-and-search`: Text history cards should use a compact, macOS-native readable body font for preview text.

## Impact

- Affected code: `Sources/Copythat/Views/ClipboardCardView.swift`.
- Affected specs: `openspec/specs/panel-and-search/spec.md`.
- No API, dependency, storage, permission, or app lifecycle changes.
