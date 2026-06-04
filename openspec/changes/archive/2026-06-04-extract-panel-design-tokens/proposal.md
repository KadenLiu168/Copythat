## Why

`BottomPanelView.swift` 的视觉 token（`panelCornerRadius: 26`、`.inset(by: 0.5)` 与 `lineWidth: 1` 的耦合、`.opacity(0.55)`、两层 shadow 的 RGB/半径/`y` 偏移、品牌橙 `Color(red: 0.95, green: 0.47, blue: 0.10)` 的多处硬编码）全部以裸字面量散布在视图体内；最近三次提交（`129a7ac`、`05651db`、当前 WIP diff）反复重写同一 `.overlay` 块，而 `lineWidth` 与 `inset` 的强耦合关系（`inset` 必须等于 `lineWidth/2` 才不漂出 `clipShape`）没有任何命名约束。`Sources/Copythat/Support/` 11 个文件里没有 Theme/DesignSystem/Tokens/Spacing 模块，`CopythatFont` 是孤例而没有 `CopythatColor` / `CopythatRadius`。这种"散落 token + 字节级重复"是后续视觉 polish 反复回踩同一块代码的根因，必须现在抽出，否则下一个 bump `lineWidth` 的改动会静默把上轮刚修好的 L 形伪影再带回来。

## What Changes

- 新增 `Sources/Copythat/Support/CopythatTokens.swift`：以嵌套 enum 形式导出 `CopythatTokens.Panel`（`cornerRadius`、`strokeWidth`、`strokeInset`、`strokeOpacity`、`shadowOrange`、`shadowBlack`）与 `CopythatTokens.Brand.accent`，所有数值与当前视觉一字不差。
- 新增 `Sources/Copythat/Support/GlassHairline.swift`：提供 `View.glassHairline()` 修饰符，封装当前 `panelShape.inset(by: 0.5).stroke(.white.opacity(0.55), lineWidth: 1)` 的视觉，使面板描边与搜索胶囊描边共享同一 token。
- 修改 `Sources/Copythat/Views/BottomPanelView.swift`：
  - L5 `panelCornerRadius` 引用 `CopythatTokens.Panel.cornerRadius`
  - L74-78 用 `CopythatTokens.Panel.strokeWidth/Opacity/Inset` + `.glassHairline()` 替换内联 `.overlay { stroke }`
  - L79-80 用 `CopythatTokens.Panel.shadowOrange/Black` 替换内联 `.shadow(...)`
  - L156 搜索胶囊改用 `.glassHairline()`，删除内联 `.overlay { Capsule().stroke(...) }`
  - 删除 L71 的 `.background(Color.clear)`（已确认为 no-op）
- 保留 L81 `.compositingGroup()`（design.md 显式决策，A/B 验证后另立 change）

## Capabilities

### New Capabilities

- `design-tokens`: 集中定义面板与品牌相关的视觉 token（圆角、描边、阴影、品牌色），是首个 `Support/` 下的视觉常量模块。
- `glass-hairline`: 玻璃质感 1pt 白色描边修饰符 `View.glassHairline()`，统一面板与搜索胶囊的同款描边视觉。

### Modified Capabilities

- `panel-ui`: 新增 Requirement"面板描边 token 与共享修饰符"——明确面板描边必须由 `CopythatTokens.Panel.stroke*` 与 `View.glassHairline()` 表达，禁止内联 `.stroke(.white.opacity(...), lineWidth: 1)`。这是契约层强化，不引入新的 UI 行为。

## Impact

- 受影响代码：
  - 新增 `Sources/Copythat/Support/CopythatTokens.swift`（约 30 行）
  - 新增 `Sources/Copythat/Support/GlassHairline.swift`（约 8 行）
  - 修改 `Sources/Copythat/Views/BottomPanelView.swift`（约 10 行）
- 公共 API：无破坏性变更（Tokens 是模块内部常量）
- 依赖变更：无
- 行为变化：肉眼几乎无；预期消除"搜索胶囊描边与面板描边可能漂移"的隐患
- 风险：低；`.glassHairline()` modifier 必须保持与现 L77 完全同款 stroke（`InsetShape` 与 `Capsule` 上的 stroke 在 1pt/0.55 opacity 下视觉同源），需视觉回归对照

## Non-goals

- 不调整 `panelCornerRadius`（仍为 26）
- 不调整 `panelTint` 三层渐变与高光区（`Sources/Copythat/Views/BottomPanelView.swift` L86-112 的 6 个 `Color(red:green:blue:)` stop）
- 不替换 `VisualEffectView` 系统材质
- 不动 `ClipboardCardView` 描边/阴影
- 不动橙色 shadow 的颜色、半径、`y` 偏移——本 change 只把它们抽成命名常量，数值不变
- 不动 `.compositingGroup()`（`design-tokens` 不解决 shadow 渲染 A/B 问题）
- 不抽取 `BottomPanelView` 内 30+ 处内联文本色、pinboard 4 色调色板——避免提案失控，下次按需逐个出 change
