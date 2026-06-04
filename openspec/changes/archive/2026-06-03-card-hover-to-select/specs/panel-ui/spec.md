## ADDED Requirements

### Requirement: 鼠标悬停立即选中卡片
当鼠标进入浮层 timeline 中某张卡片的可点击区域时，系统 SHALL 立即将该卡片的 id 写入 `ClipboardStore.selectedID`，并复用现有"选中"视觉态（4pt 描边、阴影、缩放 1.025、y -5）作为唯一高亮来源。系统 SHALL NOT 引入第二种高亮态（hovered ≠ selected 时不再有独立视觉差异）。

悬停路径 SHALL NOT 调用 `NSApp.keyWindow?.makeFirstResponder(nil)`，不抢搜索框焦点。

键盘 ←/→ 与悬停共享单一 `selectedID` source of truth，互不干扰：谁后动听谁的，不引入键盘保护窗。

悬停路径 SHALL 走 `store.selectFromHover(_:)`，100ms first-wins 节流；不与 `store.select(_:)`（单击 / 键盘 / onAppear 共用）混用。

#### Scenario: 悬停切换选中
- **WHEN** 鼠标从卡片 A 移到卡片 B（A、B 都在 `filteredItems` 中），且距上一次 hover-select 写入已超过 100ms
- **THEN** 卡片 B 立即显示选中视觉态，卡片 A 失去选中视觉态；`store.selectedID` 等于 B 的 id

#### Scenario: 悬停快速来回抑制抖动
- **WHEN** 鼠标在 100ms 内先后进入卡片 A、卡片 B、卡片 A（在 LazyHStack 水平相邻卡之间快速来回）
- **THEN** `store.selectedID` 保持为 A（first-wins，窗口内事件被丢弃），不出现 `snappy(0.18s)` 动画反复启动导致的视觉抖动

#### Scenario: 双击悬停的卡 = 复制该卡
- **WHEN** 鼠标悬停在卡片 C 上并保持悬停状态
- **AND** 用户在该卡上双击
- **THEN** `onPaste` 回调触发且 `store.selectedItem` 等于 C（与悬停一致）

#### Scenario: 搜索框 focus 时悬停不抢焦
- **WHEN** 搜索框处于 focus 状态且 `searchText` 非空
- **AND** 鼠标悬停到任意卡片上
- **THEN** `store.selectedID` 更新为该卡 id；搜索框保持 focus，可继续接收键盘输入

#### Scenario: 悬停后键盘 ← 移动
- **WHEN** 鼠标悬停在卡片 D 上使 D 成为 selected
- **AND** 用户按键盘 ← 键
- **THEN** 选中按 `store.moveSelection(-1)` 规则移动到 D 的左邻卡片；悬停位置不再影响选择

#### Scenario: 拖动滚动 timeline
- **WHEN** 用户在 `ScrollView` 上拖动 timeline 使某些卡片滚出可视区
- **THEN** 滚出可视区的卡片若仍持有 hover 状态，写入 `store.selectedID` 的最后值在下一次 `selectFirstVisibleItem()` 被覆盖前保留（无残留副作用）

#### Scenario: hover 不触发 ScrollView 自动滚动
- **WHEN** 鼠标悬停从卡片 A 移到卡片 B，selectedID 跟随变化
- **THEN** `BottomPanelView` 的 `onChange(of: store.selectedItem?.id)` 因 `lastUserSelectAt` 未在 0.3s 内被刷新而跳过 `proxy.scrollTo`；`ScrollView` 不滚动，无"卡片被推着走"的视觉反馈

#### Scenario: 主动选择仍触发 ScrollView 居中
- **WHEN** 用户单击卡片 C / 按键盘 ←/→ 选中卡片 D / 复制产生新卡片 E
- **THEN** `lastUserSelectAt` 被刷新到当前时间，`onChange` 检查通过，ScrollView 把目标卡片滚动到 `.center` 位置（保持既有 snappy(0.18s) 动画）

#### Scenario: 浮层关闭后再次打开
- **WHEN** 浮层已关闭后再次被召唤
- **THEN** `BottomPanelView.onAppear` 调用 `selectFirstVisibleItem()`，悬停写入的最后 `selectedID` 被覆盖为 `filteredItems.first`
