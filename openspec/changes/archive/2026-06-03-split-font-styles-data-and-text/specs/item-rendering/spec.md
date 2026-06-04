## MODIFIED Requirements

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
