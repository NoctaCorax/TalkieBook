#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/.build/sparkle"
VERSION=2.10.0
SHA=c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c
if [ -d "$DEST/Sparkle.framework" ] && [ "$(cat "$DEST/.talkiebook-version" 2>/dev/null || true)" = "$VERSION" ]; then exit 0; fi
STAGE="$(mktemp -d /private/tmp/talkiebook-sparkle.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
curl --fail --location --retry 3 "https://github.com/sparkle-project/Sparkle/releases/download/$VERSION/Sparkle-$VERSION.tar.xz" -o "$STAGE/sparkle.tar.xz"
printf '%s\n' "$SHA  $STAGE/sparkle.tar.xz" | shasum -a 256 -c -
mkdir -p "$DEST"
tar -xJf "$STAGE/sparkle.tar.xz" -C "$DEST"
printf '%s\n' "$VERSION" > "$DEST/.talkiebook-version"
