## 1. 调整 `textPreview` 排版参数

- [x] 1.1 改 `Sources/Copythat/Views/ClipboardCardView.swift` 中 `textPreview` 的 `Text(item.preview).font(...)`：`size: 16` → `size: 13`，`weight: .regular` 保持
- [x] 1.2 改同 `Text` 的 `.lineSpacing(3)` → `.lineSpacing(1.5)`
- [x] 1.3 改同 `Text` 的 `.lineLimit(7)` → `.lineLimit(8)`

## 2. 移除 `textPreview` 中废弃修饰符

- [x] 2.1 删 `Sources/Copythat/Views/ClipboardCardView.swift` 中 `textPreview` 的 `.mask(LinearGradient(...))` 整段（含 `stops` 三元组、`startPoint` / `endPoint`）
- [x] 2.2 删同视图的 `.fixedSize(horizontal: false, vertical: false)` 调用

## 3. 验证

- [x] 3.1 运行 `./script/verify_all.sh`，确认 SwiftPM 编译与现有测试通过、视觉未引入回归
