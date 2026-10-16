#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/.build/module-cache"
swiftc -swift-version 5 -parse-as-library -module-cache-path "$ROOT/.build/module-cache" \
  "$ROOT/Sources/Models.swift" "$ROOT/Sources/Localization.swift" "$ROOT/Sources/PDFService.swift" "$ROOT/Sources/PDFInteraction.swift" "$ROOT/Tests/PDFTests.swift" \
  -o "$ROOT/.build/pdf-tests" -framework SwiftUI -framework AppKit -framework PDFKit -framework Vision -framework NaturalLanguage
"$ROOT/.build/pdf-tests" "$@"
swiftc -swift-version 5 -parse-as-library -module-cache-path "$ROOT/.build/module-cache" \
  "$ROOT/Sources/Models.swift" "$ROOT/Sources/Localization.swift" "$ROOT/Sources/Engine.swift" \
  "$ROOT/Sources/AppModel.swift" "$ROOT/Sources/PDFService.swift" "$ROOT/Sources/PDFReader.swift" \
  "$ROOT/Sources/PDFInteraction.swift" "$ROOT/Sources/ReaderBridge.swift" "$ROOT/Tests/PlaybackTests.swift" \
  -o "$ROOT/.build/playback-tests" -framework SwiftUI -framework AppKit -framework WebKit -framework AVFoundation -framework PDFKit -framework Vision -framework NaturalLanguage
"$ROOT/.build/playback-tests"
