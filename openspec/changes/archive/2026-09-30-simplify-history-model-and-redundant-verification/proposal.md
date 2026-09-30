## Why

历史项的媒体变换与粘贴 materialization 反复重建完整 `ClipboardItem`，新增字段时容易漏传来源图标、组织信息或 blob identity，影响历史卡片显示、去重和恢复。将这些变换改为受控的值复制，并合并重复验证、删除已证实无用的转发代码，可以降低维护风险，而不减少现有产品行为与验证保障。

## What Changes

- 简化 `ClipboardItem.storageOptimized`、`withLinkPreview`、`releasingResidentMedia` 和 Store 的临时粘贴 materialization：复制既有值，仅通过模型拥有的操作修改实际变化的字段；保持 bytes 与 content address 同步。
- 将 `script/verify/source_resolution.swift` 中的全部断言映射到 Swift Testing；先补齐现有单元测试遗漏的用例，再删除独立 executable 与 `script/verify_all.sh` 中重复的编译、执行步骤。
- 删除 `ClipboardDiagnostics.emitLinkPreview` 未调用的 private 实现，保留实际使用的 `logLinkPreview` 路径。
- 将 `runDeferredLinkPreviewReconcile` 的直接转发内联到 `withHistoryStateMutation` 的原有 `defer` 位置，保持先退出 mutation 状态、再 reconcile 的顺序。
- 不改变用户可见行为、持久化格式、来源解析规则或测试隔离；不以减少行数作为验收标准。

## Capabilities

### New Capabilities

无。

### Modified Capabilities

无。现有 `clipboard-history` 与 `paste-and-permissions` 契约已覆盖媒体身份、持久化、来源上下文和临时恢复行为，本 Change 只改变实现及验证组织方式。`.openspec.yaml` 设置 `skip_specs: true`，不生成 delta，也不修改 main specs。

## Impact

- **Models / Stores:** `Sources/Copythat/Models/ClipboardItem.swift`、`Sources/Copythat/Stores/ClipboardStore.swift`、`Sources/Copythat/Stores/ClipboardStore+LinkPreview.swift`。仅被模型变换修改的字段可以改为模型私有 setter；媒体字段不获得外部自由写入权限。
- **Diagnostics:** `Sources/Copythat/Support/ClipboardDiagnostics.swift` 删除未调用的方法，事件内容、开关、序列化和 sinks 均不变。
- **Verification:** `Tests/CopythatTests/CopySourceResolutionTests.swift` 补齐覆盖；删除 `script/verify/source_resolution.swift`，最小调整 `script/verify_all.sh`。保留 source-attribution timing gate、完整 Swift tests 和 packaged-app gates。
- **Regression tests:** 在现有模型身份、storage optimization、Store preview、durable release、persistence 和 paste materialization 测试中补充针对性的字段保留与操作计数断言；不另建通用测试框架。
- **Compatibility:** 保持 `ClipboardItem` 的 CodingKeys、legacy 解码、V2 manifest 与 blob 布局；不引入迁移、新依赖或新设置。

## Non-goals

- 不删除或退役 `history_media_acceptance.sh`、`AcceptanceMetrics`、DI seams、`MediaHashObservation` 或现有测试计数器。
- 不以 `NSCache` 替换严格预算 / LRU；不改变 cache 容量、media loader、source tracker 或 source-icon cache change。
- 不合并不同语义的 PNG 编码路径，不重构新 capture item 的构造，不增加通用 copy builder、patch 协议或 capture factory。
- 不修改 Settings Scene、Pinboard unknown fallback、RelativeTime、颜色、搜索动画、pollTask、启动环境变量或 paste attempt 协调。
- 不调整 Pillow 依赖或图标验证，不删除图标资产，不更改 pasteboard / Accessibility 安全检查。
- 不实现 audit 中未经证实或需要独立行为决策的建议。
