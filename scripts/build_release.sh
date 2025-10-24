#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWIFT_DIR="$ROOT_DIR/macOSApp"
PYTHON_DIR="$ROOT_DIR/python"
DIST_DIR="$ROOT_DIR/dist"
APP_TARGET="WallpaperControlApp"
APP_DISPLAY_NAME="AuraFlow"
APP_BUNDLE="$DIST_DIR/${APP_DISPLAY_NAME}.app"
APP_ZIP="$DIST_DIR/${APP_DISPLAY_NAME}.zip"
APP_DMG="$DIST_DIR/${APP_DISPLAY_NAME}.dmg"
ICON_PNG="$ROOT_DIR/Resources/AppIcon.png"
ICON_ICNS="$ROOT_DIR/Resources/AppIcon.icns"
PYTHON_BIN="${PYTHON_BUILD_PYTHON:-/usr/bin/python3}"

log() {
  printf '[build] %s\n' "$1"
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

build_swift_app() {
  log "Building Swift target"
  pushd "$SWIFT_DIR" >/dev/null
  swift build -c release

  local arm_binary="$SWIFT_DIR/.build/arm64-apple-macosx/release/${APP_TARGET}"
  local x86_binary="$SWIFT_DIR/.build/x86_64-apple-macosx/release/${APP_TARGET}"
  local universal_dir="$SWIFT_DIR/.build/universal"

  if command -v arch >/dev/null 2>&1; then
    if arch -x86_64 swift build -c release >/dev/null 2>&1; then
      log "Built x86_64 slice"
    else
      log "[warn] Failed to build x86_64 slice (Rosetta required). Using arm64 only."
    fi
  else
    log "[warn] 'arch' command not found; building arm64 slice only."
  fi

  local bin_path
  if [[ -f "$arm_binary" && -f "$x86_binary" ]]; then
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
  <string>com.example.auraflow</string>
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
    local venv="$ROOT_DIR/.build-venv"
    "$PYTHON_BIN" -m venv "$venv"
    source "$venv/bin/activate"
    pip install --upgrade pip >/dev/null
    pip install -r "$PYTHON_DIR/requirements.txt" --target "$py_dir/site-packages" >/dev/null
    deactivate
    rm -rf "$venv"
  fi
}

apply_plist_customizations() {
  local plist="$APP_BUNDLE/Contents/Info.plist"
  plist_set_string "$plist" CFBundleName "$APP_DISPLAY_NAME"
  plist_set_string "$plist" CFBundleDisplayName "$APP_DISPLAY_NAME"
  plist_set_string "$plist" CFBundleIdentifier "com.example.auraflow"
  plist_set_bool "$plist" LSUIElement true

  /usr/libexec/PlistBuddy -c "Delete :LSEnvironment" "$plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :LSEnvironment dict" "$plist"
  /usr/libexec/PlistBuddy -c "Add :LSEnvironment:PYTHON_EXECUTABLE string /usr/bin/python3" "$plist"

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
  log "DMG готов: $APP_DMG"
}

main() {
  prepare_environment
  build_swift_app
  sync_python_payload
  apply_plist_customizations
  package_distribution
  log "Готово: $APP_BUNDLE"
  log "Архивы: $APP_ZIP и $APP_DMG"
}

main "$@"
