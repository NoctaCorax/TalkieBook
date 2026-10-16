#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCHIVE="${1:?Usage: prepare-update.sh /path/to/TalkieBook.dmg [output-directory]}"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Info.plist")
OUTPUT="${2:-$ROOT/.build/release-$VERSION}"
bash "$ROOT/scripts/setup-updater.sh"
mkdir -p "$OUTPUT" "$ROOT/updates"
cp "$ARCHIVE" "$OUTPUT/$(basename "$ARCHIVE")"
"$ROOT/.build/sparkle/bin/generate_appcast" --account app.talkiebook.updates \
  --download-url-prefix "https://github.com/NoctaCorax/TalkieBook/releases/download/v$VERSION/" \
  --maximum-deltas 0 --link https://github.com/NoctaCorax/TalkieBook "$OUTPUT"
"$ROOT/.build/sparkle/bin/sign_update" --account app.talkiebook.updates --verify "$OUTPUT/appcast.xml"
cp "$OUTPUT/appcast.xml" "$ROOT/updates/appcast.xml"
printf '%s\n' 'Signed feed prepared. Publish the release assets first, then publish updates/appcast.xml.'
