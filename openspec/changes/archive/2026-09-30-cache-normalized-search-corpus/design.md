## Context

动机见 `proposal.md`。`ClipboardItem.searchText` 当前是计算属性；Store 每次 refresh trim 并 lowercase query 后遍历 item。searchable fields 中 `kind`、`preview`、`sourceApp`、`fileURLs` 不可变，`title`、`linkTitle` 的 setter 属于 model；现有运行时修改入口为 `withLinkPreview`。

legacy decoder 自行填充字段，V2 `PersistedClipboardItemV2.makeClipboardItem` 调用普通 initializer。`storageOptimized`、`releasingResidentMedia`、`materializedForPaste` 均复制 `self` 后仅更新 media。Pin/Pinboard 操作直接更新组织字段。设计涉及 model、Store 和恢复边界，因此保留 design artifact。

## Goals / Non-Goals

**Goals:** 缓存 item 到 normalized corpus 的派生关系；所有构造/恢复路径返回完整 corpus，低频 enrichment 返回更新后的 corpus；query refresh 没有 corpus build。

**Non-Goals:** 不缓存 query results，不将 derived state 暴露为 caller 输入，不改变 selection、media ownership、save coordinator 或 preview orchestration。完整范围见 `proposal.md`。

## Decisions

### 1. Model 拥有 stored corpus

采用 `private(set) var searchText: String`，由 initializer/decoder 完成其他字段赋值后直接赋值；如 Swift 初始化顺序需要默认值，可使用空字符串默认值，但不得从任何正常构造路径返回空的未建立缓存。不增加 `searchText` initializer 参数。

私有静态 `makeSearchText` 接收六类 searchable fields，完整保留原表达式语义：`[title, preview, linkTitle, sourceApp, kind.label].compactMap(\.self)` 后追加 `fileURLs.map(\.path)`，以一个空格 join，再执行 `localizedLowercase`。不增删字段，不去重，不改变 nil/空字符串、顺序、delimiter 或 URL path 表达方式。

普通 initializer 和 legacy `init(from:)` 各调用一次 helper。V2 restore 复用普通 initializer，不另加 restore rebuild。拒绝 Store dictionary、NSCache、actor/global cache 和 lazy-on-first-search：这些方案增加生命周期状态或首键输入成本。

### 2. 唯一运行时 rebuild 边界

`withLinkPreview` 完成现有 title/linkTitle 和 media 修改后无条件调用 helper 一次；保持 `title: nil` 保留显示 title、清空 linkTitle 的现有语义。相同 title、nil title 或仅图片 enrichment 也允许这一次 rebuild，避免增加 invalidation 分支。

其余三个 media transform 与 Pin/Unpin、Pinboard assignment/removal/rename/clear 直接保留已有 String，不 normalize。add/dedupe/remove/eviction/clear 无额外 cache registry 要维护。后续新增 searchable-field transform 时，必须在 model 返回前维护同一不变量。

### 3. Store 保持同步过滤

保留每次 refresh 一次 `trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase`，保持 `items.filter` 顺序与现有 board switch（含 unknown）。board 不匹配时立即返回 false，否则返回 `query.isEmpty || item.searchText.contains(query)`。

不改 filter 之后的 selection 和 `reconcileLinkPreviewFallback` 路径。已知差异：main spec 的 `Search query changes` scenario 写为总是选第一项，实现则保留仍匹配的 selection。本次以保留当前 runtime 行为为范围边界，不修改原 requirement 或借缓存变更修复这一差异；新增 regression 证明仍可见的 selection 被保留，失效时选首项，无结果时清空。

### 4. Runtime-only 与恢复边界

不把 corpus 放入 legacy `CodingKeys`、`PersistedClipboardItemV2`、blob、manifest、save coordinator 或 migration。legacy 和 V2 均从 metadata 重建，不信任输入 JSON 中额外的 `searchText`/`searchCorpus`。显式断言两种编码均无这两个字段，V2 version 为 2。

### 5. Deterministic observation 与 regression

参考 `Sources/Copythat/Models/PreparedMedia.swift` 的 `MediaHashObservation`，提供最小 `SearchCorpusObservation` 和每测试独立的 recorder，使用 TaskLocal 安装、锁保护单一 build count；只在实际 normalization helper 记录一次。无 recorder 时无记录；不记录 clipboard 字段、query、URL、path 或 item identifiers。不创建通用 metrics/caching framework。

计数窗口必须有正向控制：窗口内创建 1000 个 item 恰好记录 1000 次，随后初始化 Store 和设置至少五个不同 query（例如 `a` 到 `abcde`）计数不增加，同时断言预期结果。Pin/Pinboard 和三个 media transform 验证零增量与 corpus 不变。enrichment 验证恰好加一、无关 item 不变、新词命中、独立旧词不再命中；补相同 title、nil title、仅图片 enrichment 的一次 build。

legacy decode 和 V2 load 分别安装 recorder，断言每个恢复 item 一次 build、构建 Store/query 不增加，并验证搜索结果。所有字段用独有 token 独立命中，补大小写、query trim、空 query、中文和原表达式等价性断言。复用现有 media identity、storage optimization 和 persistence fixture。

TaskLocal 不会自动覆盖 detached work；计数场景优先直接测量同步 model/restore 和受控 Store enrichment，异步路径必须等待已有 completion checkpoint，若经过 detached 边界则显式传播 recorder，禁止以未观测的零计数作为证据。不使用 sleep 或 wall-clock threshold。

## Risks / Trade-offs

- 常驻拼接 String 增加 metadata 内存与创建/启动恢复成本 → 用 eager build 换取 session 内 query 复用；struct 复制直接继承 String，不重建。此变更不宣称 `contains` 对长文本为固定成本，也不以计数证明实际耗时上限。
- searchable-field transform 漏更新产生 stale corpus → private setters、唯一 helper、旧词失效测试与 mutation audit 共同约束。
- 计数 seam 未安装造成零增量假通过 → 同 scope 构造/恢复正向计数，受控异步 completion 和隔离 recorder。
- 派生字段进入 synthesized Equatable → 保持 derived state 与 metadata 一致，不重写整个 Equatable；用 legacy round-trip 和 transforms 的现有 equality regression 验证。
- locale 相关行为 → 完整复用 `localizedLowercase`，恢复时重新生成 corpus；本次不引入自定义 Unicode 算法或 locale-change observer。
- full gates 接触真实 clipboard/history/defaults → 验证使用临时 persistence、独立 defaults、named pasteboard 并清理子进程；physical UI/TCC/multi-display 证据未执行时明确标为未覆盖，不把自动化重命名为人工验收。

## Migration Plan

无 schema/data migration。发布后从现有 metadata 创建 runtime corpus；回退代码仍读取相同 legacy/V2 数据。实现后运行 `tasks.md` 的 focused/full gates，并完成三轮独立主题的对抗式审查；不要提交单次运行报告。
