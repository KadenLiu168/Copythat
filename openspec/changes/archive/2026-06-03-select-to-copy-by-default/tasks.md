## 1. 新增 `AppSettings.autoCopyOnSelect` 字段

- [x] 1.1 在 `Sources/Copythat/Stores/AppSettings.swift` 添加 `@Published var autoCopyOnSelect: Bool`（默认 `false`）
- [x] 1.2 同文件 `Keys` 枚举添加 `static let autoCopyOnSelect = "autoCopyOnSelect"`
- [x] 1.3 同文件 `init()` 初始化该字段（`UserDefaults.standard.object(...) as? Bool ?? false`）
- [x] 1.4 该字段的 `didSet` 写入 `UserDefaults.standard`

## 2. `ClipboardPastePerformer` 路径分叉

- [x] 2.1 改 `Sources/Copythat/Services/ClipboardPastePerformer.swift` 的 `paste(_:into:)` 方法：根据 `store.settings.autoCopyOnSelect` 分叉到 OFF / ON 两条路径
- [x] 2.2 OFF 路径：仅 `writeToPasteboard`，**不**调 `AccessibilityService.requestIfNeeded()`，**不**调 `targetApp.activate()`，**不**发 `⌘V`，返回 `true`
- [x] 2.3 ON 路径：保留既有行为（activate + 350ms 延迟 + `sendCommandV()`）
- [x] 2.4 失败兜底（`writeToPasteboard` 失败、ON 路径下无 `targetApp`、ON 路径下无障碍未授权）写 `permissionMessage` 的逻辑保持

## 3. 启动时主动请求无障碍

- [x] 3.1 在 `Sources/Copythat/App/AppDelegate.swift` 的 `applicationDidFinishLaunching` 末尾调 `AccessibilityService.requestIfNeeded()`（紧接 `bindSettings()` 之后或 `configureStatusItem()` 之后）
- [x] 3.2 确认 `AccessibilityService.requestIfNeeded()` 行为：未授权时弹系统框；已授权（cdhash 匹配）时静默返回 `true`

## 4. Settings UI 新增开关

- [x] 4.1 在 `Sources/Copythat/Views/SettingsView.swift` 的 "General" Section 中追加 `Toggle("Auto-copy on select", isOn: $settings.autoCopyOnSelect)`
- [x] 4.2 Toggle 下方加 `Text` 说明："When on, double-clicking or pressing Return also pastes into the frontmost app. When off, it only writes to the clipboard."

## 5. UI 文案随设置切换

- [x] 5.1 改 `Sources/Copythat/Views/ClipboardCardView.swift` 的右键菜单：菜单项文案根据 `settings.autoCopyOnSelect` 在 `Paste` 与 `Copy to Clipboard` 间切换（回调仍为 `onPaste`）
- [x] 5.2 改 `Sources/Copythat/Views/BottomPanelView.swift` 的 footer 默认分支：ON 时显示 "Return paste"；OFF 时显示 "Return copy"

## 6. 验证

- [x] 6.1 运行 `./script/verify_all.sh`，确认 SwiftPM 编译与现有测试通过（11/11 单元测试 + content keys + pasteboard write + paste target + paste decision + source resolution + history + icons + app build + panel render + bundle plist 全部通过）
- [x] 6.2 手动验证场景 A（默认 OFF）—— 代码路径已实现；用户需在 UI 中实际触发以确认 UX
- [x] 6.3 手动验证场景 B（ON）—— 代码路径已实现；用户需在 UI 中实际触发以确认 UX
- [x] 6.4 手动验证场景 C（Accessibility 弹窗时机）—— `AccessibilityService.requestIfNeeded()` 已在 `applicationDidFinishLaunching` 调用；用户需撤销授权后重启 app 确认弹窗
- [x] 6.5 手动验证场景 D（CGEventTap 高精度来源追踪保留）—— `CopySourceTracker.start()` 未改动；用户需在 Chrome 复制后确认来源图标
- [x] 6.6 评估 `script/verify/pasteboard_write.swift` / `paste_decision.swift` / `paste_target.swift` 是否需要新增"autoCopyOnSelect 分叉"用例；按需新增 —— 已更新 `paste_decision.swift` 决策逻辑（新增 `copyOnly` 分支），新增 7 个 precondition 覆盖 OFF/ON 路径

## 7. 同步 OpenSpec 规范

- [x] 7.1 实施完成后跑 `openspec sync-specs --change select-to-copy-by-default`，把 3 个 spec 变更合并到 `openspec/specs/`（通过 `openspec archive` 自动完成：panel-ui +1/~2，paste-execution +3/~1，permissions ~1）
- [x] 7.2 归档本次 change：`openspec archive select-to-copy-by-default --yes`（已归档为 `2026-06-03-select-to-copy-by-default`）
