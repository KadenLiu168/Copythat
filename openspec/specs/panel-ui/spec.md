# 浮层 UI 规范

## Purpose
Copythat 在用户召唤时呈现一个底部悬浮浮层（"bottom panel"），承载搜索、pinboard 切换与卡片时间线。浮层是用户与历史交互的单一窗口；本规范描述其外观、几何、键盘行为与可见区域规则。
## Requirements
### Requirement: 浮层几何
系统 SHALL 将浮层高度固定为 342 pt；宽度为 `min(max(560, visibleFrame.width * 0.96), 2200, visibleFrame.width - 24)`。浮层 SHALL 水平居中于可见区域，底部上移 24 pt（或当 `prefersScreenBottomAnchor` 为 true，或目标应用的窗口触到可见区域底部时，锚定到屏幕物理底部）。

#### Scenario: 标准桌面
- 假设 可见区域为 1440 × 900
- 当 浮层打开
- 则 宽度 1382（在 560–2200 内），高度 342，y 距底 24 pt，x 居中

#### Scenario: 超宽屏
- 假设 可见区域宽 4 000 pt
- 当 浮层打开
- 则 宽度 2 200（最大值），仍居中

#### Scenario: 窄屏
- 假设 可见区域宽 400 pt
- 当 浮层打开
- 则 宽度为 `400 - 24 = 376`（可用宽度约束），不再受 560 下限限制——可用宽度优先

#### Scenario: 锚定到物理屏底
- 假设 目标应用的窗口触到可见区域底部
- 当 浮层打开
- 则 浮层 `y` 为 `screenFrame.minY + 24`（锚定到物理屏幕，而不是可见区域）

### Requirement: 多屏感知
系统 SHALL 把浮层放在激活时鼠标所在屏幕上；若鼠标移动到另一屏，则重新评估放置。

#### Scenario: 鼠标在副屏
- 假设 有两块屏幕，鼠标在右边那块
- 当 用户触发全局快捷键
- 则 浮层出现在右屏，按该屏的可见区域大小计算

### Requirement: 窗口样式
浮层 SHALL 是一个无边框、浮动、accessory 类型的 `NSPanel`，背景为透明的 `NSVisualEffectView`，带圆角，`canBecomeKey == true` 以接收键盘事件。

#### Scenario: 浮于其它应用之上
- 假设 有一个普通应用处于最前
- 当 用户召唤浮层
- 则 浮层置顶，但不把之前的前台应用拉到最前

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

### Requirement: 顶部
浮层顶部 SHALL 依次包含（从左到右）：绑定 `searchText`（见 `search-and-filtering`）的搜索胶囊、按 `pinning-and-pinboards` 的横向可滚动 pinboard 切换条、以及一个打开 Settings 的 "+" 入口。

#### Scenario: 搜索展开 / 收起
- 假设 浮层已打开且 `searchText` 为空
- 当 用户点击搜索胶囊
- 则 胶囊展开为可输入文本框；点击外部或按 Esc 收起

#### Scenario: Settings 入口
- 假设 浮层已打开
- 当 用户点击 "+" 按钮
- 则 Settings 窗口被带到最前

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

### Requirement: 空态
当 `filteredItems` 为空时，浮层 SHALL 显示居中的透明 app 标 + 一行提示（例如 "No clipboard history yet — copy something to get started"）。

#### Scenario: 首次启动
- 假设 历史为空
- 当 浮层打开
- 则 显示空态，而非空白的卡片行

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

## ADDED Requirements

### Requirement: 面板描边由 token 与共享修饰符表达

`BottomPanelView` 的面板描边 SHALL 由 `CopythatTokens.Panel.strokeWidth / strokeOpacity / strokeInset` 表达，不允许在 `BottomPanelView` 视图体内出现内联的 `.stroke(.white.opacity(<数字>), lineWidth: <数字>)` 字面量（`View.glassHairline()` 内部对 `CopythatTokens.Panel.*` 的引用除外）。

`BottomPanelView` 视图体内 MUST NOT 出现 `.background(Color.clear)` 这类已被识别为 no-op 的 modifier。

`BottomPanelView` 的两层 `.shadow(...)` SHALL 改用 `CopythatTokens.Panel.shadowOrange` 与 `CopythatTokens.Panel.shadowBlack`，数值与原 `.shadow(color: Color(red: 0.95, green: 0.47, blue: 0.10).opacity(0.44), radius: 28, y: 16)` 与 `.shadow(color: .black.opacity(0.10), radius: 12, y: 5)` 一致。

`BottomPanelView` 的 `.compositingGroup()` SHALL 保持不变。

#### Scenario: 面板描边无内联字面量

- **WHEN** 在 `Sources/Copythat/Views/BottomPanelView.swift` 视图体内 grep `.stroke(.white.opacity(`
- **THEN** 命中数 ≤ 1（即搜索胶囊的 `Capsule().glassHairline()` 展开后产生的引用，面板描边本体不再有内联字面量）

#### Scenario: 不再出现 .background(Color.clear)

- **WHEN** 在 `Sources/Copythat/Views/BottomPanelView.swift` 视图体内 grep `.background(Color.clear`
- **THEN** 命中数为 0

#### Scenario: 阴影由 token 提供

- **WHEN** 浮层渲染
- **THEN** 面板呈现的橙色 + 黑色双层阴影与 `CopythatTokens.Panel.shadowOrange` / `shadowBlack` 的 (color, radius, y) 三元组完全一致；与原 L79-80 视觉无差异

