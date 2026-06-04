# 固定项与 Pinboard 规范

## Purpose
Copythat 允许用户把任意 `ClipboardItem` 钉住（pinned）并归类到自定义 pinboard。被钉条目在保留策略（`clipboard-history`）与过滤（`search-and-filtering`）里享有特殊地位。本规范描述固定项与 pinboard 的用户行为契约。

## Requirements

### Requirement: 钉切换
系统 SHALL 暴露 `togglePin(item)` 操作，用于翻转条目的 `isPinned` 标志。切换不会改变 `pinboardName`。

#### Scenario: 钉住一个条目
- 假设 有一条未钉的条目
- 当 用户从卡片右键菜单选择 "Pin"
- 则 `isPinned == true`，且卡片上显示钉徽标

#### Scenario: 取消钉住
- 假设 有一条属于 pinboard "Work" 的被钉条目
- 当 用户选择 "Unpin"
- 则 `isPinned == false`，但 `pinboardName` 仍为 `"Work"`（条目仍留在 Work 板，直到被移动或删除）

### Requirement: 移动到 Pinboard
系统 SHALL 暴露 `move(_ item:, toPinboard name:)` 操作，将 `pinboardName` 设为 `name`；若条目尚未被钉，则同时把 `isPinned` 设为 `true`。在不同 pinboard 之间移动保留 `isPinned` 状态。

#### Scenario: 移动到新板
- 假设 有一条未钉条目，存在自定义板 "Ideas"
- 当 用户选择 "Move to Ideas"
- 则 该条目 `isPinned == true` 且 `pinboardName == "Ideas"`

#### Scenario: 在被钉条目间移动
- 假设 有一条 "Work" 中的被钉条目
- 当 用户把它移动到 "Ideas"
- 则 `isPinned` 保持 `true`，`pinboardName == "Ideas"`

### Requirement: 自定义 Pinboard 列表来源
系统 SHALL 从 `pinboardsText` 设置派生 `customPinboards`：按换行切分、去除两端空白、丢弃空行、去重，并保留首次出现的顺序。

#### Scenario: 解析默认板
- 假设 `pinboardsText == "Work\nIdeas"`
- 当 浮层读取自定义 pinboards
- 则 顺序列表为 `["Work", "Ideas"]`

#### Scenario: 容忍空行与重复
- 假设 `pinboardsText == "Work\n\n  Ideas  \nWork\n"`
- 当 浮层读取自定义 pinboards
- 则 顺序列表为 `["Work", "Ideas"]`

#### Scenario: 空列表
- 假设 `pinboardsText == ""` 或只有空白
- 当 浮层读取自定义 pinboards
- 则 列表为空，不提供任何自定义板

### Requirement: Pinboard 切换条
浮层 SHALL 渲染一条横向的 pinboard 切换条，按此顺序包含："All" 选项卡、"Pinned" 选项卡、`customPinboards` 的每一项（按原顺序）、一个用于打开 Settings 的 "+" 入口。当前选中项在视觉上区别显示。

#### Scenario: 切换条组成
- 假设 `customPinboards == ["Work", "Ideas"]`
- 当 浮层打开
- 则 切换条按顺序显示：All、Pinned、Work、Ideas、+

#### Scenario: 选中一个选项卡
- 假设 用户点击 "Work" 选项卡
- 当 点击被注册
- 则 `selectedBoardID` 变为 `.custom("Work")`，`filteredItems` 按 `search-and-filtering` 更新

### Requirement: Pinboard 颜色提示
系统 SHALL 在每个自定义 pinboard 选项卡上显示一个小色点。Pinboard 默认使用系统 accent 颜色，未来增强可支持每板独立配色。

#### Scenario: 默认配色
- 假设 存在自定义板 "Work"
- 当 切换条渲染
- 则 在 "Work" 标签旁显示一个 accent 色色点
