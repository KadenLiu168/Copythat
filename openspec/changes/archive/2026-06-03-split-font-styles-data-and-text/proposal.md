## Why

当前 `CopythatFont` 用单一 `Maple Mono NF CN` 等宽字体覆盖浮层、卡片、footer、搜索框与按钮等所有文本。等宽字体是产品差异化的有意选择（数据型字符对齐、字符风格统一），但被不加区分地用在 10–13pt 的副文本、按钮 label、搜索输入等"扫读"场景：阅读拥挤、与 SF Symbol 图标的几何感冲突，且 `monospacedDigit()` 未启用导致时间戳、字符计数、图片尺寸在 layout 切换时数字宽度抖动。

redesign-skill 的修复优先级把"字体替换"列为**最大即时视觉回报、最低风险**的优化点；本变更把"等宽 vs 正文"拆为两个明确语义的字体样式，最小改动、最大改善。

## What Changes

- `CopythatFont` 暴露 `enum Style { case data, text }`，`font(_:size:weight:)` 按样式分流：`data` 继续走 `Maple Mono NF CN`（系统未装则回退 `monospacedDigit()`），`text` 走系统无衬线。
- `ClipboardCardView` 内：保留等宽的"数据型"字符（kind 分类词、时间戳、字符计数、图片尺寸、文件路径、URL host 暂保留以维持对齐），将"正文/标题"类（链接标题、文件标题、`textPreview` 正文、链接副信息、文件副信息）切到 `text`。
- `BottomPanelView` 内：搜索输入框、pinboard 标题、footer 提示语、状态行全部切到 `text`；footer 字号从 10pt 升到 11pt（接近 a11y 下限，可读性优先）。
- `EmptyTimelineView` 文案 "Copy something to start" 保持当前 13pt semibold 字体但切到 `text`（仅字体变化，文案不动）。
- 在 `item-rendering` spec 的"字体"Requirement 中追加 `data` vs `text` 两种样式的语义化定义与使用边界。

不引入新依赖、不替换字体文件、不改 `Maple Mono NF CN` 的现有回退逻辑。

## Capabilities

### New Capabilities

无。新增的"双字体样式"语义由 `item-rendering` 的 MODIFIED Requirement 承载。

### Modified Capabilities

- `item-rendering`: 在"字体"Requirement 中追加 `Style.data`（等宽，用于分类标识符、时间戳、字符计数、图片尺寸、文件路径）与 `Style.text`（系统无衬线，用于卡片正文、标题、按钮 label、状态行）两种样式的语义定义与覆盖范围。

## Impact

- 源码改动：`Sources/Copythat/Support/CopythatFont.swift`、`Sources/Copythat/Views/ClipboardCardView.swift`、`Sources/Copythat/Views/BottomPanelView.swift`、`Sources/Copythat/Views/EmptyTimelineView.swift`
- Spec 改动：`openspec/specs/item-rendering/spec.md` 的"字体"Requirement 增补子条款
- 依赖：无新增
- 行为：纯外观变化，无功能、API、持久化、热键、权限影响
- 风险：低。`CopythatFont.font(_:size:weight:)` 保留原 `font(size:weight:)` 调用兼容（默认 `.text`，但旧调用点全部迁移到显式 style）

## Non-goals

- 不替换 `Maple Mono NF CN` 字体文件或选用其它字体（如 `Geist`、`SF Mono`）
- 不引入第二款等宽字体
- 不改 `Maple Mono NF CN` 的系统回退逻辑（仍回退系统等宽）
- 不改 `EmptyTimelineView` 的提示语文案（保持 "Copy something to start"）
- 不动卡片几何（236×236、圆角 23、间距 28）
- 不动 panel 高 342pt、键盘交互、sourceAccent 算法
- 不引入 `design token` / `Theme` 文件（下一轮再议）
- 不修 `prefersDarkForeground` 阈值、浮层阴影颜色、卡片选区动效
- 不涉及 footer 文案重写、字号以外的间距节奏调整
