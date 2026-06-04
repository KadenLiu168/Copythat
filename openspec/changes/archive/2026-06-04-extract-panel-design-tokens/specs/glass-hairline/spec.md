## ADDED Requirements

### Requirement: 玻璃描边修饰符统一面板与胶囊的同款描边视觉

系统 SHALL 在 `Sources/Copythat/Support/GlassHairline.swift` 内提供 `View.glassHairline()` 修饰符，其内部用 `CopythatTokens.Panel.strokeWidth / strokeOpacity / strokeInset / cornerRadius` 生成 1pt、内缩 `strokeInset`、白色不透明度 `strokeOpacity` 的圆角描边，并覆盖在被修饰视图上。

`BottomPanelView` 的搜索胶囊 SHALL 改用 `Capsule().glassHairline()` 替代原本的内联 `.overlay { Capsule().stroke(.white.opacity(0.55), lineWidth: 1) }`。

#### Scenario: 胶囊描边由修饰符表达

- **WHEN** 浮层渲染且搜索胶囊展开
- **THEN** 胶囊上的 1pt 白色描边由 `View.glassHairline()` 提供，视觉与改前 L156 等价

#### Scenario: 修饰符不重复构造 RoundedRectangle

- **WHEN** 编译期检查 `View.glassHairline()` 的实现
- **THEN** 修饰符内部 MUST 仅用 `RoundedRectangle(cornerRadius: CopythatTokens.Panel.cornerRadius, style: .continuous)` 一次构造，不可重复调用 shape 构造器
