# 条目渲染规范

## Purpose
每条 `ClipboardItem` 在浮层里呈现为一张 236 × 236 pt 的卡片。本规范描述卡片的视觉结构、按 `kind` 切换的预览、来源色 accent、拖拽与右键菜单，以及相对时间和字体。

## Requirements

### Requirement: 卡片布局
每张卡片 SHALL 渲染为 236 × 236 pt，自顶向下包括：按条目 `sourceAccent`（见来源色小节）上色的顶部色条、来源应用图标、条目标题/预览、相对时间标签。

#### Scenario: 卡片尺寸
- 假设 任一条目
- 当 在时间线中渲染
- 则 卡片正好 236 × 240 pt（高度因钉徽标可多 4 pt）

### Requirement: 来源色 accent
系统 SHALL 从来源应用图标中提取 `sourceAccent` 颜色——选取最饱和的像素；若图标缺失则使用中性色。accent 较浅的卡片 SHALL 把前景（标题/图标）切换为深色以保证对比度。

#### Scenario: 红色 logo
- 假设 来源应用图标以红色为主
- 当 卡片渲染
- 则 顶部色条为红色，前景切换为深色以保证可读性

#### Scenario: 无图标
- 假设 `sourceAppIconData == nil`
- 当 卡片渲染
- 则 使用中性 accent（不崩溃、不随机取色）

### Requirement: 按 kind 切换的预览
卡片主体 SHALL 渲染取决于 `kind` 的预览：`.image` 用适配尺寸的 `NSImage` 展示 `imageData`；`.url` 展示链接预览（URL + 已抓取的 `linkTitle` 与 `linkImageData`）；`.file` 展示文件名与首个文件的路径；`.text` 展示截断到合适长度的 `preview`。

#### Scenario: 图片卡片
- 假设 有一条 `.image` 条目
- 当 渲染
- 则 卡片主体填满图片（裁剪到圆角矩形）

#### Scenario: 带预览的 URL 卡片
- 假设 有一条 `.url` 条目且 `linkImageData != nil`
- 当 渲染
- 则 卡片显示预览图与 `linkTitle`（标题缺失时回退到 URL）

#### Scenario: 文件卡片
- 假设 有一条 `.file` 条目，含一个 `fileURL`
- 当 渲染
- 则 卡片显示文件名与绝对路径

### Requirement: 右键菜单
卡片 SHALL 暴露右键菜单：**Pin** / **Unpin**（切换）、**Pinboard** 子菜单（列出 All / Pinned / 每一个自定义 pinboard 与当前选中项）、**Paste**、**Delete**。

#### Scenario: 被钉卡片的菜单
- 假设 有一张属于 "Work" 的被钉卡片
- 当 用户打开右键菜单
- 则 看到 "Unpin"、Pinboard 子菜单（"Work" 上有对勾）、"Paste"、"Delete"

### Requirement: 拖拽
卡片 SHALL 支持 `onDrag`，产出：`.file` 条目 → `fileURLs` 作为可拖拽文件 URL；`.image` 条目 → `imageData` 作为 `NSImage`；其余 → `preview`（或 `textValue`）作为字符串。

#### Scenario: 拖出图片
- 假设 有一张 `.image` 卡片
- 当 用户把它拖到 Finder
- 则 Finder 接受该拖拽并显示图片移动

### Requirement: 相对时间
系统 SHALL 把自 `createdAt` 起的经过时间显示为："just now"（< 60 秒）、"N minute(s) ago"（< 60 分）、"N hour(s) ago"（< 24 时）、"N day(s) ago"（≥ 24 时）。

#### Scenario: 30 秒前
- 假设 `createdAt` 距今 30 秒
- 当 卡片渲染
- 则 标签为 "just now"

#### Scenario: 3 小时前
- 假设 `createdAt` 距今 3 小时
- 当 卡片渲染
- 则 标签为 "3 hours ago"

### Requirement: 字体
系统 SHALL 在系统已安装 "Maple Mono NF CN" 时使用该字体渲染**数据型**字符；否则回退到带 `monospacedDigit()` 的系统字体。系统 SHALL 暴露**正文型**字体样式（无衬线系统字体）供"扫读类"文本使用。两种样式的具体覆盖范围与字体选择逻辑的真实定义在 `Sources/Copythat/Support/CopythatFont.swift`；选择字体 SHALL NOT 在缺少自定义字体的系统上崩溃，SHALL NOT 改变卡片几何或 panel 高度。

#### Scenario: 数据型字符走等宽字体
- 假设 系统已安装 "Maple Mono NF CN"
- 当 卡片渲染数据型字符（kind 分类词、相对时间、字符计数、图片尺寸、文件路径、URL host）
- 则 文本使用 "Maple Mono NF CN"

#### Scenario: 正文型字符走无衬线字体
- 假设 系统已安装 "Maple Mono NF CN"
- 当 卡片或浮层渲染正文型字符（卡片标题、`textPreview` 正文、链接副信息、文件标题/副信息、搜索输入框、按钮 label、pinboard 标题、状态行）
- 则 文本使用系统无衬线字体，而非 "Maple Mono NF CN"

#### Scenario: 字体缺失时不崩溃
- 假设 系统未安装 "Maple Mono NF CN"
- 当 卡片或浮层渲染
- 则 数据型字符透明地回退到带 `monospacedDigit()` 的系统字体，正文型字符保持系统无衬线字体
- **AND** 渲染不崩溃、不改变卡片几何与 panel 高度

### Requirement: 文本 kind 排版密度
文本 kind 卡片 SHALL 在 `cardSize.contentHeight`（`cardSize.height − headerHeight`，当前 188pt）内完整展示尽可能多行的 `preview`，**不**得使用渐变蒙版、clip 截断或 `.fixedSize` 让内容"看似"溢出可用区；正文 SHALL 与其它 kind 卡片中的副级文字（URL 副文、文件路径）保持同一字号档位以维持卡片家族的视觉层级。

#### Scenario: 短文本不出现"假溢出"
- 假设 复制了一段 30 字符以内的纯文本
- 当 卡片渲染
- 则 卡片完整渲染该 `preview`，不被渐变蒙版遮蔽
- **AND** 卡片底部 `characterCount` 标签正常显示且不被裁切

#### Scenario: 长文本在内容区内完整排版
- 假设 复制了一段 240 字符的纯文本（`preview` 截断上限）
- 当 卡片渲染
- 则 卡片正文在 `textPreview` 可用高度内排版，不超出 `cardShape` 的圆角裁切
- **AND** 字符计数标签可见，正文与标签之间保留 `Spacer` 间距
