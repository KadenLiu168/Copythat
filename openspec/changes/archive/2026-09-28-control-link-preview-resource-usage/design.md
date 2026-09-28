## Context

动机见 `proposal.md`。本方案以重新读取的 `main@35a1b152a44a469df6f130fabdebe082b3f35cc3` 为基线：

- `LinkPreviewFetcher.fetch` 依次请求 LP metadata、imageProvider、iconProvider、WKWebView；返回 optional 无法表达成功但所有字段为空。LP timeout 为 8 秒；截图区域与 PNG 最大尺寸为 640×360 / 640px。
- `ClipboardStore.enrichLinkPreviewIfNeeded` 仅对新插入且无 linkTitle/image 的 URL 启动未保存的 Task；`applyLinkPreview` 仅检查 ID 存在，然后 refresh/save。
- `selectedID` 是 Published 属性；`add` 直接赋值，`selectID`、搜索、pinboard 和 item mutation 也影响选择。`selectedItem` 有首项兜底，不能将兜底作为网络工作的隐式授权。
- `PanelWindowController.show/close` 控制实际显示；NSHostingView 长期存在，Views 的 appear/disappear 不能表达 orderOut。
- history policy 通常对 unpinned 重复内容保留已有 ID，但插入仍可淘汰其他 item。必须对实际移除的 IDs 清理工作，而不是猜测哪类操作删除了 item。
- `withLinkPreview(title:nil, ...)` 会清空 linkTitle；fallback 应沿用当前 title。Change 2 已提供媒体 blob、save coordinator 与 latest-state persistence，无需新增存储。
- 现有 Store persistence 测试直接调用 applyLinkPreview 验证保存，但没有 preview orchestration 或 WebKit lifecycle 测试。

此 Change 跨 Support、Store 与 panel window 边界，必须提供 design。

## Goals / Non-Goals

**Goals:**

- 将 eager metadata 与昂贵的 browser fallback 分离，首先证明 closed panel 下 snapshot loader 调用数为零。
- 明确任务的身份、取消和交接，使 UI 状态变更不产生 stale apply、重复 resume 或多个 active WebView。
- 保留现有 title/image 呈现和 persistence 调用路径，新增状态仅存在于 session。

**Non-Goals:**

- 完整范围见 proposal；这里不建立通用 scheduler，不让 Fetcher 理解 ClipboardItem 或 UI。
- 不声称 LPMetadataProvider 内部完全不使用 WebKit；零 fallback 指 Copythat 自己的 browser snapshot 路径。
- 不承诺 stopLoading 能撤回已经提交的 takeSnapshot 或立刻终止共享 WebKit process。

## Decisions

### 1. 分离结果和资源边界

`fetchMetadata(url:)` 仅完成 LPMetadataProvider、imageProvider、iconProvider。使用显式 success(metadata)/failure 结果或等价 throwing API；取消独立传播，成功对象允许 title/image 都为空。保持 8 秒 LP timeout、image 优先于 icon、640px 图片处理；整个阶段完成后才判定 eligibility。

`fetchWebSnapshot(url:)` 仅请求截图。建议 focused `LinkPreviewSnapshotController` 隔离一次 MainActor 上的 WebKit 请求；缓存、selection 与 item lifecycle 留在 Store。相比把两阶段保留在一个 fetch 内，这使 metadata 路径在结构上无法创建 fallback WebView。

LP cancellation handler 调用 provider.cancel；NSItemProvider 的 load Progress 应取消并在返回后再次检查 Task cancellation。Apple callback 与本地 cancellation 的竞态经 exactly-once finish 处理。取消前开始的 provider callback 可以迟到，但不能继续进入下一阶段或 apply。

每个 callback bridge 必须先建立可同步访问的 terminal/cancelled 状态，再注册 continuation 和启动请求；取消可先于上述任一步发生。取消主动结束本地等待者，不依赖 Apple 再回调。若取消时 load 调用尚未返回 Progress，返回后注册 Progress 必须观察 terminal 状态并立即 cancel。callback 与 cancellation handler 不假定在 MainActor 上执行，采用小型线程安全状态或等价串行化；外部 cancel/resume 在状态锁外执行，防止同步回调重入。每次 metadata 请求使用新的 LPMetadataProvider。测试覆盖取消后永不回调、同步 callback 和 Progress 延迟注册，而非仅覆盖正常异步返回。

### 2. Store 的 transient 状态与唯一评估入口

Store 持有每 item 的 metadata Task、请求身份与本 session outcome（pending/success-no-image/success-image/failure），以及 panelVisible、active fallback Task/identity、最新 desired target 和 session cache。可用小型状态记录取代多个重复集合，避免 outcome 与 eligibility 不一致。

新增 `panelDidOpen/panelDidClose`。show 完成窗口显示且选择已就绪后 open；close 首先撤销可见性并取消 fallback，再 orderOut。metadata 可在 panel closed 时继续。

统一 reconcile fallback 的调用来源：panel open/close、所有 selectedID 改变、metadata 完成、移除 items、filteredItems 刷新、fallback 清理完成。可对 selectedID 加 didSet 或收敛赋值入口，但必须覆盖 add 的直接赋值。刷新过程中避免启动临时旧选择；检查 selectedID 对应 item 确实存在于 filteredItems。

显式 select/selectFirstVisibleItem 即使 selectedID 未变化也必须重新评估 cache/TTL；现有 selectID 的 equality guard 只能避免重复 Published 更新，不能吞掉此次评估。仍在运行的同一请求保持不变，不能因为重复选择而取消重启。add 的 item replacement、removed-ID cleanup、filter/selection 更新和 metadata 注册作为一次同步状态更新完成后再 reconcile，避免 refreshFilteredItems 的临时首项引发不必要请求。若极小 history limit 使 insertedItem 已被淘汰，不启动其 metadata。

fallback 启动条件同时满足：panelVisible；selectedID 对应可见 URL；其 metadata outcome 为 success-no-image；仍无 linkImageData；没有有效 negative entry。positive cache 可满足请求，但也必须经过同样的 metadata/selection/apply 条件。

```text
add URL --> metadata pending --> success with image --> apply/save
                   |
                   +--> failure/cancel --> no fallback
                   |
                   +--> success without image --> eligible
                                                   |
                          panel visible + selected |
                                                   v
                                  cache or single snapshot
```

恢复历史的无图 URL 没有本 session outcome。建议在首次 panel open/selection 时请求其 metadata（包括已有 linkTitle 的项），成功无图才 eligible；不在启动时遍历历史发请求。现有图片直接使用，不重新获取。metadata failure 在同一 item/session 不因选择反复重试；跨 session 重新验证。此为默认恢复策略，不新增 metadata retry scheduler。

### 3. Latest-wins 包含资源清理交接

active fallback 包含 itemID、完整 URL 与唯一 request token。状态为 idle/running/cancelling；Task.cancel 后仍保留 active slot，等待请求完成资源清理再释放，期间 desired target 只保存最新选择。A→B→C 时不启动已被 C 覆盖的 B。

快切只取消 fallback，不取消仍然存在的 item 的 eager metadata。panel close 同理；delete/eviction/clear 则取消被移除项的全部 work。

旧任务结束只在 token 仍匹配时清理自身 slot；随后读取当前 UI 状态，而不是沿用结束前捕获的目标。避免 A→B→A、close→open 和旧任务 defer 清理新 task。不使用 semaphore 或 task pool。

### 4. 一次 WebKit 请求的终态与期限

WebView configuration 使用 `.nonPersistent()`，保留现有尺寸和 incremental rendering 行为。请求对象在 MainActor 串行协调 delegate、timer、snapshot callback 和 cancellation；callback 不强持有 WebView。

- loading：didFinish 提前进入 snapshot；3 秒 navigation deadline 到达时尝试当前状态。
- loading 阶段 navigation 明确失败：结束为 failure，不做网络恢复；snapshotting 后的迟到 navigation finish/failure 忽略，由 snapshot callback/deadline 决定结果。WebContent process 终止在 loading 或 snapshotting 均立即结束为 failure。
- snapshotting：调用 takeSnapshot 前再次检查取消/终态；最多提交一次。截图 callback deadline 为额外 2 秒，使单请求最长约 5 秒（不含调度延迟）。这限制应用持有任务的时间，不保证系统进程在期限内退出。
- cancelled/finished：一个 finish 入口先标记终态、清空 continuation，取消 timer、stopLoading、解绑 delegate、释放应用持有的 WebView，再 resume 一次。迟到 callback 不再触发 snapshot、resume、cache 或 Store 更新。

取消必须涵盖 handler 注册前已取消、load 前取消、navigation/timeout 同时到达、截图已提交后取消。已提交的 WebKit API 无撤回承诺，迟到结果必须丢弃。与固定 sleep 相比，navigation completion 不等待无意义余量；与 network idle 相比，不引入 JS/图片静止检测。

### 5. Session cache 的最小边界

Store（生产中只有 AppModel 的单一实例）持有 session cache。正缓存使用最多 64 项的小型 dictionary 与插入顺序，超出时淘汰最早项；完整 URL.absoluteString 为 key，值为成功的最终 PNG。相同 URL 被多个 item 引用时复用；query 不删除，redirect 后仍以原请求 URL 为 key。不构建通用 cache 类型；显式条目上限比 NSCache 的自动回收策略更易确定性验证。

负缓存为 URL→expiry，TTL=300 秒，使用现有 uptimeProvider，读取/写入清理过期 entry，并限制最多 64 项（超出时删除最早 expiry）。failure 才插入，cancelled 与 stale completion 不写缓存。TTL 到期后的下一次 panel open 或重新选择可重试，无后台 retry timer。panel close/删除 item 不清空 URL session cache。

相比磁盘 cache，现有 linkImageData persistence 已覆盖成功结果；相比无限失败集合，有界 TTL 状态不会成为另一种泄漏。

### 6. Apply 与 item removal

metadata 结果二次检查：任务未取消、token 当前、item 仍存在、kind 为 URL、完整请求 URL 未变。保留已有图片和 title；无新字段时不制造空更新/save。成功无图 outcome 可以独立于是否发生数据变化。

snapshot（含 cache hit）额外检查 panelVisible、selectedID、filteredItems membership、当前 eligibility 与 image 仍为空。沿用当前 linkTitle，再通过 applyLinkPreview/saveItems 保存；不绕过 coordinator、不直接写 blobs。

在 remove、clearHistory 和 add 的实际 item 集合变化处对移除 IDs 执行统一清理：取消 metadata 与 fallback，删除 transient outcome。全量/部分 clear 仅影响实际移除项，保留项仍遵循新选择。普通同内容复制复用旧 ID 时保留正在进行的 metadata，不重复启动；若被 limit 淘汰则清理。对 Store 释放的检查需防止 task/closure 强引用循环；取消和 finish 后移除任务引用。

Store-owned Task 只捕获 loader、请求身份和 weak Store；不得在网络 await 前将 weak Store 提升并跨 await 持有。Store 释放时取消尚存 preview tasks，请求清理只依赖自身资源而不依赖 Store 存活。测试释放 Store 后 weak reference 为 nil，并等待取消/清理事件；此检查不能由测试主动完成所有请求后再释放 Store 替代。

### 7. Deterministic seam 与证据

Store 注入 metadata/snapshot async closures，复用 uptimeProvider 测 TTL，persistItems recorder 检查 stale callback 没有 save。测试 loader 必须既能响应取消，也能故意迟到返回。

WebKit helper 使用小型 focused driver/factory 与可控 deadline seam，验证 load/stopLoading/takeSnapshot/delegate detach、资源释放和 exactly-once finish。Store mock 的调用计数不足以证明真实 adapter 的取消；必须分别测试请求状态机与生产 WebKit adapter 的接线。unit tests 不访问真实网络，不加载真实网页，不依赖实际 sleep 或任意次 yield。

Case 1 应作为最早自动化验收。完整测试矩阵在 tasks；本地真实 provider runner 与确定性测试共同完成当前环境功能验收，各自记录覆盖范围，不把 in-process runner 当真实 UI 证据。

### 8. 当前环境自动化功能验收（tasks 8.2/8.3）

8.2/8.3 以当前 macOS 环境可自动执行的功能验证为完成标准。复用现有本地 fixture runner、生产 Store/providers、可控 seam 测试和 panel smoke；无需 computer use、独立测试账号、真实浏览器 Copy、截图或第二台显示器。功能规则与 Cases 1–11 保留，调整的是证据获取方式及真实桌面回归的必需范围。

8.2 运行 `bash script/verify/preview_live.sh run --port 18765 --output .build/preview-functional-acceptance`，验证 image/title-only/失败页面和 open/select/rapid switch/close/reopen/cache 序列。runner 使用真实 LPMetadataProvider/WebKit；依据实际 metadata outcome 判断 failure 零 fallback、success-no-image 可 fallback。含 cleanup 的并发上限、迟到零 apply/save、缺失 callback、timeout、negative cache 与 299/300 秒 TTL 边界由 targeted deterministic/lifecycle 测试补齐，不要求真实 provider 恰好触发所有分支或等待五分钟。runner 不显示真实面板，其结果证明 Store/provider 行为，不证明 UI pixels。

8.3 对 title/image 数据、Search、Pin/Pinboard、删除、保存后新 Store 恢复、pasteboard restore 和 paste 目标/权限决策建立功能断言到测试的映射。复用既有测试；缺少行为断言时在后续实施中补最小测试，不能只凭 source inspection 判通过。持久化恢复须从临时目录读取实际保存结果，不能只检查 save recorder。panel 接线结合生产 caller-chain 检查、Store 生命周期测试及既有 panel smoke；其覆盖不扩展到所有 UI 交互。

测试通过 named pasteboard、独立 defaults、内存 recorder 或临时 persistence 目录隔离所操作的数据，不要求独立 macOS 用户。named pasteboard 只隔离剪贴板；涉及 settings/history 的测试仍须分别注入隔离依赖。无需为验收操作私人历史或重置 TCC。报告记录命令、源码身份、测试/场景、关键断言、结果和 artifact 路径；截图为可选材料。

真实 card 像素、外部文档 paste、系统 Accessibility granted/denied 切换、全局快捷键投递和物理多显示器作为可选补充，环境不具备时标记 not-covered，不阻塞 8.2/8.3。权限决策与合成 display frame 测试仍可验证相应逻辑，但不得声称系统授权或物理多屏实测通过。必需自动化项存在 failed/blocked 或覆盖缺口时任务保持未勾选；文档调整和历史 green run 本身不产生通过结论。

## Requirement traceability

| Requirement | Design decision | Task | Existing code constraint | Planned test |
|---|---|---|---|---|
| Preserve eager URL metadata enrichment | §1 分离结果与 callback bridge；§6 非空更新 | 1.1–1.2, 3.3, 7.1 | fetch 当前串联 WKWebView；applyLinkPreview 会无条件 save | Cases 1/2/10：closed panel 零 snapshot；空成功与 failure 分离；image/icon 优先；无字段零额外 save |
| Generate browser previews only for the visible selected eligible URL | §2 visibility、显式选择与 session outcome | 2.1–2.3 | show 先选择再显示；selectedItem 有兜底；add 直接赋值；restored item 无 outcome | Case 3/10：过滤、鼠标/键盘、add；恢复有 title 无图；pending→image/no-image |
| Keep browser fallback single and cancellable | §3 cleanup 交接；§6 移除与 weak ownership | 3.1–3.4, 6.1–6.3, 7.2 | close 只 orderOut；remove/clear/add 分散；普通 dedup 保留 ID | Cases 4–7/11：A→B→C、A→B→A、close→open、实际淘汰、Store 释放 |
| Bound temporary browser rendering | §4 loading/snapshotting/terminal 与两个 deadline | 4.1–4.2, 7.2 | 当前固定 sleep，缺少 delegate、snapshot deadline 与 cleanup | Case 11：早完成、3+2 秒可控期限、不同阶段失败、缺失/重复 callback |
| Reuse session browser previews and suppress repeated failures | §5 有界完整 URL cache；§2 同 ID 显式选择 | 5.1–5.2 | uptimeProvider 已有；selectID equality guard 会吞重选 | Cases 8/9：query 隔离、65 项淘汰、299/300 秒、当前项重选、cancel 不缓存 |
| Apply only current link preview results | §6 token/URL 校验与现有 persistence | 3.5, 7.3 | applyLinkPreview 只检查 ID；withLinkPreview(nil) 清 title/image；coordinator 已有 | Cases 4/6/7/10：迟到零 save/cache；有效 snapshot 保留 title/source/pin/URL；既有 blob/coordinator tests |

8.2/8.3 的补充 trace：metadata/eligibility/cancellation/deadline/cache/apply 要求 → §8 → 8.2 的真实 provider runner + deterministic tests；title/image/search/pinboard/delete/restore/paste/panel 兼容性 → §8 → 8.3 的隔离功能测试 + panel smoke。真实 UI、系统权限、快捷键与物理多屏另列可选覆盖。前述 Cases 1–11 的 deterministic coverage 保留。

## Risks / Trade-offs

- [页面 didFinish 时图片/JS 仍变化] → 保留当前尺寸与视觉形式，接受临时 preview；不等待完美截图。
- [timeout 当前状态可能无可用图片] → 返回失败并采用 TTL；不保证所有 URL 有图片。
- [WebKit 已提交的截图可能仍有迟到 callback] → 终态与 token 检查，释放应用资源，不承诺撤回系统 API。
- [session eligibility 不持久化使恢复项需重验] → 只对当前选择补 metadata，避免启动时网络 fan-out。
- [有界缓存会淘汰旧 URL] → 复用与失败抑制以 entry 仍在 cache 为前提，淘汰后仍遵循 eligibility 与 single fallback。
- [Apple callback 与 cancellation 竞态] → 所有终态串行且 exactly once；timer/cancel/delegate 各种顺序均测试。
- [视图隐藏 preview 的 privacy toggle] → 维持现有纯呈现契约，本 Change 不新增此 toggle 的网络语义。

## Migration Plan

按 tasks 的八阶段顺序实施。首先拆阶段并证明 closed-panel invariant，再增加 UI trigger、取消、navigation deadline、cache、移除清理与完整测试。无需数据迁移，旧 manifest/blob 和已有图片直接读取。

实施后运行 build、完整 gate、当前环境自动化功能验收与 adversarial review。回滚仅撤销本 Change 的代码；新增成功 preview 仍属于现有格式，数据继续兼容。规划完成不代表上述验收已执行。
