## 1. 在卡片视图挂 onHover

- [x] 1.1 修改 `Sources/Copythat/Views/ClipboardCardView.swift`：在 `body` 的修饰符链中、`onTapGesture` 之前（或之后，等价）新增 `.onHover { hovering in if hovering { onSelect() } }`。不调 `makeFirstResponder(nil)`，不复用 `onTapGesture` 闭包。确认 4 个 SwiftUI 修饰符（`onTapGesture` / `onTapGesture(count: 2)` / `onDrag` / `onHover`）按视觉链顺序排列，不与现有动画 `.animation(.snappy(duration: 0.18), value: isSelected)` 冲突。

## 2. 验证

- [x] 2.1 运行 `swift build` 在仓库根目录，确认编译通过、无 warning 增量。
- [x] 2.2 启动 app 并按 `README.md` "Verify" 段手工验证六条 spec Scenario：
  - 悬停切换选中（卡片 B 替代 A）
  - 悬停快速来回抑制抖动（100ms 节流，无视觉跳动）
  - 双击悬停的卡 = 复制该卡
  - 搜索框 focus 时悬停不抢焦
  - 悬停后键盘 ← 移动
  - 拖动滚动 timeline（无残留副作用）
  - 浮层关闭后再次打开（`onAppear` 覆盖）
- [x] 2.3 运行 `script/verify_all.sh`，确认既有 paste-decision 校验仍通过；本次变更未触碰 paste 路径，预期无差异。

## 3. 修复：hover 路径 100ms 节流

- [x] 3.1 `Sources/Copythat/Stores/ClipboardStore.swift` 新增 `lastHoverSelectAt: Date?` 与 `hoverSelectInterval: TimeInterval = 0.1` 私有状态，公开 `selectFromHover(_:)` 入口：100ms first-wins 节流后写 `selectedID`。`select(_:)` 不动。
- [x] 3.2 `Sources/Copythat/Views/ClipboardCardView.swift` 新增 `onHoverSelect: () -> Void` prop；`.onHover` 改调 `onHoverSelect()`。
- [x] 3.3 `Sources/Copythat/Views/BottomPanelView.swift` 卡片构造点注入 `onHoverSelect: { store.selectFromHover(item) }`。
- [x] 3.4 重新 `swift build` + `script/verify_all.sh` 回归通过。

## 4. 修复：scrollTo 不响应 hover 引起的 selectedID 变化

- [x] 4.1 `Sources/Copythat/Stores/ClipboardStore.swift` 新增公开 `var lastUserSelectAt: Date?`。`select(_:)` / `moveSelection(_:)` / `selectFirstVisibleItem()` / `add(_:)` / `remove(_:)` 在写 `selectedID` 之前设 `lastUserSelectAt = Date()`。`selectFromHover(_:)` 保持不设。
- [x] 4.2 `Sources/Copythat/Views/BottomPanelView.swift` `onChange(of: store.selectedItem?.id)` 检查 `now.timeIntervalSince(store.lastUserSelectAt ?? .distantPast) < 0.3`：是则 `proxy.scrollTo`，否则跳过（hover 引起的变化不滚）。
- [x] 4.3 重新 `swift build` + `script/verify_all.sh` 回归通过。

