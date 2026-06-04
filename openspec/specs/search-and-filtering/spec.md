# 搜索与过滤规范

## Purpose
Copythat 浮层提供一个搜索胶囊与一个 pinboard 切换条，两者的筛选结果在内存中以单一 `filteredItems` 数组对外呈现。本规范描述过滤的语义、组合顺序与性能预算。

## Requirements

### Requirement: 板选择器
系统 SHALL 支持 `selectedBoardID` 为以下之一：`.all`（全部历史）、`.pinned`（仅被钉条目）、`.custom(name)`（`pinboardName` 等于给定名称的条目）。

#### Scenario: 全部板
- 假设 `selectedBoardID == .all`
- 当 用户打开浮层
- 则 显示每一条历史条目（受搜索过滤约束）

#### Scenario: Pinned 板
- 假设 `selectedBoardID == .pinned`
- 当 用户打开浮层
- 则 只显示 `isPinned == true` 的条目

#### Scenario: 自定义板
- 假设 `selectedBoardID == .custom("Work")`
- 当 用户打开浮层
- 则 只显示 `pinboardName == "Work"` 的条目（无论 `isPinned`）

### Requirement: 搜索过滤
系统 SHALL 将浮层的 `searchText` 视为对每个条目 `searchText` 字段（定义见 `clipboard-history`）的不区分大小写子串匹配。

#### Scenario: 子串匹配
- 假设 历史中包含标题为 "Design notes" 与 "Project brief" 的条目
- 当 用户输入 "design"
- 则 `filteredItems` 中只剩 "Design notes"

#### Scenario: 空搜索
- 假设 `searchText == ""`
- 当 浮层刷新
- 则 搜索条件不参与过滤；只剩板过滤生效

### Requirement: 复合过滤
系统 SHALL 按"先搜索、后板"顺序施加两个过滤，AND 组合：条目必须同时通过两个过滤才会被显示。

#### Scenario: 在 Pinned 板中搜索
- 假设 `selectedBoardID == .pinned` 且 `searchText == "openai"`
- 当 浮层刷新
- 则 结果为 `{item ∈ history | isPinned(item) 且 searchText 包含 "openai"}`

### Requirement: 过滤性能
系统 SHALL 在开发者 Mac 上对 5 000 条历史在 100 毫秒内产生 `filteredItems`，端到端计时（搜索 + 板）。

#### Scenario: 5 000 条搜索
- 假设 5 000 条历史中，恰好有一条包含字符串 "4997"
- 当 用户输入 "4997"
- 则 `filteredItems.count == 1`，且刷新在 100 毫秒内完成
