## Context

Copythat 浮层（`BottomPanelView`）目前把"选中"完全交给 `ClipboardStore.selectedID`，由三类入口写入：

| 入口 | 当前行为 | 来源 |
|------|----------|------|
| `onAppear` | `store.selectFirstVisibleItem()` | `BottomPanelView.swift:25` |
| 搜索文本变化 | `store.selectFirstVisibleItem()` | `BottomPanelView.swift:28` |
| 卡片单击 | `store.select(item)` + 搜索框失焦 | `ClipboardCardView.swift:45-48` |
| 键盘 ←/→ | `store.moveSelection(±1)` | `BottomPanelView.swift:36-45` |

视觉态由 `isSelected` 单一 prop 驱动：4pt 描边、`sourceAccent` 阴影、缩放 1.025、y -5（`ClipboardCardView.swift:37-42`）。双击链路走 `onPaste()` 闭包，闭包最终调 `PanelWindowController.pasteSelected()` 读 `store.selectedItem`——也就是说，**双击任何卡片都复制"当前 selectedID"对应的卡片**，与"双击哪张"无关。

`store.selectedID` 在 `LazyHStack` 的 `ForEach` 中作为 `isSelected` 的判定：`item.id == store.selectedItem?.id`（`BottomPanelView.swift:260`）。SwiftUI 会在 `selectedID` 变化时重绘所有相关卡片，但卡片几何 + 描边 + 阴影的渲染成本很低。

约束（来自 `CLAUDE.md` 衍生约定）：
- `Views/` 内禁止 AppKit 边界（`NSPasteboard` / `CGEvent` / `NSTrackingArea`）；本变更仅用 SwiftUI 声明式修饰符，**不**新增 AppKit 调用，符合约束。
- 真实领域术语保留：hover 选中的目标仍是"卡片" / "paste 提交"，文案不重写。

## Goals / Non-Goals

**Goals:**
- 在卡片层加 1 个 SwiftUI 修饰符（`.onHover`），让"鼠标移到哪张 = 选中哪张"成立。
- 不引入第二种高亮态；不引入新的"hover" prop。
- 不动 `store` 层 API 表面（`select(_:)` 闭包已存在）。
- 不动键盘、Return、Esc、右键菜单、拖拽、footer 文案、卡片几何。
- 在 `panel-ui` spec 的"键盘导航"Requirement 增补一条 Scenario 锁住 hover 行为。

**Non-Goals:**
- 不加键盘← 后的 hover 保护窗（用户已确认接受"互不干扰"）。
- 不加节流 / 防抖（性能可接受；如未来 hover 抖动再加 50ms throttle，1 行代码）。
- 不加 setting 开关（默认行为；如未来需要，store 加 1 个 `Bool` 即可）。
- 不重写双击链路（`onPaste` 读 `store.selectedItem` 的契约保持不变；hover 改 `selectedID` 即可让"双击悬停卡 = 复制悬停卡"成立）。
- 不重写 `selectFirstVisibleItem()` 行为。
- 不动 `split-font-styles-data-and-text` 的任何决定。

## Decisions

### D1：用 SwiftUI `.onHover` 而非 `NSTrackingArea`

`NSTrackingArea` 是 AppKit 边界，按约定应在 `Services/`。把 tracking 拉过去要写 `NSViewRepresentable` 包装层，跨 4 个文件，付出与本变更体量严重不匹配。

SwiftUI `.onHover { hovering in ... }` 由 view 内部的 tracking area 自己管理，NSPanel 默认可用——`PanelWindowController` 把 panel 设为 `acceptsMouseMovedEvents` 的等价物（panel 是 `canBecomeKey == true` 且默认会接收 `mouseEntered` / `mouseExited` / `mouseMoved` 经由 NSWindow 的 tracking）。**不需要触碰 AppKit。**

考虑过的替代：
- ❌ `NSViewRepresentable + NSTrackingArea`：超出体量。
- ❌ `NSEvent.addLocalMonitorForEvents(matching: .mouseMoved)`：要写到 `Services/`，要管订阅生命周期，要管 panel 关闭时反订阅，得不偿失。
- ✅ SwiftUI `.onHover`：3 行代码，无新边界。

### D2：调既有 `onSelect` 闭包，不直写 `store`

`ClipboardCardView` 已经接受 `onSelect: () -> Void`（`BottomPanelView.swift:263` 注入 `store.select(item)`）。新增 `.onHover` 直接调 `onSelect()`，**不**绕过 closure——这样保持 `BottomPanelView` 仍是"卡片不知道 store"的不变式，未来要把 panel 嵌进其他容器也无需改卡片。

### D3：hover 不调 `makeFirstResponder(nil)`

现有单击路径里有 `NSApp.keyWindow?.makeFirstResponder(nil)`（`ClipboardCardView.swift:47`），目的是让单击后 Return 立即可用。如果 hover 也走这步，搜索框正在输入时鼠标一过就失焦，破坏输入连续性。

拆分语义：
- **hover** = "我想看这张卡" → 只写 `selectedID`
- **单击** = "我想用这张卡" → 写 `selectedID` + 失焦（让 Return 提交）
- **双击** = "提交" → 走 `onPaste`，本身已经失焦 + 关闭

### D4：单层 `onHover` 修饰符，不嵌套 hover 状态

不在卡片里维护 `isHovered` 本地 `@State`，不引入第二种视觉态（hover 不再有自己的描边/缩放）。所有视觉反馈走既有 `isSelected` 路径。`onHover` 仅做"写入 store"这一副作用。

理由：
- 引入第二种高亮会让"hovered 卡的视觉 ≠ selected 卡的视觉"产生认知成本。
- 现在 selected = hover 共用 4pt 描边，最强对比来自"被选中"，是单一权威态。
- 单层 `onHover` 不需要任何本地状态，0 个 `@State` 增量。

### D5：hover 走专用 `selectFromHover` 入口，与 `select(_:)` 解耦

`store.select(_:)`（`ClipboardStore.swift:88-90`）仍只做"覆盖写"，保持纯语义，被单击 / 键盘 / 搜索 onAppear 共用——无任何守卫。

新增 `store.selectFromHover(_:)` 专供 hover 路径，写入前先检查 `lastHoverSelectAt`：
- 窗口（100ms）外：写入并刷新时间戳
- 窗口内：直接 return（first-wins）

为什么不直接用 `select(_:)` + 闭包节流：节流要"全局视角"才能正确处理"A → B → A"快速来回——把节流放在 view 层的 `@State` 上是 per-card 状态，跨卡节流失效；放在 `BottomPanelView` 上要新增 @State 闭包。放在 store 层的"专门入口"是唯一既能全局节流、又不污染 `select(_:)` 语义的位置。键盘 / 单击路径完全无感。

100ms 的取值：snappy 动画时长 180ms，节流 100ms 后 hover 切换最少 100ms 才"允许"下一次切换，落在人类感知阈值（~150ms）下方，仍是"立即跟手"。如果未来反馈"延迟感"再降到 60ms。

## Risks / Trade-offs

[R1] **手肘蹭鼠标抢回键盘选中** → 已与用户确认接受。如未来反馈，方案：在 `store` 加 `lastKeyboardNavAt: Date?`，hover 调用前 `if now.timeIntervalSince(lastKeyboardNavAt ?? .distantPast) > 0.8` 守卫。1 个属性 + 1 个 if 分支。

[R2] **高频 hover 写 `@Published selectedID`** → 触摸板快速划过会让 `selectedID` 短时间内被写 N 次，触发 N 次 SwiftUI 重绘 + `snappy(0.18s)` 动画反复启动，视觉上像"卡片左右抖动"。**实装时已修复**：在 `ClipboardStore` 加 `selectFromHover(_:)` 入口，100ms first-wins 节流（仅 hover 路径，不影响 `select(_:)` / `moveSelection(_:)`）。`lastHoverSelectAt` 拦截窗口内的事件；`selectFromHover` 走与 `select(_:)` 相同的"写 `selectedID`"路径，复用既有动画与视觉态。

[R6] **hover 触发的 `selectedID` 变化带动 `ScrollView` 自动滚动** → 第一次手工验证（tasks 2.2）发现 100ms 节流后仍"左右快速滑动"：根因不是动画抖动，而是 `BottomPanelView:onChange(of: store.selectedItem?.id)` 监听 `selectedID` 变化并 `withAnimation(.snappy(0.18)) { proxy.scrollTo(id, anchor: .center) }`——hover 让 `selectedID` 跳到 Card4 → ScrollView 试图把 Card4 滚到中心 → 卡片视觉上被"推着走"。**实装时已修复**：`ClipboardStore` 暴露 `lastUserSelectAt: Date?`（普通 `var`），仅在 `select(_:)` / `moveSelection(_:)` / `selectFirstVisibleItem()` / `add(_:)` / `remove(_:)` 写 `selectedID` 之前设。`selectFromHover(_:)` 保持不设。`BottomPanelView` 的 `onChange` 检查 `now.timeIntervalSince(lastUserSelectAt ?? .distantPast) < 0.3`，是则 `scrollTo`，否则跳过。键盘 / 单击 / 复制 / 删除 → 滚；hover → 不滚。

[R3] **NSPanel 关闭后残留 hover 状态** → SwiftUI `.onHover(false)` 在 view 离屏时会自动触发，但 panel `orderOut` 时整个 view 树销毁，无残留。`selectedID` 保持为最后悬停卡的 id，下次 panel 打开 `selectFirstVisibleItem()` 覆盖。

[R4] **LazyHStack 滚动时 hover 跟踪** → SwiftUI 的 hover tracking 跟 view 的可见性挂钩。滚动出视野的卡片 view 会被 `LazyHStack` 复用/销毁，其 `onHover(false)` 会在 view 销毁前触发。即使时序异常（view 销毁但 `onHover(false)` 未触发），`store.selectedID` 保留为旧值也不影响——`BottomPanelView.onAppear` 调 `selectFirstVisibleItem()` 会覆盖。

[R5] **NSTrackingArea 的 mouseEntered / mouseExited 风暴** → SwiftUI 内部去重；同一 view 上一次只持有一个 hover 状态。空 hover 间不会写 store。

## Migration Plan

- 部署：单文件 diff（`ClipboardCardView.swift` 加 3 行 + spec.md 增 1 个 Scenario）。无 schema、无持久化、无用户设置变化。冷启动即可生效，无需迁移。
- 回滚：`git revert` 单 commit。卡片回到"单击选中 + 双击粘贴"原状，零数据风险。
- 验证：
  1. `swift build` 通过（编译期保证）。
  2. 手工：打开浮层 → 鼠标划过 5 张卡 → 每张依次高亮 → 双击悬停的卡 → 浮层关闭 + 目标 app 收到内容。
  3. 手工：搜索框输入 "git" → 鼠标移到一张卡上 → 搜索框仍能继续输入 → 双击悬停的卡 = 复制该卡。
  4. 手工：键盘← 选中 → 手肘蹭鼠标 → 选中跳到手肘方向（已知 UX，已接受）。
  5. 手工：单击卡 → 搜索框失焦 → Return 提交（既有行为不变）。
- 不需要新增 `Tests/CopythatTests/*` 单元测试（hover 是纯 SwiftUI 声明式，无业务逻辑可断言）；视觉/交互靠手工 verify。

## Open Questions

无。设计已与用户全部对齐。
