本 Change 所有测试与验收均自动执行。无需人工 smoke、权限授权点击或物理键鼠/显示器操作；自动化证据边界见 design Decision 8。实施任务仍待 Apply，本次仅修订规划。

## 1. Model semantics（先补 correctness tests）

- [x] 1.1 在 `ClipboardItemStorageOptimizationTests` 增加 reference-only image/link fixtures，覆盖 presence、eager/lazy相同contentKey、storageOptimized传播、title-only保留、新preview清旧ref与Data转换身份；verify：先确认旧实现失败，再运行focused model suite通过。
- [x] 1.2 修改 `ClipboardItem` 的runtime refs、默认构造参数、legacy decode nil refs、semantic properties和stable contentKey，保持原inline CodingKeys；verify：1.1、legacy decode tests以及现有source icon原样/pixel bounds断言均通过。
- [x] 1.3 覆盖 `ClipboardHistoryPolicy`、`ClipboardStoreImageDeletionTests` 的lazy/eager duplicate、pinned duplicate、deletedContentKeys、current pasteboard matching；verify：named NSPasteboard下删除匹配lazy image不读history blob、不recapture，新的真实copy仍可捕获。

## 2. V2 persistence与GC

- [x] 2.1 在 `ClipboardHistoryPersistenceTests` 先添加readData recorder与互不重叠的icon/image/link blob fixture；verify：V2 restore只有manifest+deduplicated source icon reads，heavy reads=0，metadata/refs完整、heavy Data=nil、version仍2。
- [x] 2.2 提取共享canonical ASCII ID/path/SHA read primitive，V2 decode先校验所有refs，仅materialize icons；verify：短/长/uppercase/nonhex/nonASCII/path traversal IDs拒绝，合法missing/corrupt heavy文件不影响metadata restore，source icon failure保留旧行为。
- [x] 2.3 保存路径增加Data优先、nil Data时validated ref复用；保留existing Data hash/check/repair与blob-first atomic commit；verify：unloaded image/link ref save heavy reads/hash=0，invalid runtime ref不commit/GC，损坏existing blob仍由实际Data修复，failed save旧manifest不变。
- [x] 2.4 通过真实Store mutation和现有coordinator/worker flush验证togglePin/unpin、move/remove pinboard assignment、rename assignment、无关item mutation与Quit snapshot传播；verify：从不materialize情况下重载manifest仍引用原heavy IDs且metadata正确，现有latest-wins/flush/failure tests通过。
- [x] 2.5 添加lazy media GC tests；verify：save+GC保留所有committed refs，共享blob最后一个item删除后才清理，删除发生在manifest commit之后，失败transaction不损坏last-good history。
- [x] 2.6 将V2 eager全等测试改成metadata/source icon/contentKey/ref和随后materialized bytes等价的双重断言，保留V1/raw array/UserDefaults、migration失败、unsupported version、backup与corruption repair覆盖；verify：`ClipboardHistoryPersistenceTests`、`ClipboardHistorySaveCoordinatorTests`、`ClipboardHistoryWorkerIntegrationTests`、`ClipboardStorePersistenceTests`全部通过，不仅删旧断言。

## 3. On-demand loader

- [x] 3.1 新增 `ClipboardHistoryMediaLoader` actor，注入shared blob primitive、内部32 MiB budget和test小budget；经 AppModel（含 DEBUG isolated verification）将对应 persistence directory 的同一loader注入Store供所有consumers使用；verify：invalid ID无disk read，正确SHA返回原bytes，missing/wrong hash失败，reader不在main thread，测试只访问temporary目录，AppModel→controller integration 也验证读取 fixture directory 而非 shared history。
- [x] 3.2 实现byte-cost LRU与oversized bypass；verify：first+second load read count=1，hit刷新recency，确定性A/B/touch-A/C序列淘汰B，cache cost始终≤budget，单blob>budget能返回但两次load读两次。
- [x] 3.3 加入排队read前cancel检查与consumer迟到completion测试seam，不建通用in-flight框架；verify：已取消排队请求不启动新read，non-cooperative完成可被消费者拒绝，failure不cache，连续有效访问共享同一bounded cache。

## 4. Link preview integration

- [x] 4.1 将 `visibleSelectedLinkURL`、`registerLinkMetadataIfNeeded`、snapshot validation和fallback缺图判定改为semantic presence；verify：真实V2 restore的URL+title+ref在open/select/filter-out-in/reopen后metadata与snapshot fetch均0，UI加载前heavy reads仍0。
- [x] 4.2 修正metadata merge/outcome与 `withLinkPreview`调用，保留已有unloaded image，明确new image清ref；verify：title-only/empty completion不丢image ref、不误授权fallback，new image保存新ID，missing/corrupt persisted preview不触发network修复。
- [x] 4.3 回归完整 `StoreLinkPreviewOrchestrationTests`、`StoreLinkPreviewCacheTests`、`StoreLinkPreviewCancellationTests`、`StoreLinkPreviewRemovalTests`；verify：new URL eager metadata、restored no-image metadata-before-fallback、single browser cleanup、TTL、late result rejection与原save断言保持通过。

## 5. Card UI与privacy生命周期

- [x] 5.1 将Store `panelVisible`发布为read-only observable state，BottomPanel传给card并更新Equatable（包括授权 generation）；panel lifecycle 同步推进授权 generation，使同一更新周期 close→reopen 也使旧请求失效；verify：retained NSHostingView中visibility变更能更新真实card task，`StorePanelWiringTests`和existing selection/source icon tests通过。
- [x] 5.2 为card增加短生命周期media state与identity-keyed task，采用panelVisible && !hidesPreview eligibility及completion后二次cancel/identity检查，离开eligible/消失清state；verify：actual card harness中visible card读取、hidden panel与Hide Previews读取均0，load不mutation/save/selection/enrichment。
- [x] 5.3 Image placeholder保持固定region，URL hasLinkImagePayload保留105pt area和带图typography，failure切fallback；verify：pending/success/failure的layout一致，ultra-wide image仍scaledToFit且header完整，通过真实NSHostingView自动测量render/layout，pending/success/failure均有assertions，不以人工看截图判定。
- [x] 5.4 通过可控loader覆盖panel close→reopen、privacy toggle、filter out→in、delete/evict、card消失/更换reference、ref→inline bytes、同ID inline bytes替换的迟到结果；verify：旧completion不能更新新UI或history，关闭后不开始新reads，completion读取当前授权状态，未经过中间 render 的 close→reopen 也拒绝旧结果；临时media释放，滚动100张image且privacy开启heavy reads=0。

## 6. Paste与Drag

- [x] 6.1 增加Store临时 `materializedItemForPaste`，非image/已有Data保持fast path；verify：named NSPasteboard收到lazy image正确图像（尺寸/pixel或normalized payload），items重Data仍nil、save count=0、selection不变；missing/corrupt/不可解码不修改原pasteboard并显示原restore failure。
- [x] 6.2 Controller增加pending task/request token、request-time item+target捕获、close/deinit cancellation，current completion才handoff，Task 不跨 await 强持有 controller；verify：non-cooperative A pending→Esc/close/release→A completes 时writes=0/send=0，release 场景须在 loader 放行前确认 weak controller=nil；A→B/A最后完成仅B可paste，stale failure不覆盖B反馈。
- [x] 6.3 先补旧performer pending fallback/queued send→new lazy request的跨边界回归，再按必要性最小暴露现有supersession cleanup入口供controller在request起点调用；verify：B等待或失败期间执行A旧callback均send=0，performer activation核心diff未改，完整 `ClipboardPastePerformerTests`、`PasteDecisionTests`、`PasteTargetTests`通过。
- [x] 6.4 Successful handoff清除pending ownership后沿用performer Bool结果同步关闭；verify：internal close不取消accepted send、current失败panel保持反馈、item与target取自request时刻、text/url/file与已有image同步路径不增加async delay，named pasteboard端到端restore测试通过。
- [x] 6.5 在 focused Support helper 中实现 image drag（Card仅调用），提供已有NSImage或async PNG data representation，读取只在receiver请求时发生，Progress cancellation与completion恰好一次；verify：真实NSItemProvider请求lazy PNG及legacy-migrated非PNG fixture均得到正确PNG，创建provider reads=0，missing/corrupt返回error且无NSString fallback，privacy开启仍可explicit drag，text/URL/file行为不变。

## 7. 无人值守 acceptance与完整verification

- [x] 7.1 在 `ClipboardHistoryPerformanceTests` 增加500-item V2 image/link-heavy restore fixture（heavy IDs与icon分离），覆盖source icon dedup与metadata ready；verify：image/link blob读取各0，不使用wall-clock门槛，以read counters作为必需性能证据。
- [x] 7.2 通过自动化集成tests执行design所列对抗场景：lazy restore→Pin→flush/quit、未显示即删除、immediate Return、pending→Esc、A→B、restored link open/search/filter、hidden scroll、missing/corrupt、GC、eviction/card disappearance、retained hosting view close、同图duplicate；verify：无引用丢失、重复/late paste、stale UI、hidden reads或多余network请求，自动报告场景到tests/evidence的映射。
- [x] 7.3 增加native AppKit无人值守验收：复用真实NSHostingView、panel/controller与生产gesture/key routing，对first-display/loading/fallback layout、selection/search/pinboard、Return/double-click/Esc、retained-panel与drag receiver自动断言；verify：从事件/gesture wiring到实际controller/materialization及named pasteboard或NSItemProvider结果完整覆盖，不依赖目测、source字符串或独立callback调用，实际执行无需TCC/global synthetic input。
- [x] 7.4 最小添加performer trust-check injection（生产默认保留AccessibilityService.requestIfNeeded）并复用activation/send seams，以true/false及target nil自动验证真实paste() restore/decision/feedback；扩展PanelFrameCalculator合成多屏fixtures；verify：测试不弹系统权限框、不改TCC、不发真实Command-V，permission拒绝send=0、允许send至多1，多屏geometry断言通过，报告标记injected/synthetic而非真实TCC/物理多屏。
- [x] 7.5 新增 `script/verify/history_media_acceptance.sh` 单命令runner，自动运行required场景及 `swift test`、`swift build`、`./script/verify_all.sh`、`git diff --check`、`openspec validate lazy-load-history-media --strict`；自动复用framework/Pillow环境并最小更新受loader影响的existing standalone driver source lists；verify：无stdin/manual steps，环境缺失/timeout自动报告并非零退出，preview_live self-test通过，所有required cases与完整gate零退出才passed，不弱化原checks。
- [x] 7.6 自动生成 `.build/history-media-acceptance/<run-id>/report.json`、`summary.md` 和logs，绑定时间/HEAD/source fingerprint、scenario IDs、expected/observed assertions、commands/exit codes与evidence type，失败也报告和清理；verify：runner self-tests覆盖成功、行为失败、环境blocked、required case缺失及timeout均正确判定，总结不泄露payload，不将synthetic标为physical、不以not-covered通过required case。
- [x] 7.7 实施后执行单命令无人值守完整验收，自动检查报告与required场景覆盖、在同一source fingerprint下保存最终gate证据；verify：全部required scenarios与gate通过，报告明确真实TCC/物理输入/第三方app/物理多屏的未覆盖边界但没有人工待办，隔离目录/defaults/named pasteboard与test-owned窗口/进程自动清理，用户真实历史和pasteboard不受影响。
