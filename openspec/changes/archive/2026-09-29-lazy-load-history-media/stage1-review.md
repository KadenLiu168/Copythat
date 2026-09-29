# Stage 1 review

日期：2026-09-29。Workflow profile: high-risk。源码基线：`637cd24b94f9dd2b958b42af33d48b144b3cb4d1`。开始时只有本 Change 目录 untracked，tracked diff 为空。此次仅审查与修订规划，不 Apply。

## Findings and repairs

以下均为 Pre-implementation fix，已写入相应设计、任务和适用的 delta scenarios；不是已复现的运行时 bug。

1. **Controller ownership**：Decision 6 / Task 6.2 要求 deinit cancellation，却未限制 Task 的强引用。现有 `PanelWindowController` 尚无 pending Task；沿常见 `guard let self` 后 await 写法会推迟 deinit。明确等待期间只 weak 捕获 controller，且测试先验证释放再完成 loader，防止“完成后才释放”的假阳性。
2. **Display authorization**：Decision 5 只列 visibility Bool 的 task identity，不能区分快速 close→reopen 被合并到一次 render 的两次授权。现有 controller 同步调用 `panelDidClose/Open`，hosting view 保留。增加该边界同步推进的 generation 与 completion 当前授权检查；Task 5.1/5.4 覆盖无中间 render 的旧 completion。
3. **Inline media identity**：Decision 5 的 ID/ref identity 未明确两次 inline payload（refs 均 nil）之间的变化。现有 `withLinkPreview` 可保留 item ID 替换 bytes。明确 ref→inline、inline→inline 的失效与测试，避免 stale decoded state；不引入全 history hashing。
4. **Composition root**：现有 `AppModel.init` 创建 Store，DEBUG convenience init 自行组装隔离 persistence。仅 Store 注入不足以让 controller 集成测试绑定 fixture blobs。Decision 2 / Task 3.1 / proposal 明确 AppModel 与 DEBUG 分支的同目录 loader 注入及读取验证。
5. **Drag ownership**：现有 Card 的 dragProvider 只做简单对象包装，新设计加入异步传输、PNG conversion、Progress/completion 协调。依 AGENTS 的平台边界规则，Decision 7 / Task 6.5 指定 focused Support helper，View 仅调用；不创建通用传输框架。

## Requirement trace

| Requirement | Design decision | Task | Existing code constraint | Planned test |
| --- | --- | --- | --- | --- |
| Restorable metadata / reference save | D1–2，Data 优先否则保留 ref | 1.1–1.2, 2.3–2.4 | `ClipboardItem` 显式 constructor/CodingKeys；Store mutation 与 coordinator 传值 | Pin/board/rename/quit 后 ref 与 metadata 等价；零 heavy reads |
| V2 lazy startup / legacy compatibility | D2，仅 icons eager，版本保持 2 | 2.1–2.2, 2.6, 7.1 | `decode` 按版本分支；legacy inline 数据；load failure backup | 500 items，manifest+dedup icons only；V1/raw/defaults 保留 |
| Blob integrity / local failure | D2–3，canonical ASCII 与 shared SHA primitive | 2.2–2.3, 3.1 | 现有 `loadBlob` 同时负责 syntax/read/hash | 无效 ID 不读，heavy missing/hash mismatch 延迟失败，source icon 失败仍拒绝 |
| Atomic save / GC / repair | D2，复用 worker 和 commit ordering | 2.3–2.6 | `save` blob-first；worker 串行；coordinator flush/latest-wins | failed commit last-good，Data 修复损坏 blob，共享 refs 最后删除才 GC |
| Residency-independent image identity | D1，bytes digest/ref ID 一致 | 1.1–1.3 | Policy、deletedContentKeys、pasteboardMatches 使用 contentKey | 同 stored bytes duplicate/pinned duplicate/删除抑制；无 blob 读取 |
| Bounded off-main loading | D3，32 MiB actor LRU | 3.1–3.3 | 同步 persistence read 必须移入 actor；test recorder 要同步 | read thread、LRU order/cost、oversized bypass、queued cancellation |
| Production/isolated loader routing | D2，AppModel→Store 同目录依赖 | 3.1, 7.3 | AppModel 的 production/injected/DEBUG init 都创建 Store | controller path 读取 temporary fixture，禁止 shared fallback |
| Existing link preview presence / current results | D4，语义 presence 而非 nil Data | 4.1–4.3 | visibleSelectedLinkURL/register/merge/snapshot guard 四条路径 | restored ref 零 metadata/snapshot；title-only 保留；旧 fallback tests |
| Card eligibility / privacy / stale results | D5，generation+payload identity+task cancellation | 5.1–5.2, 5.4 | LazyHStack + equatable card + retained hosting | close/reopen 同 render、filter、remove、inline 替换、hidden scroll、state release |
| Stable preview geometry | D5，presence 决定 region/typography | 5.3, 7.3 | URL 105pt；image scaledToFit；固定 header/card | real NSHostingView pending/success/failure 布局及 ultra-wide fixture |
| Lazy paste / safety / supersession | D6，临时 item、同步 fast path、request token | 6.1–6.4, 7.4 | performer 先 restore 后 target/trust；其 cleanup 目前 private | named pasteboard，A→B/B失败，旧 callback，permission injection，fast paths |
| Controller release / accepted handoff | D6，weak owner await，handoff 前清 ownership | 6.2, 6.4 | controller owns performer；close 撤销 Store visibility | loader 放行前 weak=nil，late zero writes/send，internal close 保留 accepted send |
| Image drag representation / cancellation | D7，focused Support helper | 6.5 | Card 原无 image 时退为 NSString；NSItemProvider 边界 | receiver request 才读、PNG/legacy nonPNG、Progress cancel、一次 completion、failure 无 text |
| Unattended evidence / no real data mutation | D8，隔离资源和 fail-closed report | 7.2–7.7 | verify_all 已含 build/test/package gates；AppKit 需要 GUI session | required scenario mapping、runner failure/blocked/timeout/missing evidence self-tests |

## Remaining tradeoffs and Apply constraints

- 32 MiB 只限制 encoded cache，不能当作进程 RSS 或所有 decoded NSImage 的上限。
- 同步 disk read 不可保证中途取消；consumer token/authorization 必须挡住迟到结果。
- reference-only save 不读取验证 payload；缺失/损坏引用保留，访问局部失败。GC 与已移除 item 的 in-flight consumer 竞争允许局部失败，不新建磁盘 lease 协议。
- Actor 同步 miss 串行是当前最小设计；不加 scheduler/in-flight registry。显示路径指 LazyHStack 生命周期，不声称精准物理 viewport 可见性。
- 项目 context 的 manual checks 与本 Change D8 的无人值守验收范围不同；本审查保留该 Change 已明确的验收要求，真实 TCC/物理输入/第三方 app/物理多屏仍作为未覆盖边界。不能把 synthetic 结果升级为这些场景的证明。
- 源码尚未实现，31 个 implementation tasks 均保持未勾选；Stage 1 不运行业务完整 gate，不构成性能、UI 或并发行为已通过的证据。
- Apply 最终由单命令 runner 调用现有完整 gate；`verify_all.sh` 已执行 build/test，不必为报告重复执行相同完整 suites，可从该命令日志记录子检查结果。任何 gate-relevant 后续改动都使旧证据失效。

## Validation

结论：修改后适合实施；无已知未解决 Blocker。这里只判定规划就绪，运行时保证仍由 Apply 的测试证明。

- `openspec validate lazy-load-history-media --strict`：exit 0，`Change 'lazy-load-history-media' is valid`。
- `git diff --check`：exit 0；因为该目录 untracked，另对目录全部文件逐一执行 `git diff --no-index --check /dev/null <file>`，均 exit 0。
- `git diff --name-only`：空；tracked 业务代码、测试和配置均未改。`git status --short` 仍仅此 Change 目录 untracked。
- 未执行 swift build / verify_all：本轮仅文档审查，不声称业务 gate 通过。
