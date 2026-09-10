# AGENTS.md

## 1. Project Context

Copythat is a native macOS clipboard history application.

Core capabilities:

* Menu bar resident application
* Global shortcut activation
* Floating clipboard panel
* Clipboard history management
* Search and filtering
* Pinboard management
* Text, URL, image, and file capture
* Restore clipboard content and paste back to previous applications

Tech stack:

* Swift
* SwiftUI
* AppKit
* Swift Package Manager
* macOS 14+

---

## 2. Design Principles

### Native macOS First

* Prefer SwiftUI native components and macOS system behaviors.
* Follow Apple Human Interface Guidelines.
* Avoid unnecessary custom UI frameworks.

### Separation of Concerns

Keep boundaries clear:

* SwiftUI Views:

  * UI rendering
  * User interactions
  * State presentation

* Services / Support:

  * Clipboard monitoring
  * Pasteboard parsing
  * Source application tracking
  * Paste execution
  * Window management
  * macOS API integration

### Preserve Domain Concepts

Use real macOS clipboard terminology:

* pasteboard
* clipboard
* copy
* paste
* source application

Do not rename concepts only for abstraction purposes.

---

## 3. Architecture Constraints

Important components:

* Clipboard capture layer

  * Detect pasteboard changes
  * Extract supported content types
  * Track source application

* History layer

  * Store clipboard items
  * Support search
  * Support pinning

* Source attribution

  * Maintain `ClipboardItem.sourceApp`
  * Maintain `sourceAppIconData`
  * Keep source tracking logic centralized

* Paste flow

  * Validate target application
  * Preserve safety checks
  * Avoid sending paste events without valid targets

---

## 4. Code Modification Rules

Before changing code:

1. Understand existing architecture.
2. Identify ownership of the behavior.
3. Modify the smallest possible scope.
4. Avoid unrelated refactoring.

Do not:

* Move logic into Views.
* Duplicate clipboard handling logic.
* Introduce unnecessary abstractions.
* Change public behavior without tests.

For bugs:

* Reproduce first.
* Add diagnostics if needed.
* Fix the root cause instead of adding workarounds.

---

## 5. Clipboard Specific Rules

Clipboard behavior is sensitive.

When modifying clipboard logic:

Check:

* pasteboard change-count ordering
* duplicate detection
* source application attribution
* same-content handling
* race conditions between copy events

Diagnostics must:

* Avoid logging raw clipboard content.
* Prefer metadata:

  * source
  * content length
  * digest
  * identifiers
  * timing information

---

## 6. Testing Strategy

Required validation:

Build:

```bash
swift build
```

Full verification:

```bash
./script/verify_all.sh
```

Manual verification areas:

* Clipboard capture
* Floating panel behavior
* Search
* Pinboard
* Restore content
* Automatic paste flow
* Accessibility permission handling
* Multi-display behavior

---

## 7. Git Workflow

* Keep commits focused.
* One logical change per commit.
* Avoid mixing refactoring with feature changes.
* Verify locally before committing.

Commit messages should explain:

* What changed
* Why it changed

---

## 8. Agent Workflow

For every task:

1. Inspect current implementation.
2. Explain current behavior.
3. Identify root cause or required change.
4. Propose minimal solution.
5. Implement.
6. Run verification.
7. Summarize changes and risks.

For reviews:

Perform adversarial review:

* Challenge assumptions.
* Look for race conditions.
* Check lifecycle issues.
* Check macOS permission edge cases.

---

## 9. Do Not

Do not:

* Replace native macOS behavior with generic solutions.
* Add dependencies without strong justification.
* Store unnecessary user clipboard data.
* Log sensitive clipboard contents.
* Ignore permission/security implications.
* Fix symptoms without understanding the cause.

---

## 10. Common Commands

Build:

```bash
swift build
```

Run:

```bash
./script/build_and_run.sh
```

Verify:

```bash
./script/verify_all.sh
```

Clipboard diagnostics:

```bash
defaults write local.copythat.clipboard clipboardDiagnosticsEnabled -bool true
```

Disable:

```bash
defaults delete local.copythat.clipboard clipboardDiagnosticsEnabled
```
