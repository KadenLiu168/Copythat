## Why

`BottomPanelView` 的 `panelContainer` 用两条 `overlay { stroke }`（一条 1px 实线 `@0.66`，一条带 `y:1` 偏移 + `blur(0.5)` 的 `@0.22`）叠在 `RoundedRectangle(cornerRadius: 26)` 上，再挂一对向下 `y` 偏移的 `shadow`（orange radius 28 / black radius 12）。在四个圆角处，这条 1px 偏移的 stroke② 在拐点附近与 stroke① 产生 1px 错位；.compositingGroup() 把它锁进离屏合成，错位无法被 anti-alias 抹平；再加上两个 `y` 偏移向下的 shadow 在圆角被切掉后形成不对称光脚，**最终在面板四个角呈现肉眼可见的 L 形阴影/高光伪影**（截图里面板四角最明显，底部两角尤甚）。

## What Changes

- `Sources/Copythat/Views/BottomPanelView.swift` 的 `panelContainer`：
  - 把主描边改为 `panelShape.inset(by: 0.5).stroke(.white.opacity(0.55), lineWidth: 1)`，从外边缘向内缩 0.5px，与第二条带 `y:1` 偏移的描边在空间上错开
  - **删除** 第二个 `.overlay(alignment: .top) { ... .offset(y: 1) ... }` 整块（`opacity(0.22)` + 0.5 blur 视觉贡献极弱，是 L 形伪影的次级来源）
  - 主描边不透明度从 `0.66` 调到 `0.55`（inset 后视觉重量比原来轻一点，回正匹配）
- 不动 `shadow(...)` 链（保留项目最有辨识度的橙色品牌 glow）
- 不动 `panelShape` 圆角 26、`panelTint` 渐变、`VisualEffectView` 系统材质、`compositingGroup()`

## Non-goals

- 不调整 `panelCornerRadius`（26 不变）
- 不调整 `panelTint` 三层渐变与高光区
- 不替换 `VisualEffectView` 系统材质（不走纯原生路线，避免失去品牌视觉语言）
- 不动卡片（`ClipboardCardView`）的描边/阴影——本次只修外层面板
- 不调整橙色 shadow 的颜色、半径、`y` 偏移
- 不动 `panel-ui/spec.md` 中"窗口样式" requirement（仍是 NSPanel + 系统材质 + 圆角，行为契约不变）
- 不修改 `Sources/Copythat/Services/PanelController.swift`（如果有）的窗口配置

## Capabilities

### New Capabilities

无。

### Modified Capabilities

- `panel-ui`：新增"面板描边为单条 inset stroke"的契约，把"双层描边 + 偏移"显式排除为反例，避免未来修改者重新引入 L 形伪影根因。

## Impact

- 受影响代码：`Sources/Copythat/Views/BottomPanelView.swift`，仅 `panelContainer` 视图函数（约 5 行内）
- 公共 API：无
- 依赖变更：无
- 测试影响：`Tests/CopythatTests/` 不涉及 SwiftUI 视图渲染；不新增测试
- 行为影响：用户可见——面板四角 L 形伪影消除，描边视觉重量从 0.66 单层 + 0.22 偏移双层，变为 0.55 inset 单层（更干净，更接近 system materials 的高光风格）
- 风险：删 `overlay(alignment: .top)` 那条描边后，顶部内边沿失去一层极淡高光（opacity 0.22 + blur 0.5），在浅色桌面上可能比改动前"略平"。已在 trade-off 评估中接受
