# 剪贴板捕获规范

## Purpose
Copythat 持续监听 macOS 的 `NSPasteboard.general`，把新出现的剪贴板内容解析为 `ClipboardItem` 并归因到来源应用。捕获流程是整个产品的事实生成点，其结果就是 `clipboard-history` 持久化的输入。

## Requirements

### Requirement: 剪贴板轮询
系统 SHALL 在 store 启动时以每 0.45 秒一次的间隔轮询 `NSPasteboard.general`。仅当 `changeCount` 推进 **且** 解析出的内容与同 kind 最近条目的 `contentKey` 不同时，SHALL 产生新的历史条目。

#### Scenario: 空闲的剪贴板
- 假设 用户没有复制任何新内容
- 当 轮询定时器触发
- 则 不会创建新的历史条目

#### Scenario: 首次复制
- 假设 历史为空
- 当 用户在 TextEdit 中复制了 "hello"
- 则 1 秒内出现一条新的文本条目，且 `sourceApp == "TextEdit"`

### Requirement: 内容类型解析
系统 SHALL 将新剪贴板内容分类为**正好一种**：`file`、`image`、`url` 或 `text`，按该优先级排序。如果多种类型同时存在，`file` 胜出；否则 image；否则 URL；否则纯文本。

#### Scenario: 仅含文件 URL
- 假设 剪贴板只包含一个 Finder 文件 URL
- 当 变化被观察到
- 则 条目为 `kind == .file`，`fileURLs == [该 URL]`

#### Scenario: 可解析为 URL 的纯文本
- 假设 剪贴板包含一个能解析为 URL 的字符串
- 当 变化被观察到
- 则 条目为 `kind == .url`（而非 `.text`），`textValue` 保存该 URL

#### Scenario: 图片数据
- 假设 剪贴板包含 PNG/TIFF 图片数据
- 当 变化被观察到
- 则 条目为 `kind == .image`，`imageData` 是 PNG 编码

### Requirement: 图片编码流水线
系统 SHALL 通过 detached 后台任务将图片条目编码为 PNG，且 SHALL 不得阻塞轮询循环。

#### Scenario: 快速连续截图
- 假设 2 秒内连续 5 次截图
- 当 轮询循环处理它们
- 则 5 条按序全部出现在历史中，UI 保持响应

### Requirement: 复制源归因
系统 SHALL 为每条新条目解析 `sourceApp`，按以下槽位顺序选取第一个新鲜候选：**shortcut**（在 `CGEvent.tap` 观察到的 `⌘C` / `⌘X` 或系统截图 `⌃⌘⇧3/4/5` 按键 3 秒内）、**currentForeground**（任意前台应用）、**recentForeground**（8 秒内）、**system**（当内容由系统生成时为 `com.apple.systemuiserver`）、**unknown**。

#### Scenario: 通过系统快捷键截图
- 假设 用户按下 `⌃⌘⇧3`
- 当 截图落到剪贴板
- 则 新图片条目的 `sourceApp == "com.apple.systemuiserver"`

#### Scenario: 前台纯文本复制
- 假设 TextEdit 处于最前
- 当 用户按下 `⌘C`
- 则 新文本条目的 `sourceApp == "TextEdit"`

#### Scenario: 回退链
- 假设 过去 3 秒没有 shortcut，过去 8 秒也没有最近前台应用
- 当 观察到一次剪贴板变化
- 则 源回退为 `"unknown"`

#### Scenario: 排除自身
- 假设 唯一候选源是 Copythat 自身
- 当 解析器运行
- 则 该候选被拒绝，使用链中的下一个槽位

### Requirement: 源候选过滤
系统 SHALL 不得将剪贴板变化归因于 Copythat（bundle id `local.copythat.clipboard` 或显示名 `Copythat`），也不得归因于 `SystemUIServer`。同一套排除规则在 `paste-execution` 中也用于拒绝粘贴目标。

#### Scenario: 自我归因被拒
- 假设 Copythat 自身刚刚写入了剪贴板
- 当 解析器把 Copythat 视为候选
- 则 拒绝该候选，使用上一个前台应用（如新鲜）

### Requirement: 忽略应用
系统 SHALL 跳过那些解析出的 `sourceApp` 显示名（大小写不敏感、每行一个）出现在 `ignoredApplications` 设置中的剪贴板变化。

#### Scenario: 被忽略的应用复制
- 假设 "1Password" 在 `ignoredApplications` 中
- 当 1Password 把密码写入剪贴板
- 则 不创建历史条目

### Requirement: 敏感内容过滤
系统 SHALL 在 `recordSensitiveContent` 设置为 `false` 时，跳过来自已知密码管理器（1Password、Bitwarden、Keychain Access）的剪贴板变化。该过滤与 `ignoredApplications` 独立。

#### Scenario: 敏感内容被拦截
- 假设 `recordSensitiveContent == false`
- 当 1Password 复制一个密码
- 则 不创建历史条目（无论 `ignoredApplications` 如何设置）

#### Scenario: 允许记录敏感内容
- 假设 `recordSensitiveContent == true`
- 当 1Password 复制一个密码
- 则 创建一条新条目，`sourceApp == "1Password"`

### Requirement: 链接预览富化
对 `kind == .url` 且尚无预览的新条目，系统 SHALL 尽力抓取元数据：先用 `LPMetadataProvider`（8 秒超时），再用 URL 的 `NSItemProvider.loadItem(forTypeIdentifier: image)`，最后用 `WKWebView` 抓取页面截图（等待 3 秒）。结果通过 `withLinkPreview` 写回；任一阶段失败都保持原条目不变。

#### Scenario: 元数据抓取成功
- 假设 新增一个 URL `https://openai.com`
- 当 预览器解析完成
- 则 该条目的 `linkTitle` 与 `linkImageData` 在不阻塞轮询循环的前提下被更新

#### Scenario: 预览器超时
- 假设 URL 较慢或不可达
- 当 三个抓取阶段全部失败
- 则 条目仍保留在历史中，`linkTitle == nil`、`linkImageData == nil`
