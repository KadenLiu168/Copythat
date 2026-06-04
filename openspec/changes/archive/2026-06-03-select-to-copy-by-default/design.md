## Context

### 现状（待修改）

**用户触发 "提交" 动作的入口**：
- `Sources/Copythat/Views/ClipboardCardView.swift:48` —— `.onTapGesture(count: 2, perform: onPaste)`
- `Sources/Copythat/Services/PanelWindowController.swift:170-171` —— `kVK_Return` / `kVK_ANSI_KeypadEnter` 触发 `onPaste?()`
- `Sources/Copythat/Views/BottomPanelView.swift:144` —— 搜索框 `onSubmit(onPaste)`
- `Sources/Copythat/Views/ClipboardCardView.swift:62` —— 右键菜单 "Paste" 项

**核心 paste 路径**（`Sources/Copythat/Services/ClipboardPastePerformer.swift:14-44`）：
```
paste(item, into: targetApp)
  → writeToPasteboard(item)
  → AccessibilityService.requestIfNeeded()     ← 弹窗源头
  → targetApp.activate(...)
  → DispatchQueue.main.asyncAfter(0.35s)
  → CGEvent.post(Cmd-V, tap: .cghidEventTap)   ← Accessibility 实际使用
```

**Accessibility 接触面**（共 2 个，1 个要被收窄）：
| 位置 | 行为 | 本次处理 |
|------|------|---------|
| `ClipboardPastePerformer.paste()` 第 24 行 | 主动调 `requestIfNeeded()` 弹窗 | 默认 OFF 路径下不再调用 |
| `CopySourceTracker.start()` 第 57 行 | 静默创建 CGEventTap（无授权时不弹窗） | **保留不动**（高精度来源追踪） |

**当前 settings 结构**（`Sources/Copythat/Stores/AppSettings.swift`）：
- `launchAtLogin: Bool`（持久化到 UserDefaults）
- `historyLimit: Int`（持久化）
- `recordSensitiveContent: Bool`（持久化）
- `ignoredApplications: String`（持久化）
- `pinboardsText: String`（持久化）
- `shortcut: String`（持久化）
- `appearance: AppearanceMode`（持久化）
- **缺**：`autoCopyOnSelect: Bool` —— 本次新增

**ad-hoc 签名漂移现象**（来自用户描述）：
- `./script/build_and_run.sh` 每次 `swift build` 后 `cdhash` 变化
- TCC 数据库中 `client` requirement 含 cdhash → 当前运行的 cdhash 找不到记录
- `AXIsProcessTrustedWithOptions(prompt:true)` 在 paste 路径被调用 → 系统弹"请授权"框
- 用户去设置看 → 看到的是旧 cdhash 的旧记录，状态显示"已授权"
- 重新授权 → 当前 cdhash 入库，但下次 build 又失效

### 目标

- 把"双击/Enter 是否自动 Cmd-V"做成**用户可配置**（默认 OFF）
- OFF 路径下，paste 链路**完全不需要 Accessibility 接触**（弹窗源消失）
- ON 路径下保留原行为
- 启动时主动引导一次授权，让 CGEventTap 工作（高优先级来源追踪需要）
- 不动 `CopySourceTracker` 实现
- 不动 ad-hoc 签名策略

### 反例（用户已拒绝的方案）

- **方案 B（彻底移除 CGEventTap）**：可做到"永不弹 + 不需权限"，但来源追踪退化（8s 兜底窗口有极端错标场景）。用户因"高精度对 UX 影响大"已选 A
- **方案仅改文案不改语义**：把"自动粘贴"叫"复制"是欺骗用户，不解决弹窗

## Goals / Non-Goals

**Goals:**

- 双击 / Enter 默认只写剪贴板，不激活目标 app，不发 `⌘V`
- 通过 Settings → General 中的 "Auto-copy on select" 开关可恢复原行为
- Accessibility 弹窗从"每次粘贴都可能弹"降到"应用启动时弹 1 次"
- 保留 `CopySourceTracker` 的 CGEventTap 高精度来源追踪
- 右键菜单项的文案与图标随设置切换
- 底部 footer 提示文案随设置切换
- 不改 `Info.plist` / 签名 / entitlements

**Non-Goals:**

- 不移除 `CopySourceTracker.start()` 中的 CGEventTap
- 不改 `HotKeyManager`（已用 Carbon `RegisterEventHotKey`，不需 Accessibility）
- 不改 `ClipboardItem` / `ClipboardStore.writeToPasteboard` 的实现
- 不改 `targetApp` 字段的捕获逻辑（`PanelWindowController.show()` 第 26-29 行），但其用途在 OFF 模式下从"激活目标 app"变成"展示提示 / 暂不使用"
- 不改 `LSUIElement`、`NSAppleEventsUsageDescription`、`NSScreenCaptureUsageDescription`
- 不改 `build_and_run.sh` 的 ad-hoc 签名策略
- 不引入新 spec 顶层文件
- 不为"Copy and keep open"或"Copy and close"做 UX 决策 —— 默认关闭面板（与现状一致），后续如需"连续复制多条"再单独提案
- 不在本次处理拖拽（`onDrag`）路径 —— 拖拽不需要 Accessibility，与本变更独立

## Decisions

### 1. 新增 `AppSettings.autoCopyOnSelect: Bool`（默认 false）

**理由：**
- 把产品决策做成显式配置，不藏代码里
- 默认 false = "双击只复制不粘贴" —— 与用户描述的"用户根据需要黏贴"完全一致
- 持久化到 `UserDefaults.standard`，key 加在既有 `Keys` 枚举里
- 走 `@Published + didSet` 模式，与既有 `recordSensitiveContent` 等布尔字段一致

**实现摘要：**
```swift
@Published var autoCopyOnSelect: Bool {
    didSet { UserDefaults.standard.set(autoCopyOnSelect, forKey: Keys.autoCopyOnSelect) }
}
// init: UserDefaults.standard.object(forKey: Keys.autoCopyOnSelect) as? Bool ?? false
// Keys.autoCopyOnSelect = "autoCopyOnSelect"
```

**备选：**
- 做成"per-card"或"per-app"配置 —— 过度设计，本次只解决"弹窗 + 误触发粘贴"两个直接问题
- 做成 NSMenu 菜单项而非 Settings 开关 —— 发现性差，且 Settings 已经有"General"区

### 2. `ClipboardPastePerformer` 拆为两条执行路径

**当前签名**（`ClipboardPastePerformer.swift:14`）：
```swift
func paste(_ item: ClipboardItem, into targetApp: NSRunningApplication?) -> Bool
```

**改动方案**：保留方法签名 + 内部根据 `autoCopyOnSelect` 分叉：

```swift
func paste(_ item: ClipboardItem, into targetApp: NSRunningApplication?) -> Bool {
    store.clearPermissionMessage()
    guard store.writeToPasteboard(item) else { ... return false }

    if store.settings.autoCopyOnSelect {
        // 原 paste 行为
        guard let targetApp else { ... return false }
        guard AccessibilityService.requestIfNeeded() else {
            store.permissionMessage = "Accessibility permission is off. The item was copied to the clipboard."
            return false
        }
        targetApp.activate(options: [.activateAllWindows])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            self.sendCommandV()
        }
        return true
    } else {
        // 新行为：只写剪贴板，不激活 app，不发 Cmd-V
        // 返回 true 表示"成功复制到剪贴板"
        return true
    }
}
```

**关键点：**
- OFF 路径下 `sendCommandV()` 与 `AccessibilityService.requestIfNeeded()` **都不会被调用** —— 这是消除每次粘贴弹窗的核心
- `writeToPasteboard` 仍然在两条路径都执行 —— 这正是用户想要的"选中即就位"
- `permissionMessage` 在 OFF 路径下不需要，因为根本不检查权限
- 保留方法名 `paste` 不变（避免大规模更名；含义扩展为"提交"）

**备选：**
- 拆为两个方法 `paste()` 与 `copyToClipboard()`，UI 层根据设置选调用哪个 —— UI 层就需要多处 `if autoCopyOnSelect` 分叉，分散关注点
- 让 `paste()` 永远执行 Cmd-V，UI 层根据设置选不调它 —— 同上，分散关注点
- 选当前方案（`paste()` 内部分叉）—— 集中权限语义，UI 层保持单一调用点

### 3. 启动时主动调一次 `AccessibilityService.requestIfNeeded()`

**位置**：`Sources/Copythat/App/AppDelegate.swift:15-35` 的 `applicationDidFinishLaunching` 末尾

**理由：**
- CGEventTap（`CopySourceTracker.start()`）静默失败时**不会**自动弹窗，新装用户会卡在"来源图标永远 unknown"却不知道为啥
- 启动时调 `requestIfNeeded()` 让 macOS 在最自然的时机弹"请授权"框
- 配合 `LSUIElement = true`（菜单栏 app），弹窗时机更不打扰
- 这次弹窗**只在 cdhash 漂移时弹**，已授权（cdhash 匹配）则不弹

**代码：**
```swift
func applicationDidFinishLaunching(_ notification: Notification) {
    model.sourceTracker.start()
    model.store.startMonitoring()
    // ... 既有初始化 ...
    AccessibilityService.requestIfNeeded()   // 新增：启动时引导一次
}
```

**备选：**
- 在首次有内容被复制（changeCount 第一次增长）时弹 —— 时机不直观，用户没看到引导前来源可能已错
- 在用户首次打开浮层时弹 —— 同样不直观
- 在 Settings 的 Permissions 区检测到未授权时弹 —— 已经存在，但默认用户不会主动去 Settings

### 4. `ClipboardCardView` 双击手势从 `onPaste` 改为 `onSelect`

**改动**（`Sources/Copythat/Views/ClipboardCardView.swift:48`）：
```swift
// 旧
.onTapGesture(count: 2, perform: onPaste)
// 新
.onTapGesture(count: 2, perform: onSelect)
```

**理由：**
- 用户原话："双击或 enter 是选中而不是直接黏贴"
- 语义统一：单击 = 选中，双击 = 也是选中（更确信的选中）+ 通过回调链触发 paste 提交
- paste 提交的实际行为仍由 `autoCopyOnSelect` 决定

**等等，这有个不一致**：用户说"双击是选中"，但我决策 2 的"双击触发 paste 提交"——这俩矛盾吗？

**重新厘清**：
- 用户说"双击是选中"：**选中的语义是写剪贴板**（"选中"在剪贴板管理器里意味着"准备就绪"）
- 双击 = "更强的选中" = 写剪贴板 + （如果设置 ON）触发 Cmd-V
- 这与决策 2 的"paste 内部根据设置分叉"是一致的
- 双击不再直接 = "粘贴到当前 app"，而是 = "激活这个卡片"（可能是仅复制，也可能是复制+粘贴）

**UI 层只关心"激活"，不关心"激活"具体执行什么** —— 这是好抽象

**结论**：双击回调仍然用 `onPaste`（既有的回调名），不改名。`onPaste` 在 OFF 模式下 = "写剪贴板"，在 ON 模式下 = "写剪贴板 + Cmd-V"。如果用户认为这个命名误导，可以单独提案把 `onPaste` 改名为 `onCommit`，但本次不动。

**修正后决策 4**：`ClipboardCardView` 双击回调 **保持 `onPaste`**，不改名。理由：`onPaste` 在剪贴板管理器语境下是"提交"而非"自动粘贴到当前 app"的标准用法（与 macOS 自身 NSPasteboard API 风格一致）。

### 5. 右键菜单项文案与 footer 文案随 `autoCopyOnSelect` 切换

**位置**：
- `Sources/Copythat/Views/ClipboardCardView.swift:62` 右键菜单 "Paste" 项
- `Sources/Copythat/Views/BottomPanelView.swift:287-308` footer

**方案**：

```swift
// ClipboardCardView.swift
contextMenu {
    // ...
    if settings.autoCopyOnSelect {
        Button("Paste", action: onPaste)
    } else {
        Button("Copy to Clipboard", action: onPaste)  // 同一回调
    }
    // ...
}

// BottomPanelView.swift footer（默认分支）
if let message = store.permissionMessage {
    // ... 既有失败提示 ...
} else {
    if settings.autoCopyOnSelect {
        Label("Return paste  -  Esc close  -  \(settings.shortcut) show", ...)
    } else {
        Label("Return copy  -  Esc close  -  \(settings.shortcut) show", ...)
    }
}
```

**理由：**
- 文案是用户对当前行为模式的唯一信号
- "Return paste" 暗示"按 Enter 会执行粘贴"；"Return copy" 暗示"按 Enter 会复制"
- 不改 icon（icon 已经在卡片头部表示"内容"而非"动作"）
- 提交动作无反馈：双击/Enter 成功后**立即**关闭浮层，**不**加 footer 临时提示
- 浮层关闭本身就是"提交已就位"的视觉信号 —— 用户预期"按 Enter 后浮层会消失"，与现状一致

**备选：**
- 动态更改 `Paste` 的 SF Symbol 图标（如 `doc.on.clipboard` vs `keyboard`）—— 过度设计，icon 区分度低
- 完全删除 OFF 模式下的菜单项 —— 不对，用户仍可通过菜单复制，只是行为不同
- 加 footer 临时反馈"Copied ✓ ..." —— 与"立即关闭浮层"在时序上冲突（关闭后 footer 看不见），review 中已否决

### 6. `targetApp` 字段在 OFF 模式下的处理

**当前**（`Sources/Copythat/Services/PanelWindowController.swift:26-29`）：
```swift
if let frontmostApplication = NSWorkspace.shared.frontmostApplication,
   isPasteTargetCandidate(frontmostApplication) {
    targetApp = frontmostApplication
}
```

**OFF 模式**：`targetApp` 仍然被设置（`show()` 行为不变），`paste()` 不会**激活**它，footer 也不显示"Press ⌘V in [app]"提示（决策 5 已确认不加 footer 临时反馈）。

**决策**：OFF 模式下 `targetApp` **仍然记录**（`show()` 不变），其用途仅为"在 ON 模式时被 activate"。

**理由：**
- 删除需要改 `paste()`、`show()`、init 顺序，影响面比保留大
- 字段多保留一帧的运行时状态不影响性能
- 未来如要加"切到 XX app 粘贴"提示或"自动延迟关闭让用户看反馈"，复用 `targetApp` 即可

**未来可单独提案**：OFF 模式下在 footer 显示 "Press ⌘V in [app] to paste" 提示。本提案不做。

### 7. spec 变更的范围

**paste-execution/spec.md**：
- 修改 Requirement "无障碍权限要求"：从"第一次触发粘贴时请求"改为"启动时请求一次"（合并到 permissions/spec）
- 修改 Requirement "激活延迟"：OFF 模式下不发送 ⌘V，因此 350ms 延迟仅在 ON 模式有效
- 新增 Requirement "提交动作分叉"：明确 `autoCopyOnSelect` 控制的行为差异

**permissions/spec.md**：
- 修改 Requirement "无障碍请求"：时机从"用户点击按钮 / 首次粘贴"改为"应用启动时一次"
- 保留 Settings 中的 "Request Accessibility" 按钮（手动重置用）

**panel-ui/spec.md**：
- 修改 Requirement "键盘导航"：Return/Enter 的语义从"粘贴当前选中卡片"改为"激活当前选中卡片（提交动作）"
- 修改 Requirement "底部"：footer 文案随 `autoCopyOnSelect` 切换
- ~~新增 Requirement "提交反馈"~~ —— **已删除**：用户 review 决定不加 footer 临时反馈，提交动作后浮层立即关闭（与现状一致）

## Risks / Trade-offs

- **[双击反馈弱化]** 旧版双击 = "立即看到内容出现在目标 app"（强反馈）；新版双击（OFF 模式） = "剪贴板就位，浮层立即关闭，用户得自己切 app + Cmd-V"（弱反馈）。→ 缓释：浮层关闭本身可作为"提交已就位"的视觉信号；footer 文案 "Return copy" 明确说明；autoCopyOnSelect 开关可让老用户切回原行为
- **[连续复制多条摩擦]** 用户想从历史里挑 3 条分别贴到不同位置：每次双击都得重新打开浮层（全局快捷键）。→ 缓释：与"按一次快捷键 = 一次操作"的 macOS 习惯一致；本提案 Non-goals 已说明"Copy and keep open"不做，后续可单独提案
- **[autoCopyOnSelect 状态的认知负担]** 新设置项增加 Settings 复杂度。→ 缓释：默认 OFF（最常见偏好），用户无需触碰；只在老用户感到"为啥不自动贴了"时再切
- **[签名漂移问题仍存在]** 本提案不根治 cdhash 漂移，只是把弹窗时机收窄到启动时。→ 缓释：用户已选 A 方案，明示要保留高精度；根治（Developer ID 签名）是独立议题
- **[Accessibility 启动时弹窗的新装体验]** 新装用户首次启动会看到 macOS 标准授权框，时机可能出乎意料。→ 缓释：这是 CGEventTap 工作所必需；可在第一次出现 ⌘V 行为不工作时再次弹（即"在用户尝试 Cmd-V 之前已经弹过"是更优时机）
- **[spec 改动面较广]** paste-execution / permissions / panel-ui 三个 spec 都要改。→ 缓释：三者有共同主题（"提交动作的语义与权限"），单独改一处会留矛盾
- **`@Published` 字段新增 → 既有 init 顺序需评估** AppSettings.init 已有 8 个字段，加第 9 个需要更新。→ 缓释：与 `recordSensitiveContent` 同模式，复用既有 didSet 模式

## Decisions Made During Review

本节记录 review 期间用户已拍板的决策（替代原 Open Questions 章节）：

| 决策 | 选择 | 影响 |
|------|------|------|
| 剪贴板覆盖 | (a) 接受直接覆盖 | 不加"覆盖前询问"开关；标准剪贴板管理器行为 |
| OFF 模式双击是否关闭浮层 | 立即关闭 | 与 ON 模式一致；predictable；与"footer 临时显示"互斥（见下） |
| 已就位反馈机制 | **不加** | review 第二轮决定移除 footer 临时显示（与"立即关闭"在时序上冲突） |
| CGEventTap 静默失败时 Settings 可见性 | 不加提示 | 保持 Settings 现状；用户大多授权后不再动 |
| `autoCopyOnSelect` 命名 | 不改 | 直接、准确；不进入"选中即复制"歧义（OFF 模式选中**不**写剪贴板） |
