# 全局快捷键规范

## Purpose
Copythat 通过 Carbon `RegisterEventHotKey` 注册一个全局快捷键来召唤浮层。用户在 Settings 里可从三个预设里选一个；macOS 可能拒绝注册（例如快捷键被其它应用占用），此时必须给用户可见的反馈。

## Requirements

### Requirement: 快捷键预设
系统 SHALL 提供正好三个全局快捷键预设：`⌘⇧V`（Command + Shift + V）、`⌥Space`（Option + Space）、`⌃Space`（Control + Space）。本版本不支持自定义映射。

#### Scenario: 默认预设
- 假设 新装环境
- 当 用户打开 Settings
- 则 `⌘⇧V` 是已选中的快捷键

#### Scenario: 切换到 Option-Space
- 假设 用户在 Settings 中选择 "Option-Space"
- 当 选择被提交
- 则 之前注册的快捷键在同一运行循环 tick 内被注销，新快捷键被注册

### Requirement: 快捷键回调
当已注册的快捷键被按下时，系统 SHALL 把动作投递到主队列，并调用已注册的回调（用于切换浮层）。回调 SHALL 不得阻塞 UI 工作——Carbon 处理器异步派发到 `DispatchQueue.main`。

#### Scenario: 按下快捷键
- 假设 浮层处于隐藏
- 当 用户按下已注册的快捷键
- 则 主线程在一帧内显示浮层

### Requirement: 注册失败反馈
若 `RegisterEventHotKey` 返回非 `noErr` 状态，系统 SHALL 将 `shortcutError` 设为人类可读消息（"Global shortcut could not be registered."），且 SHALL NOT 静默吞掉失败。菜单栏图标作为回退入口仍然可用。

#### Scenario: 快捷键已被占用
- 假设 其它应用已占用所选快捷键
- 当 Copythat 尝试注册
- 则 浮层仍可通过菜单栏图标打开，Settings 显示行内警告

#### Scenario: 重新注册成功
- 假设 之前注册失败，用户选择一个空闲快捷键
- 当 注册成功
- 则 `shortcutError` 立即被清空

### Requirement: 应用生命周期
快捷键 SHALL 在应用启动完成时被注册，在应用退出时被注销。Settings 变更触发的重新注册是原子的（旧 handler 移除后安装新 handler）。

#### Scenario: 退出
- 假设 应用正在运行并已注册快捷键
- 当 用户退出 Copythat
- 则 `UnregisterEventHotKey` 被调用，快捷键被释放回系统
