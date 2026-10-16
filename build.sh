#!/bin/bash
set -euo pipefail
APP_SOURCE="$(cd "$(dirname "$0")" && pwd)"
APP_OUTPUT="${1:-$APP_SOURCE/dist/TalkieBook.app}"
case "$APP_OUTPUT" in
  *.app) ;;
  *) printf '%s\n' 'Output path must end in .app.' >&2; exit 1 ;;
esac
# Build and sign outside Finder-managed folders to avoid resource-fork metadata.
BUILD_OUTPUT="$(mktemp -d /private/tmp/talkiebook-build.XXXXXX)/TalkieBook.app"
FINAL_OUTPUT="$APP_OUTPUT"
APP_OUTPUT="$BUILD_OUTPUT"
trap 'rm -rf "$(dirname "$BUILD_OUTPUT")"' EXIT
PIPER_ROOT="${TALKIEBOOK_PIPER_ROOT:-$APP_SOURCE/.build/engine}"
PY_BASE="${TALKIEBOOK_PYTHON_BASE:-}"
if [ -z "$PY_BASE" ]; then
  PY_BIN="$(find "$APP_SOURCE/.build/python" -path '*/bin/python3.12' -type f 2>/dev/null | head -n 1 || true)"
  if [ -n "$PY_BIN" ]; then PY_BASE="$(dirname "$(dirname "$PY_BIN")")"; fi
fi
if [ -z "$PY_BASE" ] || [ ! -x "$PY_BASE/bin/python3.12" ] || [ ! -d "$PIPER_ROOT/.venv/lib/python3.12/site-packages" ]; then
  printf '%s\n' 'Build dependencies are missing. Run bash scripts/setup-engine.sh first.' >&2
  exit 1
fi
if [ "$(uname -s)" != Darwin ] || [ "$(uname -m)" != arm64 ]; then
  printf '%s\n' 'Building the app currently requires Apple Silicon macOS.' >&2
  exit 1
fi
bash "$APP_SOURCE/scripts/setup-updater.sh"
mkdir -p "$APP_OUTPUT/Contents/Frameworks"
ditto "$APP_SOURCE/.build/sparkle/Sparkle.framework" "$APP_OUTPUT/Contents/Frameworks/Sparkle.framework"
mkdir -p "$APP_OUTPUT/Contents/MacOS" "$APP_OUTPUT/Contents/Resources" "$APP_SOURCE/.build/module-cache"
swiftc -swift-version 5 -parse-as-library -O -target arm64-apple-macos14.0 \
  -module-cache-path "$APP_SOURCE/.build/module-cache" "$APP_SOURCE"/Sources/*.swift \
  -F "$APP_SOURCE/.build/sparkle" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  -o "$APP_OUTPUT/Contents/MacOS/TalkieBook" -framework SwiftUI -framework WebKit -framework AVFoundation -framework AppKit -framework PDFKit -framework Vision -framework NaturalLanguage
rsync -a --delete "$APP_SOURCE/Resources/Web/" "$APP_OUTPUT/Contents/Resources/Web/"
mkdir -p "$APP_OUTPUT/Contents/Resources/Engine/python/bin" "$APP_OUTPUT/Contents/Resources/Engine/python/lib/python3.12"
rsync -a "$APP_SOURCE/Resources/Engine/" "$APP_OUTPUT/Contents/Resources/Engine/"
cp "$PY_BASE/bin/python3.12" "$APP_OUTPUT/Contents/Resources/Engine/python/bin/python3.12"
if [ -d "$PY_BASE/licenses" ]; then rsync -a "$PY_BASE/licenses/" "$APP_OUTPUT/Contents/Resources/Engine/python/licenses/"; fi
rsync -a --exclude=site-packages --exclude=__pycache__ --exclude=test --exclude=tests --exclude=idlelib --exclude=ensurepip \
  "$PY_BASE/lib/python3.12/" "$APP_OUTPUT/Contents/Resources/Engine/python/lib/python3.12/"
rsync -a --exclude=__pycache__ --exclude=tests --exclude=pip --exclude='pip-*.dist-info' \
  "$PIPER_ROOT/.venv/lib/python3.12/site-packages/" "$APP_OUTPUT/Contents/Resources/Engine/python/lib/python3.12/site-packages/"
cp "$PIPER_ROOT/voices/pl_PL-mc_speech-medium.onnx" "$PIPER_ROOT/voices/pl_PL-mc_speech-medium.onnx.json" "$APP_OUTPUT/Contents/Resources/Engine/"
cp "$APP_SOURCE/Info.plist" "$APP_OUTPUT/Contents/Info.plist"
if [ -d "$APP_SOURCE/Resources/Localization" ]; then rsync -a "$APP_SOURCE/Resources/Localization/" "$APP_OUTPUT/Contents/Resources/"; fi
if [ -d "$APP_SOURCE/Resources/Licenses" ]; then rsync -a "$APP_SOURCE/Resources/Licenses/" "$APP_OUTPUT/Contents/Resources/Licenses/"; fi
cp "$APP_SOURCE/LICENSE" "$APP_SOURCE/THIRD_PARTY_NOTICES.md" "$APP_OUTPUT/Contents/Resources/"
if [ -f "$APP_SOURCE/Resources/TalkieBook.icns" ]; then cp "$APP_SOURCE/Resources/TalkieBook.icns" "$APP_OUTPUT/Contents/Resources/"; fi
xattr -cr "$APP_OUTPUT"
xattr -d com.apple.FinderInfo "$APP_OUTPUT" 2>/dev/null || true
# Sparkle includes nested helper applications and XPC services.
find "$APP_OUTPUT/Contents/Frameworks/Sparkle.framework" -type f -perm -111 -print0 | while IFS= read -r -d '' binary; do
  if file "$binary" | grep -q 'Mach-O'; then codesign --force --sign - "$binary"; fi
done
codesign --force --deep --sign - "$APP_OUTPUT"
mkdir -p "$(dirname "$FINAL_OUTPUT")"
if [ -e "$FINAL_OUTPUT" ]; then rm -rf "$FINAL_OUTPUT"; fi
ditto --norsrc --noextattr "$APP_OUTPUT" "$FINAL_OUTPUT"
printf 'Application built: %s\n' "$FINAL_OUTPUT"
