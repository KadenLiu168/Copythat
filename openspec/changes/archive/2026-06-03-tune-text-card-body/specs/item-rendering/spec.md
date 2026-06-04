## ADDED Requirements

### Requirement: 文本 kind 排版密度

文本 kind 卡片 SHALL 在 `cardSize.contentHeight`（`cardSize.height − headerHeight`，当前 188pt）内完整展示尽可能多行的 `preview`，**不**得使用渐变蒙版、clip 截断或 `.fixedSize` 让内容"看似"溢出可用区；正文 SHALL 与其它 kind 卡片中的副级文字（URL 副文、文件路径）保持同一字号档位以维持卡片家族的视觉层级。

#### Scenario: 短文本不出现"假溢出"

- **WHEN** 复制了一段 30 字符以内的纯文本
- **THEN** 卡片完整渲染该 `preview`，不被渐变蒙版遮蔽
- **AND** 卡片底部 `characterCount` 标签正常显示且不被裁切

#### Scenario: 长文本在内容区内完整排版

- **WHEN** 复制了一段 240 字符的纯文本（`preview` 截断上限）
- **THEN** 卡片正文在 `textPreview` 可用高度内排版，不超出 `cardShape` 的圆角裁切
- **AND** 字符计数标签可见，正文与标签之间保留 `Spacer` 间距
