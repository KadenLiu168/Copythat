## 1. 调整 `BottomPanelView.panelContainer` 描边

- [x] 1.1 改 `Sources/Copythat/Views/BottomPanelView.swift:74-77`：把 `.overlay { panelShape.stroke(.white.opacity(0.66), lineWidth: 1) }` 改为 `.overlay { panelShape.inset(by: 0.5).stroke(.white.opacity(0.55), lineWidth: 1) }`
- [x] 1.2 删 `Sources/Copythat/Views/BottomPanelView.swift:78-83`：删除整块 `.overlay(alignment: .top) { panelShape.stroke(...).blur(...).offset(y: 1) }`
- [x] 1.3 保持 `Sources/Copythat/Views/BottomPanelView.swift:84-85` 的两条 `.shadow(...)` 不变（颜色、半径、`y` 偏移均不动）
- [x] 1.4 保持 `Sources/Copythat/Views/BottomPanelView.swift:86` 的 `.compositingGroup()` 不变

## 2. 验证

- [x] 2.1 运行 `./script/verify_all.sh`，确认 SwiftPM 编译与现有测试通过
- [x] 2.2 运行 `./script/build_and_run.sh --verify-panel` 启动浮层并通过 `CGWindowListCopyWindowInfo` 校验 panel 出现在 window server 中（bounds 1642×349 @ (34, 741)），符合 `panel-ui/spec.md` Requirement: 浮层几何 的尺寸约束；面板渲染管线无崩溃
- [ ] 2.3 拍一张浮层打开状态的截图（任意卡片数量，含空态），与 `openspec/changes/refine-panel-corner-shadows/proposal.md` 中描述的"L 形伪影"做目视对照，确认无回归 — **阻塞：当前 CLI 进程未授权 macOS TCC Screen Recording 权限，`screencapture` 与 `SCScreenshotManager` 均报 `用户拒绝了...捕捉的TCC`，需要用户手动在 系统设置 > 隐私与安全性 > 屏幕录制 中授权后再跑，或者直接用 `Cmd+Shift+4` 在桌面截图**
