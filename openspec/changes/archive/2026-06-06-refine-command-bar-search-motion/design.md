## Context

`BottomPanelView` currently renders search, pinboard filters, and add-pinboard as a centered command group. Pinboard filters use a 26-point visible pill, while the compact search and add controls use a 32-point visible rounded rectangle. The expanded search field also uses a 32-point visible height.

Search expansion is currently implemented by switching between compact and expanded view branches. The state change is animated, but the background shape and content do not share one continuous container, so the transition reads as a hard replacement.

## Goals / Non-Goals

**Goals:**

- Give search, pinboard filters, and add-pinboard the same 26-point visible control height.
- Preserve approximately 32-point hit areas for compact icon controls.
- Make search expansion feel continuous by animating one trailing-anchored pill from compact width to expanded width.
- Use a smooth 0.22-second motion with no rebound.
- Fade search text and the clear button in after the pill begins expanding.

**Non-Goals:**

- Change search matching, filtering, submission, or clear-button semantics.
- Change command-bar horizontal spacing, pinboard ordering, or add-pinboard behavior.
- Introduce a reusable animation framework or new dependency.

## Decisions

### Use one visible command-control height

Visible command controls use a shared 26-point height and 10-point continuous corner radius, matching the current pinboard filter shape. The outer layout remains 32 points tall where needed so search and add retain a comfortable pointer target.

Increasing pinboard filters to 32 points was considered, but it would make the entire command bar heavier and move away from the compact panel style.

### Animate one search container instead of swapping controls

Search renders as one trailing-aligned container whose width changes between compact and expanded states. The magnifying-glass icon remains inside that container and moves with the left edge as the pill opens, while the right edge stays fixed to preserve the no-layout-shift behavior.

Keeping separate `if` branches was considered, but that is the source of the current abrupt transition.

### Use delayed content fade for search text

The text field and clear button only become interactive and visible when search is expanded or contains text. Their opacity is animated with the same smooth curve and a short delay on expansion so content does not appear before the pill has visually opened.

Animating the text field width independently was considered, but it would add complexity without improving the user-visible motion.

## Risks / Trade-offs

- [A 26-point expanded field can feel tight] -> Keep the current text size and verify Aqua/Dark Aqua rendering before accepting the change.
- [Delayed content fade could make typing feel late] -> Focus the field immediately after expansion while keeping the visual fade short.
- [Compact icon controls could feel harder to click] -> Keep the 32-point outer hit area while shrinking only the visible background.
