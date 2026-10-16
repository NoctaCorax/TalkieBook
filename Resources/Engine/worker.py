"""Local, line-delimited JSON worker. No network or shell execution."""
import sys
import json
import os
import re
import wave
import hashlib
import zipfile
import html
import time
import tempfile
import posixpath
import xml.etree.ElementTree as ET
from pathlib import Path

VOICE = None
ESPEAK_ALIAS = None
ENGINE = Path(__file__).resolve().parent


def inspect_book(path):
    path = Path(path)
    with zipfile.ZipFile(path) as z:
        infos = z.infolist()
        if len(infos) > 20000 or sum(i.file_size for i in infos) > 512 * 1024**2:
            raise ValueError("Książka przekracza limit 512 MB po rozpakowaniu.")
        if any(i.flag_bits & 1 for i in infos):
            raise ValueError("Ten plik jest zaszyfrowany. Wybierz EPUB bez DRM.")
        container = ET.fromstring(z.read("META-INF/container.xml"))
        rootfile = next(e for e in container.iter() if e.tag.endswith("rootfile"))
        opf = rootfile.attrib["full-path"]
        root = ET.fromstring(z.read(opf))
        def field(name):
            return next(("".join(e.itertext()).strip() for e in root.iter()
                         if e.tag == "{http://purl.org/dc/elements/1.1/}" + name), "")
        items = {e.get("id"): e for e in root.iter() if e.tag.endswith("}item")}
        encrypted = "META-INF/encryption.xml" in z.namelist()
        if encrypted:
            enc = ET.fromstring(z.read("META-INF/encryption.xml"))
            algorithms = [e.get("Algorithm", "") for e in enc.iter() if e.tag.endswith("EncryptionMethod")]
            allowed = {"http://www.idpf.org/2008/embedding", "http://ns.adobe.com/pdf/enc#RC"}
            if any(a not in allowed for a in algorithms):
                raise ValueError("Książka jest chroniona DRM. Obsługiwane są EPUB-y bez DRM.")
        cover = next((e for e in items.values() if "cover-image" in e.get("properties", "").split()), None)
        if cover is None:
            cover_id = next((e.get("content") for e in root.iter()
                             if e.tag.endswith("}meta") and e.get("name") == "cover"), None)
            cover = items.get(cover_id)
        cover_name = ""
        if cover is not None:
            location = posixpath.normpath(posixpath.join(posixpath.dirname(opf), cover.get("href", "")))
            if location in z.namelist():
                data = z.read(location)
                if len(data) < 15 * 1024**2:
                    suffix = Path(location).suffix.lower()
                    if suffix in (".jpg", ".jpeg", ".png", ".webp", ".gif"):
                        cover_name = "cover" + suffix
                        (path.parent / cover_name).write_bytes(data)
        return {"title": field("title") or path.stem, "author": field("creator") or "Nieznany autor",
                "cover": cover_name, "language": field("language") or "pl"}


def make_epub(text, title, destination):
    text = text.strip()
    if not text:
        raise ValueError("Tekst jest pusty.")
    if len(text) > 8_000_000:
        raise ValueError("Tekst jest zbyt długi (limit 8 milionów znaków).")
    paragraphs = re.split(r"\n\s*\n", text)
    # Smaller chapters keep layout and sentence mapping responsive for large TXT files.
    chapters, group, size = [], [], 0
    for p in paragraphs:
        group.append(p)
        size += len(p)
        if size > 18000:
            chapters.append(group)
            group, size = [], 0
    if group:
        chapters.append(group)
    esc = html.escape
    with zipfile.ZipFile(destination, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("mimetype", "application/epub+zip", compress_type=zipfile.ZIP_STORED)
        z.writestr("META-INF/container.xml", '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="book.opf" media-type="application/oebps-package+xml"/></rootfiles></container>')
        manifest = '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>'
        spine, links = "", ""
        for i, paragraphs in enumerate(chapters):
            label = title if len(chapters) == 1 else f"Część {i + 1}"
            body = "".join("<p>" + esc(p).replace("\n", "<br/>") + "</p>" for p in paragraphs)
            z.writestr(f"c{i}.xhtml", f'<html xmlns="http://www.w3.org/1999/xhtml" lang="pl"><head><title>{esc(label)}</title></head><body><h1>{esc(label)}</h1>{body}</body></html>')
            manifest += f'<item id="c{i}" href="c{i}.xhtml" media-type="application/xhtml+xml"/>'
            spine += f'<itemref idref="c{i}"/>'
            links += f'<li><a href="c{i}.xhtml">{esc(label)}</a></li>'
        z.writestr("nav.xhtml", f'<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Spis treści</title></head><body><nav epub:type="toc"><ol>{links}</ol></nav></body></html>')
        z.writestr("book.opf", f'<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">{hashlib.sha256(text.encode()).hexdigest()}</dc:identifier><dc:title>{esc(title)}</dc:title><dc:creator>Twój tekst</dc:creator><dc:language>pl</dc:language><meta property="dcterms:modified">2026-01-01T00:00:00Z</meta></metadata><manifest>{manifest}</manifest><spine>{spine}</spine></package>')
    return inspect_book(destination)


def synthesize(req):
    global VOICE, ESPEAK_ALIAS
    import onnxruntime
    onnxruntime.disable_telemetry_events()
    from piper import PiperVoice, SynthesisConfig
    text = str(req["text"]).strip()
    if not text or len(text) > 12000:
        raise ValueError("Nieprawidłowa długość fragmentu.")
    cache = Path(req["cache"])
    cache.mkdir(parents=True, exist_ok=True)
    key = hashlib.sha256(("mc_speech-medium-1.8-A2|" + text).encode()).hexdigest()
    output = cache / (key + ".wav")
    if not output.exists():
        if VOICE is None:
            from piper.phonemize_espeak import ESPEAK_DATA_DIR
            # eSpeak's internal data-path buffer is shorter than macOS PATH_MAX.
            # App bundles in deeply nested folders therefore need a short alias.
            ESPEAK_ALIAS = tempfile.TemporaryDirectory(prefix="talkiebook-espeak-", dir="/tmp")
            phonemes = Path(ESPEAK_ALIAS.name) / "espeak-ng-data"
            phonemes.symlink_to(ESPEAK_DATA_DIR, target_is_directory=True)
            VOICE = PiperVoice.load(ENGINE / "pl_PL-mc_speech-medium.onnx", espeak_data_dir=phonemes)
        config = SynthesisConfig(length_scale=1.16, noise_scale=0.667, noise_w_scale=0.8)
        temp = output.with_suffix(".tmp")
        try:
            with wave.open(str(temp), "wb") as w:
                VOICE.synthesize_wav(text, w, syn_config=config)
            temp.replace(output)
        finally:
            temp.unlink(missing_ok=True)
        # Bounded persistent cache. Current and recently prefetched audio stays newest.
        files = sorted(cache.glob("*.wav"), key=lambda p: p.stat().st_mtime)
        total = sum(p.stat().st_size for p in files)
        for p in files:
            if total <= 750 * 1024**2:
                break
            total -= p.stat().st_size
            p.unlink(missing_ok=True)
    os.utime(output, None)
    with wave.open(str(output), "rb") as w:
        duration = w.getnframes() / w.getframerate()
    return {"path": str(output), "duration": duration}


def handle(req):
    cmd = req.get("cmd")
    if cmd == "inspect":
        return inspect_book(req["path"])
    if cmd == "text":
        text = req.get("text")
        if text is None:
            raw = Path(req["source"]).read_bytes()
            try:
                text = raw.decode("utf-8-sig")
            except UnicodeDecodeError:
                text = raw.decode("cp1250")
        return make_epub(text, req["title"], req["path"])
    if cmd == "synthesize":
        return synthesize(req)
    if cmd == "ping":
        return {"ready": True}
    raise ValueError("Nieznane polecenie.")


if __name__ == "__main__":
    for line in sys.stdin:
        request = {}
        try:
            request = json.loads(line)
            result = {"id": request.get("id"), "result": handle(request)}
        except Exception as e:
            print(str(e), file=sys.stderr, flush=True)
            result = {"id": request.get("id"), "error": str(e)}
        print(json.dumps(result, ensure_ascii=False), flush=True)
