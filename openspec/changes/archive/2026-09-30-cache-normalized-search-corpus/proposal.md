## Why

搜索框每次输入都会为历史中的每个候选 item 重复拼接和 normalize 相同的 searchable metadata。将这份派生文本随 item 建立并复用，可以降低即时搜索的重复计算，保持现有搜索结果和同步响应方式。

## What Changes

- 将 `ClipboardItem.searchText` 改为 model 自有的 runtime-derived stored property，在创建和恢复时生成一次。
- `withLinkPreview` 在完成 searchable metadata 修改后重建；组织状态和 media residency transform 直接保留 corpus。
- `refreshFilteredItems()` 先排除不符合 Pinboard 的 item，再对缓存文本执行现有 substring predicate。
- 增加隔离的 normalization build-count observation 和 deterministic regression，覆盖构造、恢复、连续 query、enrichment、组织状态和 media transforms。
- 缓存不进入 legacy Codable 或 V2 manifest，schema version 2 不变。

## Capabilities

### New Capabilities

无。

### Modified Capabilities

- `panel-and-search`: 增加即时搜索复用 normalized corpus 的性能与持久化边界 contract，保持现有字段、normalization 和联合过滤语义。

## Impact

- 主要代码范围：`Sources/Copythat/Models/ClipboardItem.swift`、`Sources/Copythat/Stores/ClipboardStore.swift`；另增加最小的计数 observation seam。
- 测试复用 selection、history performance、media identity/storage optimization、link-preview orchestration 和 persistence suites；Panel acceptance 保持通过。
- 每个 item 常驻一份 normalized String；不引入 dependency、Store-level cache、第二套 item 生命周期或 persistence migration。
- 现有 Search spec 的 query-change selection 描述与实现存在差异：实现保留仍可见的 selection。本次保留实现，不修改该既有 scenario，也不在本次解决差异。

## Non-goals

不增加 debounce、异步/background search、fuzzy search、tokenization、inverted index、Pinboard index、ranking、search history、SQLite/FTS、Core Spotlight、持久化搜索索引、schema bump、big-text blob migration 或通用 ClipboardItem 重构；不改变 searchable fields、delimiter、字段顺序、大小写及 Unicode/localization 算法、selection 或 Link Preview lifecycle。
