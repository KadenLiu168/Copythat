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
