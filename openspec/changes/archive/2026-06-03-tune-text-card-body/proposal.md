## Why

在 236×236 卡片中，文本 kind 的正文以 16pt regular + lineSpacing(3) + lineLimit(7) 渲染，理论占位 155pt，溢出可用 145pt 区约 10pt；其中 70% 实色起点以下的渐变蒙版（0.12 终点）又遮蔽了底部 30%。实际稳定可读约 4.5 行，约 231 字。同时 16pt 与 URL 卡片副文（13pt medium）字号不对齐，在卡片家族里成为"独苗"，破坏视觉层级。

## What Changes

- `Sources/Copythat/Views/ClipboardCardView.swift` 中 `textPreview` 的 `Text(item.preview)` 字号 `16` → `13`，`weight: .regular` 不变
- 同视图 `lineSpacing(3)` → `lineSpacing(1.5)`
- 同视图 `lineLimit(7)` → `lineLimit(8)`
- 同视图移除底部 `LinearGradient` 蒙版和 `.fixedSize(horizontal: false, vertical: false)`
- 保留 `VStack` 结构、`Spacer(minLength: 0)`、"X characters" footer（12pt medium）以及 padding `(.horizontal, 16) / (.top, 14) / (.bottom, 9)`

## Non-goals

- 不动其他 kind（image / url / file）卡片的视觉与版式
- 不动卡片几何（236×236）、header 高度（48pt）、卡片圆角、阴影、选中态动效
- 不修改 `ClipboardItem` 的 `preview` 截断阈值（240 字符，`ClipboardStore.swift:261`）
- 不修改 `item-rendering/spec.md` 现有 requirement —— 本次是实现级排版调优，"展示截断到合适长度的 preview" 的行为契约不变
- 不引入新的 spec 条款；不在 `openspec/specs/` 下新建文件
- 不调整 footer 的 12pt 字号、颜色、文案与居中对齐

## Capabilities

### New Capabilities

无。

### Modified Capabilities

无。`item-rendering` 的现有 requirement 仅约束按 `kind` 切换的预览与字体回退（`item-rendering/spec.md` Requirement: 字体 / 按 kind 切换的预览），未规定字号、行距、行数或渐变；本次变更不触及需求层。

## Impact

- 受影响代码：`Sources/Copythat/Views/ClipboardCardView.swift`，仅 `textPreview` 视图函数（约 30 行内）
- 公共 API：无
- 依赖变更：无
- 测试影响：`Tests/CopythatTests/` 不涉及 SwiftUI 视图；不新增测试
- 行为影响：用户可见——文本卡片单卡可读字符数从约 231 提升到约 336（+45%），底部字符计数标签与无渐变后的实色截止更干净
