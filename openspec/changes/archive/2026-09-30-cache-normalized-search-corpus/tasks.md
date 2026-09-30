## 1. Model corpus 与计数边界

- [x] 1.1 在 `Sources/Copythat/Models/ClipboardItem.swift` 将 `searchText` 改为 private-set stored derived state，提取完全等价的私有 normalization helper，在普通 initializer 和 legacy decoder 各生成一次；验证字段顺序、nil/空值、空格 delimiter、URL path 和 localized lowercase 与原表达式一致，且不新增 caller 参数或 Codable key。
- [x] 1.2 增加最小 TaskLocal `SearchCorpusObservation` 和每测试独立的线程安全 build recorder，只在实际 helper 计数；验证同 scope 的构造正向计数、测试间隔离，以及无 recorder 时无记录，不携带任何 clipboard/query/URL/path 内容。
- [x] 1.3 在 `withLinkPreview` 完成现有 mutation 后无条件 rebuild 一次，保留其他 transforms 的复制路径；复用 media identity/storage optimization fixture，验证三个 media transform corpus 不变且零增量，title 替换、nil、相同 title 与仅图片 enrichment 各一次 build。

## 2. 同步查询与语义回归

- [x] 2.1 将 `ClipboardStore.refreshFilteredItems()` 的 predicate 改为 board-first guard，保留 query normalization、board switch、filter 顺序和之后的 selection/fallback 路径；运行 `ClipboardStoreSelectionTests` 和 `PanelAcceptanceTests`，验证 All/Pinned/custom/unknown board、联合 query、空 query、trim、无结果及仍匹配的 selection 保留规则。
- [x] 2.2 在 `ClipboardHistoryPerformanceTests` 添加 1000-item regression：计数窗口内恰好 1000 次创建 build，Store 初始化与至少五个不同 query 均零增量，并断言各 query 的 matching IDs/order；禁止 sleep、wall-clock threshold 或只断言计数而不检查结果。
- [x] 2.3 增加六个 searchable fields 的独立 token 命中、大小写、中文和 Unicode 原表达式等价测试，并加强 Pin/Unpin、Pinboard move/remove/rename/clear 的计数与结果断言；验证组织 mutation 零增量、无新增组织字段搜索语义，remove/clear/dedupe 后过滤和 selection 不回归。
- [x] 2.4 加强 `StoreLinkPreviewOrchestrationTests`：受控 enrichment 恰好一个 item rebuild、新词立即可搜索、只存在于替换 title/linkTitle 的旧词消失、无关 item 不变；等待现有 completion checkpoint 并确认 observation scope 覆盖实际工作，继续通过 stale/cancelled completion 与 fallback lifecycle regressions。

## 3. 恢复与持久化兼容

- [x] 3.1 加强 legacy Codable round-trip：每个 decode item 恰好一次 build、字段默认值仍正确、metadata matches 与 equality 保持一致；解析 encoded JSON 验证无 `searchText`/`searchCorpus`，注入伪 corpus 字段后仍以 metadata 重建。
- [x] 3.2 复用 `ClipboardStorePersistenceTests` 的临时 V2 保存和新 Store restore fixture：每个恢复 item 恰好一次 build，Store 初始化和查询零增量、enriched title/Pinboard 搜索正确；解析 manifest 验证 version 为 2、根及 item records 均无 corpus 字段，且不新增 corpus blob、重读 heavy media 或 migration。

## 4. 完整验证与三轮对抗式审查

- [x] 4.1 使用临时 persistence、独立 defaults 和 named pasteboards 运行 focused suites：`ClipboardStoreSelectionTests`、`ClipboardHistoryPerformanceTests`、`ClipboardItemMediaIdentityTests`、`ClipboardItemStorageOptimizationTests`、`StoreLinkPreviewOrchestrationTests`、`ClipboardStorePersistenceTests`、`PanelAcceptanceTests`；必要时沿用项目 `swift test` 的 Swift Testing framework lookup。验证全部通过并清理测试资源，详细输出保留在 `.build/verification/` 或 `/tmp/`。
- [x] 4.2 完成 Review 1（stale cache）：用 `rg` 搜索 `title`、`linkTitle`、`preview`、`sourceApp`、`kind`、`fileURLs` 的全部赋值，逐项核对构造、legacy decode、V2 restore、两个 Store enrichment caller 和 model transform；验证无漏建/漏 rebuild、无重复恢复 build，旧词失效和 nil-title tests 能约束真实 mutation。
- [x] 4.3 完成 Review 2（persistence）：审查 `CodingKeys`、`PersistedClipboardItemV2`、history JSON、blob、save coordinator 与 schema version；验证 cache 从未进入持久化，存储流程无额外复杂度，并与 JSON/schema assertions 相互印证。
- [x] 4.4 完成 Review 3（scope）：审查最终 diff，验证没有 Store-level corpus/result cache、debounce、search actor、通用 LRU、database/index service 或新 concurrency ownership；确认 selection 与 Link Preview lifecycle 未改，observation 仅统计 build 且具有正向控制。发现问题后修复并重跑受影响检查，审查结果只在响应中汇报。
- [x] 4.5 在隔离验证环境执行 `swift test`、`swift build`、`./script/verify_all.sh`、`git diff --check` 和 `openspec validate cache-normalized-search-corpus --strict`；验证各命令退出成功，不削弱 gate 或依赖要求。可补充已有无人值守 live panel verification，未执行的 physical UI/permissions/multi-display 范围明确为未覆盖，不用人工 sleep-based performance test；不把单次结果、hash、路径或 pass report 放入 Change artifacts。
