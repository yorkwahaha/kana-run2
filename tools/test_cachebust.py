"""Regression checks for the post-export step (`python -m unittest discover -s tools`)."""

from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest


class CacheBustTest(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        root = Path(tmp.name)
        self.script = root / "tools" / "cachebust.py"
        self.script.parent.mkdir()
        shutil.copyfile(Path(__file__).with_name(self.script.name), self.script)
        self.web = root / "build" / "web"
        self.web.mkdir(parents=True)
        self.html = self.web / "index.html"
        self.suffixes = (".js", ".wasm", ".pck", ".audio.worklet.js", ".audio.position.worklet.js")

    def run_script(self):
        return subprocess.run([sys.executable, str(self.script)], capture_output=True, text=True)

    def new_export(self, missing=""):
        self.html.write_text(
            '<head></head><script src="index.js"></script>\n'
            'const GODOT_CONFIG = {"executable":"index","fileSizes":{"index.pck":3,"index.wasm":4}};',
            encoding="utf-8",
        )
        for suffix in self.suffixes:
            if suffix != missing:
                (self.web / ("index" + suffix)).write_text(suffix, encoding="utf-8")

    def test_rerun_preserves_referenced_assets(self):
        self.new_export()
        first = self.run_script()
        self.assertEqual(first.returncode, 0, first.stderr)
        html = self.html.read_text(encoding="utf-8")
        version = re.search(r'"executable":"(kr2_\d+)"', html).group(1)
        headers_file = self.web / "_headers"
        self.assertTrue(headers_file.is_file())
        headers_txt = headers_file.read_text(encoding="utf-8")
        self.assertIn("Cross-Origin-Opener-Policy: same-origin", headers_txt)
        self.assertIn("Cross-Origin-Embedder-Policy: require-corp", headers_txt)
        second = self.run_script()
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(self.html.read_text(encoding="utf-8"), html)
        self.assertIn(f'src="{version}.js"', html)
        for suffix in self.suffixes:
            self.assertEqual((self.web / (version + suffix)).read_text(encoding="utf-8"), suffix)

    def test_incomplete_export_fails_before_removing_old_assets(self):
        self.new_export(missing=".pck")
        old = self.web / "kr2_20261103024407.pck"
        old.touch()
        self.assertNotEqual(self.run_script().returncode, 0)
        self.assertTrue(old.is_file())
        self.assertIn('"executable":"index"', self.html.read_text(encoding="utf-8"))
