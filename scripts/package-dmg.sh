#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/dist/TalkieBook.app}"
OUTPUT="${2:-$ROOT/dist/TalkieBook-1.2.0-arm64.dmg}"
if [ ! -f "$APP/Contents/MacOS/TalkieBook" ]; then printf '%s\n' 'Build TalkieBook.app first.' >&2; exit 1; fi
STAGE="$(mktemp -d /private/tmp/talkiebook-dmg.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
ditto --norsrc --noextattr "$APP" "$STAGE/TalkieBook.app"
ln -s /Applications "$STAGE/Applications"
xattr -cr "$STAGE/TalkieBook.app"
codesign --force --deep --sign - "$STAGE/TalkieBook.app"
codesign --verify --deep --strict "$STAGE/TalkieBook.app"
mkdir -p "$(dirname "$OUTPUT")"
hdiutil create -volname TalkieBook -srcfolder "$STAGE" -ov -format UDZO "$OUTPUT"
