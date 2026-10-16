# TalkieBook

A native macOS ebook reader with **fully local text-to-speech** and synchronized sentence highlighting. Read your own books, switch to listening, and keep everything on your Mac.

Built with SwiftUI, [foliate-js](https://github.com/johnfactotum/foliate-js), and a persistent [Piper](https://github.com/OHF-Voice/piper1-gpl) speech worker. The interface is available in **English and Polish**, with an instant, persistent language switch. The bundled MC Speech voice is **Polish**; changing the interface language does not change the voice.

## Features

- Import DRM-free EPUB, PDF, TXT, and pasted text.
- Read PDFs in their original layout or a customizable text view, with sentence highlighting in both.
- Extract text locally, with Apple Vision OCR for scanned pages.
- Browse a cover grid or list, organize collections, and track reading status.
- Listen offline with the Polish MC Speech medium voice and the A2 preset.
- Highlight spoken sentences, follow playback, or browse independently.
- Pause, resume, skip sentences, change speed, and set a sleep timer.
- Navigate the table of contents, search, bookmark, highlight, and take notes.
- Choose white, cream, sepia, or gray paper with matching night palettes.
- Select light, dark, or system appearance and customize typography, spacing, columns, and scrolling.

## Requirements and status

An early personal-use application for **macOS 14+ on Apple Silicon**. It is not affiliated with Apple Books.

DRM, password-protected PDFs, cloud sync, word-level highlighting, and M4B export are not implemented. Fixed-layout EPUB typography may be limited. Footnote and code skipping depend on the book's markup.

There is no public notarized binary release yet. Locally built bundles use an ad hoc signature, not Developer ID signing or Apple notarization.

## Build

Install Apple's Command Line Tools and [uv](https://docs.astral.sh/uv/getting-started/installation/) first. Setup downloads a portable Python 3.12 runtime, pinned Python packages, and the voice.

```sh
git clone https://github.com/NoctaCorax/talkiebook.git
cd talkiebook
xcode-select --install  # if Command Line Tools are not installed
bash scripts/setup-engine.sh
bash build.sh
```

Open `dist/TalkieBook.app` in Finder. The bundle includes its runtime and voice; listening requires no Python installation, terminal, local server, or internet connection after setup.

Choose another output location:

```sh
bash build.sh "$HOME/Applications/TalkieBook.app"
```

Advanced: provide an existing **portable** Python 3.12 installation and Piper environment. A framework-based Python installation or virtualenv alone is not a self-contained runtime.

```sh
TALKIEBOOK_PYTHON_BASE=/path/to/portable/python \
TALKIEBOOK_PIPER_ROOT=/path/to/piper \
bash build.sh
```

The Piper directory needs `.venv/lib/python3.12/site-packages/` and `voices/pl_PL-mc_speech-medium.onnx` with its `.onnx.json` configuration. Build-time paths are not embedded in the app.

## Local DMG package

After building the app:

```sh
bash scripts/package-dmg.sh
```

The image contains the self-contained app and an Applications shortcut. It uses an ad hoc signature and is not notarized.

## In-app updates

TalkieBook checks the signed Sparkle appcast hosted in this repository. Use **TalkieBook → Check for Updates** to check manually, or enable automatic checks in Appearance settings. Updates are downloaded from the matching GitHub release. The update feed and each release archive are signed with Sparkle's EdDSA key. Version 1.2.0 is the first release with the updater; earlier local builds must be replaced once from the DMG.

## Use

1. Select **Importuj książkę** (Import book), drop an EPUB/PDF/TXT into the window, or press **⌘O**.
2. Open a book and press play. Space toggles playback while the book text has focus.
3. Right-click a sentence and select **Czytaj od tego zdania** (Read from this sentence) to start there.
4. The target button returns to the narrator. Follow mode can be disabled in reading settings.
5. The **Aa** panel controls paper color, day/night appearance, and typography.
6. Select text to highlight or annotate it; **⌘D** bookmarks the current location.

Shortcuts: **← / →** pages, **⌘F** search, **⌘L** library, **⌘N** pasted text, **⇧⌘P** playback. The player also offers sentence skipping and a 5–60 minute sleep timer.

## PDF reading

PDF import runs in a background queue and creates a reusable speech index. The first import processes the whole document before it becomes available; scanned books take longer because OCR is required. Subsequent opening uses the saved index.

- **Original / Text** switches between native PDFKit pages and accessible text. Original view has zoom controls; Text view uses the reader's paper colors, fonts and spacing.
- Narration, sentence skipping, search, bookmarks, highlights and notes work in both views. PDF annotations anchor to sentences, so a selection within a sentence highlights that sentence.
- Layout line breaks are joined before sentence segmentation, and repeated marginal headers and footers are filtered heuristically.
- Apple Vision OCR runs on-device for pages without enough embedded text. Supported languages depend on macOS; Polish support was verified on the development Mac.
- Multi-column layouts, tables, equations, rotated scans and damaged text layers can still produce imperfect reading order. The app does not promise lossless conversion or automatic table interpretation.
- Input size limit: 500 MB. The original PDF is retained and can be exported unchanged.

## Interface language

Choose **App language / Język aplikacji** in the library sidebar or reading appearance panel. The preference persists across launches. User book titles, notes, collections and document text are never translated.

## Privacy and storage

The app does not call cloud TTS or run an HTTP server. Book scripts and remote resources are blocked. External book links do not open automatically.

- Library, imported copies, settings, and annotations: `~/Library/Application Support/Lektura/`
- Audio cache: `~/Library/Caches/Lektura/Audio/` (approximately 750 MB maximum)
- Worker log: `~/Library/Application Support/Lektura/engine.log`

Original files remain untouched. Removing a book moves the app's copy to Trash and removes its entry and annotations. Cache files can be deleted while the app is closed and will be regenerated.

## Development

```sh
python3 -m unittest discover -s Tests -v
bash scripts/test-native.sh
# Optional local OCR integration test:
bash scripts/test-native.sh --ocr
```

Tests generate their own EPUB fixtures and do not inspect personal folders. To explicitly test a local EPUB:

```sh
TALKIEBOOK_TEST_EPUB=/path/to/book.epub python3 -m unittest discover -s Tests -v
```

See [Architecture](docs/ARCHITECTURE.md), [Contributing](CONTRIBUTING.md), and [Third-party notices](THIRD_PARTY_NOTICES.md).

## License

TalkieBook's original application code is **[MIT licensed](LICENSE)**. Dependencies retain their own licenses: in particular Piper is GPL-3.0. MIT does not relicense Piper, its dependencies, or the voice. Read the [third-party notices](THIRD_PARTY_NOTICES.md) before redistributing a bundle.

The local data directories retain the original `Lektura` name for compatibility with existing libraries.
