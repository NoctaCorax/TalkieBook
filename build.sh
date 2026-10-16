#!/bin/bash
set -euo pipefail
APP_SOURCE="$(cd "$(dirname "$0")" && pwd)"
APP_OUTPUT="${1:-$APP_SOURCE/dist/TalkieBook.app}"
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
mkdir -p "$APP_OUTPUT/Contents/MacOS" "$APP_OUTPUT/Contents/Resources" "$APP_SOURCE/.build/module-cache"
swiftc -swift-version 5 -parse-as-library -O -target arm64-apple-macos14.0 \
  -module-cache-path "$APP_SOURCE/.build/module-cache" "$APP_SOURCE"/Sources/*.swift \
  -o "$APP_OUTPUT/Contents/MacOS/TalkieBook" -framework SwiftUI -framework WebKit -framework AVFoundation -framework AppKit
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
cp "$APP_SOURCE/LICENSE" "$APP_SOURCE/THIRD_PARTY_NOTICES.md" "$APP_OUTPUT/Contents/Resources/"
if [ -f "$APP_SOURCE/Resources/TalkieBook.icns" ]; then cp "$APP_SOURCE/Resources/TalkieBook.icns" "$APP_OUTPUT/Contents/Resources/"; fi
xattr -cr "$APP_OUTPUT"
xattr -d com.apple.FinderInfo "$APP_OUTPUT" 2>/dev/null || true
codesign --force --deep --sign - "$APP_OUTPUT"
printf 'Application built: %s\n' "$APP_OUTPUT"
