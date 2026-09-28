## Why

在 `main@35a1b152`，复制 URL 后的 metadata enrichment 会直接进入 WKWebView fallback，即使面板从未打开，也可能加载和渲染真实网页。该工作没有受 item、selection 或 panel 生命周期约束，造成无意义的后台资源消耗。

## What Changes

- 保留 eager LPMetadataProvider enrichment，拆出独立的 metadata 与 WebKit snapshot 阶段；明确区分 metadata 成功无图、失败和取消。
- 仅当 panel 可见、当前选中的可见 URL 已完成本 session 的 metadata 且无图时，允许 WebKit fallback。
- Store 持有任务与 transient eligibility；selection latest-wins，旧请求清理后再启动最新目标，最多一个 active WebKit fallback。
- selection change、panel close、删除、history eviction 与 Clear History 取消无效工作；请求身份校验阻止 stale result、重复 resume 和旧任务清理新状态。
- navigation 完成后尽早截图，页面等待约 3 秒后可尝试当前状态；截图阶段也有有界结束。使用 non-persistent website data。
- 按完整 URL 复用 session 成功截图；失败使用 5 分钟 retry TTL，取消不算失败。继续通过现有 saveItems/persistence 保存有效 preview。
- 增加无真实网络或网页的 deterministic orchestration 与 lifecycle 测试，并复用本地真实 provider runner、隔离功能测试和 panel smoke 完成当前环境自动化验收，记录功能断言与资源生命周期证据；真实桌面 UI、系统权限与物理多屏实测作为可选补充。

## Capabilities

### New Capabilities

无新增 capability。

### Modified Capabilities

- `clipboard-history`: 增加 URL preview enrichment、按需 WebKit fallback、取消、session cache 与 stale-result 防护契约；复用现有历史与媒体持久化能力。

## Impact

- 主要实施位置：`Support/LinkPreviewFetcher.swift`、`Stores/ClipboardStore.swift`、`Services/PanelWindowController.swift`。
- 可增加 focused `Support/LinkPreviewSnapshotController.swift`，仅隔离单次 WKWebView 请求的 navigation、snapshot 与清理；不构建通用资源管理框架。
- Tests 增加可控 metadata/snapshot loader、时间与 WebKit lifecycle seam；现有 persistence preview 测试继续保留。
- `ClipboardItem`、URL card 呈现、search、pinboard 与 paste 继续使用现有契约。无 dependency、persistence schema 或用户设置变化。

## Non-goals

- 不改变 clipboard capture、source attribution、paste flow、history limit 或图片 clipboard encoding pipeline。
- 不重新设计 Change 2 persistence，不新增数据库、磁盘 Web cache，不直接操作 history-media。
- 不重做 Link card UI，不重构 ClipboardItem，不新增用户设置或第三方依赖。
- 不实现 metadata 全局并发队列、semaphore、通用网络 scheduler 或登录态复用。
- 不等待 JS/图片网络完全静止，不保证所有 URL 都生成图片。
