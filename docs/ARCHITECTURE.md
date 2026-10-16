# Architecture

## Native application

SwiftUI implements the library, reader chrome, and settings. AppKit provides file dialogs; AVFoundation plays generated audio. `AppModel.swift` owns state and playback. `Models.swift` defines data saved atomically as JSON under Application Support. EPUB CFIs locate text independently of page layout.

## EPUB reader

`ReaderBridge.swift` hosts WKWebView with a restricted `talkiebook://` resource handler, without an HTTP server. Main-frame messages update native state. `reader.js` integrates foliate-js, maps Polish sentences to DOM ranges and CFIs, and draws overlays without rewriting the original text.

Segmentation uses `Intl.Segmenter` with abbreviation handling and length limits for speech fragments. Highlighting is sentence-level. A content security policy blocks book scripts and remote resources. Not every EPUB layout or embedded-media feature is supported.

## PDF reader

`PDFService.swift` uses PDFKit to extract document text, normalizes layout whitespace while retaining UTF-16 source offsets, and uses NaturalLanguage sentence tokenization. Repeated short lines near page margins and page numbers are removed heuristically before sentence splitting. Each sentence stores its speech text and page rectangles. Pages without sufficient text use local Apple Vision OCR. Import is serialized off the main thread; opening an older PDF index upgrades only that book in the background and remaps saved positions and annotations.

`PDFReader.swift` implements the shared `ReaderControlling` command interface with a native PDFView and a read-only NSTextView. A transparent interaction surface maps hover, click and context-menu events to sentence rectangles in both views, while modifier keys and scroll events continue to reach native text/PDF interactions. Stable `pdf:page:sentence` locators connect playback, search and annotations across the original and text views. Highlight overlays modify the in-memory document only; the imported source is never rewritten. The original PDF and `pdf-index.json` stay together in the book directory. An optional format field preserves decoding of existing EPUB libraries.

## Localization

English and Polish native `.lproj/Localizable.strings` resources are bundled with the app. `Localization.swift` resolves the persistent app language override; SwiftUI receives the selected locale. Stable stored status/sort identifiers and user content remain unchanged. Interface language is independent of the bundled Polish speech model.

## Speech

`Engine.swift` exchanges line-delimited JSON with a persistent Python worker over pipes. Piper and the model load lazily once per worker session. A small look-ahead queue generates sentence audio; highlights follow actual playback.

The MC Speech A2 preset uses length scale 1.16, noise scale 0.667, and noise-W scale 0.8. User speed is applied by the player. A text-and-preset hash identifies cached audio, with an approximately 750 MB disk limit. Generation tokens discard obsolete work. Browsing and narration positions are tracked separately.

## Packaging

`scripts/setup-engine.sh` downloads build dependencies into ignored directories. `build.sh` compiles native sources, copies the runtime and voice, and applies an ad hoc signature. The repository excludes user books, caches, model weights, virtualenvs, and app bundles. Dependencies retain their own licenses.

Sparkle is bundled for signed in-app updates. `Info.plist` pins the public EdDSA key and appcast URL; `scripts/prepare-update.sh` signs a release feed with the private key kept in the maintainer's Keychain. Publish the matching release assets before updating `updates/appcast.xml`.
