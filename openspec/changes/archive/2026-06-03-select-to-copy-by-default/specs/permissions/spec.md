# 权限规范（变更中）

> 完整规范见 `openspec/specs/permissions/spec.md`。本文件记录本次 change 引入的增量与替换。

## MODIFIED Requirements

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

## ADDED Requirements

无。

## REMOVED Requirements

无。
