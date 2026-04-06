#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWIFT_DIR="$ROOT_DIR/macOSApp"
PYTHON_DIR="$ROOT_DIR/python"
DIST_DIR="$ROOT_DIR/dist"
APP_TARGET="WallpaperControlApp"
APP_DISPLAY_NAME="AuraFlow"
APP_VERSION="${AURAFLOW_VERSION:-1.2.1}"
APP_BUILD="${AURAFLOW_BUILD:-3}"
APP_BUNDLE="$DIST_DIR/${APP_DISPLAY_NAME}.app"
APP_ZIP="$DIST_DIR/${APP_DISPLAY_NAME}.zip"
APP_DMG="$DIST_DIR/${APP_DISPLAY_NAME}.dmg"
ICON_PNG="$ROOT_DIR/Resources/AppIcon.png"
ICON_ICNS="$ROOT_DIR/Resources/AppIcon.icns"
PYTHON_BIN="${PYTHON_BUILD_PYTHON:-/usr/bin/python3}"
BUILD_UNIVERSAL="${BUILD_UNIVERSAL:-1}"
REQUIRE_UNIVERSAL="${REQUIRE_UNIVERSAL:-0}"
PYTHON_RUNTIME_BUNDLING="${PYTHON_RUNTIME_BUNDLING:-1}"
FFMPEG_RUNTIME_BUNDLING="${FFMPEG_RUNTIME_BUNDLING:-1}"
REQUIRE_FFMPEG_RUNTIME="${REQUIRE_FFMPEG_RUNTIME:-0}"
FFMPEG_BIN="${AURAFLOW_FFMPEG_BIN:-}"
FFPROBE_BIN="${AURAFLOW_FFPROBE_BIN:-}"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
CODESIGN_KEYCHAIN_PATH="${CODESIGN_KEYCHAIN_PATH:-}"
REQUIRE_CODESIGN="${REQUIRE_CODESIGN:-0}"
LOCK_DIR="$ROOT_DIR/.build-lock"

log() {
  printf '[build] %s\n' "$1"
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    log "Required command not found: $1"
    exit 1
  fi
}

cleanup_lock() {
  rm -rf "$LOCK_DIR"
}

acquire_lock() {
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    log "Another build is already running. Stop it first or remove $LOCK_DIR"
    exit 1
  fi
  trap cleanup_lock EXIT
}

plist_set_string() {
  local plist="$1"
  local key="$2"
  local value="$3"
  /usr/libexec/PlistBuddy -c "Set :${key} ${value}" "$plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Add :${key} string ${value}" "$plist"
}

plist_set_bool() {
  local plist="$1"
  local key="$2"
  local value="$3"
  /usr/libexec/PlistBuddy -c "Set :${key} ${value}" "$plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Add :${key} bool ${value}" "$plist"
}

ensure_icon() {
  if [[ -f "$ICON_ICNS" ]]; then
    return
  fi

  if [[ ! -f "$ICON_PNG" ]]; then
    log "Icon not found. Place AppIcon.png or AppIcon.icns under Resources/ before building."
    exit 1
  fi

  if ! command -v iconutil >/dev/null 2>&1; then
    log "iconutil not available. Install Xcode command line tools."
    exit 1
  fi

  tmpdir="$(mktemp -d)"
  iconset="$tmpdir/AppIcon.iconset"
  mkdir -p "$iconset"

  for size in 16 32 64 128 256 512; do
    for scale in 1 2; do
      scaled=$((size * scale))
      name="icon_${size}x${size}"
      if [[ "$scale" -eq 2 ]]; then
        name+="@2x"
      fi
      sips -z "$scaled" "$scaled" "$ICON_PNG" --out "$iconset/${name}.png" >/dev/null
    done
  done

  iconutil -c icns "$iconset" -o "$ICON_ICNS"
  rm -rf "$tmpdir"
  log "Generated AppIcon.icns from AppIcon.png"
}

prepare_environment() {
  rm -rf "$DIST_DIR"
  mkdir -p "$DIST_DIR"
}

resolve_python_framework_root() {
  "$PYTHON_BIN" - <<'PY'
from pathlib import Path
import sys

base_prefix = Path(sys.base_prefix).expanduser().resolve()
for candidate in (base_prefix, *base_prefix.parents):
    if candidate.name.endswith(".framework"):
        print(candidate)
        raise SystemExit(0)

raise SystemExit("Unable to locate Python framework root for bundling.")
PY
}

resolve_optional_binary() {
  local env_override="$1"
  shift

  local candidate=""
  if [[ -n "$env_override" ]]; then
    candidate="$env_override"
  else
    for candidate in "$@"; do
      if [[ -x "$candidate" ]]; then
        printf '%s\n' "$candidate"
        return 0
      fi
    done
    return 1
  fi

  if [[ -x "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  return 1
}

build_swift_app() {
  log "Building Swift target"
  pushd "$SWIFT_DIR" >/dev/null
  swift build -c release

  local arm_binary="$SWIFT_DIR/.build/arm64-apple-macosx/release/${APP_TARGET}"
  local x86_binary="$SWIFT_DIR/.build/x86_64-apple-macosx/release/${APP_TARGET}"
  local universal_dir="$SWIFT_DIR/.build/universal"
  local built_x86="0"

  if [[ "$BUILD_UNIVERSAL" == "1" ]] && command -v arch >/dev/null 2>&1; then
    log "Building x86_64 slice (Rosetta may be required)"
    if arch -x86_64 swift build -c release; then
      log "Built x86_64 slice"
      built_x86="1"
    else
      if [[ "$REQUIRE_UNIVERSAL" == "1" ]]; then
        log "Failed to build x86_64 slice and REQUIRE_UNIVERSAL=1 is set."
        exit 1
      fi
      log "[warn] Failed to build x86_64 slice. Using arm64 only."
    fi
  elif [[ "$BUILD_UNIVERSAL" != "1" ]]; then
    log "Skipping x86_64 build (BUILD_UNIVERSAL=$BUILD_UNIVERSAL)"
  else
    if [[ "$REQUIRE_UNIVERSAL" == "1" ]]; then
      log "'arch' command not found and REQUIRE_UNIVERSAL=1 is set."
      exit 1
    fi
    log "[warn] 'arch' command not found; building arm64 slice only."
  fi

  local bin_path
  if [[ "$built_x86" == "1" && -f "$arm_binary" && -f "$x86_binary" ]]; then
    mkdir -p "$universal_dir"
    lipo -create -output "$universal_dir/${APP_TARGET}" "$arm_binary" "$x86_binary"
    bin_path="$universal_dir"
    log "Created universal binary"
  elif [[ -f "$arm_binary" ]]; then
    bin_path="$(dirname "$arm_binary")"
  else
    bin_path=$(swift build -c release --show-bin-path)
  fi
  popd >/dev/null

  local binary="$bin_path/${APP_TARGET}"
  local resources_bundle="$bin_path/${APP_TARGET}_${APP_TARGET}.bundle"

  if [[ ! -x "$binary" ]]; then
    log "Не найден бинарник ($binary)"
    exit 1
  fi

  rm -rf "$APP_BUNDLE"
  mkdir -p "$APP_BUNDLE/Contents/MacOS"
  mkdir -p "$APP_BUNDLE/Contents/Resources"

  cp "$binary" "$APP_BUNDLE/Contents/MacOS/${APP_TARGET}"
  chmod +x "$APP_BUNDLE/Contents/MacOS/${APP_TARGET}"

  if [[ "$REQUIRE_UNIVERSAL" == "1" ]]; then
    local archs
    archs="$(lipo -archs "$APP_BUNDLE/Contents/MacOS/${APP_TARGET}" 2>/dev/null || true)"
    if [[ "$archs" != *"arm64"* || "$archs" != *"x86_64"* ]]; then
      log "Universal build required, but produced architectures were: ${archs:-unknown}"
      exit 1
    fi
  fi

  if [[ -d "$resources_bundle" ]]; then
    cp -R "$resources_bundle" "$APP_BUNDLE/Contents/Resources/${APP_TARGET}.bundle"
  fi

  cat > "$APP_BUNDLE/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>WallpaperControlApp</string>
  <key>CFBundleIdentifier</key>
  <string>com.andrijvergeles.auraflow</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>AuraFlow</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
EOF
}

sync_python_payload() {
  local resources_dir="$APP_BUNDLE/Contents/Resources"
  local py_dir="$resources_dir/Python"
  mkdir -p "$py_dir"
  rsync -a --delete "$PYTHON_DIR/" "$py_dir/"

  if [[ -f "$PYTHON_DIR/requirements.txt" ]]; then
    log "Vendoring Python dependencies"
    local venv="$ROOT_DIR/.build-venv-$$"
    rm -rf "$venv"
    "$PYTHON_BIN" -m venv "$venv"
    source "$venv/bin/activate"
    python -m pip install --upgrade pip
    python -m pip install --prefer-binary -r "$PYTHON_DIR/requirements.txt" --target "$py_dir/site-packages"
    deactivate
    rm -rf "$venv"
  fi
}

sync_python_runtime() {
  if [[ "$PYTHON_RUNTIME_BUNDLING" != "1" ]]; then
    log "Skipping bundled Python runtime (PYTHON_RUNTIME_BUNDLING=$PYTHON_RUNTIME_BUNDLING)"
    return
  fi

  local framework_root
  framework_root="$(resolve_python_framework_root)"
  if [[ -z "$framework_root" || ! -d "$framework_root" ]]; then
    log "Bundled Python runtime not found for $PYTHON_BIN"
    exit 1
  fi

  local frameworks_dir="$APP_BUNDLE/Contents/Frameworks"
  local bundled_framework="$frameworks_dir/$(basename "$framework_root")"
  mkdir -p "$frameworks_dir"
  rsync -a --delete \
    --exclude '__pycache__' \
    --exclude 'test' \
    --exclude 'tests' \
    "$framework_root/" "$bundled_framework/"
}

sync_ffmpeg_runtime() {
  if [[ "$FFMPEG_RUNTIME_BUNDLING" != "1" ]]; then
    log "Skipping bundled ffmpeg runtime (FFMPEG_RUNTIME_BUNDLING=$FFMPEG_RUNTIME_BUNDLING)"
    return
  fi

  local ffmpeg_path=""
  local ffprobe_path=""

  ffmpeg_path="$(resolve_optional_binary "$FFMPEG_BIN" \
    "/opt/homebrew/bin/ffmpeg" \
    "/usr/local/bin/ffmpeg" \
    "/usr/bin/ffmpeg" \
  )" || true
  if [[ -z "$ffmpeg_path" ]]; then
    ffmpeg_path="$(command -v ffmpeg 2>/dev/null || true)"
  fi
  ffprobe_path="$(resolve_optional_binary "$FFPROBE_BIN" \
    "/opt/homebrew/bin/ffprobe" \
    "/usr/local/bin/ffprobe" \
    "/usr/bin/ffprobe" \
  )" || true
  if [[ -z "$ffprobe_path" ]]; then
    ffprobe_path="$(command -v ffprobe 2>/dev/null || true)"
  fi

  if [[ -z "$ffmpeg_path" || -z "$ffprobe_path" ]]; then
    local message="Bundled ffmpeg runtime not found."
    if [[ "$REQUIRE_FFMPEG_RUNTIME" == "1" ]]; then
      log "$message"
      log "Set AURAFLOW_FFMPEG_BIN and AURAFLOW_FFPROBE_BIN or install ffmpeg locally."
      exit 1
    fi
    log "[warn] $message Build will fall back to system ffmpeg if available on the user's Mac."
    return
  fi

  local bin_dir="$APP_BUNDLE/Contents/Resources/bin"
  mkdir -p "$bin_dir"
  cp "$ffmpeg_path" "$bin_dir/ffmpeg"
  cp "$ffprobe_path" "$bin_dir/ffprobe"
  chmod +x "$bin_dir/ffmpeg" "$bin_dir/ffprobe"
}

codesign_args() {
  local args=(
    --force
    --sign "$CODESIGN_IDENTITY"
    --timestamp
  )
  if [[ -n "$CODESIGN_KEYCHAIN_PATH" ]]; then
    args+=(--keychain "$CODESIGN_KEYCHAIN_PATH")
  fi
  printf '%s\n' "${args[@]}"
}

prepare_bundle_for_codesign() {
  if [[ -z "$CODESIGN_IDENTITY" ]]; then
    if [[ "$REQUIRE_CODESIGN" == "1" ]]; then
      log "REQUIRE_CODESIGN=1 but CODESIGN_IDENTITY is not set."
      exit 1
    fi
    return 0
  fi

  require_command codesign
  if command -v xattr >/dev/null 2>&1; then
    xattr -cr "$APP_BUNDLE" || true
  fi
  find "$APP_BUNDLE" -type d -name "_CodeSignature" -prune -exec rm -rf {} +
}

find_macho_files() {
  while IFS= read -r -d '' candidate; do
    if /usr/bin/file -b "$candidate" 2>/dev/null | grep -q "Mach-O"; then
      printf '%s\n' "$candidate"
    fi
  done < <(find "$APP_BUNDLE" -type f -print0)
}

codesign_target() {
  local target="$1"
  shift || true
  local args=()
  while IFS= read -r arg; do
    args+=("$arg")
  done < <(codesign_args)
  if [[ "$#" -gt 0 ]]; then
    args+=("$@")
  fi
  codesign "${args[@]}" "$target"
}

sign_app_bundle() {
  prepare_bundle_for_codesign
  if [[ -z "$CODESIGN_IDENTITY" ]]; then
    return 0
  fi

  log "Signing app bundle"
  while IFS= read -r target; do
    codesign_target "$target"
  done < <(find_macho_files)

  if [[ -d "$APP_BUNDLE/Contents/Frameworks" ]]; then
    while IFS= read -r framework; do
      codesign_target "$framework"
    done < <(find "$APP_BUNDLE/Contents/Frameworks" -mindepth 1 -maxdepth 1 -type d \( -name "*.framework" -o -name "*.bundle" \) | sort)
  fi

  codesign_target "$APP_BUNDLE" --options runtime
  codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
}

sign_disk_image() {
  if [[ -z "$CODESIGN_IDENTITY" ]]; then
    return 0
  fi

  log "Signing DMG"
  codesign_target "$APP_DMG"
}

apply_plist_customizations() {
  local plist="$APP_BUNDLE/Contents/Info.plist"
  plist_set_string "$plist" CFBundleName "$APP_DISPLAY_NAME"
  plist_set_string "$plist" CFBundleDisplayName "$APP_DISPLAY_NAME"
  plist_set_string "$plist" CFBundleIdentifier "com.andrijvergeles.auraflow"
  plist_set_string "$plist" CFBundleShortVersionString "$APP_VERSION"
  plist_set_string "$plist" CFBundleVersion "$APP_BUILD"
  plist_set_bool "$plist" LSUIElement true

  ensure_icon
  cp "$ICON_ICNS" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
  plist_set_string "$plist" CFBundleIconFile "AppIcon"
}

package_distribution() {
  log "Создание ZIP архива"
  pushd "$DIST_DIR" >/dev/null
  ditto -c -k --keepParent "${APP_DISPLAY_NAME}.app" "$(basename "$APP_ZIP")"
  popd >/dev/null

  log "Создание DMG"
  local dmg_stage="$DIST_DIR/.dmg-stage"
  rm -rf "$dmg_stage"
  mkdir -p "$dmg_stage"
  cp -R "$APP_BUNDLE" "$dmg_stage/${APP_DISPLAY_NAME}.app"
  ln -s /Applications "$dmg_stage/Applications"

  hdiutil create -volname "$APP_DISPLAY_NAME" \
    -srcfolder "$dmg_stage" \
    -ov -format UDZO "$APP_DMG" >/dev/null

  rm -rf "$dmg_stage"
  sign_disk_image
  log "DMG готов: $APP_DMG"
}

main() {
  acquire_lock
  prepare_environment
  build_swift_app
  sync_python_payload
  sync_python_runtime
  sync_ffmpeg_runtime
  apply_plist_customizations
  sign_app_bundle
  package_distribution
  log "Готово: $APP_BUNDLE"
  log "Архивы: $APP_ZIP и $APP_DMG"
}

main "$@"
