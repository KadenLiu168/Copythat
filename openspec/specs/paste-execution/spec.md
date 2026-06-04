# 粘贴执行规范

## Purpose
用户在浮层里选中卡片、按下 Return / Enter 或点击 "Paste" 时，Copythat 必须把对应 `ClipboardItem` 重新写回系统剪贴板，切换到正确的目标应用，并触发 `⌘V`。本规范描述这条链路的语义、边界与失败回退。
## Requirements
### Requirement: 条目恢复语义
系统 SHALL 按 kind 恢复 `ClipboardItem` 到剪贴板：`.text` / `.url` 写入 `textValue`（或 URL）；`.image` 写入 `imageData`；`.file` 写入每一个 `fileURLs` 条目，**跳过磁盘上已不存在的 URL**。当 Copythat 无法完整恢复条目时，恢复操作 SHALL 保留系统返回的既有剪贴板内容。

#### Scenario: 文件缺失
- 假设 一个条目的 `fileURLs` 包含 `/tmp/missing.txt`
- 当 用户粘贴
- 则 缺失文件被跳过，剩余有效文件（或既有内容）保留在剪贴板上；不抛异常

#### Scenario: 文本恢复
- 假设 有一条文本条目
- 当 用户粘贴
- 则 `textValue` 被写入剪贴板；若为空则操作为 no-op（返回 `false`）

### Requirement: 粘贴目标过滤
系统 SHALL 通过在用户触发粘贴后检查最前 `NSRunningApplication` 来选定粘贴目标。目标 MUST NOT 是 Copythat 自身或 `com.apple.systemuiserver`。检查复用 `CopySourceResolution.isSourceCandidate`。

#### Scenario: Copythat 处于最前
- 假设 触发粘贴时 Copythat 自身处于最前
- 当 目标检查运行
- 则 Copythat 被拒绝，使用上一个非 Copythat 的应用；若无候选则中止粘贴

#### Scenario: SystemUIServer 处于最前
- 假设 SystemUIServer 处于最前
- 当 目标检查运行
- 则 它被拒绝，按激活顺序选择下一个用户应用

#### Scenario: 无有效目标
- 假设 唯一可用的目标是 Copythat 或 SystemUIServer
- 当 目标检查运行
- 则 粘贴被中止，`permissionMessage` 被设置，**不**发送 `⌘V`

### Requirement: 无障碍权限要求

系统 SHALL 在应用启动时调一次 `AXIsProcessTrustedWithOptions(prompt: true)` 以引导用户授权（详见 `permissions/spec`）。当且仅当 `settings.autoCopyOnSelect == true` 时，提交动作在执行 `⌘V` 注入**之前**调用 `AXIsProcessTrusted`（**不**带 prompt 选项）查询授权状态；该调用 SHALL NOT 触发系统弹窗。

在 `autoCopyOnSelect == false` 时，提交动作 SHALL 完全不调用 `AXIsProcessTrusted` 系列函数。

若 `autoCopyOnSelect == true` 且无障碍未授予，系统 SHALL 仍把条目复制到剪贴板并显示行内消息请求用户授权，SHALL NOT 发送 `⌘V`。

#### Scenario: 首次启动未授权

- 假设 无障碍未授予
- 当 应用启动
- 则 系统弹出无障碍授权框（仅此 1 次）

#### Scenario: 启动后已授权，OFF 模式提交

- 假设 无障碍已授予、`autoCopyOnSelect == false`
- 当 用户双击卡片或按 Return
- 则 `AXIsProcessTrusted` **不**被调用；条目被写入剪贴板；**不**激活目标 app；**不**发送 `⌘V`

#### Scenario: 已授权粘贴

- 假设 无障碍已授予、`autoCopyOnSelect == true`
- 当 用户双击卡片或按 Return
- 则 目标应用被激活，等待 350 ms 后发送一次 `⌘V` 键事件

#### Scenario: ON 模式未授权兜底

- 假设 `autoCopyOnSelect == true`、无障碍未授予
- 当 用户双击卡片或按 Return
- 则 `AXIsProcessTrusted` 返回 `false`；条目已写入剪贴板；显示行内消息 "Accessibility permission is off. The item was copied to the clipboard."；**不**发送 `⌘V`

### Requirement: 激活延迟
在激活目标应用之后，系统 SHALL 等待 350 ms 再发送 `⌘V` 事件，以保证目标 key window 准备好接收。

#### Scenario: 慢激活目标
- 假设 目标应用需要约 300 ms 让 key window focus
- 当 触发粘贴
- 则 `⌘V` 在窗口就绪后到达（仍在 350 ms 窗口内）且粘贴成功

### Requirement: 失败反馈
当以下任一条件成立时，系统 SHALL 向 store 写入 `permissionMessage` 并跳过 `⌘V`：缺少无障碍权限、无有效粘贴目标、恢复返回 `false`。

#### Scenario: 条目无法恢复
- 假设 有一条 `textValue` 为空的文本条目
- 当 用户粘贴
- 则 不会有内容被写入剪贴板，底部显示权限/粘贴失败消息

### Requirement: 粘贴目标是否触屏底（锚定提示）
系统 SHALL 计算 `targetAppTouchesScreenBottom` 来判断目标窗口是否触到可见区域底部；该信号被 `panel-ui` 消费，用于决定是否锚定到物理屏底。

#### Scenario: 目标在屏幕顶部
- 假设 目标应用窗口位于屏幕上半部
- 当 浮层重新锚定
- 则 浮层使用可见区域底部锚定（菜单栏/Dock 下方 24 pt）

#### Scenario: 目标到达屏幕底
- 假设 目标应用窗口到达屏幕物理底部
- 当 浮层重新锚定
- 则 浮层锚定到屏幕物理底部（`screenFrame.minY` 之上 24 pt）

### Requirement: 提交动作分叉

提交动作（双击卡片 / 按 Return / 触发右键菜单中的对应项）SHALL 根据 `settings.autoCopyOnSelect` 分叉为两条路径：

- `autoCopyOnSelect == false`（默认）：仅调用 `store.writeToPasteboard(item)`；**不**激活目标 app；**不**发送 `⌘V`；返回 `true` 表示"已就位"。
- `autoCopyOnSelect == true`：依次执行 `writeToPasteboard` → `AXIsProcessTrusted` → `targetApp.activate()` → 350 ms 后 `⌘V`。

两条路径都 MUST 复用 `paste(_:into:)` 方法，UI 层 SHALL NOT 根据设置分叉调用不同方法。

#### Scenario: OFF 模式提交

- 假设 `autoCopyOnSelect == false`、有选中卡片
- 当 用户双击卡片
- 则 剪贴板写入卡片内容；浮层关闭；**不**激活任何外部 app；用户可在目标 app 手动 `⌘V`

#### Scenario: ON 模式提交

- 假设 `autoCopyOnSelect == true`、有选中卡片、目标 app 存在
- 当 用户双击卡片
- 则 剪贴板写入 + 目标 app 激活 + 350 ms 后 `⌘V`；浮层关闭

### Requirement: ON 模式下激活延迟

在 `autoCopyOnSelect == true` 时激活目标应用之后，系统 SHALL 等待 350 ms 再发送 `⌘V` 事件，以保证目标 key window 准备好接收。该延迟 SHALL 仅在 ON 模式生效；OFF 模式不发送 `⌘V`，因此无延迟。

#### Scenario: 慢激活目标

- 假设 `autoCopyOnSelect == true`、目标应用需要约 300 ms 让 key window focus
- 当 触发提交
- 则 `⌘V` 在窗口就绪后到达（仍在 350 ms 窗口内）且粘贴成功

### Requirement: ON 模式失败反馈

在 `autoCopyOnSelect == true` 时，当以下任一条件成立，系统 SHALL 向 store 写入 `permissionMessage` 并跳过 `⌘V`：缺少无障碍权限、无有效粘贴目标、恢复返回 `false`。

在 `autoCopyOnSelect == false` 时，唯一可能的失败是 `writeToPasteboard` 返回 `false`（条目无法恢复）。该情况下同样 SHALL 写入 `permissionMessage` 并跳过关闭浮层。

#### Scenario: OFF 模式文本为空

- 假设 `autoCopyOnSelect == false`、有 `textValue` 为空的文本条目
- 当 用户双击
- 则 没有内容被写入剪贴板，底部显示 "This clipboard item could not be restored."

#### Scenario: ON 模式无目标

- 假设 `autoCopyOnSelect == true`、唯一可用的目标是 Copythat 或 SystemUIServer
- 当 用户双击
- 则 剪贴板写入成功，但 `permissionMessage` 被设置，**不**发送 `⌘V`

