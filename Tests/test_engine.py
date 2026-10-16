import importlib.util
import tempfile
import unittest
import zipfile
import json
import subprocess
import sys
import wave
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("worker", ROOT / "Resources/Engine/worker.py")
worker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(worker)


class ImportTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name) / "book.epub"

    def tearDown(self):
        self.temp.cleanup()

    def test_polish_text_is_valid_epub_with_escaped_markup(self):
        meta = worker.make_epub('Zażółć gęślą jaźń.\n\n<script>alert(1)</script> & tekst.', 'Tytuł <test>', self.path)
        self.assertEqual(meta['title'], 'Tytuł <test>')
        with zipfile.ZipFile(self.path) as z:
            text = z.read('c0.xhtml').decode()
            self.assertIn('Zażółć', text)
            self.assertNotIn('<script>', text)
            self.assertIn('&lt;script&gt;', text)
            self.assertEqual(z.infolist()[0].filename, 'mimetype')
            worker.ET.fromstring(z.read('book.opf'))
            worker.ET.fromstring(z.read('nav.xhtml'))

    def test_long_text_has_navigable_chapters(self):
        worker.make_epub(('Długi akapit. ' * 1000 + '\n\n') * 6, 'Długi tekst', self.path)
        with zipfile.ZipFile(self.path) as z:
            self.assertGreater(len([n for n in z.namelist() if n.startswith('c')]), 1)

    def test_drm_is_reported_explicitly(self):
        worker.make_epub('Tekst.', 'Książka', self.path)
        with zipfile.ZipFile(self.path, 'a') as z:
            z.writestr('META-INF/encryption.xml', '<encryption><EncryptionMethod Algorithm="http://ns.adobe.com/adept"/></encryption>')
        with self.assertRaisesRegex(ValueError, 'DRM'):
            worker.inspect_book(self.path)

    def test_empty_text_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'pusty'):
            worker.make_epub(' \n ', 'Pusto', self.path)

    @unittest.skipUnless(os.environ.get('TALKIEBOOK_TEST_EPUB'), 'Set TALKIEBOOK_TEST_EPUB to test a local EPUB explicitly.')
    def test_import_explicit_local_epub(self):
        import shutil
        shutil.copy2(Path(os.environ['TALKIEBOOK_TEST_EPUB']), self.path)
        meta = worker.inspect_book(self.path)
        self.assertTrue(meta['title'])


class WorkerTests(unittest.TestCase):
    def test_protocol_recovers_after_invalid_command(self):
        result = subprocess.run([sys.executable, str(ROOT / 'Resources/Engine/worker.py')],
                                input='{"id":1,"cmd":"bad"}\n{"id":2,"cmd":"ping"}\n',
                                capture_output=True, text=True, timeout=10)
        lines = [json.loads(x) for x in result.stdout.splitlines()]
        self.assertIn('error', lines[0])
        self.assertTrue(lines[1]['result']['ready'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
