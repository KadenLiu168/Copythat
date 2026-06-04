## Why

当前浮层卡片的双击复制链路在心智上不连贯：用户必须先**单击**让卡片"变选中"（边框 4pt + 缩放 + 抬升），再**双击**才触发 `onPaste`。两步中只有第二步真正"做事"，第一步是 ceremony。鼠标党用户本能在卡片之间移动光标"看哪张想要"，却得不到任何视觉确认；想要复制必须先停下来点击、再双击。

本变更让"鼠标移到哪张卡 = 选中哪张"成立，用户即可在面板内**直接双击**复制/粘贴到目标 app，消除那次冗余的单击。

## What Changes

- `ClipboardCardView` 挂 `.onHover { if hovering { onSelect() } }`，悬停时调用既有 `onSelect` 闭包把 `store.selectedID` 写到该卡。
- 视觉上"hover == select"：复用现有 `isSelected` 渲染（4pt 描边、阴影、缩放 1.025、y -5），**不**新增第二种高亮态。
- 单击的行为升级为"hover 的强化版"：除 `onSelect()` 外保留 `makeFirstResponder(nil)`，让 Return 立即可用。
- 双击链路不变（`onPaste()` 读 `store.selectedItem`），但因 hover 已让 `selectedID` 跟着鼠标走，**双击悬停的卡 = 复制悬停的卡**，与用户直觉一致。
- 搜索框 focus 时 hover **不**调 `makeFirstResponder(nil)`，仅写 `selectedID`；双击才失焦 + 提交。
- 键盘 ←/→ 与 hover "互不干扰"：`store.selectedID` 单一 source of truth，谁后动听谁的。已知风险：键盘← 选中后手肘蹭鼠标会被抢回（已与用户确认接受）。
- 在 `panel-ui` spec 的"键盘导航"Requirement 增补 hover 选中 Scenario。

## Capabilities

### New Capabilities

无。

### Modified Capabilities

- `panel-ui`: 在"键盘导航"Requirement 追加"鼠标悬停立即选中"的行为条款与对应 Scenario，约束 hover 路径不抢焦、不影响键盘导航、不引入第二种高亮态。

## Impact

- 源码改动：`Sources/Copythat/Views/ClipboardCardView.swift`（在 `onTapGesture` 旁挂一个 `.onHover` 修饰符，约 3 行）。`BottomPanelView.swift` 不动——`onSelect` 闭包和 `selectedItem` 链路都已经在那里。
- Spec 改动：`openspec/specs/panel-ui/spec.md` 增补 Scenario。
- 依赖：无新增。
- 行为：纯交互增量，无功能、API、持久化、热键、权限、剪贴板写入路径变化。
- 风险：低。改动面积极小（1 个 SwiftUI 修饰符 + 1 个 spec Scenario）；最坏情况是 hover 不工作，回退到单击选中即可。已知 UX 风险（手肘蹭鼠标抢回键盘选中）已与用户确认接受。
- 性能：`@Published var selectedID` 在 hover 高频时会被反复写；SwiftUI 重绘只刷卡片描边/阴影/缩放，可接受。后续可加 50ms 节流，但本变更先不做。

## Non-goals

- 不引入第二种高亮态（hover 与 selected 共用视觉）。
- 不加设置项（默认行为；如未来需要，store 层加 1 个 Bool 即可）。
- 不改 footer 文案（footer 是键盘党提示，hover 是鼠标党发现式交互）。
- 不改 `BottomPanelView.onAppear` 的 `selectFirstVisibleItem()`——首次打开仍默认选中第一张。
- 不改 `onMoveCommand` / `onExitCommand` / Return / Esc 任何既有行为。
- 不改双击链路的语义（仍走 `PanelWindowController.pasteSelected()` 读 `store.selectedItem`）。
- 不做键盘← 后的 hover 保护窗（与用户确认接受"互不干扰"）。
- 不改卡片几何、间距、阴影、sourceAccent 算法。
- 不动 `split-font-styles-data-and-text` 变更的任何决定。
