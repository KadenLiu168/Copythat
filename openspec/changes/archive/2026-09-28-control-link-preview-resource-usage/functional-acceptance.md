# Tasks 8.2 / 8.3 自动化功能验收 — 2026-09-28

结论：**8.2 passed；8.3 passed**。必需自动化项均通过后才更新 tasks。此次只执行这两项验收及必要测试/隔离支持；未重新执行完整 Stage 3 审计，不将历史 task 8.4 或旧 green run 作为本次证据。未 archive、commit、push 或重置 TCC。

## 源码身份和证据

- Worktree: `/Users/kaden/Copythat`；base HEAD `35a1b152a44a469df6f130fabdebe082b3f35cc3`，包含本轮开始前已有的未提交 Change 实现。
- 最终 source fingerprint (SHA-256): `6df3cf16f7c8553f30ae99b36e4fad8bb0ddf0c14fb10c6f087817a1afc37139`。
- `ProductName:		macOS; ProductVersion:		27.0; BuildVersion:		26A428`；`macOS-27.0-arm64-arm-64bit`；Swift `Apple Swift version 6.4 (swiftlang-6.4.0.34.1 clang-2100.3.34.1)
Target: arm64-apple-macosx27.0.0`；Xcode developer directory `/Applications/Xcode.app/Contents/Developer`。
- 逐文件 SHA-256、最终检查时间：`evidence/2026-09-28-functional-acceptance/source-identity.json`。覆盖 Sources、Tests、script、Package.swift 和 Copythat.entitlements；最终 gate 后逐文件核对，代码/测试/脚本无漂移。
- 下文每一项绑定上述源码身份；实际命令和结果另存 `commands.json`，每个确定性测试的名称、源码行号、断言和结果在 `test-assertions.json`。证据文件路径均相对于本报告的 `evidence/2026-09-28-functional-acceptance/`。
- runner 原始输出同时位于 `.build/preview-functional-acceptance/`，持久副本位于 Change evidence 目录。`report.json` 的 evidenceLevel 为 `automated-real-providers`，不把 in-process provider 行为称作完整桌面 UI 验收。

## 隔离支持与新增断言

在运行完整 gate 之前，先补齐以下支持并通过 focused tests：

1. `ClipboardStorePersistenceTests.previewSavedToDiskRestoresIntoNewStoreAndRetainsURLBehavior`：生产 coordinator → save worker → 临时 manifest/blob → 新 persistence 实例实际 load → 新 Store。验证 title、PNG bytes/可解码尺寸、ID、URL、source、pin、pinboard；再验证按 preview title Search、Pinned/Work 过滤、已有图不新建 metadata/fallback、named pasteboard restore 和删除。
2. `StorePanelWiringTests.realPanelControllerShowCloseUpdatesStoreVisibility`：隔离 AppModel，实际生产 controller show → close → reopen → close；检查真实 NSWindow visibility 和 Store panelVisible。现有 source 字符串测试仅作补充。
3. AppModel 加入 settings/initialItems 注入；DEBUG verification 启动从临时 root、独立 suite、named pasteboard 构造模型。为所有 AppSettings 读取键写入 suite 中的测试值，避免 UserDefaults search list 继承私人设置；以空历史启动，不读取私人 legacy history。
4. `build_and_run.sh` 的 verify/portable/panel 模式使用自己的 child PID 和临时隔离配置；等待 AppDelegate 的 launch-ready 文件后验证。退出时只清理自己的 child、临时目录和 suite。拒绝 release verification，避免 DEBUG 隔离被编译掉。生产 panel 仍经 AppDelegate → PanelWindowController → Store；verification 关闭 source event tap 和全局快捷键注册，named pasteboard 监控仍运行。
5. 既有 AppModel/termination/settings/selection/image deletion 测试补齐独立 defaults、空 initialItems、discard/注入 worker、named pasteboard；完整测试不会经默认参数操作私人 history 或系统剪贴板。真实 provider runner 不再回退到 `.standard`。

首次 focused compile 证明确实缺少 AppModel 注入参数（`pre-support.log`）；补齐后通过。另一次 compile 使用了错误的嵌套 enum 名称（`isolation-settings-compile-attempt.log`），修正为 AppSettings 内的类型后重新通过全部 gate。

磁盘恢复负向对照：临时将新 Store 的输入改为未恢复的原始 item，title/image 断言失败，exit 1；见 `disk-restore-negative-control.log/.exit`。这不是 gate failure，而是验证恢复断言能拒绝假恢复。随后恢复实际磁盘 load 源码，最终 targeted/full gate 均通过。

## 实际命令与结果

所有命令 cwd 为 `/Users/kaden/Copythat`，未跳过必需 gate。每行源码身份同上。

| 项目 | 命令 | 结果 | 证据 |
| --- | --- | --- | --- |
| 8.2 live runner | `bash script/verify/preview_live.sh run --port 18765 --output .build/preview-functional-acceptance` | exit 0；8/8 scenarios，全部 assertions true | `preview-live.log/.exit`，`report.json` |
| 8.2/8.3 deterministic tests | `swift test -Xswiftc -F -Xswiftc /Applications/Xcode.app/Contents/Developer/Library/Frameworks --filter 'LinkPreview|StorePanelWiring|ClipboardStorePersistence|ClipboardStorePasteboard|PasteDecision|ClipboardPastePerformer|PasteTarget|PanelFrame'` | exit 0；96 tests / 15 suites | `targeted.log/.exit`，`test-assertions.json` |
| 8.3 complete gate | `PATH=/opt/homebrew/Caskroom/miniconda/base/bin:$PATH ./script/verify_all.sh` | exit 0；241 tests / 40 suites | `verify-all.log/.exit` |
| OpenSpec | `openspec validate control-link-preview-resource-usage --strict` | exit 0；valid | `openspec-validate.log/.exit` |

完整 gate 包括 `swift build`、全部 Swift tests、packaging fixtures、source resolution/timing、Pillow icon checks、隔离 app startup、portable startup、panel smoke、bundle/signature checks。Python 使用 Conda 的 Pillow，未弱化检查。最终 gate log 内三条 `isolation root=... defaults=... pasteboard=... pid=...` 记录各启动的隔离路径和 PID；panel smoke 实际观察到当前 child 的窗口（1642 × 350），并清理该 child。它覆盖 window-server 窗口出现，不能证明 card pixels。

## 8.2 真实 providers：逐场景断言

以下每行使用 live runner 命令和相同 source fingerprint；expected/observed/passed 的逐断言原始值、事件和时间在 `report.json`，运行结果在 `preview-live.log`。

| Scenario | 关键断言（expected → observed） | 结果 |
| --- | --- | --- |
| P1-metadata-image-closed-panel | metadata-image-event: 1 → 1；zero-snapshot-events: 0 → 0；og-image-stored: true → true | passed |
| P2-title-only-batch | metadata-title-only-events: 3 → 3；zero-snapshot-events: 0 → 0；cards-stay-plain-while-closed: true → true | passed |
| P3-open-select-selected-only | selected-item-applied: 1 → 1；unselected-item-idle: 0 → 0；total-applied: 2 → 2 | passed |
| P4-rapid-switch-overlap | final-target-applied-once: 1 → 1；superseded-target-never-applied: 0 → 0；cancellations-observed: >=2 → 5 | passed |
| P5-close-cancel-reopen-retry | cancel-observed: >=1 → 1；no-late-apply-while-closed: 0 → 0；reopen-retried-and-applied: 1 → 1 | passed |
| P6-refused-no-recovery | metadata-outcome-observed: 1 → 1；snapshot-failures: 1 → 1；snapshot-starts: 1 → 1；no-snapshot-applied: 0 → 0 | passed |
| P7-pinned-duplicate-cache-reuse | distinct-item-for-pinned-duplicate: true → true；metadata-for-new-item: 1 → 1；cache-hit-applied: 1 → 1；no-extra-live-loads: 1 → 1 | passed |
| P8-event-payload-safety | no-url-tokens-in-events: 0 → 0 | passed |

P6 本次真实 provider 返回 metadata success-empty，真实 WebKit snapshot failure 为 1 次，重新打开/选择不重试、不 apply。metadata failure 零 fallback 分支由下方 deterministic test 补齐，不把本次 P6 声称为真实 metadata failure。P4 的真实取消事件用于验证 supersession；含 cleanup 的并发上限由可控 seam 断言证明。

## 8.2 必需确定性补充

下表全部使用 targeted 命令；result 均为 passed，证据为 `targeted.log` 和 `test-assertions.json`，源码身份同上。

| 必需行为 | 测试名称 | 功能断言 |
| --- | --- | --- |
| closed panel 零 fallback；metadata image/icon/empty/failure | `closedPanelAddURLMetadataTitleOnlyNeverSnapshots`, `metadataImageAppliesAndPanelOpenNeverSnapshots`, `extractPreviewPrefersImageOverIconAndBoundsTo640px`, `extractPreviewFallsBackToIconWhenImageMissing`, `extractPreviewAllowsEmptySuccess`, `metadataFailureNoFallbackAndNoRetryOnReselect` | title 正常保存；snapshot 次数零；image/icon 顺序与尺寸；failure 重选无请求 |
| 仅 visible selected eligible URL；pending race | `fallbackRunsForSelectedVisibleEligibleURLOnly`, `searchFilteringCancelsFilteredOutFallback`, `pinboardFilterAndAssignmentCancelIneligibleFallback`, `pendingMetadataDoesNotAuthorizeFallbackUntilNoImageOutcome`, `emptyFilteredSelectionAuthorizesNoFallback` | 可见选择和 metadata outcome 驱动请求，filter/pinboard/空选择撤销资格 |
| cleanup 并发上限；A→B→A / close→open | `cleanupHandoffSkipsSupersededTargets`, `roundTripDiscardsOldResultAndWaitsForCleanup(closePanel:)`, `closeCancelsFallbackAndReopenRetries`, `lateResultAfterCloseIsDiscarded` | peakConcurrency=1；清理期间跳过 B；旧图不 apply/cache/save；取消不写失败缓存 |
| 删除/clear/eviction/deinit | `removalCancelsPendingSnapshotWithoutSavingLateImage(operation:)`, `deleteCancelsPendingMetadataAndDiscardsLateResult`, `clearHistoryRetainsPinnedWorkAndCleansRemoved`, `evictedInsertedItemDoesNotStartMetadata`, `releasingStoreCancelsPendingWorkWithoutSaving` | 实际移除项全部 work 清理；迟到不恢复/save；Store pending 时可释放 |
| bounded cache/query/TTL | `positiveCacheHitDoesNotStartLoaderAndQueryDoesNotShare`, `positiveCacheEvictsEarliestInsertedBeyond64`, `snapshotFailureSuppressesRetryUntilTTLExpiry`, `negativeCacheStaysBoundedAt64` | 完整 URL key；64 项容量；299 秒不请求、300 秒重选可重试；受控 metadata success-no-image 前置条件，无实际五分钟等待 |
| metadata callback/Progress cancellation | `cancelledMetadataRequestDoesNotStartProvider`, `cancellationOfPendingItemProviderEndsWithoutCallback`, `cancelBeforeRegisterPreventsStartAndThrowsCancellation`, `lateCallbackAfterCancelIsIgnored`, `doubleCancelResumesWaiterExactlyOnce`, `adoptProgressAfterCancelCancelsProgressImmediately`, `synchronousCallbackDuringStartCompletes` | 注册前/回调迟到/永不回调/Progress race 结束有界且 exactly once |
| WebKit lifecycle/deadlines/adapter | `earlyDidFinishSubmitsSnapshotImmediately`, `navigationDeadlineAttemptsSnapshotOnceWithoutDidFinish`, `missingSnapshotCallbackFailsAtSnapshotDeadline`, `cancelBeforeSnapshotSubmissionSendsNoSnapshot`, `cancelAfterSubmissionDiscardsCallback`, `duplicateSnapshotCallbacksKeepFirstResult`, `productionAdapterCancellationReleasesRealWebView`, `productionAdapterRunsAboutBlankLifecycleWithRealWebKit` | 手动 deadlines 验证 3+2 秒阶段；最多一次 snapshot/resume；stopLoading/detach/release；production adapter 接入真实 WebKit，about:blank 不作外部网页证据 |
| 有效结果沿原 persistence path；空/stale 零额外保存 | `orchestratedPreviewCompletionDoesNotAddExtraSaves`, `rapidMutationsAndPreviewArrivalCommitOnlyLatestSnapshot`, `previewSavedToDiskRestoresIntoNewStoreAndRetainsURLBehavior` | recorder 拒绝 removed/empty 额外保存；latest-state generation；实际 manifest/blob 恢复 |

## 8.3 兼容性功能：逐项映射

以下全部使用 targeted 命令、相同源码身份；result 均为 passed。tests 的逐断言记录在 `test-assertions.json`，结果在 `targeted.log`；完整 suite 的复验见 `verify-all.log`。

| 项目 | 测试名称 / caller chain | 关键功能断言与证据 |
| --- | --- | --- |
| URL title/image 数据 | `previewSavedToDiskRestoresIntoNewStoreAndRetainsURLBehavior`；metadata extraction tests | 恢复的 linkTitle 正确；PNG bytes 等于保存值，可解码为 32×32；original ID/kind/URL/source 保留 |
| Search | `previewSavedToDiskRestoresIntoNewStoreAndRetainsURLBehavior`, `searchFilteringCancelsFilteredOutFallback` | 按 preview title 查到相同 URL ID；search 排除项不 fallback |
| Pin / Pinboard | `previewSavedToDiskRestoresIntoNewStoreAndRetainsURLBehavior`, `pinboardFilterAndAssignmentCancelIneligibleFallback` | 保存 pin/Work 后恢复；Pinned/Work 过滤都返回该 URL；assignment/filter 控制 fallback |
| 删除 | `previewSavedToDiskRestoresIntoNewStoreAndRetainsURLBehavior`, `removalCancelsPendingSnapshotWithoutSavingLateImage(operation:)` | remove 后 items/filteredItems 为空、selectedID=nil；迟到媒体无 save，clear/eviction 参数场景也通过 |
| 持久化后新 Store 恢复 | `previewSavedToDiskRestoresIntoNewStoreAndRetainsURLBehavior` | flush 成功；临时 manifest 实际存在；新 persistence reader load 后构造新 Store；从 disk/blob 恢复 title/image/pin/board；已有图片没有 metadata task/active fallback。负向对照见对应 log |
| pasteboard restore | `previewSavedToDiskRestoresIntoNewStoreAndRetainsURLBehavior`, `restoresSupportedItemsAndRejectsInvalidInputs`, `invalidRestoreDoesNotAdvancePasteboardMonitor` | named pasteboard 恢复完整 URL 而非 preview title/image；无效内容不清空已有内容或推进 capture 状态 |
| paste target 选择 | `excludesCopythatAndSystemProcessesButAcceptsUserApps`, `missingTargetIsReportedAfterRestore` | 排除自身/system processes；有效用户 app 可接受；缺 target 不发事件 |
| paste 权限/发送决策 | `restoreFailureTakesPrecedence`, `accessibilityFailureIsReportedBeforeSendingPaste`, `pasteIsSentOnlyWhenEveryPreconditionPasses`；`ClipboardPastePerformerTests` | restore/target/permission 前置决策；mocked send 仅在前提全通过时发生；activation/timeout 竞争最多发送一次、失败的新请求淘汰旧请求。没有向外部文档真实发送 paste |
| panel show/close | AppDelegate → `PanelWindowController.show/close` → `panelDidOpen/Close`；`realPanelControllerShowCloseUpdatesStoreVisibility`；Store cancellation tests | 生产 show 顺序 select → orderFront → panelDidOpen；close 先 panelDidClose 再 orderOut；toggle、panel onClose、view onClose 和成功 paste close 均沿同一 close。真实 controller/window visibility 功能测试 + window-server smoke + Store 取消测试共同支持，source 字符串检查不单独判 passed |
| display frame 逻辑 | `framesStayWithinVisibleBounds` | 合成 display frame 在 visible bounds 内；不代表物理多屏测试 |

## 隔离保护与覆盖边界

`private-integrity.json`：私人 `Library/Application Support/Copythat` 文件树、应用 preferences plist 及 defaults export 的 SHA-256 在 final acceptance 前后完全一致。仅记录路径/长度/digest，没有保存私人 clipboard payload。baseline 在首次隔离 support tests 后、live/full gate 前取得；不会将这次比较扩展为整个会话的历史取证。源码/入口检查确认所有本轮执行写入均采用隔离依赖。TCC 未重置。

| 可选真实桌面项目 | 状态 | 自动化证据的限制 |
| --- | --- | --- |
| 真实 card 像素/视觉表现 | not-covered | 只检查数据、PNG 可解码和窗口出现 |
| 外部文档发送 paste | not-covered | 只运行 named pasteboard restore 和 mock send/target 决策 |
| 系统 Accessibility granted/denied 切换 | not-covered | 注入权限决策不代表系统 TCC 授权实测 |
| 全局快捷键真实投递 | not-covered | isolated app smoke 禁止注册；unit tests 仅覆盖内部逻辑 |
| 物理多显示器 | not-covered | 只有合成 frame 测试与当前桌面的 panel smoke |

必需项没有 failed/blocked 或未补齐的覆盖缺口。以上结论仅用于 tasks 8.2/8.3；保留历史 Stage 3 报告及其当时结论，不以这份验收报告代替新的独立审计或发布授权。
