## 1. 字体 API 重构

- [x] 1.1 在 `Sources/Copythat/Support/CopythatFont.swift` 中：暴露 `enum Style { case data, text }`；将 `font(size:weight:)` 改为 `font(_:size:weight:)` 强制显式 `Style`；`Style.data` 在 `Maple Mono NF CN` 缺失时回退到 `.system(size:).monospacedDigit()`，`Style.text` 始终走系统无衬线

## 2. 迁移 ClipboardCardView 调用点

- [x] 2.1 `Sources/Copythat/Views/ClipboardCardView.swift` `headerSection`：行 76（kind 19pt semibold）与行 88（相对时间 13pt medium）改为 `font(.data, ...)`，保留等宽
- [x] 2.2 `Sources/Copythat/Views/ClipboardCardView.swift` `linkPreview`：行 203（链接标题 19/16pt semibold）与行 209（URL host 13pt medium）改为 `font(.text, ...)`，切无衬线
- [x] 2.3 `Sources/Copythat/Views/ClipboardCardView.swift` `filePreview`：行 229（文件标题 16pt semibold）与行 233（文件副信息 12pt medium）改为 `font(.text, ...)`，切无衬线
- [x] 2.4 `Sources/Copythat/Views/ClipboardCardView.swift` `textPreview` / `imagePreview` / `fallbackPreview`：行 248（`textPreview` 正文 13pt regular）改为 `font(.text, ...)`；行 176（图片尺寸 chip 13pt medium）改为 `font(.data, ...)`；行 256（字符计数 12pt medium）改为 `font(.data, ...)`；行 268（fallback preview 13pt medium）改为 `font(.text, ...)`

## 3. 迁移 BottomPanelView 调用点

- [x] 3.1 `Sources/Copythat/Views/BottomPanelView.swift` `searchControl`：行 137（放大镜 13pt medium）、行 141（搜索输入 13pt medium）、行 150（清除按钮 X 12pt medium）、行 173（折叠态搜索图标 15pt medium）全部改为 `font(.text, ...)`
- [x] 3.2 `Sources/Copythat/Views/BottomPanelView.swift` `pinboardButton`：行 220（pinboard 标题 12pt medium/semibold）改为 `font(.text, ...)`，切无衬线
- [x] 3.3 `Sources/Copythat/Views/BottomPanelView.swift` `addButton` 与 `footer`：行 241（`+` 按钮 16pt medium）改为 `font(.text, ...)`；行 306（footer 10pt medium）改为 `font(.text, size: 11, weight: .medium)`，**字号从 10pt 升到 11pt**

## 4. 迁移 EmptyTimelineView 调用点

- [x] 4.1 `Sources/Copythat/Views/EmptyTimelineView.swift`：行 8（"Copy something to start" 13pt semibold）与行 10（副提示 12pt regular）改为 `font(.text, ...)`，**字号与文案均不动**

## 5. 验证

- [x] 5.1 Run `./script/verify_all.sh` —— 编译通过、既有测试不崩溃、字体选型逻辑不破坏 `Maple Mono NF CN` 缺失时的回退路径

## 6. 实施期补漏（API 强制迁移触发）

- [x] 6.1 `Sources/Copythat/Views/SettingsView.swift`（8 处调用）：原任务未列出，但新 API `font(_:size:weight:)` 强制所有调用方迁移；编译时 Swift 报缺参错，全部切到 `font(.text, ...)`（行 14 错误提示 Label、行 23 auto-copy 说明、行 37 快捷键错误 Label、行 56 pinboards TextEditor、行 59 pinboard 提示、行 65 ignore apps TextEditor、行 68 ignore apps 提示、行 82 Form 默认字体）
