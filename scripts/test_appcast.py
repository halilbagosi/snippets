"""Tests for appcast.py. Run: python3 -I -m unittest discover -s scripts -p 'test_appcast.py'"""
import pathlib
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET

SCRIPT = pathlib.Path(__file__).with_name("appcast.py")
SEED = pathlib.Path(__file__).parent.parent / "site" / "appcast.xml"
SP = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"


class AppcastTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.dir = pathlib.Path(tmp.name)
        self.feed = self.dir / "appcast.xml"
        self.feed.write_text(SEED.read_text())
        self.notes = self.dir / "notes.html"
        self.notes.write_text("<ul><li>Updates arrive in the app</li></ul>")

    def add(self, version, build):
        return subprocess.run(
            [sys.executable, "-I", str(SCRIPT), "--appcast", str(self.feed),
             "--version", version, "--build", str(build),
             "--url", f"https://github.com/o/r/releases/download/v{version}/Snippets.dmg",
             "--length", "1234", "--signature", "c2ln", "--min-system", "26.0",
             "--notes-file", str(self.notes)],
            capture_output=True, text=True)

    def check(self, build):
        return subprocess.run(
            [sys.executable, "-I", str(SCRIPT), "--appcast", str(self.feed),
             "--build", str(build), "--check"],
            capture_output=True, text=True)

    def items(self):
        return ET.parse(self.feed).getroot().find("channel").findall("item")

    def test_adds_a_signed_item(self):
        self.assertEqual(self.add("1.1", 812).returncode, 0)
        [item] = self.items()
        self.assertEqual(item.find(f"{SP}version").text, "812")
        self.assertEqual(item.find(f"{SP}shortVersionString").text, "1.1")
        self.assertEqual(item.find(f"{SP}minimumSystemVersion").text, "26.0")
        self.assertIn("Updates arrive", item.find("description").text)
        enc = item.find("enclosure")
        self.assertEqual(enc.get("url"), "https://github.com/o/r/releases/download/v1.1/Snippets.dmg")
        self.assertEqual(enc.get("length"), "1234")
        self.assertEqual(enc.get(f"{SP}edSignature"), "c2ln")

    def test_newest_goes_first(self):
        self.add("1.1", 812)
        self.add("1.2", 900)
        self.assertEqual([i.find(f"{SP}version").text for i in self.items()], ["900", "812"])

    def test_refuses_a_build_that_is_not_newer(self):
        self.add("1.1", 812)
        result = self.add("1.1.1", 812)
        self.assertEqual(result.returncode, 1)
        self.assertIn("812", result.stderr)
        self.assertEqual(len(self.items()), 1)

    def test_check_passes_a_newer_build_without_writing(self):
        self.add("1.1", 812)
        before = self.feed.read_bytes()
        self.assertEqual(self.check(813).returncode, 0)
        self.assertEqual(self.feed.read_bytes(), before)

    def test_check_refuses_a_build_that_is_not_newer(self):
        self.add("1.1", 812)
        before = self.feed.read_bytes()
        result = self.check(812)
        self.assertEqual(result.returncode, 1)
        self.assertIn("812", result.stderr)
        self.assertEqual(self.feed.read_bytes(), before)

    def test_adding_requires_the_item_fields(self):
        result = subprocess.run(
            [sys.executable, "-I", str(SCRIPT), "--appcast", str(self.feed),
             "--version", "1.1", "--build", "812", "--length", "1234",
             "--signature", "c2ln", "--min-system", "26.0",
             "--notes-file", str(self.notes)],
            capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn("--url", result.stderr)

    def test_keeps_the_sparkle_prefix(self):
        self.add("1.1", 812)
        text = self.feed.read_text()
        self.assertIn('xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"', text)
        self.assertIn("<sparkle:version>812</sparkle:version>", text)


if __name__ == "__main__":
    unittest.main()
