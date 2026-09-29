## Why

Copythat 的 V2 manifest 已将媒体存为独立 blob，但启动仍同步读取并验证所有 image/link image，导致未使用的历史图片消耗启动 I/O 和常驻内存。将媒体存在性与内存驻留分开，可以先恢复可搜索、可组织的历史，再在显示、paste 或 drag 时取得媒体。

## What Changes

- `ClipboardItem` 保留内部 image/link blob references 与 payload presence semantics；eager/lazy image 的 contentKey 一致，模型复制不丢引用。
- V2 startup 仅加载 metadata 与 source icons；保持 schema version 2、V1/raw array/UserDefaults 兼容。非法 ID 仍拒绝 manifest，合法 ID 的 missing/corrupt heavy blob 延迟到访问时局部失败。
- 保存 unloaded references 不读、不 hash heavy blobs；保留既有 blob-first/atomic-manifest、save worker、GC 和 materialized Data 的校验修复行为。
- 增加共享验证 primitive 与非 MainActor media loader，使用内部 32 MiB byte-cost LRU；媒体不写回 history 数组，不触发 save、selection 或 preview enrichment。
- 可见 card 按需加载，panel hidden/Hide Previews 取消 UI loading，保留固定 placeholder；已有 persisted link preview 不因 Data 为 nil 重新抓取。
- paste 前生成临时 image item，由 panel controller 管理 newest-wins 与 close cancellation；沿用现有 performer activation coordination。lazy image drag 提供异步 image representation，禁止退化为 text。
- 以 read counters、可控 completion 与 named pasteboard 验证数据完整性、取消和 500-item 零重媒体 startup reads。所有必需测试与验收均无人值守执行，不要求人工 smoke、系统权限点击或物理外设操作；提供单命令 runner 与自动报告，明确真实 AppKit / synthetic 权限与屏幕证据边界。

## Capabilities

### New Capabilities

无；复用现有 capability paths。

### Modified Capabilities

- `clipboard-history`: lazy V2 restore、引用持久化/GC、稳定媒体身份、局部完整性失败与 bounded on-demand loading；已存 link image 的语义判定。
- `panel-and-search`: 仅显示路径加载、privacy/visibility gating、稳定布局与正确异步 image drag。
- `paste-and-permissions`: lazy image paste materialization 与交给 performer 前的取消/supersession 保证。

## Impact

基线：2026-09-29，当前 `main` commit `637cd24b94f9dd2b958b42af33d48b144b3cb4d1`，与本地 `origin/main` 相同，创建 change 前工作区干净。

涉及 `ClipboardItem`、`ClipboardHistoryPersistence`、新增 `ClipboardHistoryMediaLoader`、`ClipboardStore`/`ClipboardStore+LinkPreview`、`AppModel` 的 loader 组装、focused image drag Support helper、`ClipboardCardView`、`BottomPanelView`、`PanelWindowController` 及相关测试。`ClipboardPastePerformer` 核心保持原样；若实测证明需要暴露已有 supersession cleanup，仅允许最小入口并保留原协调机制；无人值守权限验收允许注入 trust-check closure，生产默认仍调用现有 AccessibilityService。无需新增依赖、权限或磁盘格式。

## Non-goals

不引入 SQLite/CoreData/SwiftData、schema V3 或额外 migration；不 lazy-load source icons，不重设计 icon cache；不做 search optimization、metadata concurrency budgeting、完整 Change 6 identity/write optimization；不重写 Store 或 performer，不修改 capture polling、source attribution、350 ms fallback/PID matching/observer ordering/single-send contract。本轮仅创建规划文件，不 Apply、归档、commit 或 push。
