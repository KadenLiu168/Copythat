## Context

动机与四项范围见 `proposal.md`。本设计涉及 model / Store 边界、媒体身份和粘贴恢复，因此需要 design，即使没有规格行为变更。

`ClipboardItem` 是值类型，组织信息可变，媒体及标题等字段目前为 `let`。三个模型操作通过全字段 initializer 重建值；`ClipboardStore.materializedItemForPaste` 也抄写同样字段以放入临时恢复 bytes。Initializer 的 `mediaBlobID(known:data:)` 在已知地址缺失且存在 bytes 时建立身份。直接把这些重建改为赋值而忽略这一点，会使 storage optimization 的新 bytes 带着旧地址。

`CopySourceResolutionTests` 已测试部分 slot 优先级，但独立 verifier 还包含 change-count 配对、stale shortcut 和 source-candidate 排除用例。`verify_all.sh` 已执行整个 Swift Testing suite，随后又单独编译执行 verifier；source-attribution timing gate 则验证不同的职责，需要保留。

`emitLinkPreview` 没有调用者，实际事件路径是 `logLinkPreview`。`runDeferredLinkPreviewReconcile` 只转发到 `performLinkPreviewReconcile`；其调用所在的 `defer` 才是 mutation 完成后 reconciliation 的语义边界。

## Goals / Non-Goals

**Goals:**

- 让既有项的变换默认保留所有未修改字段，避免新增字段时逐个更新 copy argument lists。
- 将媒体 bytes / ID 的变换留在模型内，沿用 PreparedMedia 与已有身份建立机制。
- 保留 standalone verifier 的全部断言语义后，统一到 Swift Testing 一个执行入口。
- 删除两个已证实重复的实现，不扩展到其他清理项。

**Non-Goals:**

- 不改变 raw construction 的 trusted-known-ID 契约，不在复制时添加额外 digest 验证。
- 不将所有模型字段改为外部可变，不引入通用 patch closure、builder、媒体存储模型或协议。
- 不重构 capture factories、编码算法、save worker、media loader、source tracker 或粘贴协调状态机。
- 不将自动化结果视为物理桌面、真实 TCC 或第三方接收应用的证据；不取消既有手工验证义务。

## Decisions

### D1: 使用模型内部的值复制，而不是另一套全字段 copy initializer

`storageOptimized`、`withLinkPreview`、`releasingResidentMedia` 从 `var copy = self` 开始，仅修改各自拥有的字段并返回 copy。仅这些操作需要修改的 `title`、`linkTitle`、heavy-media bytes 和对应 blob ID 改为 `private(set) var`；来源名称、来源图标及身份、UUID、创建时间和其他不变字段继续保持不可变。既有 `isPinned` / `pinboardName` 修改方式不变。

Store 不直接赋值媒体字段。为临时粘贴恢复增加一个窄的模型操作，接收可信的 `PreparedMedia`，复制原项并成对替换 image bytes / ID。Store 仍先从相同 loader 获取当前 blob 的 verified bytes，并执行原有可解码检查，再用已知 blob ID 构造 PreparedMedia 转交模型。该操作不执行读盘、hash、decode、encode、保存或 UI 状态修改。

替代方案：通用 copy helper 仍需要一份完整字段列表，且 optional 参数容易混淆「保持」与「清空」；公开 setter 会允许媒体字段脱离身份独立修改；把每项替换迁移到通用媒体对象会扩大数据模型和持久化改动。均不采用。

### D2: 显式保留每种变换的现有语义

| 操作 | 必须保持的行为 |
| --- | --- |
| Storage optimization | reference-only 保持引用；无 payload 保持无 payload；优化失败清除 bytes 与 ID；输出 bytes 相同保持旧 ID；不同 bytes 建立一次新的匹配地址。原有 1,200 / 640px 编码路径不变。 |
| Link preview | `title` 使用传入 title，nil 时保持原展示 title；`linkTitle` 按现有实现赋传入值，包括 nil；nil PreparedMedia 保持现有 preview bytes / ID，非 nil 成对替换。调用方的 merged-title 策略不变。 |
| Durable release | 每个媒体角色独立判断 resident bytes 与 durable identity 是否匹配；匹配只释放 bytes，保留地址；无任何释放仍返回 nil。 |
| Paste materialization | 仅对未加载的 image 生成临时有 bytes 的副本；保留所有 metadata 和已知 ID；原始项与 Store history 不被修改；loader 失败或不可解码保持现有错误路径。 |

Optimization 是最容易丢失 initializer 隐含行为的位置：继续使用模型已有 `mediaBlobID(known:data:)` 身份规则，将优化结果的 bytes 与其最终地址一起赋给 copy。不能把 helper 返回的 nil「待建立地址」直接写入有 bytes 的模型，也不能沿用已被替换 bytes 的旧地址。已知地址转发与 release / preview / materialization 不增加 hash。保留 CodingKeys、legacy decoder、合成 encode 与 Equatable 的外部语义。

替代方案：统一规定 nil 一律清空或一律保留，虽然实现短，却改变不同操作的既有契约；重新 hash 每个 copy 能掩盖身份错误，但违反零重复 hash 保证。均不采用。

### D3: 先迁移断言，再移除 standalone source verifier

迁移到 `Tests/CopythatTests/CopySourceResolutionTests.swift`，使用固定 `now`，通过真实 `CopySourceResolution` API 断言 slot、index 和 candidate 结果，不再复制 verifier 的 `resolvedName` 包装。已有等价测试可以复用，但必须覆盖每个原 precondition 的输入语义：

- fresh shortcut 优先、无 shortcut 的 current foreground、first-observed 优先、recent foreground fallback、stale shortcut 不被接受、System shortcut、system-generated fallback、无候选 unknown；System shortcut 的名称属于 snapshot 内容，slot 必须仍为 shortcut。
- 使用 baseline counts 10 / 12 的两条 snapshot：current count 12 选择较早已写入的 snapshot，13 选择较晚已写入的 snapshot；无 baseline 的 legacy single-change 路径选最早 fresh snapshot；stale snapshot 被忽略并保留原数组 index。
- 排除当前 Copythat PID、SystemUIServer、不同 PID 的 Copythat bundle；接受普通用户应用。

在这些断言经 Swift Testing 验证后，删除 verifier 文件与 verify_all 的临时二进制编译 / 执行 / 删除段。保留整套 swift tests 的工具链 framework lookup、source-attribution timing gate、图标和 packaged-app 验证。删除不是移除 source resolution gate，而是让其由已有完整 suite 承担。

替代方案：直接删除独立 verifier 会丢失覆盖；保留两套同职责 runner 则继续重复维护；把 `resolvedName` 搬进生产代码只为测试增加不必要 API。均不采用。

### D4: 删除代码，但保留所有真实边界

删除未调用的 private `emitLinkPreview`，不改 `logLinkPreview`、event sink、JSON 结构、默认关闭开关或 payload-safety。将 `runDeferredLinkPreviewReconcile()` 在原 defer 内替换为 `performLinkPreviewReconcile()`，然后移除包装；必须保持先设置 `isMutatingHistoryState = false` 再调用。不得把 reconcile 移入 mutation body 或增加异步调度。

`publishReleasedResidentMedia` 是 class private setter 与 extension 的访问边界，不属于本次转发删除。验收 runner、AcceptanceMetrics、hash counters、DI、LRU 和现有 source-icon cache 工作也全部保持。

替代方案：为 diagnostics 的两份短 jsonLine 引入序列化协议，或顺便减少 Store 边界 helper，都会超出这次已证实重复的范围，不采用。

## Risks / Trade-offs

- [值复制跳过 initializer 的身份建立] -> 以 optimization 的相同 bytes、不同 bytes、失败、reference-only 用例验证 bytes / ID 配对；复用实际 hash counters 区分 identity 与 integrity 工作。
- [复制少改字段却改变 nil 语义] -> 对 preview title / linkTitle / PreparedMedia 的 nil 组合写精确断言，不根据注释推断行为；保持 source icon 与组织信息。
- [private setter 修改影响 Codable] -> 保留 keys 和 decoder，验证 inline legacy round-trip、runtime BlobID 不进入 inline encoding，以及 V2 保存 / 重载兼容。
- [删除 verifier 丢掉独有断言] -> 删除前按 D3 完成断言映射并跑 targeted tests；验证 verify_all 仍执行这些 tests 且 timing gate 保持。
- [reconcile 顺序改变导致重复或 stale apply] -> 保持 defer 的同步顺序，运行 orchestration / cancellation / removal / lazy-link tests，验证一次最终状态 reconciliation 和现有 at-most-one fallback 保证。
- [跨 change 的未提交改动混入清理] -> 不编辑 CopySourceTracker、其 cache tests 或另一个 change 的产物；以本 Change 的目标文件和 diff 审查界定修改，不重置已有工作。
- [减少代码却削弱验证隔离] -> 复用 named pasteboards、临时 persistence 和 isolated defaults；运行 broad gates 前检查其隔离，保留 required checks 与报告能力。环境不足作为 blocker，不以跳过测试替代通过。

## Migration Plan

无数据迁移。先补回归测试与 source-resolution 覆盖，再做模型局部 refactor、两个删除和 verification 入口合并，最后跑完整验证。部署保持现有 app 构建流程；回滚仅恢复这些实现及 verifier gate，不转换历史文件。验收证据放在 `.build/verification/` 或 `/tmp/`，结论在会话中报告。
