## ADDED Requirements

### Requirement: 面板描边为单条 inset stroke

浮层外壳的描边 SHALL 只使用一条 stroke，且 SHALL 向面板圆角边缘**内**侧偏移（`panelShape.inset(by:)`），**不得**在面板圆角边缘同位置再叠加第二条带 `offset(...)` 或 `blur(...)` 的描边。

理由：两条 stroke 在 `panelShape` 同一边缘叠加时，由于第二条带 `offset(y: ...)` 在圆角拐点附近仅做平移而不沿曲线插值，会在四个圆角处产生 1px 错位的 L 形伪影。inset 后的单条描边与边缘空间上分开，从几何上消除错位源。

#### Scenario: 浮层四角无可视 L 形描边错位

- **WHEN** 浮层打开且显示任意数量卡片
- **THEN** 浮层外壳的四个圆角边缘 SHALL NOT 出现 1px 量级的 L 形描边错位或亮线断裂
- **AND** 浮层圆角 SHALL 完整且连续，无可感知的高光"光脚"

#### Scenario: 描边实现层只存在一条 stroke

- **WHEN** 维护者阅读 `BottomPanelView.panelContainer` 的 modifier 链
- **THEN** 面板描边 SHALL 只由一处 `.overlay { ... .stroke(...) }` 实现，且该 stroke 路径 SHALL 是 `panelShape.inset(by:)` 的结果
- **AND** 不得存在第二条带 `offset(...)` 或 `blur(...)` 后再 `.stroke(...)` 的 overlay

#### Scenario: 阴影链保持现状

- **WHEN** 浮层打开
- **THEN** 浮层外壳 SHALL 继续渲染两条 `shadow`（橙色品牌 glow + 暗色近阴影），其颜色、半径、`y` 偏移 SHALL 与本变更前一致
- **AND** 浮层 SHALL 继续使用 `VisualEffectView` 系统材质与 `panelTint` 三层渐变
