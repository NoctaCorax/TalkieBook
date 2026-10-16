# Third-party notices

The root MIT license covers TalkieBook's original code and documentation. It does not replace the licenses of vendored libraries, the speech engine, Python, or voice assets.

## foliate-js

- Upstream: <https://github.com/johnfactotum/foliate-js>
- Revision: `78914aef4466eb960965702401634c2cb348e9b1`
- MIT; see `Resources/Web/foliate/LICENSE`.
- Bundled dependencies: zip.js (BSD-3-Clause), fflate (MIT).

Upstream source and notices are retained. This distribution omits the optional PDF.js assets because TalkieBook renders PDFs natively with Apple PDFKit. The upstream optional PDF adapter remains in the source tree but cannot load without those assets. Supplemental dependency licenses are under `Resources/Web/foliate/vendor/`.

## Piper

- Upstream: <https://github.com/OHF-Voice/piper1-gpl>
- `piper-tts==1.8.0`
- GPL-3.0; see `Resources/Engine/PIPER-LICENSE` and installed package notices.

Piper runs in a separate local Python process. The repository does not commit its binaries, weights, or a Python environment. Setup downloads those separately. Redistributing a bundle must preserve notices and satisfy the licenses of its GPL components, including applicable corresponding-source requirements. The application MIT license does not relicense these components.

## Polish MC Speech voice

- Voice: `pl_PL-mc_speech-medium`
- Distribution: <https://huggingface.co/rhasspy/piper-voices/tree/main/pl/pl_PL/mc_speech/medium>
- Model card: `Resources/Engine/MC-SPEECH-MODEL-CARD.txt`
- Dataset: <https://www.kaggle.com/datasets/czyzi0/the-mc-speech-dataset>

The upstream model card identifies the dataset license as CC0 and describes fine-tuning from the U.S. English Lessac medium voice. This reports upstream metadata; it is not a new license grant for third-party assets.

## Python runtime and packages

Setup uses a portable Python 3.12 distribution managed by uv, from <https://github.com/astral-sh/python-build-standalone>. Installed dependencies include ONNX Runtime and NumPy. Their license files and package metadata must remain with redistributed runtimes. Build copies package metadata and the portable runtime's license directory when available.

## Sparkle

[Sparkle 2.10.0](https://github.com/sparkle-project/Sparkle/releases/tag/2.10.0) provides signed in-app updates. Its license and third-party notices are included in `Resources/Licenses/Sparkle-LICENSE` and the bundled framework.
