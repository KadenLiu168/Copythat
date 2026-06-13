## Why

Ultra-wide image history cards can render an unstable preview region and crop most of the captured image, making the card header appear broken and the preview unusable. The card needs an explicit content-region boundary and a proportional full-image preview so image aspect ratio cannot affect the header presentation.

## What Changes

- Constrain every card content section to the fixed space below the existing header and clip preview overflow at that boundary.
- Render image-card previews proportionally within that content section without cropping the captured image.
- Preserve the existing card size, header structure, source icon, image-detail badge position, and non-image preview designs.

## Non-goals

- Do not redesign the card header or timeline.
- Do not move or restyle the image-detail badge.
- Do not change clipboard capture, image data, card dimensions, selection effects, or non-image preview implementations.

## Capabilities

### New Capabilities

### Modified Capabilities

- `panel-and-search`: Require image-card previews to remain inside the card content region, leave the header fully visible, and show the complete image proportionally.

## Impact

- Affected code is limited to `Sources/Copythat/Views/ClipboardCardView.swift`.
- No model, service, dependency, persistence, or API changes are required.
- Verification includes `swift build`, `swift test`, `./script/verify_all.sh`, and a panel UI check with an ultra-wide image.
