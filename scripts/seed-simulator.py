#!/usr/bin/env python3
"""Seed disposable simulator fixtures; never writes an iCloud folder."""
import importlib.util
import json
import subprocess
import sys
import wave
from argparse import Namespace
from pathlib import Path

repo = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("book", repo / "skills/bedtime-book-create/scripts/book.py")
book = importlib.util.module_from_spec(spec); spec.loader.exec_module(book)
container = Path(subprocess.check_output(["xcrun", "simctl", "get_app_container", sys.argv[1], "com.matteozajac.bedtimestories", "data"], text=True).strip())
documents = container / "Documents"
root = documents / "QA Library"
root.mkdir(parents=True, exist_ok=True)
inputs = container / "tmp" / "QA Inputs"; inputs.mkdir(parents=True, exist_ok=True)
text = inputs / "fox.md"
text.write_text("## Światło w lesie\n\nLisek spojrzał na księżyc. **Dobranoc**, szepnął do gwiazd.\n\n- Ciepły kocyk\n- Spokojny oddech\n\n## Spokojny sen\n\nLas zasnął, a wraz z nim mały lisek.\n", encoding="utf-8")
audio = inputs / "narration.wav"
with wave.open(str(audio), "wb") as file:
    file.setparams((1, 2, 8000, 0, "NONE", "not compressed")); file.writeframes(bytes(8000 * 2 * 60))
media = inputs / "media.json"
media.write_text(json.dumps({"1":{"startTime":0},"2":{"startTime":30}}))
fixtures = [
    ("Fox", "Lisek i księżyc", "11111111-1111-4111-8111-111111111111", str(text), str(audio), str(media)),
    ("Soon", "A story for tomorrow", "22222222-2222-4222-8222-222222222222", None, None, None),
    ("Read", "The Quiet Forest", "33333333-3333-4333-8333-333333333333", str(text), None, None),
    ("Audio", "Moonlight Lullaby", "44444444-4444-4444-8444-444444444444", None, str(audio), None)
]
for name, title, identifier, prose, recording, chapter_media in fixtures:
    output = root / name
    if not output.exists():
        book.create(Namespace(output=str(output),title=title,id=identifier,text=prose,audio=recording,chapter_media=chapter_media,cover=None,author="Mateusz Zając",description=None))
archive = documents / "Fox.bedtimestory"
if not archive.exists(): book.package(root / "Fox", archive)
print(root)
