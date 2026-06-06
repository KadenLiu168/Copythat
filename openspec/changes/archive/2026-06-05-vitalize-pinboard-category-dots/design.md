## Context

The bottom-panel command bar renders each non-Clipboard pinboard color as a low-opacity short capsule with a white highlight. Against the panel's warm glass tint, this treatment reduces color separation and makes the markers feel muted. Pinboard color selection and persistence are owned by the `add-colored-pinboard-creation` change; this change only refines marker presentation.

## Goals / Non-Goals

**Goals:**

- Make pinboard categories immediately distinguishable with vivid circular markers.
- Preserve each pinboard's configured color across Aqua and Dark Aqua.
- Preserve the existing compact command-bar layout and selected-filter treatment.

**Non-Goals:**

- Change user-configurable or persisted pinboard colors.
- Change pinboard identity, ordering, filtering, or settings behavior.
- Redesign other panel surfaces.

## Decisions

### Render simple opaque circular markers

Non-Clipboard filters use compact circles with strong opacity in both selected and unselected states. The existing white highlight is removed because it lightens the small marker and reduces perceived saturation. The circle uses the configured pinboard color without replacing it with an order-based or system color.

Selection remains communicated by the filter background, border, and text weight rather than by materially muting or enlarging the marker. This keeps category identity stable while preserving the existing interaction hierarchy.

## Risks / Trade-offs

- [Vivid dots could compete with selected clipboard cards] -> Keep the dots compact and leave selection emphasis on the existing subtle filter treatment.
- [Configured colors could repeat] -> Keep category names visible and treat color as a supporting identifier.
