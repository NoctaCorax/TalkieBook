#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENGINE_ROOT="$PROJECT_ROOT/.build/engine"
PYTHON_ROOT="$PROJECT_ROOT/.build/python"
if [ "$(uname -s)" != Darwin ] || [ "$(uname -m)" != arm64 ]; then
  printf '%s\n' 'Setup currently supports Apple Silicon macOS only.' >&2
  exit 1
fi
if ! command -v uv >/dev/null 2>&1; then
  printf '%s\n' 'Install uv first: https://docs.astral.sh/uv/getting-started/installation/' >&2
  exit 1
fi
mkdir -p "$ENGINE_ROOT/voices" "$PYTHON_ROOT"
uv python install 3.12 --install-dir "$PYTHON_ROOT"
PYTHON_BIN="$(find "$PYTHON_ROOT" -path '*/bin/python3.12' -type f | head -n 1)"
if [ -z "$PYTHON_BIN" ]; then printf '%s\n' 'Portable Python 3.12 was not found.' >&2; exit 1; fi
uv venv --python "$PYTHON_BIN" "$ENGINE_ROOT/.venv"
uv pip install --python "$ENGINE_ROOT/.venv/bin/python" -r "$PROJECT_ROOT/requirements-engine.txt"
MODEL_URL='https://huggingface.co/rhasspy/piper-voices/resolve/main/pl/pl_PL/mc_speech/medium'
for asset in pl_PL-mc_speech-medium.onnx pl_PL-mc_speech-medium.onnx.json; do
  curl --fail --location --retry 3 "$MODEL_URL/$asset" -o "$ENGINE_ROOT/voices/$asset.tmp"
  mv "$ENGINE_ROOT/voices/$asset.tmp" "$ENGINE_ROOT/voices/$asset"
done
printf '%s\n' 'Engine and voice are ready. Run: bash build.sh'
