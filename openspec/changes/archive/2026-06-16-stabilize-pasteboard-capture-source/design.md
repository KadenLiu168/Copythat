## Context

Copythat polls `NSPasteboard.general.changeCount` and currently reads clipboard content immediately after detecting a new count. The reported log shows a single ChatGPT copy action producing two observed pasteboard states: an intermediate state with ChatGPT source metadata but the previous Doubao text content, followed by the real ChatGPT text content.

The existing duplicate policy then removes an unpinned item with the same `contentKey` and inserts the newly captured item. That turns the transient "old content + new source" capture into a visible history mutation where the earlier Doubao card appears to become a ChatGPT card.

## Goals / Non-Goals

**Goals:**

- Avoid inserting transient pasteboard states from multi-step pasteboard writes.
- Preserve per-item source app and icon metadata when duplicate content is observed again.
- Keep same-content deduplication and pinned-item protection.
- Keep diagnostics payload-safe.

**Non-Goals:**

- Do not change source resolution heuristics.
- Do not add persistence fields or migrate saved history.
- Do not alter card layout or panel UI.
- Do not make different source apps bypass content deduplication.

## Decisions

1. Treat pasteboard content as readable only after the observed change count is stable across poll cycles.

   Rationale: macOS apps can publish pasteboard data in multiple observable steps. Waiting for the same change count to be seen twice avoids reading a stale or intermediate value while preserving the existing polling model.

   Alternative considered: add a fixed async sleep before every read. That is harder to test deterministically and can still race if another change lands during the sleep.

2. Update `lastChangeCount` only after a stable change count has been processed.

   Rationale: the current implementation updates `lastChangeCount` before reading. If the read catches a transient value, the store has already accepted that change as handled. Pending state should track observed counts separately from processed counts.

   Alternative considered: keep eager `lastChangeCount` updates and filter duplicates later. That would still allow wrong intermediate items to affect source snapshots and selection.

3. Return structured insertion results from `ClipboardHistoryPolicy`.

   Rationale: the store needs to know which item actually exists after policy application. A duplicate move should select the retained item, not the new item that was never inserted.

   Alternative considered: keep returning only `[ClipboardItem]` and have the store search afterward. That spreads policy knowledge across modules.

4. Preserve existing unpinned duplicate metadata instead of replacing it.

   Rationale: an item's source app, source icon, ID, and creation time describe when that content first entered history. Re-copying the same content should make the item newest without rewriting that context.

   Alternative considered: include source app in `contentKey`. That would create duplicate ordinary cards for identical content copied from different apps and weaken existing deduplication behavior.

## Risks / Trade-offs

- Stable-count capture adds up to one poll interval before a copied item appears -> accepted to avoid wrong history mutations.
- If an app leaves a stale pasteboard value stable before later updating it, the app could still capture stale content -> duplicate-source preservation prevents this from rewriting existing card source, and a later real change will still be captured.
- Moving existing duplicates instead of replacing them preserves the original timestamp -> acceptable because source context should remain historical, while item order still reflects recent activity.
