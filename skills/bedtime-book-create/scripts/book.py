#!/usr/bin/env python3
"""Create, validate and package Bedtime Story v1 books. Python standard library only."""
import argparse
import json
import math
import re
import shutil
import stat
import tempfile
import unicodedata
import uuid
import zipfile
from pathlib import Path, PurePosixPath

MAX_BYTES = 2 * 1024**3
MAX_ENTRIES = 10_000
EXTENSIONS = {"cover": {"jpg", "jpeg", "png", "heic"}, "image": {"jpg", "jpeg", "png", "heic"},
              "text": {"txt", "md"}, "audio": {"m4a", "mp3", "wav"}}


def safe_path(name):
    if not isinstance(name, str) or not name or any(c in name for c in "\\:") or any(ord(c) < 32 for c in name):
        raise ValueError(f"Unsafe file path: {name!r}")
    parts = name.split("/")
    if any(not p or p.startswith(".") for p in parts):
        raise ValueError(f"Unsafe file path: {name!r}")
    return PurePosixPath(name)


def asset(folder, name, kind):
    path = safe_path(name)
    if path.suffix.lower().lstrip(".") not in EXTENSIONS[kind]:
        raise ValueError(f"Unsupported {kind} type: {name}")
    result = folder
    for part in path.parts:
        result = result / part
        if result.is_symlink():
            raise ValueError(f"Symlink is not allowed: {name}")
    if not result.is_file():
        raise ValueError(f"Missing file: {name}")
    if kind == "text":
        result.read_text(encoding="utf-8")
    return result


def validate(folder):
    folder = Path(folder)
    manifest = folder / "book.json"
    if manifest.is_symlink() or manifest.stat().st_size > 2_000_000:
        raise ValueError("Invalid or oversized manifest")
    book = json.loads(manifest.read_text(encoding="utf-8"))
    if type(book.get("formatVersion")) is not int or book["formatVersion"] != 1:
        raise ValueError("Unsupported format version")
    uuid.UUID(book["id"])
    if not isinstance(book.get("title"), str) or not book["title"].strip():
        raise ValueError("A book needs a title")
    for key in ("author", "description"):
        if book.get(key) is not None and not isinstance(book[key], str):
            raise ValueError(f"{key} must be text")
    chapters = book.get("chapters") or []
    if not isinstance(chapters, list) or len(chapters) > 9999:
        raise ValueError("Invalid chapter list")
    ids = set()
    refs = {"book.json"}
    for key in ("cover", "audio"):
        if book.get(key) is not None:
            asset(folder, book[key], key); refs.add(book[key])
    if book.get("audio") is not None and any(c.get("audio") is not None for c in chapters):
        raise ValueError("Use a full-book recording or chapter recordings, not both")
    previous, timestamp_count = -1, 0
    for chapter in chapters:
        identifier = uuid.UUID(chapter["id"])
        if identifier in ids:
            raise ValueError("Duplicate chapter identity")
        ids.add(identifier)
        if chapter.get("title") is not None and not isinstance(chapter["title"], str):
            raise ValueError("Chapter title must be text")
        for key in ("text", "image", "audio"):
            if chapter.get(key) is not None:
                asset(folder, chapter[key], key); refs.add(chapter[key])
        if chapter.get("startTime") is not None:
            start = chapter["startTime"]
            if type(start) not in (int, float) or not math.isfinite(start) or start < 0 or start <= previous or book.get("audio") is None:
                raise ValueError("Chapter timestamps must increase and require a full-book recording")
            previous, timestamp_count = start, timestamp_count + 1
    if timestamp_count not in (0, len(chapters)):
        raise ValueError("Provide timestamps for every chapter or none")
    canonical = [unicodedata.normalize("NFC", p).lower() for p in refs]
    if len(set(canonical)) != len(canonical):
        raise ValueError("Asset paths collide on Apple filesystems")
    if len(refs) > MAX_ENTRIES or sum((folder / p).stat().st_size for p in refs) > MAX_BYTES:
        raise ValueError("Book exceeds v1 limits")
    return book, sorted(refs)


def package(folder, output):
    _, paths = validate(folder)
    output = Path(output)
    if output.exists():
        raise ValueError(f"Output already exists: {output}")
    try:
        with zipfile.ZipFile(output, "x", compression=zipfile.ZIP_STORED, allowZip64=False) as archive:
            for path in paths:
                archive.write(Path(folder) / path, path)
        validate_archive(output)
    except BaseException:
        output.unlink(missing_ok=True)
        raise
    return output


def validate_archive(path):
    if Path(path).stat().st_size > MAX_BYTES + 16_000_000:
        raise ValueError("Archive exceeds v1 limits")
    with zipfile.ZipFile(path) as archive, tempfile.TemporaryDirectory(prefix="bedtime-validate-") as temporary:
        entries = archive.infolist()
        if not 0 < len(entries) <= MAX_ENTRIES or sum(e.file_size for e in entries) > MAX_BYTES:
            raise ValueError("Archive exceeds v1 limits")
        names = set()
        for entry in entries:
            name = entry.filename.rstrip("/") if entry.is_dir() else entry.filename
            safe_path(name)
            key = unicodedata.normalize("NFC", name).lower()
            if key in names:
                raise ValueError(f"Duplicate archive path: {name}")
            names.add(key)
            mode = stat.S_IFMT(entry.external_attr >> 16)
            if mode not in (0, stat.S_IFDIR if entry.is_dir() else stat.S_IFREG):
                raise ValueError("Archive links and special files are not allowed")
            if entry.compress_type != zipfile.ZIP_STORED or entry.flag_bits & ~0x0800 or entry.extract_version > 20 or entry.volume != 0:
                raise ValueError("Only stored, unencrypted ZIP32 entries without descriptors are supported")
            if entry.compress_size != entry.file_size or (entry.is_dir() and entry.file_size != 0):
                raise ValueError("Invalid stored file size")
            index = 0
            while index < len(entry.extra):
                if index + 4 > len(entry.extra):
                    raise ValueError("Invalid ZIP metadata")
                field = int.from_bytes(entry.extra[index:index+2], "little")
                length = int.from_bytes(entry.extra[index+2:index+4], "little")
                if field == 1 or index + 4 + length > len(entry.extra):
                    raise ValueError("ZIP64 or malformed metadata is unsupported")
                index += 4 + length
            target = Path(temporary) / name
            if entry.is_dir():
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                with archive.open(entry) as source, target.open("xb") as destination:
                    shutil.copyfileobj(source, destination, 256 * 1024)
        return validate(Path(temporary))[0]


def split_text(text):
    # Preserve every source character; headings supply labels without rewriting prose.
    headings = list(re.finditer(r"(?m)^#{1,2} +(.+?)\s*$", text))
    if not headings:
        return [(None, text)] if text else []
    sections = []
    if headings[0].start() > 0 and text[:headings[0].start()].strip():
        sections.append((None, text[:headings[0].start()]))
    for index, heading in enumerate(headings):
        end = headings[index+1].start() if index+1 < len(headings) else len(text)
        sections.append((heading.group(1), text[heading.start():end]))
    return sections


def create(args):
    output = Path(args.output)
    if output.exists():
        raise ValueError(f"Output already exists: {output}")
    identifier = uuid.UUID(args.id) if args.id else uuid.uuid4()
    media = json.loads(Path(args.chapter_media).read_text(encoding="utf-8")) if args.chapter_media else {}
    if not isinstance(media, dict):
        raise ValueError("Chapter media must be an object keyed by chapter number")
    for key, info in media.items():
        if not key.isdecimal() or str(int(key)) != key or not 1 <= int(key) <= 9999 or not isinstance(info, dict):
            raise ValueError("Chapter media keys must be 1-based numbers and values must be objects")
        if set(info) - {"id", "title", "image", "audio", "startTime"}:
            raise ValueError(f"Unsupported chapter media fields for chapter {key}")
    text = Path(args.text).read_text(encoding="utf-8") if args.text else ""
    chapters = split_text(text)
    count = max(len(chapters), max((int(k) for k in media), default=0))
    if count > 9999:
        raise ValueError("Too many chapters")
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".bedtime-create-", dir=output.parent) as temporary:
        staging = Path(temporary)
        book = {"formatVersion": 1, "id": str(identifier), "title": args.title, "chapters": []}
        if args.author: book["author"] = args.author
        if args.description: book["description"] = args.description

        def copy(source, relative):
            source = Path(source)
            if source.is_symlink() or not source.is_file():
                raise ValueError(f"Supply a regular media file: {source}")
            destination = staging / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, destination)
            return relative

        if args.cover: book["cover"] = copy(args.cover, "cover" + Path(args.cover).suffix.lower())
        if args.audio: book["audio"] = copy(args.audio, "audio/narration" + Path(args.audio).suffix.lower())
        for index in range(count):
            number = index + 1
            info = media.get(str(number), {})
            chapter = {"id": str(uuid.UUID(info["id"]) if info.get("id") else uuid.uuid5(identifier, f"chapter/{number}"))}
            if index < len(chapters):
                title, prose = chapters[index]
                if title: chapter["title"] = title
                relative = f"chapters/{number:02}.md"
                (staging / "chapters").mkdir(exist_ok=True)
                (staging / relative).write_text(prose, encoding="utf-8", newline="")
                chapter["text"] = relative
            if "title" in info: chapter["title"] = info["title"]
            for key in ("image", "audio"):
                if key in info:
                    relative = f"{'audio' if key == 'audio' else 'chapters'}/{number:02}" + Path(info[key]).suffix.lower()
                    chapter[key] = copy(info[key], relative)
            if "startTime" in info: chapter["startTime"] = info["startTime"]
            book["chapters"].append(chapter)
        (staging / "book.json").write_text(json.dumps(book, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        validate(staging)
        shutil.move(str(staging), str(output))
    return book


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    creation = commands.add_parser("create")
    for key in ("title", "output"):
        creation.add_argument("--" + key, required=True)
    for key in ("text", "cover", "audio", "author", "description", "id", "chapter-media"):
        creation.add_argument("--" + key)
    creation.add_argument("--archive", help="Also export to this .bedtimestory path")
    exporting = commands.add_parser("export")
    exporting.add_argument("folder"); exporting.add_argument("output")
    validating = commands.add_parser("validate")
    validating.add_argument("path")
    args = parser.parse_args()
    try:
        if args.command == "create":
            book = create(args)
            if args.archive: package(args.output, args.archive)
        elif args.command == "export":
            book = validate(args.folder)[0]; package(args.folder, args.output)
        else:
            book = validate(args.path)[0] if Path(args.path).is_dir() else validate_archive(args.path)
        print(json.dumps({"title": book["title"], "id": book["id"], "status": "valid"}, ensure_ascii=False))
    except (ValueError, OSError, KeyError, TypeError, zipfile.BadZipFile, RuntimeError) as error:
        parser.exit(1, f"Error: {error}\n")


if __name__ == "__main__":
    main()
