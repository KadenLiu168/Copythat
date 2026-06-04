## Why

当前 Copythat 在双击卡片或按 Return / Enter 时，会调用 `ClipboardPastePerformer.paste()`：先把条目写回系统剪贴板，然后激活目标 app，等待 350 ms 后用 `CGEvent.post(tap: .cghidEventTap, ...)` 注入 `⌘V`。这条路径的副作用是每次触发都会调用 `AccessibilityService.requestIfNeeded()` —— 当 macOS TCC 数据库中当前二进制的 cdhash 不在白名单时（即 ad-hoc 签名漂移场景），系统会再次弹"辅助功能访问"授权框，但用户在系统设置里看到的又是另一条已存在的旧记录，造成"每次都有这个问题"的体验。

**用户选择的根本方案是产品语义层面的**：把双击 / Enter 的默认语义从"自动粘贴到当前 app"改成"选中并写入系统剪贴板"，让用户自己切到目标 app 按 `⌘V`。Accessibility 权限仍然保留（用于 `CopySourceTracker` 的 CGEventTap 高精度来源追踪），但**粘贴路径不再主动触发授权弹窗**。

## What Changes

### 用户可见行为

- **默认（`autoCopyOnSelect = false`）**：
  - 单击 / 方向键 / 拖拽：只切换选中态，不写剪贴板
  - 双击 / Enter：把当前卡片写入系统剪贴板，**不**激活目标 app，**不**发送 `⌘V`
  - 浮层**立即**关闭（与 ON 模式行为一致，predictable）
  - 右键菜单项：`Paste` → `Copy to Clipboard`
- **`autoCopyOnSelect = true`（可切换）**：
  - 单击 / 方向键：选中即写剪贴板
  - 双击 / Enter：写剪贴板 + 激活目标 app + 发送 `⌘V`（与现状一致）
  - 浮层立即关闭
  - 右键菜单项：`Paste`（保持现状）
- **Accessibility 弹窗时机**：从"每次粘贴都可能被弹"改为"应用启动时一次"

### 代码层

- 新增 `AppSettings.autoCopyOnSelect: Bool`（默认 `false`），持久化到 `UserDefaults`
- `Sources/Copythat/Services/ClipboardPastePerformer.swift`：根据 `autoCopyOnSelect` 分叉到两条执行路径；默认路径移除 `CGEvent` 注入代码
- `Sources/Copythat/Services/AccessibilityService.swift`：行为不变（仍提供 `isTrusted` 与 `requestIfNeeded()`），但调用点收窄
- `Sources/Copythat/Sources/Copythat/App/AppDelegate.swift`：在 `applicationDidFinishLaunching` 调一次 `AccessibilityService.requestIfNeeded()` 引导授权
- `Sources/Copythat/Views/SettingsView.swift`：新增 `autoCopyOnSelect` 开关，置于 "General" 区
- `Sources/Copythat/Views/ClipboardCardView.swift`：双击由 `onPaste` 改为 `onSelect`（仅手势回调变化）
- `Sources/Copythat/Services/PanelWindowController.swift`：`CopythatPanel.handleKeyEvent` 中 `kVK_Return` / `kVK_ANSI_KeypadEnter` 从 `onPaste?()` 改为 `onPaste?()` 仍存在，但 `onPaste` 内部已根据设置分叉（不改这一层）
- `Sources/Copythat/Views/BottomPanelView.swift`：搜索框 `onSubmit` 调用 `onPaste`（不变，由分叉层处理）；footer 文案根据 `autoCopyOnSelect` 调整
- 右键菜单项文案与图标根据 `autoCopyOnSelect` 动态切换

### 规范层

- `paste-execution/spec.md`：将"双击/Enter = 粘贴"重写为"双击/Enter = 触发提交动作，提交动作在 `autoCopyOnSelect = false` 时仅写剪贴板，在 `true` 时走完整粘贴链路"
- `permissions/spec.md`：将"无障碍请求"要求改为"应用启动时请求一次"而非"粘贴时请求"
- `panel-ui/spec.md`：键盘导航 / 右键菜单的"粘贴"语义同步更新

## Non-goals

- **不移除 CGEventTap**（`CopySourceTracker` 的来源追踪依赖）—— 用户明确要求高精度来源
- **不**改 `CopySourceTracker` 的实现
- **不**改 `HotKeyManager`（`RegisterEventHotKey` 不需要 Accessibility）
- **不**改 `LSUIElement`、`Info.plist` 中的 `NSAppleEventsUsageDescription`（这些是 Apple Events 用的，本变更不触发 Apple Events）
- **不**改 ad-hoc 签名策略（`build_and_run.sh`）—— 用户的核心痛点通过收窄 Accessibility 接触点解决，签名漂移的根治（Developer ID）独立于本次变更
- **不**改 `ClipboardItem` / `ClipboardStore` 的写入逻辑（`store.writeToPasteboard` 仍然存在，由 `paste()` / `selectToCopy()` 各自调用）
- **不**改 `targetApp` 字段在 `autoCopyOnSelect = false` 时的展示用途 —— 保留供"切到 XX app 粘贴"提示（如果后续设计选用）
- **不**为本次变更新增 `specs/` 顶层文件 —— 所有规格归入 `paste-execution` / `permissions` / `panel-ui` 三个已存在 capability

## Capabilities

### New Capabilities

无。

### Modified Capabilities

- `paste-execution` —— 双击/Enter 提交动作的二分语义、permission 调用时机、右键菜单文案
- `permissions` —— 无障碍请求时机从"粘贴时"改为"启动时"
- `panel-ui` —— 键盘导航要求（双击/Enter 触发何种动作）、footer 提示文案、右键菜单项

## Impact

- **受影响代码**：
  - `Sources/Copythat/Stores/AppSettings.swift`（+1 @Published 字段 + Keys 项）
  - `Sources/Copythat/Services/ClipboardPastePerformer.swift`（路径分叉）
  - `Sources/Copythat/App/AppDelegate.swift`（+1 行启动时引导）
  - `Sources/Copythat/Views/SettingsView.swift`（+1 Toggle）
  - `Sources/Copythat/Views/ClipboardCardView.swift`（双击手势回调）
  - `Sources/Copythat/Views/BottomPanelView.swift`（footer 文案 + 菜单项文案）
- **公共 API**：无破坏性变更
- **依赖变更**：无
- **测试影响**：`Tests/CopythatTests/` 内不涉及 SwiftUI 视图；需评估 `script/verify/pasteboard_write.swift` / `paste_decision.swift` / `paste_target.swift` 是否需要新增 "autoCopyOnSelect 分叉" 用例
- **行为影响**：用户可见——双击/Enter 不再自动激活目标 app 与发送 `⌘V`；可通过 Settings 切回原行为
