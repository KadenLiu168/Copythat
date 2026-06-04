# 菜单栏规范

## Purpose
Copythat 是一款 `LSUIElement` 应用（不出现于 Dock），因此菜单栏图标是用户唯一始终可见的入口。本规范描述状态项的图标、点击行为与右键菜单。

## Requirements

### Requirement: 状态项存在
系统 SHALL 在应用启动完成时，在系统菜单栏创建正好一个 `NSStatusItem`。图标 SHALL 使用模板图 `MenuBarIconTemplate.png`，以便跟随系统菜单栏外观（浅色 / 深色）。

#### Scenario: 应用已启动
- 假设 应用启动完成
- 当 用户看向菜单栏
- 则 看到一个 Copythat 模板图标

#### Scenario: 系统外观切换
- 假设 用户把 macOS 切换到深色模式
- 当 菜单栏重绘
- 则 模板图标无需手动更新即可保持可读

### Requirement: 左键切换浮层
左键点击状态项 SHALL 显示底部浮层。再一次左键（或按全局快捷键，或按 Esc）SHALL 隐藏浮层。

#### Scenario: 首次点击
- 假设 浮层已隐藏
- 当 用户点击状态项
- 则 浮层出现，配置与按全局快捷键相同

#### Scenario: 再次点击关闭
- 假设 浮层已显示
- 当 用户再次点击状态项
- 则 浮层被关闭

### Requirement: 右键菜单
右键点击状态项 SHALL 弹出 `NSMenu`，至少包含：**Show Copythat**（等价于左键）、**Settings…**（打开 Settings 窗口）、**Quit Copythat**（退出应用）。这些菜单项 SHALL 始终可用。

#### Scenario: 右键
- 假设 用户右键点击状态项
- 当 菜单出现
- 则 列出三个菜单项，使用系统默认字体并在合适处显示键盘等效项

#### Scenario: 退出
- 假设 用户选择 "Quit Copythat"
- 当 菜单项被调用
- 则 应用退出；全局快捷键被注销（见 `global-shortcut`）

### Requirement: Settings 入口
Settings… 菜单项 SHALL 把 Settings 窗口带到最前（若未打开则先打开），无论浮层当前是否可见。

#### Scenario: 通过菜单打开 Settings
- 假设 浮层已隐藏
- 当 用户选择 "Settings…"
- 则 Settings 窗口作为 key window 出现
