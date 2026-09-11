#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

swift build
SWIFT_PATH="$(xcrun --find swift 2>/dev/null || command -v swift)"
SWIFT_ROOT="$(cd "$(dirname "$SWIFT_PATH")/../.." && pwd)"
SWIFT_FRAMEWORKS="$SWIFT_ROOT/Library/Developer/Frameworks"
SWIFT_TEST_FLAGS=()
if [[ -d "$SWIFT_FRAMEWORKS/Testing.framework" ]]; then
    SWIFT_TEST_FLAGS=(-Xswiftc -F -Xswiftc "$SWIFT_FRAMEWORKS")
fi
swift test "${SWIFT_TEST_FLAGS[@]}"
SOURCE_RESOLUTION_BIN="$(mktemp -t copythat_source_resolution)"
swiftc Sources/Copythat/Support/CopySourceResolution.swift script/verify/source_resolution.swift -o "$SOURCE_RESOLUTION_BIN"
"$SOURCE_RESOLUTION_BIN"
rm -f "$SOURCE_RESOLUTION_BIN"
./script/verify/source_attribution_timing_test.sh

python3 - <<'PY'
from pathlib import Path
from PIL import Image

expected = {16, 32, 64, 128, 256, 512, 1024}
found = set()
for path in Path("Sources/Copythat/Resources/Assets.xcassets/AppIcon.appiconset").glob("icon_*.png"):
    image = Image.open(path)
    assert image.size[0] == image.size[1], path
    found.add(image.size[0])

missing = expected - found
assert not missing, f"missing icon sizes: {sorted(missing)}"

transparent = Image.open("Sources/Copythat/Resources/AppIcon-transparent.png").convert("RGBA")
assert transparent.size == (1024, 1024), transparent.size
assert transparent.getpixel((0, 0))[3] == 0, "transparent icon corner is opaque"

print("icons ok", sorted(found))
PY

./script/build_and_run.sh --verify
./script/build_and_run.sh --verify-portable
./script/build_and_run.sh --verify-panel

python3 - <<'PY'
import plistlib
from pathlib import Path

info = plistlib.loads(Path("dist/Copythat.app/Contents/Info.plist").read_bytes())
assert info["CFBundlePackageType"] == "APPL", info
assert info["CFBundleName"] == "Copythat", info
assert info["CFBundleExecutable"] == "Copythat", info
assert info["CFBundleIdentifier"] == "local.copythat.clipboard", info
assert info["LSUIElement"] is True, "Copythat should run as a menu bar resident app"
assert "NSAppleEventsUsageDescription" in info, info
assert "NSScreenCaptureUsageDescription" not in info, info
print("bundle ok", info["CFBundleIdentifier"], "LSUIElement", info["LSUIElement"])
PY

codesign_info="$(codesign -dv --verbose=4 dist/Copythat.app 2>&1)"
grep -q "Runtime Version" <<<"$codesign_info"
