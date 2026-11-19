import pathlib
import os
import shutil
import subprocess
import unittest


class WebBeschriftungenTest(unittest.TestCase):
    def test_dialoge_und_zugriffsrollen(self):
        root = pathlib.Path(__file__).resolve().parents[2]
        runtime = shutil.which("node")
        if not runtime:
            jsc = pathlib.Path("/System/Library/Frameworks/JavaScriptCore.framework/Versions/A/Helpers/jsc")
            if jsc.exists():
                runtime = str(jsc)
        if not runtime:
            self.skipTest("JavaScript-Laufzeit fehlt")
        for zone in ("UTC", "Europe/Berlin"):
            with self.subTest(zone=zone):
                result = subprocess.run(
                    [runtime, str(root / "tool/tests/web_beschriftungen_test.js")],
                    cwd=root, capture_output=True, text=True, timeout=30,
                    env={**os.environ, "TZ": zone},
                )
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("Dialogregressionen bestanden", result.stdout)


if __name__ == "__main__":
    unittest.main()
