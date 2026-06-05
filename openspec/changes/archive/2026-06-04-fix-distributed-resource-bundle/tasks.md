## 1. Package SwiftPM Resources

- [x] 1.1 Update resource loading and packaging verification so `Copythat_Copythat.bundle` is used from `dist/Copythat.app/Contents/Resources`; verify the bundle contains `MenuBarIconTemplate.png` at that path after packaging.
- [x] 1.2 Add a packaging verification mode that launches a copied app while the repo-local SwiftPM resource bundle is unavailable; verify the copied app starts without `.build` resources.

## 2. Review Similar Install-Location Issues

- [x] 2.1 Search runtime and packaging code for hardcoded development paths or resource locations; fix any same-class issue found and record the result.

Review result: no other runtime or packaging dependency on repo-local `.build` paths was found. The only hardcoded `/Users/kaden/...` occurrence is sample preview text in `ClipboardItem.sample`, not an install-location dependency.
- [x] 2.2 Include the portable packaging check in the full verification script; verify `swift build` and `./script/verify_all.sh` cover the distribution resource contract.
