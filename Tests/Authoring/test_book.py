import importlib.util
import json
import tempfile
import unittest
import zipfile
from argparse import Namespace
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[2] / "skills/bedtime-book-create/scripts/book.py"
spec = importlib.util.spec_from_file_location("book", SCRIPT)
book = importlib.util.module_from_spec(spec)
spec.loader.exec_module(book)


class AuthoringTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)

    def tearDown(self):
        self.temporary.cleanup()

    def args(self, **changes):
        values = dict(output=str(self.root / "Book"), title="Lisek i księżyc", id=None, text=None,
                      cover=None, audio=None, author=None, description=None, chapter_media=None)
        values.update(changes)
        return Namespace(**values)

    def test_title_only_and_archive_round_trip(self):
        source = self.root / "Book"
        original = book.create(self.args())
        archive = self.root / "Book.bedtimestory"
        book.package(source, archive)
        self.assertEqual(book.validate_archive(archive), original)
        with zipfile.ZipFile(archive) as z:
            self.assertEqual(z.namelist(), ["book.json"])
            self.assertEqual(z.getinfo("book.json").compress_type, zipfile.ZIP_STORED)

    def test_prose_and_unicode_preserved(self):
        text = "## Światło\n\nLisek mówi: **dobranoc**.\n\n## Sen\n\nZasnął.\n"
        input_file = self.root / "story.md"
        input_file.write_text(text, encoding="utf-8")
        original = book.create(self.args(text=str(input_file)))
        joined = "".join((self.root / "Book" / c["text"]).read_text(encoding="utf-8") for c in original["chapters"])
        self.assertEqual(joined, text)
        self.assertEqual(len(original["chapters"]), 2)

    def test_missing_media_and_mixed_layout_leave_no_output(self):
        audio = self.root / "all.mp3"
        audio.write_bytes(b"recording")
        media = self.root / "media.json"
        media.write_text(json.dumps({"1": {"audio": str(audio)}}))
        with self.assertRaises(ValueError):
            book.create(self.args(audio=str(audio), chapter_media=str(media)))
        self.assertFalse((self.root / "Book").exists())

    def test_existing_output_is_preserved(self):
        book.create(self.args())
        with self.assertRaises(ValueError):
            book.create(self.args(title="Other"))
        self.assertEqual(book.validate(self.root / "Book")[0]["title"], "Lisek i księżyc")

    def test_archive_path_traversal_duplicate_and_compression(self):
        original = book.create(self.args())
        for mode in ("traversal", "duplicate", "compressed"):
            archive = self.root / f"{mode}.bedtimestory"
            with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED if mode == "compressed" else zipfile.ZIP_STORED) as z:
                z.writestr("book.json", json.dumps(original))
                if mode == "traversal": z.writestr("../outside", "bad")
                if mode == "duplicate": z.writestr("BOOK.JSON", "{}")
            with self.assertRaises(ValueError):
                book.validate_archive(archive)
        self.assertFalse((self.root / "outside").exists())

    def test_audio_only_chapters_and_timestamp_validation(self):
        audio = self.root / "all.m4a"
        audio.write_bytes(b"recording")
        media = self.root / "media.json"
        media.write_text(json.dumps({"1": {"title": "One", "startTime": 0}, "2": {"title": "Two", "startTime": 12}}))
        original = book.create(self.args(audio=str(audio), chapter_media=str(media)))
        self.assertEqual([c["startTime"] for c in original["chapters"]], [0, 12])
        original["chapters"][1]["startTime"] = -1
        (self.root / "Book/book.json").write_text(json.dumps(original))
        with self.assertRaises(ValueError): book.validate(self.root / "Book")


if __name__ == "__main__":
    unittest.main()
