## Context

- 当前 `Sources/Copythat/Support/CopythatFont.swift:5-16` 只暴露 `font(size:weight:)`，单一走 `Maple Mono NF CN`，缺失回退到 `monospacedDigit()`。
- `Views/{ClipboardCardView,BottomPanelView,EmptyTimelineView}.swift` 现有 ~16 处调用点，全部走 `font(size:weight:)` 形态。
- `openspec/specs/item-rendering/spec.md:78-82` 现有"字体"Requirement 只锁定"安装则有，否则回退系统等宽"，未约束"哪些文本该等宽、哪些该走无衬线"。
- 项目无外部 font API 消费者；`CopythatFont` 是 internal `enum`，调用方都在 `Sources/Copythat/Views/`。
- Brownfield 改动面：`Support/` 1 文件 + `Views/` 3 文件 + `specs/item-rendering/spec.md` 1 文件；预计 diff < 30 行。
- 约束：保留 `Maple Mono NF CN` 作为产品差异化字符风格；不引入新依赖；不动卡片几何、panel 高、键盘交互、sourceAccent 算法。

## Goals / Non-Goals

**Goals:**
- `CopythatFont` 暴露 `Style` 语义（`data` / `text`），让调用点显式声明"这块文本是数据字符还是正文"。
- 把卡片 / 浮层中"扫读类"文本（按钮 label、搜索输入、状态行、链接标题、`textPreview` 正文、链接副信息、文件标题/副信息）切到 `Style.text`（系统无衬线）。
- 把"数据型"字符（kind 分类词、时间戳、字符计数、图片尺寸、文件路径、URL host）保留在 `Style.data`（`Maple Mono NF CN`）。
- `data` 在 `Maple Mono NF CN` 缺失时回退到 `.system(size:).monospacedDigit()`，避免数字在 layout 切换时宽度抖动。
- footer 字号从 10pt 升到 11pt；`EmptyTimelineView` 提示语字体切到 `.text` 但**文案与字号均不动**。
- 把上述边界写进 `item-rendering` 的 MODIFIED Requirement 中。

**Non-Goals:**
- 不替换或新增字体文件；不评估其它字体（`Geist`、`SF Mono` 等）。
- 不动 `Maple Mono NF CN` 已有的"系统未装时回退到系统等宽"逻辑之外的部分。
- 不引入 design token / Theme 文件（下一轮）。
- 不动卡片几何（236×236、圆角 23、间距 28）、panel 高 342pt、键盘交互、sourceAccent 算法、`prefersDarkForeground` 阈值。
- 不修 footer 文案与"回车粘贴 / Esc 关闭"语义；不动浮层阴影、卡片选区动效。
- 不修 `EmptyTimelineView` 提示语文案（"Copy something to start"）与字号。
- 不引入新单元测试（视觉与字体选型无可观测行为差异；纯外观变化由 `script/verify_all.sh` 锁住"未崩溃"基线）。

## Decisions

### 1. `Style` 枚举 + 显式签名

```swift
enum CopythatFont {
    enum Style { case data, text }
    static func font(_ style: Style, size: CGFloat, weight: Font.Weight = .regular) -> Font
}
```

- **Decision**：把 `font(size:weight:)` 替换为 `font(_:size:weight:)`，强制调用方显式选择 `Style`。
- **Why**：可选默认参数会"零成本"被忽略（项目里 16 处调用全部走默认），达不到拆分目的。强制参数让改动 diff 显式、code review 一眼可见"哪些切了 `.text`、哪些留 `.data`"。
- **Alternatives considered**：
  - (a) 保留 `font(size:weight:)` 默认 `.text`（最不破坏）：但调用点会全留 `.text`，不达目的。
  - (b) 拆成两个独立函数 `mono(size:weight:)` + `text(size:weight:)`：调用点噪声更大，且未来加 `Style.display` 等第三档时扩展差。
  - (c) 用 `Environment` 注入默认 `Style`：SwiftUI 风格更"地道"，但本项目所有调用点都显式传 size/weight，再叠一层环境没有收益。

### 2. `data` 缺失回退用 `monospacedDigit()`，不回退到普通 system

```swift
case .data:
    if hasMono { return .custom(monoName, size: size).weight(weight) }
    return .system(size: size, weight: weight).monospacedDigit()
```

- **Why**：当前回退是普通 `.system(size:weight:)`，导致数字字符（"3m ago"、"324 characters"、"1024 x 768"）在 layout 切换时宽度抖动。`monospacedDigit()` 是 Apple 公开 API，零成本对齐等宽数字字符。
- **Trade-off**：在系统未装 `Maple Mono NF CN` 时，`.data` 不再是全字符等宽——只有数字等宽。这是可以接受的：等宽在缺失时退化为"数字等宽"已能消除最明显的抖动；字母字符在 13pt 以下视觉差异可忽略。
- **Alternatives considered**：
  - (a) `.monospaced()`（全字符等宽）：会强制 `text` 也变成等宽，破坏拆分目的。
  - (b) 抛 fatalError / 警告日志：会破坏 `script/verify_all.sh` 的"无崩溃"基线。

### 3. 调用点迁移表（逐处决断）

| 文件 | 行 | 当前 | 改后 | 理由 |
|---|---|---|---|---|
| `ClipboardCardView.swift` | 76 | `font(size: 19, weight: .semibold)` (kind label) | `font(.data, size: 19, weight: .semibold)` | 分类标识符，等宽保留 |
| 同上 | 88 | `font(size: 13, weight: .medium)` (相对时间) | `font(.data, size: 13, weight: .medium)` | 时间戳数字，等宽保留 |
| 同上 | 176 | `font(size: 13, weight: .medium)` (图片尺寸 "1024 x 768") | `font(.data, size: 13, weight: .medium)` | 数字 + 字符 `x`，等宽保留 |
| 同上 | 203 | `font(size: 19/16, weight: .semibold)` (链接标题) | `font(.text, size: 19/16, weight: .semibold)` | 标题是"给人读"，sans 优先 |
| 同上 | 209 | `font(size: 13, weight: .medium)` (URL host 副信息) | `font(.text, size: 13, weight: .medium)` | URL host 长度不等，sans 节省宽度 |
| 同上 | 229 | `font(size: 16, weight: .semibold)` (文件标题) | `font(.text, size: 16, weight: .semibold)` | 标题，正文类 |
| 同上 | 233 | `font(size: 12, weight: .medium)` (文件路径副信息) | `font(.text, size: 12, weight: .medium)` | 路径在 12pt 等宽会显得拥挤；改 sans + monoDigit 备用 |
| 同上 | 248 | `font(size: 13, weight: .regular)` (`textPreview` 正文) | `font(.text, size: 13, weight: .regular)` | 8 行正文，等宽最不合适 |
| 同上 | 256 | `font(size: 12, weight: .medium)` (字符计数) | `font(.data, size: 12, weight: .medium)` | "324 characters" 数字 + 单位，等宽保留 |
| 同上 | 268 | `font(size: 13, weight: .medium)` (fallback preview) | `font(.text, size: 13, weight: .medium)` | 异常路径的预览，按正文处理 |
| `BottomPanelView.swift` | 137 | `font(size: 13, weight: .medium)` (search 放大镜) | `font(.text, size: 13, weight: .medium)` | SF Symbol 旁的 label，sans 配适 |
| 同上 | 141 | `font(size: 13, weight: .medium)` (search 输入) | `font(.text, size: 13, weight: .medium)` | 用户输入，正文 |
| 同上 | 150 | `font(size: 12, weight: .medium)` (清除按钮 X) | `font(.text, size: 12, weight: .medium)` | 按钮 |
| 同上 | 173 | `font(size: 15, weight: .medium)` (折叠态搜索图标) | `font(.text, size: 15, weight: .medium)` | 按钮 label |
| 同上 | 220 | `font(size: 12, weight: isSelected ? .semibold : .medium)` (pinboard 标题) | `font(.text, size: 12, weight: isSelected ? .semibold : .medium)` | 短分类标签 |
| 同上 | 306 | `font(size: 10, weight: .medium)` (footer) | `font(.text, size: 11, weight: .medium)` | 字号升 1pt + 切 sans（10pt 接近 a11y 下限） |
| `EmptyTimelineView.swift` | 8 | `font(size: 13, weight: .semibold)` ("Copy something to start") | `font(.text, size: 13, weight: .semibold)` | 提示语，正文类；**不动文案与字号** |
| 同上 | 10 | `font(size: 12)` (副提示) | `font(.text, size: 12)` | 同上 |

- **Why 这些切 `.text`、那些留 `.data`**：判据是"读者是否要扫读一长串数字 / 字符，还是在读一句句子"。短大写分类词（"Text"、"URL"）、时间戳、计数、尺寸 → `.data`；标题、副信息、状态行、按钮 label → `.text`。
- **URL host 例外**：`linkDisplayURL`（"github.com/anthropics/..."）虽含字符 `x` 与 `/`，但语义是"给人读的 URL 文本"而非"对齐数据"。13pt 12 行限制下等宽浪费宽度，改 sans。

### 4. 不引入测试

- **Why**：本变更无可观测行为差异，纯外观由 SwiftUI 渲染管线处理。`Tests/CopythatTests/` 现有覆盖领域逻辑（store、policy、paste、frame），不覆盖 `CopythatFont`。
- **Trade-off**：`script/verify_all.sh` 跑通即代表"未崩溃 / 未编译失败"，作为最低门槛。

### 5. 不抽 `CopythatMetrics` design token

- **Why**：本次只动字体。spacing、padding、corner radius、阴影颜色等其它"魔法数字"问题已在 redesign-skill 审计中列出，留到下一轮 `theme-and-spacing-tokens` 变更集中处理。
- **Trade-off**：本次 diff 内仍有 50+ 散落的 `Color(red:)`、padding 数字，但与字体无关。

## Risks / Trade-offs

- **[Risk] 视觉风格突变**：用户已习惯"全部等宽"的产品调性，切到双字体后短期内可能感觉"不一致"。→ **Mitigation**：仅切"明显错位"的正文类（13pt 搜索输入、13pt 文本预览、12pt 副信息），保留所有"分类标识符"为等宽，让"产品记忆点"不丢。
- **[Risk] 在没装 `Maple Mono NF CN` 的开发机上，`monospacedDigit()` 退化的视觉** → **Mitigation**：保留 `hasMono` 检测，仅在缺失时退化；`.monospacedDigit()` 是 Apple 公开稳定 API，无版本兼容风险。
- **[Risk] `footer` 字号从 10→11 触发布局溢出**（spec 锁定 panel 高 342pt）→ **Mitigation**：footer 单行 `Label` + `Text`，从 10pt 升到 11pt 行高增加 ~1pt，远未触及 342pt 高度约束；timeline 高度 258pt 也未受影响。
- **[Risk] `font(_:size:weight:)` 改签名导致外部调用方编译失败** → **Mitigation**：`CopythatFont` 是 `internal` enum，调用方全在 `Sources/Copythat/Views/` 三文件内，全量迁移由 tasks.md 切片执行；编译失败即视为改动遗漏，由 verify 捕获。
- **[Trade-off] "等宽感"产品记忆点减弱** → **Mitigation**：所有"分类标识符"（kind、时间、计数、尺寸）仍走 `Maple Mono NF CN`，产品差异化的字符风格不丢；只是"扫读正文"不再被等宽拖累。
- **[Trade-off] `data` 缺失回退时只有数字等宽** → **Mitigation**：13pt 以下字母字符在普通 sans 与等宽之间视觉差异可忽略；主要修复的数字对齐目标达成。

## Migration Plan

无运行时数据迁移。本变更：

1. 修改 `Sources/Copythat/Support/CopythatFont.swift` 暴露 `Style` 枚举与新签名
2. 同步修改 3 个 `Views/` 文件中 16 处调用点（按 §3 迁移表）
3. 跑 `./script/verify_all.sh` 验证编译与既有测试通过
4. 提交一个 commit，message 形如 `Split CopythatFont into data/text styles for readability`

回滚策略：`git revert` 单一 commit 即可，因为改动集中在 1 个 `Support` 文件 + 3 个 `Views` 文件的 16 行调用点。

## Open Questions

无。已与用户确认：
- `EmptyTimelineView` 文案 "Copy something to start" **不修改**
- 字体切换按 §3 迁移表执行
- 不引入设计 token 文件
- footer 字号从 10→11 视为可接受的范围调整
