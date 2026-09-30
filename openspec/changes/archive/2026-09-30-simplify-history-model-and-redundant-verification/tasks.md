## 1. 锁定现有语义与完整断言覆盖

- [x] 1.1 在 `Tests/CopythatTests/CopySourceResolutionTests.swift` 中按 design D3 映射 standalone verifier 的每条 precondition；复用等价测试，补齐 stale / System shortcut、无候选与 fallback、baseline 10/12 对 current 12/13、legacy single-change、stale 原数组 index、Copythat PID / bundle 与 SystemUIServer 排除、普通应用接受。验证：固定 now 的 targeted suite 全通过，并逐条对照原 verifier 确认没有遗漏后才允许任务 3.3 删除文件。
- [x] 1.2 在现有 `ClipboardItemMediaIdentityTests` 和 `ClipboardItemStorageOptimizationTests` 中补充完整 metadata / source-icon 保留、preview nil 组合、optimization 相同 / 不同 bytes、优化失败清除 bytes 与 ID、reference-only 保留、durable roles 独立释放及 no-op 返回 nil 的必要断言。验证：重构前 targeted tests 通过，非变更字段与原项相同，hash counters 证明已知身份转发零 hash、实际新优化 payload 每个只建立一次 identity。
- [x] 1.3 在现有 `PanelPasteMaterializationTests`、`ClipboardStorePreviewIdentityTests` 和 durable-release / persistence tests 中补齐受控复制的集成断言。验证：临时 materialized item 保留原 UUID、来源、source icon、组织信息和 blob ID，原始项与 Store history 不变且不触发保存；preview/title-only 与 committed release 保留已有零额外 hash/read 保证；loader 错误与不可解码仍失败。使用 named pasteboards、临时 persistence 和 isolated defaults，targeted tests 在重构前通过。

## 2. 模型拥有的值复制与 Store 集成

- [x] 2.1 将模型变换需要修改的 title、linkTitle、image/link-image bytes 与对应 ID 最小改为 `private(set) var`，将 `storageOptimized` 改为 copy-and-change，并通过原有媒体身份规则建立最终地址；保持 source icon、其他不可变字段、initializer 与 CodingKeys。验证：任务 1.2 的 optimization cases 全通过，reference-only 不加载、不 hash，变更 bytes 不沿用旧地址，失败不留下地址；inline Codable round-trip 与 runtime BlobID 不进入 encoded payload 的测试通过。
- [x] 2.2 将 `withLinkPreview` 和 `releasingResidentMedia` 改为模型内部值复制；严格保持 design D2 的 nil 语义和角色独立释放，不改变匹配条件。验证：任务 1.2 / 1.3 对应测试、`ClipboardStorePreviewIdentityTests`、`StoreLazyLinkPreviewTests`、`ClipboardStoreDurableReleaseTests` 与 `ClipboardHistoryDurableReleaseTests` 通过，source icon、metadata、contentKey 和 unloaded references 保留，无新增 hash/save。
- [x] 2.3 添加接收可信 PreparedMedia 的窄模型 materialization 操作，并替换 `ClipboardStore.materializedItemForPaste` 的全字段 reconstruction；Store 保留原 loader、blob ID、decode 检查和错误边界，不直接写媒体字段。验证：`PanelPasteMaterializationTests`、`ClipboardPostReleasePasteDragTests` 和任务 1.3 的 metadata/原项不变断言通过；verified payload 转发不产生 identity hash，不改变取消、supersede、pasteboard 写入或 Command-V 安全检查。
- [x] 2.4 运行模型 / Store 与持久化集成回归。验证：`ClipboardItemMediaIdentityTests`、`ClipboardItemStorageOptimizationTests`、`ClipboardHistoryPersistenceTests`、`ClipboardStorePersistenceTests`、`ClipboardHistoryMetadataSaveAcceptanceTests`、`ClipboardStoreImageCaptureIdentityTests` 通过；metadata-only pin、unpin、pinboard、title 变更仍零 media hash/read/write，legacy 与 V2 保存 / 重载兼容；`swift build` 通过。

## 3. 删除已证实重复的代码和执行入口

- [x] 3.1 删除 `ClipboardDiagnostics.emitLinkPreview` 未调用的 private 实现，仅保留现有 `logLinkPreview` 行为。验证：源码中该声明和引用均消失，`ClipboardDiagnosticsTests` 及现有 link-preview diagnostics 断言通过；默认关闭、事件字段、sink 与 payload-safety 不变。
- [x] 3.2 在 `withHistoryStateMutation` 的原同步 defer 中直接调用 `performLinkPreviewReconcile`，保持先清除 `isMutatingHistoryState`；删除 `runDeferredLinkPreviewReconcile` 包装。验证：`StoreLinkPreviewOrchestrationTests`、`StoreLinkPreviewCancellationTests`、`StoreLinkPreviewRemovalTests`、`StoreLinkPreviewCacheTests`、`StoreLazyLinkPreviewTests` 通过；mutation 只在最终状态 reconcile，stale completion 不应用，fallback 仍至多一个；源码中包装无残留。
- [x] 3.3 在任务 1.1 覆盖验证完成后删除 `script/verify/source_resolution.swift`，只移除 `script/verify_all.sh` 中其临时二进制编译 / 执行 / 清理段。验证：`bash -n script/verify_all.sh`、完整 Swift Testing 与 `script/verify/source_attribution_timing_test.sh` 通过；verify_all 保留原 framework lookup、timing、图标、packaging 和 packaged-app gates；活跃代码与工具无失效的 verifier 引用，归档历史文档不改写。

## 4. 完整验证与范围审查

- [x] 4.1 执行现有广域验证前确认验证隔离，运行 `swift build` 和 `./script/verify_all.sh`，沿用安装工具链需要的 Testing.framework lookup 与可用 Pillow 环境。验证：全部 required gates 成功退出，真实用户 history/preferences 不被验证流程覆盖；缺失环境作为 blocker 保持任务未完成，不删检查、不修改权限来掩盖失败。输出留在 `.build/verification/` 或 `/tmp/`。
- [x] 4.2 确认既有 history-media 验收能力保留并回归。验证：`script/verify/history_media_acceptance.sh self-test` 及其完整 run 成功，expected/observed 报告能力和 AcceptanceMetrics 不减少；使用现有执行环境配置解决 framework/Pillow lookup，不在本 Change 扩展 runner 实现。blocked、timeout 或 not-covered 不算通过，原始报告保留在忽略的 `.build/` 下。
- [x] 4.3 执行变更范围与逆向审查。验证：本 Change 只修改 proposal 所列实现/测试/tooling，媒体 setter 不向外开放，所有 copy 路径不抄全字段且不额外 hash；验收 runner、DI、hash counters、LRU、PNG 路径、Settings、UI、pollTask、paste coordination 与现有 source-icon change 保持。运行 `openspec validate simplify-history-model-and-redundant-verification --strict` 和 `git diff --check`，两者通过；源码变化具备实际静态诊断或编译证据，验证结论仅在会话中汇报。
- [x] 4.4 完成与模型变换相关的人工验收，保留项目其他既有手工检查义务。验证：在隔离测试历史中浏览 resident / 已释放 image 与 URL，pin/unpin、移动 pinboard、搜索、重开 panel 后 source icon 与组织状态保持；恢复 image 并在有效目标与已授权 Accessibility 下验证 paste，缺失权限时仍可手工粘贴已恢复内容；记录实际覆盖边界到会话，不能以 synthetic tests 声称完成物理多显示器或真实权限验证，未完成的检查保持未勾选。
