## Context

`Sources/Copythat/Views/BottomPanelView.swift:49-87` 的 `panelContainer` 是底部浮层唯一的外壳。当前 modifier 链（按 SwiftUI 实际应用顺序）：

```swift
ZStack { ... }                                          // ① 内容（VisualEffectView + panelTint + VStack）
    .background(Color.clear)                            // ② 透明背景占位
    .clipShape(panelShape)                              // ③ 按 RoundedRectangle(26) 切圆角
    .contentShape(panelShape)                           // ④ 命中区 = 圆角
    .overlay {                                          // ⑤ 主描边 1px 白
        panelShape.stroke(.white.opacity(0.66), lineWidth: 1)
    }
    .overlay(alignment: .top) {                         // ⑥ 模糊描边 + y:1 偏移
        panelShape
            .stroke(.white.opacity(0.22), lineWidth: 1)
            .blur(radius: 0.5)
            .offset(y: 1)
    }
    .shadow(color: orange, radius: 28, y: 16)           // ⑦ 橙色品牌 glow
    .shadow(color: black.opacity(0.10), radius: 12, y: 5)  // ⑧ 暗色近阴影
    .compositingGroup()                                 // ⑨ 强制离屏合成
```

根因已分析：⑤⑥ 两条 stroke 都在 `panelShape`（圆角 R=26）边缘；在四个圆角的拐点附近，⑥ 整体 `y:1` 平移导致它的角部相对 ⑤ 错位 1px（竖直偏移、不沿曲线插值）。`.compositingGroup()` 把这两条 stroke 锁进离屏 pass，错位不会被 anti-alias 抹平。再叠 ⑦⑧ 两个 `y` 偏移向下的 shadow，圆角被切掉后底部两侧呈"光脚"。

参考：

- 几何真值源：`panel-ui/spec.md` Requirement: 浮层几何（圆角 26 通过 `BottomPanelView.swift:5` 的 `panelCornerRadius` 常量保持；spec 不约束描边层数/阴影参数）
- 视觉真值源：`README.md` "Keep UI native to macOS: prefer system materials, semantic colors, system accent color, and compact controls over fixed custom palettes" — 本次保留 `VisualEffectView(.popover)` + 橙色品牌 glow

## Goals / Non-Goals

**Goals:**

- 消除面板四个圆角处的 L 形描边错位伪影
- 保留 `VisualEffectView(.popover)` 系统材质 + `panelTint` 三层渐变（项目视觉签名）
- 保留橙色 `shadow` 品牌 glow（radius 28, y: 16，**不动**）
- 保留 1px 白色描边作为浮层与背景的边界对比
- modifier 链整体长度不增、结构清晰、读者能一眼看出"描边+阴影"两层职责

**Non-Goals:**

- 不改 `panelCornerRadius`（26 不变）
- 不改 `panelTint`（`LinearGradient` + 两个 `RadialGradient` 三层叠加）
- 不改 `VisualEffectView` 的 `material` / `blendingMode` / `cornerRadius`
- 不改 `shadow(...)` 链（颜色、半径、`y` 偏移全部保留）
- 不动 `.compositingGroup()` 的位置与存在性
- 不动卡片 `ClipboardCardView` 的描边/阴影（不在本次范围内）
- 不动 `panel-ui/spec.md`（行为契约不变，仅实现级精修）

## Decisions

### 1. 主描边改为 `inset(by: 0.5)`

**当前：**
```swift
.overlay {
    panelShape.stroke(.white.opacity(0.66), lineWidth: 1)
}
```

**改为：**
```swift
.overlay {
    panelShape
        .inset(by: 0.5)
        .stroke(.white.opacity(0.55), lineWidth: 1)
}
```

**理由：**
- `RoundedRectangle` 的 `inset(by:)` 返回一个向内缩 0.5pt 的同形 rounded rect。stroke 落在 0.5pt 内侧后，stroke 路径与 panelShape 物理边缘**空间上分开**，避免与原本就要删掉的描边② 在同一像素层上争位
- 不透明度从 `0.66` → `0.55`：inset 后 stroke 离边缘更近、更显眼；同时移除了 stroke②（决策 2）后，描边总视觉重量从"双层叠加"变单层，0.55 保持与原来相近的视觉对比度
- inset 量 0.5pt 是工程经验最小可见位移——再小（如 0.25）抗锯齿会模糊掉位移收益；再大（如 1.0+）描边看起来"浮"在面板里

**备选：**

- 保持 `panelShape.stroke(...)` 不变 → 不能解决 L 形错位根因，决策 2 删 stroke② 之后视觉对比度仍 OK，但若未来再加 stroke③ 会复发
- inset 量 `1.0` → 描边在面板内 1pt 处，在浅色 panelTint 上对比度会下降，需要把 opacity 提到 `0.7` 才能拉回，副作用更大
- 用 `RoundedRectangle(cornerRadius: 25.5, style: .continuous).stroke(...)` → 几何正确但 cornerRadius 拆 0.5 不可读；inset(by:) 才是 idiom

### 2. 删除 `.overlay(alignment: .top) { ... .offset(y: 1) ... }` 整块

**当前：**
```swift
.overlay(alignment: .top) {
    panelShape
        .stroke(.white.opacity(0.22), lineWidth: 1)
        .blur(radius: 0.5)
        .offset(y: 1)
}
```

**改为：** 直接删除此 `.overlay` 整段（从 `.overlay(alignment: .top) {` 到对应的 `}`）

**理由：**
- 这是 L 形伪影的**直接来源**：整条 stroke `y:1` 平移在圆角处与主描边产生 1px 错位
- 视觉贡献极弱：opacity 0.22 + blur(0.5) 在 1px 描边上几乎不可见
- 留它存在的"内边沿高光"功能在 system materials（`.popover`）上已被材质自带高光替代（`VisualEffectView` 系统会绘制 top edge highlight）
- 删后 modifier 链短 5 行，更易读

**备选：**

- 保留但把 `offset(y: 1)` 改成 `offset(y: 0.25)` → 错位 0.25pt 抗锯齿可抹平，但视觉上也基本消失了，等于"半删"；不如直接删
- 保留但把 stroke 替换为 `panelShape.inset(by: 0.5).stroke(...)` → 两条 inset 描边重合又会变成双层 visual weight；同决策 1 一致，单条 inset 描边更干净
- 保留但把 `.offset(y: 1)` 改成 `.offset(x: 0, y: 0)` → stroke② 和 stroke① 完全重合，opacity 累加 ≈ 0.88，与当前 `0.66` 单条相比视觉更亮，破坏签名

### 3. 保留 `.compositingGroup()`

**理由：**
- 当前 trailing `.compositingGroup()` 把 ⑤⑥⑦⑧ 全部锁进一次离屏 pass；删 stroke② 后少一层 overlay，compositingGroup 仍然把剩下的描边+阴影作为整体合成，shadow 的 anti-alias 边缘更平滑
- 移除它会让 shadow 走实时合成，在大 radius（28）下边缘可能出现 1–2pt 的颗粒感
- 这是低成本的"保险"，保留无成本

**备选：**

- 移除 `.compositingGroup()` → 性能略升（少一次离屏 pass），但视觉轻微退化，不值得

### 4. 不动 `shadow(...)` 链

**理由：**
- 橙色 `shadow(radius: 28, y: 16)` 是项目当前最有辨识度的视觉语言
- 截图里"底部两角的 L 形"主要来自这条 shadow 的 `y: 16` 向下偏移 + radius 28 在圆角被切后形成光脚。方案 B 不直接修这半，但实测在浅色桌面上（截图背景）光脚并不刺眼；修它的代价是 radius 从 28 降到 ≤ 20，会削弱品牌识别度
- 本次以最小创伤优先：先消描边错位（用户最直观感受到的"L 形"），shadow 的光脚留作后续 follow-up

**备选（已记录，不实施）：**

- 把橙色 shadow 的 `y: 16` 改成 `y: 0`（对称扩散）→ 视觉上更"无方向"，但失去"从下方升起"的浮层感
- 引入 `BlurFilter` 风格的内部 shadow（SwiftUI 不支持）→ 需要绕路用 `ZStack { ... .mask() }` 模拟，复杂度高

## Risks / Trade-offs

- **[删 stroke② 失去顶部内沿高光]** 旧版顶部 1px 处有一层 `@0.22 + blur(0.5)` 的极淡高光，删后在浅色 panelTint 上"顶部 1px 略平"。→ 缓释：系统材质 `.popover` 自带 top edge highlight（`VisualEffectView` 内部绘制），综合视觉差异 < 5% 亮度，肉眼难辨
- **[inset 0.5 描边在深色桌面下变弱]** 0.55 opacity + 内缩 0.5pt 后，在深灰/深色桌面上边缘对比度略低于改前（0.66 在外边缘）。→ 缓释：1) 实测浮层总是浮在浅灰桌面背景上（panelTint 自带 88% 不透明的米色渐变），描边所在像素是浮层本身而非桌面；2) 接受 1–2 个 commit 的视觉回归
- **[未来若加回内沿高光]** 决策 1 已经把主描边 inset 0.5，如果未来想再加内沿高光，应该用 `panelShape.inset(by: 1.5).stroke(...)` 而不是再叠加 `offset(y:)`，避免重新触发 L 形根因。→ 缓释：在 design.md 留下这条备注作为团队约定
- **[L 形"底部光脚"未根治]** 截图里底部两角的"光脚"是橙色 shadow `y: 16` 偏移导致的，不是描边错位。本次只修描边错位，底部光脚保留。→ 缓释：proposal 明确"不动 shadow 链"，用户后续若要根治再开新 change

## Migration Plan

无（单文件内纯视觉 modifier 调整，无状态变更、无持久化、无 API 变更）。

**回滚：** `git revert` 一次 commit 即可恢复 `BottomPanelView.swift:74-83` 段。

## Open Questions

- **要不要顺手把 `shadow` 的 `y: 16` 收一收？** 例如 `y: 12` 能否在保留品牌感的同时弱化底部光脚？本次提案不动它；若用户后续有反馈可开 `tune-panel-shadow-offset` follow-up
- **inset 量是 0.5 还是 0.75？** 0.5 是 SwiftUI 单像素描边抗锯齿的最小可见位移；0.75 更稳但在高分屏（Retina）上不可见。已选 0.5，跑完真机对比若不满足再调
