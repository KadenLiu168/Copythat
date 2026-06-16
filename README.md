# Copythat

Copythat 是一个原生 macOS 剪贴板历史应用，常驻菜单栏，支持全局快捷键、底部浮动面板、搜索、置顶、自定义 Pinboard，以及文本、URL、图片和文件捕获。

## 安装步骤

1. 打开 DMG 后，将 `Copythat.app` 拖入 `Applications`。
2. 打开 `Applications`，按住 Control 点击 `Copythat`，然后选择 `Open`。
3. 如果 macOS 阻止打开应用，请前往 System Settings > Privacy & Security，允许 Copythat 运行。
4. 打开 Copythat 设置，在 Permissions 中授予 Accessibility 权限。授予后，选择剪贴板历史项目时，Copythat 才能粘贴回上一个应用。

当前 DMG 是临时分享版本，已经用于临时分发签名，但尚未经过 Apple notarization。因此首次打开时，macOS 可能要求你通过 Control-click 或 Privacy & Security 手动确认。

## 当前版本主要功能

- 菜单栏常驻剪贴板历史应用。
- 使用全局快捷键打开底部浮动剪贴板面板。
- 搜索剪贴板历史。
- 捕获文本、URL、图片和文件类型的剪贴板内容。
- 置顶重要剪贴板项目。
- 创建和筛选自定义 Pinboard。
- 选择历史项目后恢复内容；授予 Accessibility 权限后可粘贴回上一个应用。
- 隐私开关：隐藏或恢复当前可见卡片预览。
- 支持开机登录和快捷键设置。

## Developer Notes

## Run

Use the Codex Run action, or run:

```sh
./script/build_and_run.sh
```

The script builds the SwiftPM app, stages `dist/Copythat.app`, and opens it as a menu bar resident app.

### Local signing for Accessibility testing

`dist/Copythat.app` uses ad hoc signing by default. That is enough to launch the app, but macOS Accessibility trust can be unstable across rebuilds because the ad hoc code hash changes.

For local development, create a self-signed Code Signing certificate in Keychain Access:

1. Open Keychain Access.
2. Choose Keychain Access > Certificate Assistant > Create a Certificate.
3. Set Name to `Copythat Local Code Signing`.
4. Set Identity Type to `Self Signed Root`.
5. Set Certificate Type to `Code Signing`.
6. Create it in the `login` keychain and set it to Always Trust if macOS asks.

After this certificate exists, `./script/build_and_run.sh` automatically uses it. You can also set the identity explicitly:

```sh
export CODESIGN_IDENTITY="Copythat Local Code Signing"
./script/build_and_run.sh
```

To force the old ad hoc fallback for comparison:

```sh
CODESIGN_IDENTITY=- ./script/build_and_run.sh
```

To inspect the staged app signature:

```sh
./script/build_and_run.sh --verify-signature
```

If you switch from ad hoc signing to local signing, remove the old Copythat entry from System Settings > Privacy & Security > Accessibility once, rebuild with `CODESIGN_IDENTITY`, grant Accessibility to `dist/Copythat.app`, rebuild again, then retry double-click or Return paste. The repeated permission prompt should stop as long as the app path, bundle identifier, and signing identity stay stable.

### Clipboard diagnostics

Clipboard capture diagnostics are hidden and off by default. Enable them when investigating source attribution, pasteboard change-count ordering, or same-content de-duplication:

```sh
defaults write local.copythat.clipboard clipboardDiagnosticsEnabled -bool true
```

Run Copythat from `dist/Copythat.app`, then stream the diagnostic events:

```sh
/usr/bin/log stream --style compact --level info --predicate 'process == "Copythat" && category == "ClipboardDiagnostics"'
```

The diagnostics intentionally avoid raw clipboard payloads. Use `source`, `contentLength`, `contentKeyDigest`, `duplicateCount`, `duplicateIDs`, `beforeCount`, and `afterCount` to determine whether a capture inserted a new card or replaced an existing same-content card.

Disable diagnostics after the investigation:

```sh
defaults delete local.copythat.clipboard clipboardDiagnosticsEnabled
```

## Development Guidelines

- Keep UI native to macOS: prefer system materials, semantic colors, system accent color, and compact controls over fixed custom palettes.
- Keep SwiftUI views focused on presentation and user actions. Put pasteboard parsing, source attribution, paste execution, window control, and other AppKit/CoreGraphics boundaries in `Services` or `Support`.
- Keep copy source tracking non-persistent. New items should continue to use `ClipboardItem.sourceApp` and `sourceAppIconData`; source resolution belongs in `CopySourceTracker` and `CopySourceResolution`.
- Preserve real domain terms such as paste, pasteboard, copy, cut, and source. Do not mechanically rename them away.
- Verify changes with `swift build`, `./script/verify_all.sh`, and targeted manual checks for panel UI, search, pinboards, horizontal scrolling, and paste flow.

## Verify

Run the full local check:

```sh
./script/verify_all.sh
```

This verifies:

- Swift build
- bottom panel frame calculation for compact, desktop, wide, and simulated multi-display visible areas
- bottom panel window creation in the staged menu bar app
- stable content keys for image history de-duplication
- pasteboard writes preserve existing contents when an item cannot be restored, including missing file items
- paste target filtering so Copythat and SystemUIServer are not selected as paste destinations
- paste decisions do not send Cmd+V without a valid target app
- 5,000 item history filtering performance
- generated app icon sizes
- staged menu bar app launch and bundle metadata

Manual checks still needed on a real Mac session:

- Grant Accessibility access to `dist/Copythat.app` from Copythat Settings > Permissions or System Settings to allow automatic paste after selecting an item. Without that permission, the app still copies the selected item and shows a permission message.
- Check the selected global shortcut on the target Mac. If macOS rejects the shortcut, Copythat Settings shows an inline warning and the menu bar icon remains available.
- Toggle Launch at login from Copythat Settings on the target Mac. If macOS rejects the change, the app restores the previous value and shows an inline warning.
- Check the panel on a physical multi-display setup. The frame calculator is covered with simulated left and right display bounds, but this machine only has one display attached.

## Temporary DMG for sharing

Create a release app bundle and DMG for a trusted tester:

```sh
./script/package_dmg.sh
```

The DMG is written to `dist/Copythat.dmg`. This is a temporary sharing build, not an Apple-notarized release, so the recipient may need to Control-click Copythat and choose Open, or allow it in System Settings > Privacy & Security. The recipient still needs to grant Accessibility permission before Copythat can paste selected history items into other apps.
