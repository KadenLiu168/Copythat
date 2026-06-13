## Context

The Settings clear-cards confirmation is a small destructive dialog with two choices: clear the default protected set or clear everything. The current copy is accurate but long, especially the default action label, which creates visual weight and makes the dialog feel more complex than the underlying decision.

## Goals / Non-Goals

**Goals:**

- Make the clear-cards confirmation faster to scan.
- Keep both clear choices visible and explicit.
- Define "Regular Cards" in the dialog so the default action remains clear.
- Avoid introducing "Unsaved" as a concept because it can be confused with persistence rather than pinned or pinboard state.

**Non-Goals:**

- No behavior changes to clearing predicates, persistence, selection refresh, or disabled states.
- No layout redesign of Settings.
- No new settings, toggles, or secondary flows.

## Decisions

- Use "Clear cards?" as the title.
  - Rationale: the dialog already appears from a clipboard-card section; the shorter title is enough context.
  - Alternative considered: keep "Clear clipboard cards?". Accurate, but longer without adding useful decision context.

- Use "Clear Regular Cards" for the default action.
  - Rationale: it is short enough for a button and avoids the new, ambiguous "Unsaved" concept.
  - Alternative considered: "Clear Unpinned and Uncategorized Cards". Precise, but too long for the primary button.

- Define regular cards in the message: "Regular cards exclude pinned cards and cards in pinboards."
  - Rationale: the message carries the rule while the button remains short.
  - Alternative considered: omit the message. That would make "Regular Cards" too vague for a destructive action.

## Risks / Trade-offs

- "Regular Cards" is still a new phrase -> mitigate by defining it in the same confirmation dialog.
- Shorter copy may be less explicitly exhaustive than the old button label -> keep the clear-all option unchanged and preserve destructive styling.

## Migration Plan

No migration is required. This is a user-facing string update only.

## Open Questions

None.
