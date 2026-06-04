## Context

`Sources/Copythat/Views/ClipboardCardView.swift:245-276` 的 `textPreview` 是文本 kind 卡片的唯一主体。当前实现：

- 字号 `CopythatFont.font(size: 16, weight: .regular)`，行距 `lineSpacing(3)`，行限 `lineLimit(7)`
- 挂了一个 `LinearGradient` 蒙版（0%–70% 实色、70%–100% 渐隐到 0.12 透明度）
- 加了 `.fixedSize(horizontal: false, vertical: false)`
- `VStack` 顶层 padding：`(.horizontal, 16) / (.top, 14) / (.bottom, 9)`，spacing `8`
- 底部 `Text("\(characterCount) characters")`（12pt medium，centered）
- 卡片几何 236×236，header 48pt，内容区 188pt（`ClipboardCardView.swift:6-7`）

几何真值源：`item-rendering/spec.md`（236×236、按 `kind` 切换预览、字体回退到系统等宽）。该 spec 未约束文本 kind 的字号/行距/行数/渐变。

字体真值源：`Sources/Copythat/Support/CopythatFont.swift`，优先 `Maple Mono NF CN`，否则回退到 `.system(size:weight:)`。Maple Mono NF CN 是等宽字体，0.6em 字符宽度。

## Goals / Non-Goals

**Goals:**

- 文本卡片在不变更卡片几何、不修改 `ClipboardItem` 模型、不动其他 kind 版式的前提下，单卡可见正文字符数从约 231 提升到约 336（+45%）
- 文本卡片正文字号与 URL 卡片副文（`ClipboardCardView.swift:209`，`size: 13, weight: .medium`）字号对齐，恢复卡片家族的视觉层级
- 移除"伪溢出"——当前 7 行在 16pt+3 行距下实际占位 155pt，溢出可用 145pt 区约 10pt，被渐变蒙版遮蔽后稳定可读约 4.5 行；改为新参数后 8 行 137pt 干净落入

**Non-Goals:**

- 不改 `Sources/Copythat/Models/ClipboardItem.swift`、`Stores/ClipboardStore.swift`（`preview.truncated(to: 240)` 不动）
- 不改卡片 236×236、header 48pt、圆角 23、阴影、选中态动效、拖拽、右键菜单
- 不改 `imagePreview` / `linkPreview` / `filePreview`
- 不修改 `item-rendering/spec.md`（行为契约"展示截断到合适长度的 preview"未变）
- 不引入新 spec、不引入新视图组件、不引入新依赖

## Decisions

### 1. 字号 16 → 13、行距 3 → 1.5、行限 7 → 8

**理由：**
- 13pt 落在 URL 副文（13pt medium）字号上，建立家族一致
- `lineLimit(8) × (13pt × 1.2 行高 + 1.5pt 行距) = 8 × 17.1pt = 136.8pt`，加上 footer 12pt + spacing 8pt + 顶底 padding 23pt = 179.8pt < 内容区 188pt，**8pt 缓冲**
- 等宽字符 0.6em × 13pt ≈ 7.8pt 宽，204pt 内容宽 ÷ 7.8pt ≈ 26 字/行；实测 Maple Mono 比例更接近 0.55–0.6，按 30–42 字/行估，8 行 ≈ 240–336 字可见
- 行距 1.5pt 在 13pt 下视觉节奏是 11.5% 加成，比 16pt+3 的 18.75% 加成更克制

**备选：**
- 14pt + 1.5 + 8 行 → 8 × 18.3 = 146.4pt（**溢出** 1.4pt），需删 footer 才安全
- 12pt + 1.5 + 9 行 → 9 × 15.9 = 143.1pt（**不溢出**），但 12pt 与 file 卡片 path（`ClipboardCardView.swift:233`，`size: 12, weight: .medium`）撞号，层级反而失衡
- 13pt + 1.0 + 9 行 → 9 × 16.6 = 149.4pt（溢出 4.4pt），同上
- 维持 16pt → 与 URL 副文错位，且 4.5 行实色可读量无法改善

### 2. 移除底部 LinearGradient 蒙版

**理由：**
- 旧蒙版实质是"溢出伪装"——把 10pt 溢出藏起来，让 layout 看起来"对"，但用户看到的是 4.5 行实色 + 2.5 行渐隐
- 新参数下 8 行 137pt 不再溢出，蒙版失去作用
- 截断与否的提示已有 footer 的字符数 + lineLimit 自然截止
- 删蒙版 = 少一个 `.drawingGroup` 不必要的合成开销（maple mono 抗锯齿开销不小）

**备选：**
- 保留蒙版 + 把实色起点从 0.70 提到 0.85 → 仍有"渐隐是装饰"还是"渐隐是截断提示"的歧义
- 保留蒙版 + 实色起点 1.0（无渐变）→ 实际就是删除，不删代码反而更怪

### 3. 移除 `.fixedSize(horizontal: false, vertical: false)`

**理由：**
- SwiftUI 中 `fixedSize(false, false)` = 让 view 在两个维度都跟随父布局约束，是默认行为
- 此处写出来对布局无效果，可能是早期防御性写法或从其它视图复制的残骸
- 删除可减少读者对"作者意图"的猜测

**备选：**
- 改为 `.fixedSize(horizontal: false, vertical: true)` → 让 text 高度跟随内容不被父约束压缩，但这本来就是 lineLimit(8) 的语义

### 4. 保留 footer 与 padding

**理由：**
- 用户明确要求"保留字符计数"
- `8pt` 缓冲足够，footer 不挤掉正文
- padding 16/14/9 与其它 kind 的 padding 节奏一致，不应单独改

**备选（已排除）：**
- footer 移到 header 旁 → 需要改 `headerSection` 的布局、影响选中态可视性、改 4 个 kind 而非 1 个，超出范围

### 5. 不修改 `item-rendering/spec.md`

**理由：**
- 该 spec 没有规定文本 kind 的字号/行距/行数/渐变，requirement 层未变
- 在 spec 里写"13pt"或"8 行限"是过度规范——把实现细节固化在规范里会让未来同类调优需要走 sync-specs 流程
- 该 spec 的 `字体` requirement 仅约束"优先 Maple Mono NF CN / 缺失时回退系统等宽"，本次不动字体选择

## Risks / Trade-offs

- **[CJK 字符视觉重量]** Maple Mono NF CN 在 13pt 下的 CJK 字符密度高于拉丁字符，行高 17.1pt 可能让中文段读起来"上下挤"。→ 缓释：1.5pt 行距加成 11.5% 略高于 CJK 排印常见 1.0–1.2 倍字号的相对行距；接受 1–2 个 commit 内的视觉回归
- **[长文截断感缺失]** 旧版靠渐变"暗示还有更多"，新版完全靠 lineLimit 自然截止 + footer 字符数。→ 缓释：footer 已经告诉用户"240 characters"，用户可双击粘贴看全文
- **[多语言混排]** Maple Mono NF CN 的非 ASCII 字符宽度与 ASCII 不严格等宽；新参数下混排行宽度略不可预测，可能偶发 1–2 字换行差异。→ 缓释：lineLimit(8) 给的 8pt 缓冲吸收这类 ±1pt 抖动
- **[design vs spec 同步]** design 写了具体数字（13pt/1.5/8），未来若有人想再调字号，可能误以为违反 design。→ 缓释：proposal 明确"实现级排版调优"，design 是当前快照而非硬约束
