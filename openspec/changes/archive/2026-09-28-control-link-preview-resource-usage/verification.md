归档证据说明：`evidence/` 下 9 个编译器/测试日志以无损 `.log.gz` 发布，报告中对应 `.log` 名称在持久证据目录解析为追加 `.gz` 的文件。`evidence/log-transport.json` 记录解压前原始 byte count 与 SHA-256；压缩后逐项解压核验一致。原始运行日志仍保留在 `.build`，此调整不改变测试结果或 source identity。

# Current Stage 3 independent review — 2026-09-28

**通过**。Workflow profile: **high-risk**；本轮独立执行 Stage 3，未参与本轮之前的 Apply。当前 proposal/design/tasks/specs 的自动化验收边界为准；下方历史 Stage 3 的 computer-use 阻塞已被后续明确调整的验收标准替代。当前 24/24 tasks 有源码、测试和有效验证证据支持，可以进入另行授权的 Stage 4。

本轮重新读取全部 Change artifacts、相关 tracked diff 和新增实现/测试/runner、生产 caller chain 与完整 gate 配置，没有用任务勾选或旧审查结论代替源码审查。未发现新的 Blocker、High 或必须修复的 Medium；本轮没有修改业务代码、测试或工具，仅追加当前审查记录和证据。没有 archive、commit、push 或操作私人 history/TCC。

## Current evidence identity

- Base HEAD：`35a1b152a44a469df6f130fabdebe082b3f35cc3`，当前未提交工作树。
- 独立逐文件重算 `evidence/2026-09-28-functional-acceptance/source-identity.json` 中全部 **120** 个文件的 SHA-256，零 mismatch；重新枚举 Sources、Tests、script、Package.swift、Copythat.entitlements，零新增遗漏、零缺失。HEAD 相同。
- 对应 source fingerprint：`6df3cf16f7c8553f30ae99b36e4fad8bb0ddf0c14fb10c6f087817a1afc37139`。记录环境为 macOS 27.0 / arm64、Apple Swift 6.4、Xcode `/Applications/Xcode.app/Contents/Developer`。
- 审查了 `.build/preview-functional-acceptance/verify-all.log` 的实际测试、build、packaging/icons、source timing、隔离 startup/portable/panel、bundle/signature 输出，以及 `verify-all.exit=0`；代码/测试/工具无漂移，按 skill 复用该完整 gate，不重复运行。
- 审查了同身份真实 provider runner 的原始 log、exit=0 与持久 `report.json`：P1–P8 全部 passed，所有 assertion 为 true。本轮复用此记录，未重新运行 live runner。P6 实际是 metadata empty success 后 snapshot failure，不声称真实 LP metadata failure；后者由确定性测试补齐。
- 本轮额外运行 targeted tests 与 build；新证据见 `evidence/2026-09-28-stage3/identity-check.json`、`targeted.log`。已有完整 gate 和 live 原始日志仍在 `.build/preview-functional-acceptance/`；持久功能验收结果与详细映射在 [functional-acceptance.md](functional-acceptance.md)。

## Requirement → design → tasks → implementation → tests → evidence

| Requirement | Design / tasks | 当前实现与独立判断 | 测试 / 有效证据 |
| --- | --- | --- | --- |
| eager metadata 与零 closed-panel fallback | §1/§6；1.1–1.2、3.3、7.1 | `fetchMetadata` 不创建 snapshot WebView；image→icon；success 空字段独立于 failure/cancel；metadata merge 保留已有 image，无变化不 save | `closedPanelAddURLMetadataTitleOnlyNeverSnapshots`、metadata extraction/bridge/pending/failure tests；fresh targeted；真实 P1/P2/P6 |
| visible selected eligible URL；restored title 不授权 | §2；2.1–2.3 | `visibleSelectedLinkURL` 使用 panelVisible、显式 selectedID、filteredItems、URL kind、image nil 与 session outcome；restored lazy metadata，无批量启动；add/filter/pin mutation 完成后 reconcile | Store orchestration/cache tests；pending→image/no-image；restored title/image tests；fresh targeted；真实 P3 |
| single fallback 包含 cleanup；取消/removal/deinit | §3/§6；3.1–3.4、6.1–6.3 | cancelled active slot 保留至 loader 返回，之后重读最新 selection；requestID 防止旧 completion 清新任务；weak Store + registry deinit cancel；实际 removed IDs 清理 | cleanup A→B→C、round-trip A→B→A/close→open、delete/partial/full clear/eviction、pending weak Store tests；fresh targeted；真实 P4/P5 |
| temporary browser 有界 rendering | §4；4.1–4.2、7.2 | MainActor controller 在 load/snapshot 前检查 cancel；first wake + terminalWake；3s navigation/2s snapshot deadline；finish 统一 stop/detach/release；生产 driver `.nonPersistent()` | controlled deadline、failure/termination、取消前后、重复/迟到 callback tests；真实 about:blank adapter/release tests；fresh targeted；真实 P3–P5 |
| session success cache 与 failure TTL | §5；5.1–5.2 | 完整 absoluteString key；positive FIFO≤64、negative earliest-expiry≤64；uptime 300s TTL；cancel/stale 不写 cache，无后台 retry timer | query identity、65 entries、299/300s current-ID reselect、取消 round-trip/cache assertions；fresh targeted；真实 P7 |
| 仅 current result apply；兼容 save path | §6；3.5、7.3 | metadata token/URL/item/kind/cancel guard；snapshot/cache 另验证 visibility/selection/eligibility/image nil；保留当前 title/source/pin/board/restorable URL；继续 coordinator/manifest/blob path | replacement metadata、image-during-pending、stale save/cache、empty metadata、latest-state persistence、实际 disk restore tests；fresh targeted + 有效 full gate |
| tasks 8.2/8.3 自动化功能与 caller chain | §8；8.1–8.4 | View selection/keyboard → Store；toggle/Escape/view close/成功 paste → controller.close → panelDidClose → orderOut；show 在 select/orderFront 后 panelDidOpen。隔离 AppModel/runner/verify PID 保留用户数据 | fresh real controller show/close、Search/Pinboard/delete/PNG/disk restore/named pasteboard restore、paste target/permission decision tests；有效 provider runner + isolated panel smoke；功能报告逐项映射 |

URL/kind 字段为 immutable；生产 caller 没有原地替换 URL 的入口，completion 的 URL/kind guard 经源码核对。同 ID 删除后重新注册通过 request token regression 覆盖。生产 LP start/cancel 在 MainActor；无 callback 的本地 exactly-once 由 bridge 与真实 pending NSItemProvider 测试支持，不扩展成 Apple 内部资源立即释放保证。WebKit deadline 限制 application-owned work，不能保证共享系统进程同步退出。

## Findings / accepted limitations

- 无新的阻塞缺陷；历史 Stage 3 修复已在当前源码中存在，并由本轮独立读取及定向复验确认。未顺带清理已有机械移位、Pinboard relocation 或变量改名。
- 非阻塞 Low：`ClipboardDiagnostics.emitLinkPreview` 未使用；cache tests 有 duplicate assertion/unused local；`extractPreviewPrefersImageOverIconAndBoundsTo640px` 使用 32px 主图片，本身不能单独证明缩小大图，尺寸处理由复用 `pngData(maxPixel: 640)` 的源码与既有 storage optimization bounds 测试共同支持。
- 真实 card pixels、向外部文档发送 paste、系统 Accessibility granted/denied 切换、全局快捷键投递、物理多显示器均 **not-covered**，按当前 §8 为可选项。权限决策 mock、合成 display frame、窗口 smoke 与 in-process provider runner 不冒充这些实测。
- 支持验证隔离的 DEBUG 启动分支只用于明确配置的 verify root/suite/named pasteboard；release 与正常启动保留生产路径。verify modes 拒绝 release，隔离 smoke 不证明全局快捷键或 event tap 实测。无 dependency/schema/settings 契约变化。

## Commands and results

| 命令 | 本轮执行 / 复用 | 结果 |
| --- | --- | --- |
| `swift test -Xswiftc -F -Xswiftc /Applications/Xcode.app/Contents/Developer/Library/Frameworks --filter 'LinkPreview\|StorePanelWiring\|ClipboardStorePersistence\|ClipboardStorePasteboard\|PasteDecision\|ClipboardPastePerformer\|PasteTarget\|PanelFrame'` | 本轮执行 | exit 0；**96 tests / 15 suites passed** |
| `swift build` | 本轮执行 | exit 0；Build complete |
| `openspec validate control-link-preview-resource-usage --strict` | 本轮执行 | valid |
| `openspec validate --all --strict` | 本轮执行 | **8 passed / 0 failed**；仅 long-text INFO |
| `openspec doctor --json` | 本轮执行 | healthy=true，status=[] |
| `git diff --check` | 本轮执行 | exit 0 |
| `PATH=/opt/homebrew/Caskroom/miniconda/base/bin:$PATH ./script/verify_all.sh` | 复用 2026-09-28 同一 source identity 的完整日志与 exit | exit 0；**241 tests / 40 suites passed**，全部 gate stages 通过 |
| `bash script/verify/preview_live.sh run --port 18765 --output .build/preview-functional-acceptance` | 复用 2026-09-28 同一 source identity 的 log/report/exit | exit 0；**8/8 scenarios passed** |

当前 `openspec --help` 未提供 `verify`；未运行或声称通过该命令。本轮仅文档/证据修改，不使 complete-gate identity 失效。**Stage 3 通过，建议进入 Stage 4；归档、commit 和 push 尚未执行。**

---

# Current tasks 8.2 / 8.3 execution — 2026-09-28

**8.2 passed；8.3 passed**。本轮补齐磁盘恢复断言、真实 panel show/close 功能测试及 gate 运行隔离后执行验收；必需项全部通过再勾选。完整逐项源码身份、命令、断言、结果、证据路径和 not-covered 边界见 [functional-acceptance.md](functional-acceptance.md)。这是当前功能验收记录，以下标准调整、Stage 3 与 Historical Apply 为各自当时的历史记录，不能覆盖本轮结论。本轮没有重新执行完整 Stage 3，也未 archive、commit 或 push。

---

# Acceptance criteria update — 2026-09-28

按用户要求，tasks 8.2/8.3 已改为当前环境可执行的自动化功能验收；同步 proposal/design/tasks 的完成标准。下方 Stage 3、computer-use prerequisite 与 Historical Apply 记录保留为历史证据，其中独立测试账号、computer use、系统权限切换及第二台显示器的强制前提已被本次标准替代，不再作为 8.2/8.3 的阻塞条件。

- 8.2：本地 fixture + 生产 Store + 真实 LPMetadataProvider/WebKit runner；取消、并发、timeout、迟到结果、negative cache/TTL 等分支由确定性测试补齐。入口：`bash script/verify/preview_live.sh run --port 18765 --output .build/preview-functional-acceptance`。
- 8.3：隔离的 title/image、Search、Pin/Pinboard、删除、磁盘保存后新 Store 恢复、pasteboard restore、paste 目标/权限决策测试，以及 panel 接线检查与现有 panel smoke。逐项映射行为断言；不能仅凭旧全量测试通过就认定这些功能都已覆盖。
- 真实 UI pixels、外部文档 paste、系统 Accessibility 切换、全局快捷键投递和物理多屏另列可选覆盖；缺条件标记 not-covered，不阻塞任务，也不冒充实测。

本次只调整验收 artifacts，未运行上述功能验收，8.2/8.3 保持未勾选。后续按新标准核对当前源码与既有证据，补齐必需断言并运行相应验证后再勾选；历史 gate 需要确认源码未漂移才能引用。本次调整没有重新判定 Stage 3 通过或宣布 Change 实施完成。

---

# Stage 3 independent review — 2026-09-28

## Verdict

**不通过（required acceptance evidence 未齐）**。Workflow profile: high-risk；本轮只执行 Stage 3，未执行 Apply、archive、commit 或 push。独立读取当前 artifacts、完整相关 diff、新增文件、caller chain、tests 与 gate configuration；未将 Apply 的任务勾选或旧 green run 视为证明。

已复现并修复本 Change 内的实际缺陷，当前自动化证据通过，无已知未解决 High 产品缺陷。验收仍因 tasks 8.2、8.3 缺少 computer use 的真实 app UI 证据而未齐，两项保持未勾选；OpenSpec 的 planning `isComplete` 不代表 implementation acceptance 完成。任务实际为 **22/24**，不是旧记录中的 20/24。

## Validation identity

- Base HEAD: `35a1b152a44a469df6f130fabdebe082b3f35cc3`，带未提交的当前工作树。
- macOS 27.0 (26A428), arm64；Xcode `/Applications/Xcode.app/Contents/Developer`；Apple Swift 6.4；Swift Testing 2084。
- Sources、Tests、script 与 Package.swift 的逐文件 SHA-256 manifest：`.build/stage3-preview-evidence/source-manifest.json`。
- Manifest timestamp (UTC): `2026-09-28T07:53:56.636062+00:00`；complete gate 完成于 `2026-09-28T07:54:15.177627+00:00`。gate 后逐文件重新校验，无 code/test/tooling 漂移。
- Manifest aggregate SHA-256: `d42dc1913672416794e2840df000888f2a24f18373882b2704c75ae7ee32ba16`。
- Python gate 使用 `/opt/homebrew/Caskroom/miniconda/base/bin/python3`（Pillow 可用），没有跳过 icon checks。系统 `/usr/bin/python3` 缺少 PIL。
- 最后一次 code/test/tooling 修改后重新运行 complete gate；下面的旧 Apply 记录不是当前 gate evidence。

## Requirement → design → implementation → tests → evidence

| Requirement | Design / tasks | Current implementation | Tests / fresh evidence |
| --- | --- | --- | --- |
| eager metadata，closed panel 零 browser fallback，image→icon，允许 empty success | §1/§6；1.1–1.2、3.3、7.1 | `LinkPreviewFetcher.fetchMetadata/extractPreview` 与 Store metadata completion 独立于 WebKit；request token + URL guard；合并已有字段，无变化不 save | `LinkPreviewFetcherMetadataTests`、callback bridge tests、closed-panel/search/image/pending/empty/failure tests；真实 NSItemProvider pending cancellation；live P1/P2/P6 |
| visible selected eligible URL；restored title 不授权，已有图片不重取 | §2；2.1–2.3 | `PanelWindowController.show/close` → `panelDidOpen/Close`；`visibleSelectedLinkURL` + current-session outcome；同步 mutation 后 reconcile | Store orchestration/cache/panel wiring tests；Pinboard assignment filtering；live P3；窗口接线另由 caller-chain inspection 支持，source-text test 不是 UI 操作证据 |
| single fallback，含 cleanup；latest-wins；close/selection/removal/deinit cancellation | §3/§6；3.1–3.4、6.1–6.3 | active request 保留至 loader 结束；request token 与 explicit cancelled flag；registry deinit cancel；await 不强持有 Store | A→B→C cleanup gate、A→B→A/close→open 在旧 callback 仍未结束时的 round-trip、weak Store；delete/full/partial clear/actual eviction；live P4/P5 |
| navigation 3s + snapshot 2s；early finish；fail/termination；non-persistent WebKit | §4；4.1–4.2、7.2 | `LinkPreviewSnapshotController` load/snapshot 前取消检查、first wake/terminal failure、phase-bound deadlines、统一 detach；生产 driver `.nonPersistent()` | controlled deadline 测试无 50ms sleep；早完成、缺失/重复 callback、failure→finish、cancel→finish、process termination；真实 about:blank 成功与取消后 release；live WebKit P3–P5 |
| success cache≤64；完整 URL/query；negative TTL300s≤64；cancel/stale 不缓存 | §5；5.1–5.2 | URL.absoluteString cache，FIFO positive、earliest-expiry negative，uptime TTL，无后台 retry timer | `StoreLinkPreviewCacheTests` 65-entry/query/299–300s/current-ID reselect；round-trip/removal 迟到 cache 增量零；live P6/P7 |
| current identity/item/URL/visibility/selection/image guard；原 save/media path | §6；3.5、7.3 | metadata requestID guard；fallback token + cancelled + current target guards；失败也先验证 target；保留 title/image/source/pin/URL，继续原 persistence coordinator | stale save/cache counts、replacement metadata token、等待期间 image 已补入；现有与新增 persistence tests、全量 blob/coordinator suite |

URL/kind matching 另经完成路径源码审查；ClipboardItem URL/kind 为 immutable，当前生产 caller 没有原地改写 URL 的入口。本轮不新增这种业务能力。metadata LP start/cancel 主线程接线经源码与真实 localhost provider 流程确认；无 callback 的 active LPMetadataProvider 本身没有可注入 Apple cancellation seam，exactly-once 无 callback 行为由 callback bridge 单测支持，NSItemProvider 另有真实 adapter test；不扩大为 Apple 内部资源立即释放的保证。

## Findings and repairs

| Severity | Concrete finding | Smallest repair / regression evidence |
| --- | --- | --- |
| High | 已取消的 controller 仍 load；didFinish 唤醒后 cancel 仍提交 takeSnapshot | `run`/`runSnapshotPhase` 直接检查 Task cancellation；新增两个 deterministic tests 在修复前失败、修复后通过 |
| High | removed item 使用同 ID 重新注册 metadata 后，旧 completion 无 request token，清空新 task/outcome | metadata 独立 requestID，registry 用 requestID，completion 只清自己的状态；replacement regression 修复前失败、修复后通过 |
| High | metadata title-only completion 将等待期间补上的 image 清空 | merge 保留已有 image，outcome 基于最终图片，无实际变化不 save；image preservation regression 修复前失败、修复后通过 |
| Medium | selectedID 未变时 refresh 返回，已有图/过滤刷新没有撤销 fallback | retained selection 也 reconcile，mutations 仍统一 defer；image-during-fallback 与 Pinboard tests |
| Medium | navigation terminal failure 可以被其他 buffered wake 覆盖；跨 phase deadline/callback 可迟到 | first wake 与 terminal failure 分开；phase-bound deadline；取消 timer 后不发假取消；failure-before-submit、duplicate callbacks、controlled deadline tests |
| Medium | metadata extraction 取消后可继续下一 provider 阶段；LP callback 强持有 provider 在不回调时有循环持有风险 | extraction 每阶段 checkCancellation；LP creation/start/cancel 统一 MainActor，cancel task 持有 provider 至 cancel 返回，callback 不再捕获 provider；cancelled extraction/metadata、real NSItemProvider test 与 live provider run |
| Medium | fallback nil/error 先判 failure、未先判当前 target；取消只依赖 Task flag | target guards 优先于 failure，显式检查 active.isCancelled，stale/cancel 不写 negative entry |
| Medium (evidence) | live P6 强制 metadata failure 后 fallback；部分 blocked 仍 exit0；deadline tests 使用真实50ms | runner 按 metadata failure/empty outcome 分支判定；任一 blocked 返回2；unit deadline 用可控 gate；真实 runner 与单测重跑 |

最初新增的4个回归测试：4 tests failed / 6 issues（见 `regression-before.log`），证明前3项行为缺陷；修复后4 tests passed。其余新增测试加强 cancellation adapter、cleanup、cache、filter 与 deadline 边界。

## Fresh commands and results

| Command | Result |
| --- | --- |
| `swift test -Xswiftc -F -Xswiftc /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks --filter 'LinkPreview&#124;StorePanelWiring'` | **62 tests / 9 suites passed**（包含名称命中 LinkPreview 的 storage optimization test；table-driven arguments 另实际执行各 case） |
| `PATH="/opt/homebrew/Caskroom/miniconda/base/bin:$PATH" ./script/verify_all.sh` | **exit 0；239 tests / 40 suites passed**；packaging、swift build、source resolution、timing analyzer、icons、app launch/portable/panel、bundle、codesign 均通过 |
| `swift build` | complete gate 内通过；另有单独 build log |
| `bash script/verify/preview_live.sh self-test` | driver compilation passed |
| `bash script/verify/preview_live.sh run --port 18765 --output .build/stage3-preview-live` | **exit 0；P1–P8 全部 passed**（真实 LPMetadataProvider/WebKit，隔离 localhost） |
| `openspec validate control-link-preview-resource-usage --strict` | valid |
| `openspec validate --all --strict` | 8 passed / 0 failed（仅已有 spec long-text INFO） |
| `openspec doctor --json` | root healthy=true，status=[] |
| `git diff --check` | passed |

`openspec --help` 未提供 `verify`；没有运行或声称通过该命令。未发现项目独立 lint gate，旧报告的“lint 规则全部满足”不作为本轮验证证据。既有测试 NSLock async-context/unused-value compiler warnings 和系统 WebKit sandbox diagnostic 不影响本次 exit0；本轮引入的 deadline seam Sendable warning 已通过 MainActor isolation 修正。

完整日志保存在 `.build/stage3-preview-evidence/`；真实 provider/WebKit report 在 `.build/stage3-preview-live/report.json`。该 live host 只驱动生产 Store/Fetchers，使用 named pasteboard、独立 defaults、内存 persistence；**没有显示实际 PanelWindowController 窗口、没有验证 UI pixels**。report 中 `automated-real-desktop` 标签不能升级为 computer use 的真实 app UI、physical HID、TCC 或实际多屏证据。完整项目 gate 另按既有脚本启动真实 app，panel smoke 仅证明进程/窗口位置和打包，不是 8.3。

## Scope and remaining acceptance

本轮修复文件：

- `Sources/Copythat/Stores/ClipboardStore.swift`、`ClipboardStore+LinkPreview.swift`。
- `Sources/Copythat/Support/LinkPreviewFetcher.swift`、`LinkPreviewSnapshotController.swift`。
- `Tests/CopythatTests/LinkPreviewFetcherMetadataTests.swift`、`LinkPreviewSnapshotControllerTests.swift`、`StoreLinkPreviewCancellationTests.swift`、`StoreLinkPreviewRemovalTests.swift`、`StoreLinkPreviewOrchestrationTests.swift`。
- `script/verify/preview_live_driver.swift`、`preview_live_scenarios.swift` 与本记录。

保留进入任务时已有的其他改动，包括 AppModel 的 DEBUG pasteboard injection、PanelWindowController 的机械变量改名、Pinboard relocation、diagnostics/test/tooling 文件；本轮没有扩展 UI、dependencies、schema、history policy 或 paste semantics，也未清理未关联的工作。

非阻塞 Low：既有 `emitLinkPreview` unused helper、cache test duplicate assertion/unused local、Store 大量机械移位和 AppModel DEBUG isolation branch 不能替代需求证据，建议 delivery 时核对 Change 的精确文件范围，不在 Stage3 顺带重构。

**当前未完成项：8.2/8.3 的 computer use 真实 app 验收。** 用户已授权以 computer use 替代真人操作，并已同步 proposal/design/tasks 的完成标准。现有 localhost automated P1–P8 提供生产 Store/providers 的补充证据，但没有通过 computer use 操作实际 app 窗口；URL card/Search/Paste/Pinboard/delete/relaunch、Accessibility、shortcut 与实际多显示器等 UI 场景仍待执行和记录。两项保持未勾选，不再要求人工验收；Stage3 尚不能据此判通过，亦未执行归档。

本次仅修改验收 artifacts：`proposal.md`、`design.md`、`tasks.md`、本记录。当前工具目录提供 macOS desktop computer use 的入口，尚未进行 UI 场景操作，因此这不是 computer use 验收通过报告。执行前仍须确认真实 app 数据隔离；不把现有 DEBUG named-pasteboard branch 当作 history 隔离保证。此前 code/test/tooling fingerprint 与完整 gate 可在确认无漂移后沿用，无需因文档修改重跑完整项目 suite。下方 Historical Apply record 的人工验收措辞仅保留历史，不再约束当前 8.2/8.3。

---

## Historical Apply record (superseded)

下方原文保留供追溯。它的 green runs、coverage、“无未解决缺陷”和完成数量仅代表旧 Apply 报告；独立 Stage3 已发现上述反例，以本节以上的当前源码与验证证据为准。

# Verification record — control-link-preview-resource-usage

## 8.1 Automated gates（已执行，2026-09-28，本机 macOS 27.0 / arm64，Xcode 工具链 swift 6.4，Swift Testing 2084）

| 命令 | 结果 |
| --- | --- |
| `swift build` | `Build complete!` |
| `swift test`（全量） | `✔ Test run with 226 tests in 40 suites passed after 1.760 seconds` |
| `swift test --filter "LinkPreview&#124;StoreLinkPreview&#124;StorePanelWiring"`（targeted preview 矩阵） | `✔ Test run with 49 tests in 9 suites passed` |
| `openspec validate control-link-preview-resource-usage --strict` | `Change 'control-link-preview-resource-usage' is valid` |
| `./script/verify_all.sh` | exit 0（packaging、build、226 tests、source_resolution 二进制、source_attribution_timing、icons、`build_and_run.sh --verify/--verify-portable/--verify-panel`、bundle plist 断言、codesign 全部通过；panel verify 输出 `panel ok` / `bundle ok local.copythat.clipboard`） |

以上均为本轮实际运行记录，无跳过或沿用旧结果。

## 8.2 人工 URL 验收 — 未执行（保持未勾选）

无法在本环境中以人工方式操作 macOS 面板、复制真实网页 URL 并观察 fallback 创建次数/时点。按要求：

- `openspec/changes/.../tasks.md` 中 8.2 保持未勾选。
- 自动化替代证据（不能替代人工验收，仅供回归参考）：
  - `StoreLinkPreviewOrchestrationTests`/`StoreLinkPreviewCacheTests` 覆盖 closed-panel add URL、metadata image/empty/failure、lazy restore、cache/TTL 等编排行为，均断言 loader 次数与 save 增量。
  - 快速左右切、close 停止应用持有 work、reopen 按 cache/TTL 重试由 `StoreLinkPreviewCancellationTests` 的确定性事件驱动测试覆盖。
  - 未见在日志中记录私人完整 URL 或 clipboard payload；诊断仅记录 itemID/kind/来源等元数据。

## 8.3 人工回归 — 未执行（保持未勾选）

URL card/title/image 呈现、Search、Paste、Pin/Pinboard、重启 persistence、Accessibility、快捷键、多显示器等需要真人操作 macOS 会话。任务保持未勾选；`script/verify_all.sh` 中的 `--verify-panel` 自动化证据仅覆盖 panel 打包与定位。

## 8.4 对抗性 review（已执行）

审查范围：最终 source/caller chain（`LinkPreviewFetcher` → `ClipboardStore(+LinkPreview)` → `LinkPreviewSnapshotController` → `PanelWindowController`）与全部新增/扩展测试。

发现并已修复的真实缺陷：

1. **LPMetadataProvider 内部 teardown 崩溃（EXC_BAD_ACCESS / SIGSEGV in `_finishedPostProcessingWithError:`）**
   - 触发条件：并行测试进程中大量真实 provider 在 store 释放时被 `provider.cancel()` 中断（Apple 内部竞态）。最小复现未触发，但全量并行测试稳定复现。
   - 修复：callback 强持有 provider（存活到 terminal state），并将 `provider.cancel()` 串行到主线程执行；bridge 的本地等待者仍在取消路径同步结束。修复后全量 226 测试多次运行无崩溃。
2. **snapshot 阶段 deadline sleep 被取消时向前推进的等待者注入伪 `.cancelled`**（阶段切换的正常 `cancelDeadline()` 也会触发 sleep 取消）。修复：deadline task 自身取消只静默返回；请求取消由等待者自身的 cancellation handler 负责。修复后 Case 11 各顺序矩阵通过。
3. **测试基建缺陷（非产品代码）**：共享 `LinkPreviewGate` 的 `cancellationObserved` 会让后续等待者立即返回，导致早期编排测试断言失真——已改为每 URL 独立 gate 并修正 save/handled 计数基线。

针对性复验：上述修复后重新运行全量 `swift test`（226/226）与 `./script/verify_all.sh`（exit 0），均通过。

其余检查项（无未解决缺陷）：

- stale result：metadata/fallback 完成路径均校验 item 存在、kind、完整 URL、token/任务标识、cancellation；fallback 另校验 panelVisible、selectedID 匹配、filteredItems 成员、eligibility、image nil。测试覆盖 stale save/cache 增量为零。
- A→B→A / close→open / cleanup overlap：slot 只由自身任务在 token 匹配时清理，重启决策重读当前 UI 状态；Cases 4/5 覆盖。
- double resume：callback bridge 与 controller waiter 均 exactly-once；bridge 与 controller 各自有 cancel-before-register / sync-callback / double-event 测试。
- timer/task/WebView leak：deadline task 在阶段切换与 finish 时取消并置 nil；`driver.detach()` 解绑 delegate 并释放应用持有的 WKWebView；registry 在完成时移除条目；deinit `cancelAll()`；weak Store 释放测试验证任务链不持有 Store。
- metadata cancellation：cancel-before-register、同步 callback、取消后迟到回调、Progress 注册竞态均有独立测试。
- cache poisoning / 额外保存：正缓存只写验证通过的结果；负缓存只写真实 failure（cancel/stale 不写）；空 metadata 与 removed-item 迟到完成不产生保存（持久化测试断言）。
- 无业务范围外修改：clipboard capture、source attribution、paste flow、history limit、dedup 语义、persistence schema、用户设置均未改动；无新依赖。
- 代码质量 gate：本仓库 lint 规则（file ≤1000 行、类型体 ≤350 行、函数体 ≤50 行等）在新触达文件上全部满足；预置代码中的既有 lint 项（如 `ClipboardStorePasteboardTests` 的 3 元组）非本次引入，未动。

## Definition of Done 状态

- 实现任务与 acceptance cases：有当前源码/测试证据（20/24 勾选）。
- automated gates：全部通过（见上）。
- 8.2/8.3：无法执行的人工验收，保持未勾选并记录限制——**Change 不标记为“实施完成”之外的人工证据状态**。
- 8.4：无未解决真实缺陷。

## Apply attempt — 2026-09-28 (computer-use prerequisites)

本轮继续 Apply 时没有操作桌面 UI，也没有改变系统剪贴板或历史数据。当前确认的环境条件：

- 当前用户为 `kaden`；已有进程 PID `55941` 正运行 `/Users/kaden/Copythat/dist/Copythat.app/Contents/MacOS/Copythat`。无法证明该会话与私人历史隔离，因此没有通过 Computer Use 打开或操作它。
- 当前接入的显示器只有一台内建 Liquid Retina 屏幕。任务 8.3 要求实际多显示器逐屏验收，不能用单屏替代。
- 当前源码默认使用 `NSPasteboard.general`；持久历史默认目录为当前用户的 `~/Library/Application Support/Copythat`，且 `AppSettings` 使用标准 defaults。named pasteboard / in-process runner 不足以隔离另一个正在运行的同用户 Copythat 进程。

因此 8.2、8.3 仍为 **blocked / not-covered**，总进度仍为 **22/24**，没有勾选任务。恢复所需条件：提供已登录、可交互且其历史/defaults 与本用户隔离的 macOS 测试会话；若要完成 8.3，还需实际连接第二台显示器。任务 checkbox 与先前 automated gate 记录保持原样。

### Follow-up — 2026-09-28

用户关闭了当前 Copythat；随后 `pgrep -x Copythat` 未发现运行进程。只设置临时 `HOME` / `CFFIXED_USER_HOME` 会把 FileManager 的 Application Support 路径改到临时目录，但 `UserDefaults` suite 仍由当前用户的 defaults 服务读取，不能证明 preferences 隔离。探查用的唯一临时 defaults key 已删除。故 8.2/8.3 仍需独立 macOS 用户会话；当前单屏条件仍使 8.3 的多显示器场景 not-covered。进度保持 22/24。
