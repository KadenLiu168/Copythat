## 1. Header Command Bar Implementation

- [x] 1.1 Refine `BottomPanelView` header spacing and grouping so search, pinboard filters, and add/settings read as three stable command bar areas; verify default header alignment manually.
- [x] 1.2 Restyle the pinboard strip as a light rounded grouped control with lower-contrast selected state; verify selected and unselected filters remain clear.
- [x] 1.3 Restyle search and add/settings controls with matching compact hover, pressed, and focus feedback; verify search expansion and add/settings action still work.
- [x] 1.4 Split `Clipboard` into the left search cluster and center only secondary pinboards with roomier spacing; verify the header remains balanced.
- [x] 1.5 Refine category color markers from circular dots into lower-noise rounded color chips; verify color classification remains visible.

## 2. Verification

- [x] 2.1 Run `swift build` and fix any compile issues.
- [x] 2.2 Run `./script/verify_all.sh` and confirm existing automated checks still pass.
- [x] 2.3 Review the final diff to ensure changes stay scoped to OpenSpec artifacts and the top header UI.
- [x] 2.4 Re-run `swift build`, `./script/verify_all.sh`, and OpenSpec validation after the secondary layout adjustment.
- [x] 2.5 Re-run `swift build` and `./script/verify_all.sh` after marker refinement.
