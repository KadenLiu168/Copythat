#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_DIR="$(mktemp -d -t copythat_packaging_fixtures)"
MOCK_BIN="$TEST_DIR/bin"
FAILURES=0

cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

mkdir -p "$MOCK_BIN"

cat >"$MOCK_BIN/swift" <<'MOCK'
#!/usr/bin/env bash
if [[ "$*" == *"--show-bin-path"* ]]; then
  printf '%s\n' "$COPYTHAT_FIXTURE_BUILD_DIR"
fi
MOCK

cat >"$MOCK_BIN/security" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK

cat >"$MOCK_BIN/codesign" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK

cat >"$MOCK_BIN/pkill" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK

cat >"$MOCK_BIN/open" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK

cat >"$MOCK_BIN/cat" <<'MOCK'
#!/usr/bin/env bash
case "${COPYTHAT_FIXTURE_INVALID_ICON:-0}" in
  1) /usr/bin/sed 's#<string>AppIcon</string>#<string>WrongIcon</string>#' ;;
  2) /usr/bin/sed '/<key>CFBundleIconFile<\/key>/{N;d;}' ;;
  *) /bin/cat ;;
esac
MOCK

cat >"$MOCK_BIN/spctl" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK

cat >"$MOCK_BIN/awk" <<'MOCK'
#!/usr/bin/env bash
if [[ "$*" == *"substr"* ]]; then
  printf '%s\n' "$COPYTHAT_PACKAGE_FIXTURE_ROOT/Volumes/Copythat"
else
  /usr/bin/awk "$@"
fi
MOCK

cat >"$MOCK_BIN/hdiutil" <<'MOCK'
#!/usr/bin/env bash
case "$1" in
  create)
    exit 0
    ;;
  attach)
    volume="$COPYTHAT_PACKAGE_FIXTURE_ROOT/Volumes/Copythat"
    mkdir -p "$volume"
    cp -R "$COPYTHAT_PACKAGE_FIXTURE_ROOT/dist/Copythat.app" "$volume/Copythat.app"
    ln -s /Applications "$volume/Applications"
    printf '## 安装步骤\n## 当前版本主要功能\n' >"$volume/README.md"
    printf '/dev/disk9 Apple_HFS %s\n' "$volume"
    ;;
  detach)
    rm -rf "$COPYTHAT_PACKAGE_FIXTURE_ROOT/Volumes/Copythat"
    ;;
esac
MOCK

chmod +x "$MOCK_BIN"/*
export PATH="$MOCK_BIN:$PATH"

new_build_fixture() {
  local name="$1"
  local layout="$2"
  local app_icon="$3"
  local source_icon="${4:-1}"
  local fixture_root="$TEST_DIR/$name"
  local build_dir="$fixture_root/build"
  local resource_bundle="$build_dir/Copythat_Copythat.bundle"

  mkdir -p "$fixture_root/script" "$fixture_root/Sources/Copythat/Resources" \
    "$resource_bundle" "$build_dir"
  cp "$ROOT_DIR/script/build_and_run.sh" "$fixture_root/script/build_and_run.sh"
  printf 'fixture executable\n' >"$build_dir/Copythat"
  if [ "$source_icon" = "1" ]; then
    printf 'fixture icon\n' >"$fixture_root/Sources/Copythat/Resources/AppIcon.icns"
  fi

  case "$layout" in
    flat)
      printf 'menu icon\n' >"$resource_bundle/MenuBarIconTemplate.png"
      printf 'preserve me\n' >"$resource_bundle/fixture-marker.txt"
      ;;
    nested)
      mkdir -p "$resource_bundle/Contents/Resources"
      printf 'menu icon\n' >"$resource_bundle/Contents/Resources/MenuBarIconTemplate.png"
      printf 'preserve me\n' >"$resource_bundle/Contents/Resources/fixture-marker.txt"
      ;;
    missing)
      ;;
  esac

  COPYTHAT_FIXTURE_BUILD_DIR="$build_dir" \
    COPYTHAT_FIXTURE_INVALID_ICON="$app_icon" \
    "$fixture_root/script/build_and_run.sh" --verify-signature >"$fixture_root/output.log" 2>&1
}

expect_build_success() {
  local name="$1"
  local layout="$2"
  local fixture_root="$TEST_DIR/$name"
  local marker_path="fixture-marker.txt"
  if [ "$layout" = "nested" ]; then
    marker_path="Contents/Resources/fixture-marker.txt"
  fi
  if new_build_fixture "$name" "$layout" 0; then
    local staged_bundle="$fixture_root/dist/Copythat.app/Contents/Resources/Copythat_Copythat.bundle"
    if [ -f "$staged_bundle/$marker_path" ]; then
      echo "build_and_run $layout resource fixture ok"
    else
      echo "build_and_run $layout did not preserve the resource bundle" >&2
      FAILURES=$((FAILURES + 1))
    fi
    /usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' \
      "$fixture_root/dist/Copythat.app/Contents/Info.plist" | grep -Fxq AppIcon || {
      echo "build_and_run $layout wrote invalid icon metadata" >&2
      FAILURES=$((FAILURES + 1))
    }
    [ -f "$fixture_root/dist/Copythat.app/Contents/Resources/AppIcon.icns" ] || {
      echo "build_and_run $layout omitted AppIcon.icns" >&2
      FAILURES=$((FAILURES + 1))
    }
  else
    echo "build_and_run rejected the $layout resource fixture" >&2
    cat "$fixture_root/output.log" >&2
    FAILURES=$((FAILURES + 1))
  fi
}

expect_build_failure() {
  local name="$1"
  local layout="$2"
  local app_icon="$3"
  local expected_message="$4"
  local source_icon="${5:-1}"
  local fixture_root="$TEST_DIR/$name"
  if new_build_fixture "$name" "$layout" "$app_icon" "$source_icon"; then
    echo "build_and_run unexpectedly accepted $name" >&2
    FAILURES=$((FAILURES + 1))
  else
    if grep -Fq "$expected_message" "$fixture_root/output.log"; then
      echo "build_and_run rejected $name fixture"
    else
      echo "build_and_run rejected $name for an unexpected reason" >&2
      cat "$fixture_root/output.log" >&2
      FAILURES=$((FAILURES + 1))
    fi
  fi
}

expect_package_result() {
  local name="$1"
  local layout="$2"
  local expected="$3"
  local expected_message="${4:-}"
  local fixture_root="$TEST_DIR/$name"
  local resource_bundle="$fixture_root/dist/Copythat.app/Contents/Resources/Copythat_Copythat.bundle"
  local status=0

  mkdir -p "$fixture_root/script" "$resource_bundle" "$fixture_root/dist" \
    "$fixture_root/Sources/Copythat/Resources"
  cp "$ROOT_DIR/script/package_dmg.sh" "$fixture_root/script/package_dmg.sh"
  cat >"$fixture_root/script/build_and_run.sh" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK
  chmod +x "$fixture_root/script/build_and_run.sh"
  cat >"$fixture_root/README.md" <<'README'
## 安装步骤
## 当前版本主要功能
## Developer Notes
README
  mkdir -p "$fixture_root/dist/Copythat.app/Contents/MacOS"
  printf 'fixture executable\n' >"$fixture_root/dist/Copythat.app/Contents/MacOS/Copythat"

  case "$layout" in
    flat)
      printf 'menu icon\n' >"$resource_bundle/MenuBarIconTemplate.png"
      ;;
    nested)
      mkdir -p "$resource_bundle/Contents/Resources"
      printf 'menu icon\n' >"$resource_bundle/Contents/Resources/MenuBarIconTemplate.png"
      ;;
    missing)
      ;;
  esac

  COPYTHAT_PACKAGE_FIXTURE_ROOT="$fixture_root" \
    "$fixture_root/script/package_dmg.sh" >"$fixture_root/output.log" 2>&1 || status=$?

  if [ "$expected" = "success" ] && [ "$status" -eq 0 ]; then
    echo "package_dmg $layout resource fixture ok"
  elif [ "$expected" = "failure" ] && [ "$status" -ne 0 ]; then
    if grep -Fq "$expected_message" "$fixture_root/output.log"; then
      echo "package_dmg rejected missing resource fixture"
    else
      echo "package_dmg rejected $layout for an unexpected reason" >&2
      cat "$fixture_root/output.log" >&2
      FAILURES=$((FAILURES + 1))
    fi
  else
    echo "package_dmg $layout fixture returned $status, expected $expected" >&2
    /bin/cat "$fixture_root/output.log" >&2
    FAILURES=$((FAILURES + 1))
  fi
}

expect_build_success build_flat flat
expect_build_success build_nested nested
expect_build_failure build_missing_resource missing 0 "Missing SwiftPM resource bundle"
expect_build_failure build_missing_icon flat 0 "Missing app icon source" 0
expect_build_failure build_invalid_icon flat 1 "CFBundleIconFile must be AppIcon"
expect_build_failure build_missing_icon_metadata flat 2 "Missing CFBundleIconFile"

expect_package_result package_flat flat success
expect_package_result package_nested nested success
expect_package_result package_missing missing failure "Missing packaged SwiftPM resources"

if [ "$FAILURES" -ne 0 ]; then
  echo "$FAILURES packaging fixture(s) failed" >&2
  exit 1
fi

echo "packaging fixtures passed"
