## Context

Text card previews currently use `CopythatFont.font(size: 14.5, weight: .regular)`, which routes through the app-wide preferred font helper before falling back to the system font. That helper is useful for the app's stylized chrome, but a text preview is a reading surface that must handle mixed Chinese, English, command snippets, and prose at a small card size.

## Goals / Non-Goals

**Goals:**

- Make text card previews slightly smaller and easier to read.
- Prefer the native macOS text font for preview body content.
- Keep the previous readability improvements: no early fade mask and compact line spacing.
- Preserve selected-card scale and raised positioning.

**Non-Goals:**

- No bundled fonts or new dependencies.
- No dynamic language or code-snippet font detection.
- No changes to app-wide `CopythatFont` behavior outside text preview body content.
- No changes to card size, timeline layout, header typography, or non-text card previews.

## Decisions

- Use SwiftUI's system font for text preview body content instead of `CopythatFont`.
  - Rationale: system text rendering provides the most reliable macOS-native fallback for mixed Chinese and English, including PingFang for Chinese where appropriate. It also avoids applying a code-oriented preferred font to normal prose.
  - Alternative considered: replace the app-wide preferred font. That would affect unrelated chrome and is too broad for this request.
  - Alternative considered: bundle a new font. That adds dependency and packaging work for a narrow preview-body issue.
- Target a smaller preview size of about 13pt.
  - Rationale: 13pt improves density over 14.5pt while keeping Chinese text readable with the native macOS text font in a compact panel card.
  - Alternative considered: 12.5pt. That may show more text but risks looking too light and compressed on high-density mixed-language content.
- Raise the preview line limit to around 10 lines while keeping tight line spacing.
  - Rationale: the previous removal of the fade mask made all visible lines readable; the smaller font can safely expose one more line.

## Risks / Trade-offs

- The body preview may feel less branded than surrounding chrome -> keep `CopythatFont` for headers, labels, and footer metadata.
- Smaller text may be harder for some users -> choose 13pt rather than a more aggressive sub-13pt treatment.
- Command snippets may look less aligned without a monospace font -> prioritize general mixed-content readability for this iteration.
