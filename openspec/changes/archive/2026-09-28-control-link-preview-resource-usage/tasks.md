## 1. Phase 1 — 拆分 metadata 与 WebKit fallback

- [x] 1.1 将 LinkPreviewFetcher 拆成 fetchMetadata 与 fetchWebSnapshot，显式区分 success（允许空字段）、failure、cancellation，保留 image/icon 顺序与 640px 处理；验证 metadata 路径无 WKWebView 创建调用且 targeted metadata 测试通过。
- [x] 1.2 为 Store 增加可控 metadata/snapshot closure seam，首先补并通过 Case 1：closed panel 下 add URL、metadata title-only 成功，snapshot fetch count 为零且 title 正常保存；测试使用独立 pasteboard、临时 settings、内存 persistence recorder，不访问网络。

## 2. Phase 2 — Panel visibility 与 selection-driven trigger

- [x] 2.1 在 PanelWindowController show/close 接入 panelDidOpen/panelDidClose，以实际窗口显示顺序为边界；验证所有当前关闭入口均撤销 eligibility，NSHostingView 保留时 close 仍取消，不在 Views 引入网络生命周期逻辑。
- [x] 2.2 建立 transient metadata outcome 与统一 fallback reconcile，覆盖 add 直接设置 selectedID、键盘/鼠标、search、pinboard 和 filteredItems 变化；同一 mutation 完成最终 filter/selection 与 metadata 注册后才评估，显式选择同 ID 仍评估 TTL 但不重启 active request；验证 Cases 2/3/9/10：metadata image 永不 fallback、eligible selected URL 才启动、metadata pending 无竞态、临时旧选择不启动 loader。
- [x] 2.3 为恢复的无图 selected URL 补本 session metadata，包含已有 linkTitle 的项；验证加载历史无批量网络请求、持久化 title 不能直接授权 fallback、已存图片不重取、metadata failure 不随重选循环请求。

## 3. Phase 3 — Single active fallback 与 cancellation

- [x] 3.1 Store 持有 metadata Task 与唯一 active fallback，采用 request token 和 cancelling 交接，清理完成后只启动最新 desired target；验证 Case 5 的最大 active 数为一，以及 A→B→C 清理期间不启动已失效 B。
- [x] 3.2 在 selection change 和 panel close 取消 fallback，保留仍存在 items 的 eager metadata；验证 Case 4、A→B→A、close→open，故意迟到结果不 apply、不 cache、不 save，旧任务不清掉新任务。
- [x] 3.3 metadata cancellation 接入 LPMetadataProvider.cancel 与 NSItemProvider load Progress，以线程安全 bridge 协调 callback/取消并主动 exactly-once 结束本地等待者；验证 continuation 注册前取消、provider loading/image loading 中取消、同步 callback、取消后永不回调、Progress 返回后才注册的竞态，以及迟到返回均不进入下一阶段并释放任务引用；外部 cancel/resume 不在状态锁内执行。
- [x] 3.4 用 focused WebKit request helper 实现 stopLoading、delegate 解绑、application-owned WebView 释放与 exactly-once continuation；验证 Case 11：取消发生在 snapshot 提交前时 takeSnapshot 为零，提交后取消的 callback 被丢弃，取消不被 sleep 吞掉。
- [x] 3.5 对 metadata/snapshot/cache apply 增加 ID、kind、完整 URL、token、cancellation 校验，并对 fallback 增加 visibility、visible selection、eligibility、image nil 校验；验证 stale save count 为零、有效 snapshot 保留 linkTitle/source/pinboard/pin/restorable URL，继续通过既有 applyLinkPreview/saveItems 路径。

## 4. Phase 4 — Navigation completion 与 bounded timeout

- [x] 4.1 使用 non-persistent WebView，didFinish 提前截图，3 秒 navigation deadline 尝试当前状态；loading navigation failure 直接失败，snapshotting 后忽略迟到 navigation failure，process termination 在两阶段均直接失败；验证可控 delegate/deadline 测试覆盖早完成、超时、两阶段失败与重复事件，最多提交一次 snapshot。
- [x] 4.2 增加 snapshot callback 额外 2 秒 deadline，与取消统一 terminal cleanup；验证 callback 永不返回也有界释放，timeout/didFinish/cancel/snapshot callback 的不同到达顺序全部 exactly once，且迟到事件不 snapshot、不 resume、不 save。

## 5. Phase 5 — Session positive / negative cache

- [x] 5.1 在 Store 增加完整 URL.absoluteString→成功 PNG 的最多 64 项 cache，超出时淘汰最早插入项；验证 Case 8：另一 eligible item 请求相同 URL 不启动 loader，query 不同不共享，65 个 URL 后容量仍有界。
- [x] 5.2 使用 uptimeProvider 建立 300 秒 negative TTL，最多 64 项，清理过期项并淘汰最早 expiry；验证 Case 9：立即重选不重试、TTL 到期后重选可重试、cancel 不写 failure、无需后台 timer、负缓存容量有界。

## 6. Phase 6 — 删除 / eviction lifecycle cleanup

- [x] 6.1 对 remove 与 clearHistory 的实际移除 IDs 清理 metadata、fallback 和 outcome；验证 Case 6 及全量/部分 clear，removed items 的迟到返回不恢复、不 save，保留 pinned/pinboard 项仍按当前选择运行。
- [x] 6.2 对 add/history policy 前后 item 集合进行移除清理，不改 history limit 或 dedup 语义；验证 Case 7、极小 limit 下 insertedItem 自身已淘汰不启动 metadata、普通同内容复制保留旧 ID/进行中任务，以及 pinned duplicate 产生新 item 时相同 URL cache 仍可复用。
- [x] 6.3 防止 Store-owned preview Task/closure 跨网络 await 强持有 Store，Store 释放时取消剩余 preview work；使用 pending loader 释放 Store，验证 weak reference 为 nil、取消与资源清理完成、迟到结果无 save，而非先完成请求再验证释放。

## 7. Phase 7 — 完整 deterministic acceptance

- [x] 7.1 完成 Cases 1–10 的 Store orchestration 测试矩阵，包含 metadata success 空字段、failure、image、icon、pending race、lazy trigger、取消、delete/eviction/clear、缓存与 TTL；验证每种路径的 loader 次数、取消观察、最大 active 数、apply/save 次数均有事件驱动断言，无真实网络或 sleep 等待。
- [x] 7.2 完成 Case 11 与 WebKit helper/adapter 测试，使用 focused driver/factory 与可控 deadline，涵盖注册前取消、load 前取消、navigation cancel、snapshot cancel、double callback、process termination、缺失 callback；验证 stopLoading/delegate detach/资源释放，以及生产 adapter 确实接入同一 lifecycle，不用 Store mock 替代 adapter 证据。
- [x] 7.3 扩展当前 ClipboardStorePersistenceTests 的 preview title/media 保存验收，保留既有 coordinator latest-state 测试；验证有效 preview 使用原 schema/blob/save path，metadata 空结果与 stale completion 不制造额外保存。

## 8. Phase 8 — Gates、当前环境自动化功能验收与 adversarial review

- [x] 8.1 运行 targeted preview 测试、swift build、./script/verify_all.sh，并执行 openspec validate control-link-preview-resource-usage --strict；记录实际命令、环境、结果，验证所有 gate 通过，不以旧 green run 或跳过 gate 替代。
- [x] 8.2 在当前 macOS 环境运行 `bash script/verify/preview_live.sh run --port 18765 --output .build/preview-functional-acceptance`，使用本地可控 fixture、生产 ClipboardStore、真实 LPMetadataProvider/WebKit 验证 OpenGraph image、title-only、失败页面及 open/select/快速切换/close/reopen/cache 行为。结合 targeted preview tests 验证 closed panel 零 fallback、仅 visible selected eligible URL 启动、含 cleanup 最多一个 active fallback、取消后迟到无 apply/save、timeout 和 cache/TTL；metadata failure 不启动 fallback，snapshot failure/TTL 使用 metadata 成功无图的受控前置条件。真实 provider 未触发的分支由可控 seam 测试补齐，300 秒 TTL 用 uptimeProvider 验证，无需实际等待。记录命令、源码身份、逐场景断言及 report/log 路径；runner 必需场景及对应确定性测试通过后可勾选，不要求 computer use、浏览器 Copy、截图或完整 app UI 会话。
- [x] 8.3 在当前环境通过隔离的功能测试验证 URL title/image 数据与 Search、Pin/Pinboard、删除、持久化保存后新 Store 恢复、pasteboard restore 和 paste 的目标/权限决策；复用既有 Store、persistence、paste、panel 测试与 `./script/verify_all.sh` 的 panel smoke，逐项列出测试名称、行为断言、结果及未覆盖部分。使用 named pasteboard、独立 defaults、内存 recorder 或临时 persistence 目录，无需独立 macOS 用户；涉及磁盘恢复的测试须实际读取保存结果。panel show/close 接线结合生产 caller-chain 检查与 smoke 验证，源码字符串检查不能单独充当功能证据。真实 card 像素、向外部文档发送 paste、系统 Accessibility 授权切换、全局快捷键投递和物理多显示器作为可选补充；缺少桌面权限或第二台显示器不阻塞本任务，明确标记 not-covered，不声称已经实测。上述必需自动化功能断言通过后可勾选；不修改私人 history/defaults、不重置 TCC。
- [x] 8.4 对最终 source/caller chain 与测试做 adversarial review，重点审查 stale result、A→B→A、close→open、cleanup overlap、double resume、timer/task/WebView leak、metadata cancellation、cache poisoning 和额外保存；记录发现、修复与针对性复验，确认无未解决真实缺陷且完成全部 Definition of Done 后才标记 Change 实施完成。

## Deterministic acceptance cases

以下编号供上述任务引用。save 次数均以触发操作本身的合法保存为基线，断言 preview completion 的增量，不能把 add/remove 的保存算成 stale result 保存。

| Case | Controlled events | Required assertions |
|---|---|---|
| 1 | closed panel add URL；metadata title-only success | metadata 一次；snapshot 零次；title 可搜索；preview save 增量一次 |
| 2 | metadata image、icon（image 无可用数据）各一次；open/select | image→icon 顺序与 640px 保留；snapshot 零次；图片沿原路径保存 |
| 3 | 两个 eligible URL；open、鼠标/键盘选择、search、pinboard、add | 只对最终 selectedID 且在 filteredItems 内的 URL 请求；selectedItem 兜底不授权；过滤掉当前项取消；同步 mutation 临时选择不启动 |
| 4 | loading/snapshotting 中 close；A→B→A；close→open；旧 loader 故意迟到 | 取消被观察；旧结果 save/cache 增量零；旧 token 不清新 slot；仍存在 item 的 metadata 继续 |
| 5 | A active；取消后阻塞 cleanup；选择 B 再 C；最后释放 A | cleanup 前 B/C loader 零次；cleanup 后只有 C；max active（含 cleanup）=1 |
| 6 | pending metadata/fallback 后 delete、full clear、partial clear | 实际 removed IDs 取消且 outcome/task 移除；迟到 save/cache 增量零；retained pinned/pinboard 项按最终选择评估 |
| 7 | limit eviction；普通 duplicate；pinned duplicate；limit 已被 pinned 占满 | 淘汰任务清理；旧 ID/metadata 保留且不重复；pinned duplicate 可复用 URL cache；insertedItem 自身淘汰时 metadata 零次 |
| 8 | 同完整 URL 的另一 eligible item；不同 query；65 个成功 URL | retained cache hit 不启动 loader；query 不共享；最多 64 项、淘汰最早插入；cache hit 也遵守 apply 校验 |
| 9 | fallback failure；uptime 299/300 秒；重选当前 ID、离开再返回、reopen；65 个失败 URL | 299 秒不重试；300 秒显式重选同 ID 可重试；active 同 ID 不重启；cancel/stale 不写 negative；过期清理、容量≤64、最早 expiry 淘汰；无 timer |
| 10 | metadata pending→image/no-image/empty success/failure/cancel；恢复有 title 无图/已有图；请求后 URL/preview 改变 | pending/failure/cancel 零 fallback；empty success 可 eligible 且零数据更新；加载无 fan-out；selected restored 无图补 metadata，已有图不重取；failure 重选不重取；stale 不覆盖或 save；有效结果保留 title/source/pinboard/pin/URL |
| 11 | driver 控制 load/didFinish/failure/process termination/deadline/snapshot callback/cancel 顺序 | 注册/load 前取消零 load/snapshot；3 秒或早完成最多一次 snapshot；额外 2 秒无 callback 也释放；snapshot 后 navigation failure 忽略、process termination 失败；所有 terminal exactly once、stopLoading/delegate detach、应用资源释放；迟到/重复事件无副作用；生产 adapter 接入同一 lifecycle |

Case 11 之外，3.3 的真实 metadata bridge seam 与 6.3 的 weak Store 生命周期检查是独立验收项，不能由 Store mock 或 WebKit driver 替代。

## Definition of Done

- 所有实现任务与上述 acceptance cases 具有当前源码/测试证据；不得仅因 planning artifact 为 done 就声称实现完成。
- 最终相关 diff 的 targeted tests、`swift build`、`./script/verify_all.sh` 和 target strict validation 均通过，记录命令、环境与结果。
- 8.2/8.3 按当前环境的必需自动化功能断言完成验收；必需项 failed/blocked 或缺少行为证据时不得勾选。真实 provider runner、可控 seam 单测、panel smoke 与可选真实 UI 证据分别标明覆盖范围；可选桌面、权限切换、快捷键和多屏实测缺失不阻塞完成，也不能由自动化证据冒充实测。验收方式调整本身不代表任务通过。
- 最终 adversarial review 无未解决真实缺陷；无业务范围外修改、依赖/schema/settings 变化、私人 payload 日志或真实用户数据测试写入。
