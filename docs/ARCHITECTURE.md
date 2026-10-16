# Architecture

## Native application

SwiftUI implements the library, reader chrome, and settings. AppKit provides file dialogs; AVFoundation plays generated audio. `AppModel.swift` owns state and playback. `Models.swift` defines data saved atomically as JSON under Application Support. EPUB CFIs locate text independently of page layout.

## EPUB reader

`ReaderBridge.swift` hosts WKWebView with a restricted `talkiebook://` resource handler, without an HTTP server. Main-frame messages update native state. `reader.js` integrates foliate-js, maps Polish sentences to DOM ranges and CFIs, and draws overlays without rewriting the original text.

Segmentation uses `Intl.Segmenter` with abbreviation handling and length limits for speech fragments. Highlighting is sentence-level. A content security policy blocks book scripts and remote resources. Not every EPUB layout or embedded-media feature is supported.

## Speech

`Engine.swift` exchanges line-delimited JSON with a persistent Python worker over pipes. Piper and the model load lazily once per worker session. A small look-ahead queue generates sentence audio; highlights follow actual playback.

The MC Speech A2 preset uses length scale 1.16, noise scale 0.667, and noise-W scale 0.8. User speed is applied by the player. A text-and-preset hash identifies cached audio, with an approximately 750 MB disk limit. Generation tokens discard obsolete work. Browsing and narration positions are tracked separately.

## Packaging

`scripts/setup-engine.sh` downloads build dependencies into ignored directories. `build.sh` compiles native sources, copies the runtime and voice, and applies an ad hoc signature. The repository excludes user books, caches, model weights, virtualenvs, and app bundles. Dependencies retain their own licenses.
