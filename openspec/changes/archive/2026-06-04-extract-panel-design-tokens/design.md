## Context

`Sources/Copythat/Views/BottomPanelView.swift` 的视觉常量目前以裸字面量散布在视图体内：

- L5 `private let panelCornerRadius: CGFloat = 26`
- L76-77 `.overlay { panelShape.inset(by: 0.5).stroke(.white.opacity(0.55), lineWidth: 1) }`
- L79-80 两层 `.shadow(...)`：orange `Color(red: 0.95, green: 0.47, blue: 0.10).opacity(0.44)` radius 28 y 16；black `Color.black.opacity(0.10)` radius 12 y 5
- L156 搜索胶囊的同款描边 `.overlay { Capsule().stroke(.white.opacity(0.55), lineWidth: 1) }`

`Sources/Copythat/Support/` 11 个文件均为功能性 utility（持久化、字体、图标、相对时间等），唯一含视觉常量语义的是 `CopythatFont`（字体封装），无 Theme/DesignSystem/Tokens/Spacing 模块。

git log 显示 panel 视觉已经被反复重写：

- `129a7ac Redesign clipboard panel and cards`
- `05651db 优化卡片顶部 logo 与复制文本显示`
- 当前 working-tree diff（对应进行中 change `refine-panel-corner-shadows`）再一次改同一个 `.overlay` 块

没有任何 token 把 `lineWidth` 与 `inset`（必须 `= lineWidth/2` 才不漂出 `clipShape`）的耦合关系表达出来。设计 `View.glassHairline()` 是为了让该耦合在一处表达完整。

stakeholders：仅 `BottomPanelView`（未来 `ClipboardCardView`、`SettingsView` 可受益，但不属本次范围）。

## Goals / Non-Goals

**Goals:**

- 把当前 `BottomPanelView` 视图中视觉相关的字面量（圆角、描边、阴影、品牌色）抽到 `Sources/Copythat/Support/CopythatTokens.swift`，数值一字不差
- 用 `View.glassHairline()` 修饰符统一面板与搜索胶囊的 1pt/0.55 opacity 描边视觉
- 删除 L71 的 `.background(Color.clear)`（已确认为 no-op）
- 为未来 `lineWidth` 调整提供"改一个常量、自动维持 inset 同步"的契约

**Non-Goals:**

- 不抽 `panelTint`（L86-112）的 6 个渐变 stop 颜色
- 不抽 pinboard 4 色调色板（L320-325）
- 不抽 `BottomPanelView` 内 30+ 处内联文本色
- 不动 `panelCornerRadius` 数值（26 不变）
- 不动 `ClipboardCardView` 描边/阴影
- 不动 `VisualEffectView` 系统材质
- 不重审 `.compositingGroup()`（原 `refine-panel-corner-shadows` 的 design.md:108-117 显式决策保留为"低成本保险"，A/B 验证后另立 change）
- 不新增 `Tests/CopythatTests/` 单元测试：token 是静态常量、`View.glassHairline()` 是 SwiftUI 视图修饰符，单元测试覆盖成本与收益不匹配（视觉行为由 `script/build_and_run.sh --verify-panel` + 目视对照覆盖）

## Decisions

### Decision 1: 嵌套 enum 表达命名空间

选择 `enum CopythatTokens { enum Panel { ... }; enum Brand { ... } }` 而非：

- ~~`struct CopythatTokens`~~：实例化后是值类型，意图上 token 应是不可变命名空间，enum 不可实例化更直接
- ~~`enum CopythatTokens.Panel` 顶级 enum~~：会把 `CopythatTokens` 拆成多个顶级类型，破坏 single-file 可发现性
- ~~`@frozen struct` 嵌套 + `static let`~~：与 enum 行为等价但更冗长

`enum` 内的 `static let` 在 Swift 中已是惰性初始化、Cold-enough 不存在线程安全问题；`Sources/Copythat/Support/CopythatFont.swift` 已用 `enum CopythatFont` 模式，本次沿用以保持 `Support/` 风格一致。

### Decision 2: `View.glassHairline()` 而不是 `Shape.strokeGlass()`

选择 `extension View` 上的 `.glassHairline()` 修饰符：

- 复用方都已经在 `.overlay { shape.stroke(...) }` 模式里写一次，再提供第二个 `Shape.strokeGlass()` 仍要调用方包 overlay，多一层间接
- `extension View` 调用链可读性更优：`.glassHairline()` 跟在 `.background(...)` `.clipShape(...)` 后面自然
- 与 SwiftUI 标准库（`.border(...)`、`.strokeBorder(...)`、`.foregroundStyle(...)`）的修饰符命名风格一致

修饰符内部统一生成 `.overlay { RoundedRectangle(cornerRadius: ...).inset(by: CopythatTokens.Panel.strokeInset).stroke(.white.opacity(CopythatTokens.Panel.strokeOpacity), lineWidth: CopythatTokens.Panel.strokeWidth) }`（面板场景）与 `.overlay { Capsule().stroke(.white.opacity(CopythatTokens.Panel.strokeOpacity), lineWidth: CopythatTokens.Panel.strokeWidth) }`（搜索胶囊场景）—— 但因两者 shape 不同，决定**不**用同一修饰符覆盖两种 shape，而是把 stroke 视觉规格抽成 token，由两个调用点各自以自己的 shape 引用 token。`.glassHairline()` 仅用于"以当前 shape 套 1pt/0.55 stroke" 的语法糖：

```swift
extension View {
    func glassHairline() -> some View {
        overlay(
            RoundedRectangle(cornerRadius: CopythatTokens.Panel.cornerRadius, style: .continuous)
                .inset(by: CopythatTokens.Panel.strokeInset)
                .stroke(.white.opacity(CopythatTokens.Panel.strokeOpacity), lineWidth: CopythatTokens.Panel.strokeWidth)
        )
    }
}
```

调用方：

- 面板：继续在 `RoundedRectangle` 上用 `panelShape.inset(...).stroke(...)` 直接引用 token（**不**用 `.glassHairline()`，因为 `panelShape` 已是形状局部变量；用 `.glassHairline()` 会重复构造一次 RoundedRectangle）
- 搜索胶囊：`Capsule().glassHairline()` 替代 `.overlay { Capsule().stroke(.white.opacity(0.55), lineWidth: 1) }`

这是为了避免"为了消除两行重复就改架构"的过度抽象。如果未来 `ClipboardCardView` 也要同款描边，那时再把面板也换成 `.glassHairline()` 调用（接受一次 RoundedRectangle 重建的代价，换一致性）。

### Decision 3: shadow 用 `static let` 存储 tuple 还是 `extension View` 提供 `.panelShadow()`

选择 `static let shadowOrange: ShadowSpec` 与 `static let shadowBlack: ShadowSpec`（自定义 struct 包装 color/radius/y），调用方写 `.shadow(spec: CopythatTokens.Panel.shadowOrange)`。

~~备选~~：提供 `.panelShadow()` 修饰符一次挂两层。**否决**——两层 shadow 的语义不总是相同（未来若加 1 层变 3 层、改 offset y 等），用 token 表达单层比一次挂两层更灵活；`refine-panel-corner-shadows` 已经声明"shadow 链保持现状"，本 change 不改变 shadow 数量与顺序。

### Decision 4: 删除 `.background(Color.clear)` 而非保留

`.background(Color.clear)` 在 ZStack 上无 size 提案效果（ZStack 已是透明），且 codebase 内 `.background(Color.clear)` 只此一处。删除后无视觉/行为/可访问性差异。`refine-panel-corner-shadows` 的 design.md 不涉及该 modifier，本次作为低风险顺手清理。

### Decision 5: 不引入 Theme/DesignSystem 顶层模块

本 change 引入 `CopythatTokens` 而不是更宏大的 `Theme` 或 `DesignSystem`，原因：

- 抽到 `CopythatTokens` 是把"已有且反复改动的字面量"集中；扩到 Theme 就要重新决定层级（亮/暗、accent vs semantic、color scheme），是产品决策不是 refactor
- `refine-panel-corner-shadows` 显式说"不动 `panel-ui/spec.md` 中'窗口样式' requirement（仍是 NSPanel + 系统材质 + 圆角，行为契约不变）"——本 change 同样不动 spec 的行为契约，只补一条"token 必须存在"的契约

未来若需 Theme/DesignSystem，自然由 `design-tokens` 这个 spec 承接扩展。

## Risks / Trade-offs

- **[R1] `.glassHairline()` 内部 `RoundedRectangle` 重建** → 接受；面板仍走原有 `panelShape` 局部变量路径，搜索胶囊只多一次 `RoundedRectangle` 构造（单 frame 一次，< 1μs）
- **[R2] shadow 抽成 token 后未来若改单层数值要改 token 定义** → 这是目标：让单层数值变更只改一处
- **[R3] `View.glassHairline()` 与未来 `Theme.glassHairline(opacity:)` 重名** → 留口子：若未来加 Theme，把 `glassHairline()` 改为 `glassHairline(opacity: CopythatTokens.Panel.strokeOpacity)`，本 change 暂不加参数以避免 YAGNI
- **[R4] `.background(Color.clear)` 删除对老 macOS / 老 SwiftUI 版本的兼容性** → 目标平台是 macOS 14 (`.v14`)，该 modifier 自 macOS 10.15 起就是 no-op，无兼容性问题
- **[R5] `enum` 嵌套 token 与现有 `CopythatFont` enum 共存** → 命名风格一致，调用方以 `CopythatTokens.Panel.cornerRadius` / `CopythatFont.font(size:weight:)` 对称调用

## Migration Plan

- 一次性提交；改动范围 `BottomPanelView.swift` 10 行 + 新增 2 个文件共 ~38 行
- 无需数据迁移、无需 feature flag、无需分阶段
- 回滚：单次 commit revert 即可
- 验证步骤见 `tasks.md` §3

## Open Questions

- 无。所有 token 数值与当前视觉一一对应（design.md §Decision 2/3 给出明确的命名规范与调用方式），没有需要用户进一步决策的事项
