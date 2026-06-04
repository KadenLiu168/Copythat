# 剪贴板历史规范

## Purpose
Copythat 把用户的剪贴板历史持久化为 `ClipboardItem` 列表，提供 schema 演进安全的数据模型、JSON 文件存储与去重 / 容量策略。本规范描述**历史数据**的形状与保留规则；捕获流程见 `clipboard-capture`，过滤与展示见 `search-and-filtering` / `panel-ui`。

## Requirements

### Requirement: 条目数据模型
系统 SHALL 将每条历史记录表示为 `ClipboardItem`，包含：`id`（UUID）、`kind`（`text` / `url` / `image` / `file`）、`title`、`preview`、`sourceApp`、`sourceAppIconData?`、`createdAt`、`isPinned`、`pinboardName?`、`textValue?`、`fileURLs`、`imageData?`、`linkTitle?`、`linkImageData?`。

#### Scenario: 新建文本条目
- 假设 用户在 TextEdit 中复制了一段文本
- 当 该条目被记录时
- 则 `kind == .text`，`textValue` 保存原始文本，`fileURLs == []`，`imageData == nil`

#### Scenario: 新建图片条目
- 假设 系统进行了一次截图
- 当 该条目被记录时
- 则 `kind == .image`，`imageData` 是 PNG 字节，`textValue == nil`

### Requirement: 向后兼容解码
系统 SHALL 在历史 JSON 缺少较新字段时仍能解码而不抛错，并使用以下默认值：缺少 `id` → 新 UUID；缺少 `title` → `""`；缺少 `preview` → `title`；缺少 `sourceApp` → `"Unknown"`；缺少 `isPinned` → `false`；缺少 `fileURLs` → `[]`。

#### Scenario: 缺少链接预览字段的旧条目
- 假设 存在一条在 `linkTitle` / `linkImageData` 字段引入之前写入的 JSON
- 当 历史被加载时
- 则 解码成功，且 `linkTitle == nil`、`linkImageData == nil`

### Requirement: 用于去重的内容键
系统 SHALL 计算 `contentKey`，使得当且仅当两个条目的 key 相等时表示同一逻辑内容：`text` / `url` 使用 `"<kind>:<textValue>"`；`file` 使用 `"file:<path1>|<path2>"`；`image` 使用 `"image:<sha256-hex>"`。

#### Scenario: 同一张图片被复制两次
- 假设 同一张图片两次出现在剪贴板上
- 当 两次变化都被观察到
- 则 第二条的 `contentKey` 与第一条相同，保留策略只保留被钉住的条目（或最新的未钉条目）

### Requirement: 搜索文本字段
系统 SHALL 为每个条目暴露一个全小写的 `searchText`，以空格拼接，包含 `title`、`preview`、`linkTitle`、`sourceApp`、`kind.label`，以及每个 `fileURLs` 条目的 `path`。

#### Scenario: 图片条目的搜索文本
- 假设 有一条标题为 "Screenshot"、`sourceApp == "Preview"` 的图片条目
- 当 用户输入 "screenshot" 或 "preview"
- 则 该条目被命中

### Requirement: 插入时的保留策略
当向长度为 `n`、上限为 `L` 的历史中插入新条目时，系统 SHALL：(1) 移除与新条目 `contentKey` 相同的所有现有条目，**被钉住的除外**；(2) 将新条目插入到索引 0；(3) 限制未钉图片条目不超过 100 张，超出时从尾部删除；(4) 限制总长度不超过 `L`（已裁剪到 `[100, 1000]`），超出时从尾部删除最早且未钉的条目。

#### Scenario: 重复的未钉文本
- 假设 历史顶部有一条未钉的 A（文本 "hello"）
- 当 再次复制 "hello"
- 则 新数组与之前相同（不增长、不重复）

#### Scenario: 达到上限
- 假设 历史已满 `L` 条，最旧的是被钉条目
- 当 新条目到达
- 则 策略会淘汰**下一个**未钉的旧条目，被钉条目保持原位

#### Scenario: 全部被钉的历史
- 假设 所有条目都被钉住，且 `n >= L`
- 当 新条目到达
- 则 被钉条目全部保留，新条目插入头部，总长度可以超过 `L`

#### Scenario: 图片数量上限
- 假设 已有超过 100 条未钉的图片条目
- 当 第 101 条未钉图片到达
- 则 最早的一张未钉图片从尾部被删除

### Requirement: 持久化 JSON 存储
系统 SHALL 将历史持久化到 `~/Library/Application Support/Copythat/clipboard-history.json`，包含 schema 版本头，每次保存时原子重写。

#### Scenario: 保存并重载
- 假设 历史中有 3 条条目
- 当 应用退出后重新启动
- 则 同样的 3 条条目按相同顺序出现

#### Scenario: 解码失败恢复
- 假设 `clipboard-history.json` 解码失败
- 当 应用启动时
- 则 该不可读文件被改名为 `clipboard-history-decode-failed-<unix-timestamp>.json` 备份，并从一份空的全新历史开始

#### Scenario: 旧版 UserDefaults 迁移
- 假设 之前剪贴板历史存放在 `UserDefaults` 中
- 当 应用在迁移变更后第一次启动
- 则 旧条目被一次性导入到 JSON 文件，旧 key 被清除
