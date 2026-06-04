## ADDED Requirements

### Requirement: 设计 token 集中定义

系统 SHALL 在 `Sources/Copythat/Support/CopythatTokens.swift` 内提供 `CopythatTokens` 命名空间，集中定义面板与品牌相关的视觉常量：

- `CopythatTokens.Panel.cornerRadius` 为面板圆角
- `CopythatTokens.Panel.strokeWidth` 为面板与玻璃描边线宽
- `CopythatTokens.Panel.strokeInset` 为玻璃描边的内缩距离，等于 `strokeWidth` 的一半
- `CopythatTokens.Panel.strokeOpacity` 为玻璃描边的白色不透明度
- `CopythatTokens.Panel.shadowOrange` 为面板的品牌橙色阴影规格（颜色、半径、y 偏移）
- `CopythatTokens.Panel.shadowBlack` 为面板的黑色阴影规格（颜色、半径、y 偏移）
- `CopythatTokens.Brand.accent` 为品牌主色

`CopythatTokens` MUST 用 `enum` 不可实例化命名空间实现；所有 token MUST 以 `static let` 暴露。

#### Scenario: 命名空间不可实例化

- **WHEN** 编译期尝试 `let _ = CopythatTokens()`
- **THEN** 编译失败（`enum` 不可实例化）

#### Scenario: 数值与当前视觉一致

- **WHEN** 读取 `CopythatTokens.Panel.cornerRadius` / `strokeWidth` / `strokeInset` / `strokeOpacity`
- **THEN** 分别为 `26` / `1` / `0.5` / `0.55`，与 `BottomPanelView` 现有 L5/L76/L77 数值一一对应

#### Scenario: strokeInset 严格等于 strokeWidth 一半

- **WHEN** 任意时刻读取 `CopythatTokens.Panel.strokeWidth` 与 `strokeInset`
- **THEN** `strokeInset * 2 == strokeWidth` 恒成立（防止未来 bump `strokeWidth` 时漏改 `strokeInset` 漂出 `clipShape`）

#### Scenario: 品牌色与当前 shadow 一致

- **WHEN** 读取 `CopythatTokens.Brand.accent` / `Panel.shadowOrange` / `Panel.shadowBlack`
- **THEN** 颜色分别与 `BottomPanelView` L79 `Color(red: 0.95, green: 0.47, blue: 0.10)` 品牌橙、`shadow(color: .black.opacity(0.10), radius: 12, y: 5)` 一致；`shadowOrange` 与 `shadowBlack` 的 radius / y 偏移分别保持 `28 / 16` 与 `12 / 5`
