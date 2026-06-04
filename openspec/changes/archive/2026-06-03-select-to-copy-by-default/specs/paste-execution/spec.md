# 粘贴执行规范（变更中）

> 完整规范见 `openspec/specs/paste-execution/spec.md`。本文件记录本次 change 引入的增量与替换。

## MODIFIED Requirements

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

## ADDED Requirements

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

## REMOVED Requirements

无。
