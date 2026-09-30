#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# Tracked text must not record machine-local home paths. git grep reports
# matches on exit 0, no matches on exit 1, and any other status means the gate
# itself could not run.
home_root="/Users"
home_path_pattern="${home_root}/[A-Za-z0-9._-]+/"
home_path_status=0
home_path_matches="$(git grep -nIE "$home_path_pattern" -- .)" || home_path_status=$?

if [ "$home_path_status" -eq 0 ]; then
    printf 'Tracked files must not contain absolute home-directory paths:\n%s\n' "$home_path_matches"
    exit 1
fi

if [ "$home_path_status" -ne 1 ]; then
    printf 'Home-directory path gate failed to run: git grep exited with status %s\n' "$home_path_status" >&2
    exit "$home_path_status"
fi

./script/verify/openspec_artifact_hygiene.sh
./script/verify/openspec_artifact_hygiene_test.sh

./script/verify/packaging_test.sh

swift build
SWIFT_PATH="$(xcrun --find swift 2>/dev/null || command -v swift)"
SWIFT_ROOT="$(cd "$(dirname "$SWIFT_PATH")/../.." && pwd)"
SWIFT_FRAMEWORKS="$SWIFT_ROOT/Library/Developer/Frameworks"
if [[ -d "$SWIFT_FRAMEWORKS/Testing.framework" ]]; then
    swift test -Xswiftc -F -Xswiftc "$SWIFT_FRAMEWORKS"
else
    swift test
fi
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
assert info["CFBundleIconFile"] == "AppIcon", info
assert info["LSUIElement"] is True, "Copythat should run as a menu bar resident app"
assert "NSAppleEventsUsageDescription" in info, info
assert "NSScreenCaptureUsageDescription" not in info, info
resources = Path("dist/Copythat.app/Contents/Resources")
assert (resources / "AppIcon.icns").is_file(), "missing outer AppIcon.icns"
resource_bundle = resources / "Copythat_Copythat.bundle"
resource_locations = (
    resource_bundle / "MenuBarIconTemplate.png",
    resource_bundle / "Contents/Resources/MenuBarIconTemplate.png",
)
assert any(path.is_file() for path in resource_locations), (
    f"missing MenuBarIconTemplate.png in supported SwiftPM locations: {resource_locations}"
)
print("bundle ok", info["CFBundleIdentifier"], "LSUIElement", info["LSUIElement"])
PY

codesign_info="$(codesign -dv --verbose=4 dist/Copythat.app 2>&1)"
grep -q "Runtime Version" <<<"$codesign_info"
