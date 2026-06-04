# 设置规范

## Purpose
Copythat 在 macOS 标准 Settings 窗口中提供偏好设置。所有偏好以 `UserDefaults` 为唯一持久化源；类型校验、范围裁剪、错误反馈由 `AppSettings` 负责。

## Requirements

### Requirement: 设置区域
Settings 窗口 SHALL 按以下顺序暴露这些区域：**General**（启动登录、历史上限、记录敏感内容、忽略应用）、**Shortcut**（来自 `global-shortcut` 的三选一切换器）、**Permissions**（无障碍状态 + 启动登录状态，见 `permissions`）、**Pinboards**（`pinboardsText` 的多行编辑器）、**Ignore Applications**（多行编辑器；某些布局下同时在 General 中显示）、**Appearance**（System / Light / Dark 选择器）。

#### Scenario: 全部区域可见
- 假设 用户打开 Settings
- 当 窗口出现
- 则 在默认尺寸下无需滚动即可看到全部 6 个区域

### Requirement: 历史上限边界
系统 SHALL 在写入 `historyLimit` 时把它裁剪到 `[100, 1000]` 区间。越界值被静默强制到最近的边界。

#### Scenario: 越界小值
- 假设 用户在历史上限字段输入 `50`
- 当 值被提交
- 则 `historyLimit` 变为 `100`

#### Scenario: 越界大值
- 假设 用户输入 `9 999`
- 当 值被提交
- 则 `historyLimit` 变为 `1 000`

### Requirement: 默认自定义 Pinboard
首次启动时，`pinboardsText` SHALL 被初始化为 `"Work\nIdeas"`，从而 `customPinboards == ["Work", "Ideas"]`。

#### Scenario: 新装环境
- 假设 用户全新安装并使用一份干净的 `UserDefaults`
- 当 应用启动
- 则 Settings → Pinboards 显示两行："Work" 与 "Ideas"

### Requirement: 持久化边界
Settings 窗口中的每次变更 SHALL 在提交时立即写入 `UserDefaults`（无 Save 按钮）。下次启动 SHALL 在边界内逐字恢复每个值。

#### Scenario: 往返一致性
- 假设 用户把外观改为 Dark、`historyLimit` 改为 `750`
- 当 他们退出并重新启动
- 则 外观仍为 Dark，`historyLimit` 仍为 `750`

### Requirement: 无效快捷键回退
若 `shortcut` 设置被设为与三个已知预设都不匹配的值，系统 SHALL 还原为 `⌘⇧V` 并持久化之。

#### Scenario: UserDefaults 被破坏
- 假设 因手动编辑 `UserDefaults` 导致 `shortcut == "garbage"`
- 当 应用启动
- 则 `shortcut == "⌘⇧V"`，Settings 选择器显示默认项

### Requirement: 错误内联展示
来自 `global-shortcut` 与 `permissions` 的错误 SHALL 在相应区域中以行内方式展示，而非以模态弹窗形式出现。每个错误在对应操作下一次成功时 SHALL 被清空。

#### Scenario: 快捷键被拒
- 假设 之前发生过快捷键注册失败
- 当 用户打开 Settings → Shortcut
- 则 在选择器下方显示行内警告 "Global shortcut could not be registered."
