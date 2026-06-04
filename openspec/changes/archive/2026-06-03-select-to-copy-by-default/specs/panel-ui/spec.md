# 浮层 UI 规范（变更中）

> 完整规范见 `openspec/specs/panel-ui/spec.md`。本文件记录本次 change 引入的增量与替换。

## MODIFIED Requirements

### Requirement: 键盘导航

当浮层处于 key 状态时，系统 SHALL 处理：**Return / Enter** 触发当前选中卡片的"提交动作"（语义由 `paste-execution` 决定，受 `settings.autoCopyOnSelect` 控制）；**Esc** 关闭浮层；**← / →** 在卡片间移动选中（不需要循环）。

搜索框获得焦点时，Return / Enter 同样触发提交动作（既有 `onSubmit` 行为不变）。

#### Scenario: 方向键

- 假设 第三张卡片被选中
- 当 用户按右方向键
- 则 第四张卡片被选中，并自动滚动到可见

#### Scenario: Esc 关闭

- 假设 浮层已打开
- 当 用户按 Esc
- 则 浮层被 order out，原来最前的应用重新被激活

#### Scenario: Enter 触发提交（OFF 模式）

- 假设 `autoCopyOnSelect == false`、第三张卡片被选中
- 当 用户按 Return
- 则 第三张卡片的内容被写入系统剪贴板；浮层关闭；**不**激活目标 app；用户可在目标 app 手动 `⌘V`

#### Scenario: Enter 触发提交（ON 模式）

- 假设 `autoCopyOnSelect == true`、第三张卡片被选中、目标 app 存在
- 当 用户按 Return
- 则 卡片内容写入剪贴板 + 目标 app 激活 + 350 ms 后 `⌘V`；浮层关闭

### Requirement: 底部

浮层底部 SHALL 显示以下之一：

1. 行内权限 / 失败消息（`store.permissionMessage` 非空时），附 "Open Settings" 链接按钮
2. 默认提示（无消息时）：根据 `settings.autoCopyOnSelect` 在两种文案间切换
   - `autoCopyOnSelect == true`：`Return paste  -  Esc close  -  {shortcut} show`
   - `autoCopyOnSelect == false`：`Return copy  -  Esc close  -  {shortcut} show`

提交动作成功后**不**在 footer 显示临时反馈；浮层**立即**关闭。浮层关闭本身就是"提交已就位"的视觉信号。

还 SHALL 显示总条目数 `items.count`。

#### Scenario: 缺少无障碍权限（ON 模式）

- 假设 无障碍权限未授予、`autoCopyOnSelect == true`
- 当 浮层打开
- 则 底部显示 "Return paste" + 权限提示入口（首次粘贴时显示行内警告）

#### Scenario: 缺少无障碍权限（OFF 模式）

- 假设 无障碍权限未授予、`autoCopyOnSelect == false`
- 当 浮层打开
- 则 底部显示 "Return copy"；**不**显示权限提示（OFF 模式不依赖无障碍）

#### Scenario: 已授予无障碍权限

- 假设 无障碍权限已授予
- 当 浮层打开
- 则 底部根据 `autoCopyOnSelect` 显示 "Return paste" 或 "Return copy"

## ADDED Requirements

### Requirement: 右键菜单文案随设置切换

卡片右键菜单中的提交动作项 SHALL 根据 `settings.autoCopyOnSelect` 在两种文案间切换：

- `autoCopyOnSelect == true`：`Paste`
- `autoCopyOnSelect == false`：`Copy to Clipboard`

两种文案 MUST 触发**同一**回调（`onPaste`，由 `paste-execution` 决定实际行为）。

提交动作完成后浮层**立即**关闭，无 footer 临时反馈（review 决定）。

#### Scenario: 右键菜单 ON 模式

- 假设 `autoCopyOnSelect == true`
- 当 用户在卡片上右键
- 则 菜单项显示 "Paste"；点击后走完整粘贴链路；浮层立即关闭

#### Scenario: 右键菜单 OFF 模式

- 假设 `autoCopyOnSelect == false`
- 当 用户在卡片上右键
- 则 菜单项显示 "Copy to Clipboard"；点击后仅写剪贴板、不发 `⌘V`；浮层立即关闭

## REMOVED Requirements

无。
