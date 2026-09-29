## Context

See `proposal.md` — Why。基线为 2026-09-29 `main@637cd24b94f9dd2b958b42af33d48b144b3cb4d1`；本地 `origin/main` 相同，未作远端刷新。

当前源码观察：

- `ClipboardHistoryPersistence.decode()` 的 V2 branch 建立临时 `[String: Data]` cache，`PersistedClipboardItemV2.makeClipboardItem()` 连续读取 source icon、image、link image；`loadBlob` 同时执行 ID/path validation、disk read 和 SHA256 validation。合法 missing/corrupt heavy blob 当前也会让整个 decode 抛错，static loader 返回空历史。
- `save()` 只从 Data 生成三类 blob IDs，`blobID(for:)` 会读取已存在 blob 并 hash，损坏时排队重写；blob-first、atomic manifest、commit 后 GC 已成立。Save coordinator/worker 已提供后台保存和 generation/latest-wins，不需要重做。
- `ClipboardItem` 有显式 `CodingKeys`、legacy decoder、完整构造器；image `contentKey` 仅使用 Data digest。`storageOptimized` 将 image/link image 分别限制为 1200/640px，source icon 原样；`withLinkPreview` 重新构造 item。
- Store 初始化同步读取 history。`panelVisible` 是非 Published read-only property，`panelDidOpen/Close` 已作为 fallback visibility boundary。Link-preview 的 visible selection、metadata registration、merge、snapshot validation 使用 `linkImageData == nil`。
- `BottomPanelView` 的 privacy 是本地 `@State hidesPreviews`，timeline 使用 `LazyHStack`；card 经 `.equatable()` 包裹。Card 直接访问 `item.image/linkImage`，URL image region 105pt，title font/line limit/padding 都依赖 image 是否已 decode。`dragProvider` 在没有 `item.image` 时返回 NSString，会误拖 lazy image 的文字。
- `PanelWindowController` 保留 `NSHostingView`，`close()` 先撤销 Store visibility，再 `orderOut`。`pasteSelected()` 同步调用 performer，成功即关闭；performer 在 `paste()` 起点 supersede，之后先 restore 再检查 target/Accessibility。Observer-before-activation、PID matching、350ms fallback、terminal claim、queued send cancellation 均已存在。
- 现有 persistence tests 会直接断言 eager item 与 V2 reload 的 `Equatable` 全等，需要改成更强的 metadata/reference + materialized-byte 等价证明。`ClipboardStorePersistenceTests` 已验证 restored URL 不 refetch；link suite 有可控 loader/counter；paste tests 已有 named pasteboard 和可注入 activation/send 回调。

现有 spec 的 relaunch/restorable content 与 stored image absence 要解释为“存在可恢复的 payload”，并非要求启动 Data resident。本 delta 保留这些原 scenario，新增 lazy 语义。`clipboard-history` 与 `panel-and-search` 对 pinboard 是否自动 pin 有已有不一致；本 Change 不处理它，也不改当前 pinboard 行为，只验证引用跨现有操作保留。

## Goals / Non-Goals

**Goals:** 建立 payload presence、persisted identity、temporary materialization 三者明确分离的契约。以零 startup heavy reads、跨 metadata save 不丢引用、严格 cache cost、真实 consumer 路径取消证明为完成条件。按用户后续明确要求，所有必需测试和验收无人值守完成；项目 context 的 manual checks 在本 Change 中由下述自动化场景替代，不保留人工完成任务。

**Non-Goals:** 见 proposal。缓存 budget 只约束新 history-media cache 的 encoded Data，不承诺整个进程 RSS ≤32 MiB；source icon、已有 browser snapshot cache、newly captured Data 及当前消费者解码的 NSImage 都在其外。当前正常 eager capture 和 V1 首次 inline decode 保留原行为。

## Decisions

### 1. Model 保留 runtime blob identity

增加内部 optional `persistedImageBlobID` / `persistedLinkImageBlobID`，构造器默认 nil，legacy decoder 初始化 nil；保持原 legacy CodingKeys，不把 runtime refs 当作新的 inline persistence 格式编码。正式 durable representation 仍由 V2 persisted item 管理。

`hasImagePayload` / `hasLinkImagePayload` 使用 Data-or-reference。Image key 优先 Data digest，次选 persisted ID，最后 `image:empty`。引用只能是已验证的 canonical ID；任何新 bytes 替换时清掉旧 ref，临时 materialization 若保留 ref则 bytes 必须与该 ID 一致。不要创建新 Data + 旧不一致 ID。

`storageOptimized` 对 reference-only media 不加载、不优化，原样传播 refs；对实际 Data 保留现有 pixel bounds，若转换 bytes，清除旧对应引用。`withLinkPreview` 的 nil image 参数视为未提供新 image，保留现有 Data/ref；非 nil 新 image 替换并清旧 link ref，image 主 payload ref始终传播。Title merge 沿现有有效 title 语义，不扩展清空接口。

替代方案只置 Data=nil 会将存在性与身份丢失；把 bytes 塞回 Store 会重新常驻，均不采用。

### 2. Persistence 与共享 blob primitive

提取一个 focused 内部 blob access primitive（可保留在 persistence 文件内部），由 persistence 持有 directory 和 injected `readData`；给 media actor 注入相同目录/reader 的 access value或 Sendable read closure。生产 Store 持有一个共享 loader供 card/paste/drag 使用；AppModel 是实际组装入口，必须把与 save worker 相同 persistence directory 的 loader 传入 Store，包括 DEBUG isolated verification 分支。给 AppModel 的现有 injected initializer 增加最小 media dependency 参数，controller integration tests 显式传入 temporary persistence 对应 loader；不能只在直接构造 Store 的单元测试中注入、而让 AppModel 路径回落到 shared 真实 history。

Primitive 提供 canonical ID validation 和 `loadBlobData(blobID:)`：仅 `[0-9a-f]` 的 64 个 ASCII 字符；path只能由 validated ID 拼成 `history-media/<id>.blob`；读后 hash 必须一致。复用现有 error semantics（invalid syntax/hash 使用 invalidBlob，filesystem failures 继续传播）；仅按需要放宽内部 error 可见性。不用 Unicode `isHexDigit` 作为 ASCII 限制，不复制 SHA256 read validation。Startup source icon cache 与 media LRU 分别持有其数据，复用该 primitive。

V2 decode 先验证所有三类引用语法，再映射 metadata、eager icons 和 heavy refs；heavy Data nil。保留 source icon missing/corrupt 的现有 eager decode-failure 行为，本次局部容错只针对 heavy media。Canonical missing/corrupt heavy files不进行 exists/read 检查，访问时才失败。

Save 分支：Data存在则沿原 `blobID(for:)` hash/verify-existing/repair；否则仅 validate 并复用 runtime ref，不检查存在、不读取、不 hash引用的文件。无 Data 且无 ref则 nil。invalid runtime ref使 save在写 manifest/GC前失败。Save snapshot正常携带 refs通过 coordinator/worker，GC依旧从已提交 manifest计算全部 references；不改变 generation、flush或 Quit handling。

Alternative schema V3/migration 无必要。对所有 materialized bytes 引入持久 identity reuse属于 Change 6，不采用。一个 ref既是 source icon又是 heavy payload时，eager icon访问不可避免读取同一物理文件；“零 heavy reads”指无 heavy-reference-driven reads，性能 fixture使用与 icon不重叠的 heavy IDs明确证明。

### 3. Actor + byte-cost LRU

新增 `actor ClipboardHistoryMediaLoader`，内部 budget为 `32 * 1024 * 1024`；tests可注入小 budget与 reader。`load(blobID:) async throws -> Data` 在 actor隔离的方法体内调用同步 shared primitive，不能是 MainActor或在 MainActor上的同步工作。Reader跨线程需有正确 Sendable boundary；计数 recorder使用锁保护，不能依赖未经同步的捕获变量。

一个字典加小规模 recency order与总 byte cost即可；key=ID、cost=Data.count，hit移至 newest，miss验证后插入，evict oldest直到≤budget。大于budget的单blob直接返回、不插入；失败不缓存、不过期重试计时、不网络修复。不加第三方库、不另做 actor-per-item或通用 cache framework。

Actor内部同步 read期间没有 suspension，自然序列化 miss/hit，无需独立 in-flight registry。进入 read前检查 cancellation；同步 filesystem read不保证中途可打断。消费者 completion后必须再次检查 cancellation和identity，因此取消后的 read即使完成也不能apply/paste；成功验证 bytes可留在bounded cache供后续使用。排队已取消请求不能启动新磁盘read。测试 barrier故意忽略取消，以证明消费者拒绝迟到结果，而非只证明 loader抛CancellationError。

### 4. Link preview用存在性，bytes仍按bytes处理

`visibleSelectedLinkURL`、`registerLinkMetadataIfNeeded`、`validatedSnapshotOutcome` 与 fallback eligibility改用`!hasLinkImagePayload`。`applyLinkMetadata` 根据 current item's semantic payload决定保留已有image/ref，不能用 nil Data误让新 metadata image覆盖已有 persisted preview，也不能归类为 successWithoutImage。现有metadata结果自身的 imageData nil检查仍有效；不机械替换日志和实际 bytes处理。

Restored URL+title+link ref在open/select/filter/reopen时 metadata/snapshot fetch=0；即使ref访问失败也不清ref或授权network fallback。Title-only update保留原ref，新明确preview替换清ref。未带preview的 restored URL仍走已有 metadata-before-fallback，new URL eager enrichment、single browser cleanup、TTL/cache contracts原样保留。

### 5. UI生命周期与布局

`panelVisible` 改为 `@Published private(set)`，由现有controller lifecycle更新。`BottomPanelView`传递read-only visibility与共享 loader给card；`ClipboardCardView.==`纳入visibility及下述授权 generation，避免`.equatable()`吞掉隐藏/显示更新。Card通过`.task(id:)`承载view-owned request，其identity至少覆盖item ID、两个blob refs、对应 inline Data 的变化及`panelVisible && !hidesPreview`；出现/消失可辅助管理card生命周期，但panel close必须由显式state撤销。

优先使用item实际Data，否则eligible时await loader。View仅持有当前显示所需的短生命周期decoded NSImage/临时结果，退出eligible、消失或改变payload时取消并清掉旧media state，避免retained hosting hierarchy累积全部浏览图片。Completion重新核对request token/identity、visibility、privacy及item仍在显示路径；close→reopen、filter out→in即使ID相同也不能接收旧task结果。同一 ID 的 ref A→inline bytes B、inline B→C（refs 均 nil）也必须使旧结果失效；采用现有值比较或局部 media identity，不在每次 body 重算中 hash 所有媒体。Completion 的 visibility 校验读取当前 Store 授权状态而非 task 捕获的旧 Bool；close→reopen 必须有可区分的授权 generation（由现有 panel lifecycle 同步推进，传给 card/task identity），不能仅依赖 SwiftUI 是否渲染过中间 false。不引入全局geometry追踪框架；继续使用现有LazyHStack display生命周期。

Image有payload即预留现有region；URL hasLinkImagePayload即固定105pt region及带图字号/行数/padding，pending显示ProgressView，failure显示稳定fallback而非无限spinner。Image dimensions使用实际临时image。Media获取不改变Store items、selectedID或触发任何save/enrichment。

Hide Previews限制UI preview加载；用户显式paste/drag仍可加载所需payload。这与现有privacy spec的actions remain available一致，不扩展为禁用全部clipboard行为或改变metadata network策略。

### 6. Paste边界及即时supersession

Store提供`materializedItemForPaste(_:) async throws -> ClipboardItem`：text/url/file、已有imageData直接返回；reference-only image await共享loader，构造临时copy，保留全部metadata且只提供验证后的imageData，不调用storageOptimized、不updateItem、不save。图像decode/write仍沿Store现有writeToPasteboard，失败不先清pasteboard。

Controller持有一个pending Task与monotonic request token。每个request首先cancel旧task/invalidate token、清旧feedback，立即捕获selected item+target；仅image需要async path，保留non-image和已有bytes的同步fast path。Materialization期间panel仍可见供Esc/close取消；completion回MainActor验证current token、!cancelled、panel仍处于授权visibility，才调用performer。Current failure使用现有restore message；stale failure不覆盖新feedback。

跨边界隐患：现有performer只在`paste()`开始supersede；B读取期间A的queued send/fallback仍可能触发。必须先写回归test（performer A pending/queued→lazy B开始或失败→执行A callback，send=0）。若该路径需要接入，最小暴露原有`supersedePendingAttempt()`的内部cancel入口，由controller在新request起点调用；不改cleanup/token/PID/350ms/activation逻辑，不提前发送伪paste或写空pasteboard。

Successful handoff前清pending task/token ownership，再同步调用performer并按原Bool成功close，close只取消未交接materialization，不撤销已接受performer。失败保持panel反馈。Task 只捕获请求值、loader/必要的 Store dependency 与 weak controller，禁止在 await 前 guard let self 后跨等待强持有 controller；completion 后才取 strong self 并验证 token。释放测试必须在放行 non-cooperative loader 之前断言 weak controller 已为 nil，再放行并断言零 writes/send。外部close/deinit使materialization失效；关闭再重开不恢复旧request。Request捕获item/target，不在await后重新取selectedItem。所有completion检查与handoff在MainActor上顺序执行，避免取消与write间竞态。

### 7. Drag提供真实image representation

新增 focused Support helper（例如 `ClipboardImageDragProvider`）负责 async representation、PNG conversion、Progress 与 completion arbitration；Card 仅调用 helper 发起用户 drag，不承载新增平台传输逻辑。`.image`先走现有NSImage provider（已有Data或匹配当前临时decoded image）；reference-only image创建`NSItemProvider`并register async data representation `UTType.png`，closure捕获blobID+loader，不捕获Store/Card state。Provider creation不load，接收方请求才await loader、SHA校验，确保representation与UTType一致再completion：PNG可直接返回，V2中由legacy migration保留的可解码非PNG bytes使用native image能力转为PNG；cache仍只存原始已校验blob bytes，转换结果不能以旧ID缓存（inline legacy仍可使用已有NSImage provider）；return Progress关联task取消，completion恰好一次。Missing/corrupt/不可解码返回error，任何image分支都不fallback NSString。Text/URL/file现有provider不改；preview hidden不阻止explicit drag。

### 8. 无人值守验收与自动报告

新增 focused runner `script/verify/history_media_acceptance.sh`，一条命令完成本 Change 的 required scenario suite 与既有全部gate，不需要用户按键、目视判断、勾选、切换display或批准系统权限。复用 Swift Testing、现有 AppKit hosting tests、`CopythatPanelTests`、`StorePanelWiringTests`、`PanelFrameCalculatorTests` 和 isolated packaged-app verify，不另建通用自动化框架。Hard-coded standalone driver如 `preview_live.sh` 若因loader依赖不能编译，最小更新source list并运行其self-test。

验收层次及自动oracle：

| 场景 | 自动执行与判定 | 证据边界 |
| --- | --- | --- |
| Card loading/success/failure、105pt布局、header与aspect ratio | 真实NSHostingView、固定fixture及可控loader，自动比较frame/布局度量；必要时保存fixture渲染图辅助诊断，图片本身不代替assertions | real-AppKit rendering，无人眼验收 |
| Retained hosting view close/reopen、Hidden滚动100张、filter/delete/evict | 驱动生产view/controller状态，等待task/checkpoint，断言read/save/apply counters与state释放 | real-AppKit lifecycle；非物理鼠标 |
| Return/Esc、double-click、selection/search/pinboard | 用本地NSEvent或窄test seam进入真实panel key routing/card gesture action及生产controller，断言paste request、close与mutation结果；gesture测试必须证明wiring，不只直调独立callback | synthetic input，无global CGEvent/TCC依赖 |
| Lazy image paste、cancel、新request覆盖、target缺失 | 真实materialization→performer.paste→named pasteboard，注入activation/fallback/send以执行旧callback并计数 | real pasteboard restore；Command-V发送行为为synthetic boundary |
| Accessibility允许/拒绝 | 最小新增performer trust-check closure，默认仍 `AccessibilityService.requestIfNeeded`；测试注入true/false，实际调用 `paste()` 并检查restored payload、message、send count及不调用prompt | injected permission state，不宣称真实TCC授予/撤销 |
| Image drag与failure/cancel | 真实NSItemProvider的async image representation由test receiver请求，检查UTType/decoded pixels、错误及completion次数 | real provider transfer，无第三方应用鼠标拖拽 |
| Multi-display | 扩展现有frame fixtures（负坐标、上下排列、不同visibleFrame/缩放参数），自动断言布局边界；仅已有生产代码支持的缩放参数作覆盖，不新增显示器管理功能 | synthetic screen geometry，不宣称物理多屏操作 |
| Startup与保存/GC | temporary目录、isolated defaults、500-item fixtures、read/commit/delete recorder与worker flush | real persistence，无真实用户数据 |

Controller/performer的依赖注入只用于既有平台边界（media、trust check、activation/send），不得改变生产默认行为、paste safety、350ms/observer/token核心，也不应为测试复制一个替代业务实现。异步测试使用continuation/checkpoint与可控late completion；bounded timeout用于失败诊断，不用固定sleep充当同步证明。AppKit操作在MainActor且相关window tests串行，测试窗口与进程清理只针对本run所有权。

Runner自动发现已有Swift toolchain/Testing.framework及可用Pillow Python环境，沿用项目相同checks，禁止弹出权限prompt、等待stdin或依赖外部网站、第三方target应用。实际GUI/window-server session是native AppKit gate的运行前提；若当前机器不具备，runner自动报告blocked并非零退出，不暂停等人操作、不把required case标skip/pass。可在具备GUI session的macOS执行环境无人值守运行。

每次run在 `.build/history-media-acceptance/<run-id>/` 生成 `report.json`、`summary.md`、command logs和必要fixture诊断。报告绑定UTC时间、HEAD、source fingerprint（相关Sources/Tests/script/Package.swift及本Change产物）、commands/exit codes、scenario IDs、expected/observed counters或layout metrics与evidence type。Required cases全部通过且全部gate退出0才总体passed；failed/timeout/blocked/not-covered/missing evidence中任一required状态都非零退出并不得勾选任务。未覆盖的真实TCC对话框、物理键鼠/第三方接收app/物理多屏列为边界说明，不是等待人工补充的required任务，也不能拿synthetic结果当其覆盖证据。失败与提前退出同样输出报告并清理隔离资源；敏感payload不写报告。

## Risks / Trade-offs

- [GC/read竞态] → 当前manifest还引用的blob不会删；item被移除后GC可让尚未开始的read失败。UI忽略失效card，drag/paste访问按既有local failure处理，不复活item或加新disk retention协议。
- [cache eviction无法回收消费者引用] → encoded cache严格计费，view state主动释放；active paste/drag可暂持bytes，大blob不cache。profile说明这个边界而不宣称进程总内存有硬上限。
- [actor中的同步read不立刻响应cancel] → caller token/eligibility检查是可靠边界，tests使用delayed non-cooperative completion；不将Task.cancel等同于停止磁盘syscall。
- [测试原全等断言依赖eager restore] → 必须同时保留metadata/identity/source icon assertions并新增materialization bytes校验；corrupt-byte repair、failed save、GC ordering、legacy/Quit tests不能因lazy而删除。
- [UI harness只测predicate不能证明wiring] → automated retained NSHostingView/card tasks测试实际read counts、布局及late-state rejection；panel integration验证真实controller/key handling与action wiring。报告标记real-AppKit或synthetic boundary，不用source-string检查或仅执行onPaste closure替代行为断言。
- [首次可见媒体增加等待] → 固定placeholder与shared cache保持布局；不增加启动预读或hidden-panel预热。

## Migration Plan

无schema bump、数据rewrite或额外migration。V2直接改变runtime解读；legacy首次decode仍inline，成功保存后自然用V2。先落地model/persistence/loader，再接link/UI/paste/drag，最后跑完整gate。

回滚runtime改动可继续读取相同V2 manifest/blob layout，旧版本回到eager restore；合法missing/corrupt heavy blob旧版本仍可能让整个history decode失败，这是旧行为，不以本Change静默修复或删reference。发布前以isolated temporary directory/UserDefaults、named NSPasteboard验证；不触碰用户Application Support历史或真实系统pasteboard。
