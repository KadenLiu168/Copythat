# 权限规范

## Purpose
Copythat 需要两项 macOS 权限才能完整运行：**无障碍**（用于 `⌘V` 注入与全局快捷键）以及 **Launch at Login**（通过 `SMAppService`）。本规范描述权限的查询、请求、失败回退与 Settings 中的可见性。
## Requirements
### Requirement: 无障碍状态
系统 SHALL 通过 `AXIsProcessTrustedWithOptions`（查询时 `kAXTrustedCheckOptionPrompt == false`）判断当前是否已授予无障碍权限。

#### Scenario: 未授予
- 假设 用户尚未向 Copythat 授予无障碍
- 当 浮层打开或触发粘贴
- 则 系统报告"未授予"，相关 UI 显示请求提示

#### Scenario: 已授予
- 假设 无障碍已授予
- 当 状态被查询
- 则 系统报告"已授予"，不再弹提示

### Requirement: 无障碍请求

系统 SHALL 在 `applicationDidFinishLaunching` 中调一次 `AXIsProcessTrustedWithOptions(prompt: true)` 引导用户授权。后续的粘贴路径（`autoCopyOnSelect == true` 时）SHALL 仅使用 `AXIsProcessTrusted`（不带 prompt）查询授权状态，**不**再次弹窗。

系统 SHALL 保留 Settings 中的 "Request Accessibility" 按钮，用于用户在系统设置中撤销授权后的手动重置。

#### Scenario: 用户首次启动

- 假设 无障碍未授予
- 当 应用启动
- 则 macOS 显示标准的系统授权弹窗（仅此 1 次）

#### Scenario: 用户点击 Request

- 假设 无障碍未授予
- 当 用户在 Settings 点击 "Request Accessibility"
- 则 macOS 显示标准的系统授权弹窗（手动重置用）

#### Scenario: 用户在系统设置中授权

- 假设 用户关闭了弹窗，然后在系统设置中授予了权限
- 当 用户返回 Copythat 并重新打开浮层
- 则 状态反映新授权，ON 模式粘贴可用，CGEventTap 来源追踪可用

#### Scenario: 粘贴不再弹窗

- 假设 无障碍已授予
- 当 用户在 ON 模式下触发粘贴
- 则 `AXIsProcessTrustedWithOptions` **不**被调用；无 `prompt` 弹窗

### Requirement: 深链到隐私设置
系统 SHALL 在用户点击 "Open System Settings" 时打开 `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`（或对应 macOS 版本的等价 URL）。

#### Scenario: 打开隐私面板
- 假设 无障碍未授予
- 当 用户点击 "Open System Settings"
- 则 系统设置在无障碍隐私面板打开

### Requirement: 启动登录注册
系统 SHALL 在用户于 Settings 切换 `launchAtLogin` 时注册 / 注销主应用到 `SMAppService.mainApp`。系统 SHALL 在启动时通过 `SMAppService.mainApp.status` 查询真实状态来初始化开关。

#### Scenario: 启用启动登录
- 假设 `launchAtLogin == false`，用户启用
- 当 切换被提交
- 则 调用 `SMAppService.mainApp.register()`，系统状态返回 `.enabled`

#### Scenario: 停用启动登录
- 假设 `launchAtLogin == true`，用户停用
- 当 切换被提交
- 则 调用 `SMAppService.mainApp.unregister()`

### Requirement: 启动登录失败回滚
若 `SMAppService.mainApp.register` / `unregister` 抛错，系统 SHALL 把 `launchAtLogin` 还原为之前的值，并将 `launchAtLoginError` 设为人类可读消息（"Launch at login could not be changed."）。下一次成功切换会清空该错误。

#### Scenario: 注册被拒
- 假设 用户启用启动登录但系统拒绝
- 当 错误被观察到
- 则 `launchAtLogin` 被静默回滚为旧值，Settings 中显示行内警告，菜单栏图标仍然可用

#### Scenario: 恢复
- 假设 之前发生过失败
- 当 用户稍后成功切换启动登录
- 则 `launchAtLoginError` 被清空

### Requirement: Settings 可见性
Settings → Permissions 区域 SHALL 显示：无障碍状态（Granted / Not granted）加 "Request" 按钮，以及 "Launch at Login" 开关。任一控件在出错时 SHALL 内联显示当前错误。

#### Scenario: Permissions 区域
- 假设 新装环境
- 当 用户打开 Settings → Permissions
- 则 无障碍显示 "Not granted" 与 Request 按钮，Launch at Login 反映系统实际状态

