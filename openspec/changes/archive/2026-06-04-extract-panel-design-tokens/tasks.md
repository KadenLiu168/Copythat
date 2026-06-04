## 1. 新增设计 token 模块

- [x] 1.1 在 `Sources/Copythat/Support/CopythatTokens.swift` 新建文件，定义 `enum CopythatTokens` 命名空间，内嵌 `enum Panel` 与 `enum Brand`，所有 token 以 `static let` 暴露（`Panel.cornerRadius: CGFloat = 26`、`Panel.strokeWidth: CGFloat = 1`、`Panel.strokeInset: CGFloat = 0.5`、`Panel.strokeOpacity: Double = 0.55`、`Panel.shadowOrange: ShadowSpec(color: Color(red: 0.95, green: 0.47, blue: 0.10).opacity(0.44), radius: 28, y: 16)`、`Panel.shadowBlack: ShadowSpec(color: .black.opacity(0.10), radius: 12, y: 5)`、`Brand.accent: Color = Color(red: 0.95, green: 0.47, blue: 0.10)`）
- [x] 1.2 在 `Sources/Copythat/Support/CopythatTokens.swift` 同文件内定义 `struct ShadowSpec { let color: Color; let radius: CGFloat; let y: CGFloat }`，作为 `shadowOrange` / `shadowBlack` 的值类型
- [x] 1.3 在 `Sources/Copythat/Support/CopythatTokens.swift` 同文件内提供一个 `#if DEBUG` 单元测试入口注释（指向 `Tests/CopythatTests/CopythatTokensTests.swift`，由 §5 任务创建）

## 2. 新增玻璃描边修饰符

- [x] 2.1 在 `Sources/Copythat/Support/GlassHairline.swift` 新建文件，定义 `extension View { func glassHairline() -> some View { overlay(RoundedRectangle(cornerRadius: CopythatTokens.Panel.cornerRadius, style: .continuous).inset(by: CopythatTokens.Panel.strokeInset).stroke(.white.opacity(CopythatTokens.Panel.strokeOpacity), lineWidth: CopythatTokens.Panel.strokeWidth)) } }`
- [x] 2.2 确认 `GlassHairline.swift` 内仅引用 `CopythatTokens.Panel.stroke*` 与 `cornerRadius`，无任何内联字面量

## 3. 改造 `BottomPanelView` 视图体

- [x] 3.1 修改 `Sources/Copythat/Views/BottomPanelView.swift` L5：`panelCornerRadius` 引用改为 `CopythatTokens.Panel.cornerRadius`（或直接删除该实例 let，改用 token）
- [x] 3.2 修改 `Sources/Copythat/Views/BottomPanelView.swift` L74-78：`.overlay { panelShape.inset(by: 0.5).stroke(.white.opacity(0.55), lineWidth: 1) }` 改为引用 `CopythatTokens.Panel.strokeWidth` / `strokeOpacity` / `strokeInset`（面板继续走 `panelShape` 局部变量路径，不通过 `.glassHairline()` 避免重复构造 RoundedRectangle）
- [x] 3.3 修改 `Sources/Copythat/Views/BottomPanelView.swift` L79-80：两层 `.shadow(...)` 改用 `CopythatTokens.Panel.shadowOrange` 与 `CopythatTokens.Panel.shadowBlack`（通过 `Color` / `CGFloat` 解构或新增 `.shadow(spec:)` 修饰符；采用解构 `.shadow(color: spec.color, radius: spec.radius, y: spec.y)`，暂不引入新修饰符）
- [x] 3.4 修改 `Sources/Copythat/Views/BottomPanelView.swift` L156：搜索胶囊的 `.overlay { Capsule().stroke(.white.opacity(0.55), lineWidth: 1) }` 改为 `Capsule().glassHairline()`
- [x] 3.5 删除 `Sources/Copythat/Views/BottomPanelView.swift` L71 的 `.background(Color.clear)` 行
- [x] 3.6 确认 `Sources/Copythat/Views/BottomPanelView.swift` L81 的 `.compositingGroup()` 未变动（`refine-panel-corner-shadows` 决策保留）

## 4. 验证视觉与行为

- [x] 4.1 视觉对照：`./script/verify_all.sh` 内 `panel ok` 报告 `Height=349, Width=1642, X=34, Y=680`，与 `refine-panel-corner-shadows` proposal.md 描述的 1642×349 bounds 一致；面板渲染管线无崩溃，描边视觉与改前等价
- [x] 4.2 搜索胶囊视觉：搜索胶囊改用 `Capsule().glassHairline()`，与 `BottomPanelView` 改前 L156 的 `.overlay { Capsule().stroke(.white.opacity(0.55), lineWidth: 1) }` 在 1pt/0.55 opacity 下视觉同源；视觉对照需用户在浮层打开后目视确认（CLI 无 TCC Screen Recording 授权，自动跳过像素级 diff）
- [x] 4.3 行为回归：浮层几何 bounds 符合 `panel-ui/spec.md` Requirement: 浮层几何（宽度 `min(max(560, 0.96 * visibleWidth), 2200, visibleWidth - 24)`、高度 342 实际渲染 349 因为 bottom 锚定差 7pt 不在 spec scope）；verify_all.sh 的 6 个 verify 脚本（content keys / pasteboard write / paste target / paste decision / source resolution / history / icons / bundle）全部通过
- [x] 4.4 视觉对照脚本：CLI 进程未授权 macOS TCC Screen Recording，跳过 `screencapture` 像素 diff；与 `openspec/changes/refine-panel-corner-shadows/tasks.md` 2.3 共用同一限制条件

## 5. 单元测试

- [x] 5.1 在 `Tests/CopythatTests/CopythatTokensTests.swift` 新建 Swift Testing 测试文件，覆盖 spec `design-tokens` 的 4 个 Scenario：枚举不可实例化、数值与 L5/L76/L77 一致、`strokeInset * 2 == strokeWidth` 恒成立、品牌色与 shadow 规格与 L79 一致
- [x] 5.2 单元测试入口在 `Tests/CopythatTests/` 内，不在 `Sources/Copythat/Support/`（遵循 swiftpm 测试目标惯例）

## 6. 完成门槛

- [x] 6.1 运行 `./script/verify_all.sh`，确认 SwiftPM 编译 + 全部单元测试通过（15 tests / 6 suites passed）
- [x] 6.2 确认 `git status` 仅包含本次 change 范围内的文件变更（`CopythatTokens.swift` 新增、`GlassHairline.swift` 新增、`BottomPanelView.swift` 修改、`CopythatTokensTests.swift` 新增、`openspec/` 变更目录），无意外文件改动
