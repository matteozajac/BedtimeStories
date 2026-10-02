# Bedtime Story format, version 1

A library folder contains immediate child book folders. Each book has `book.json` at its root. Unknown folders/files are ignored. Shared access is managed by Files/iCloud Drive; the app requires no cloud service account.

```json
{
  "formatVersion": 1,
  "id": "05dc38a2-a1d9-41a1-bd1d-5b7bcdd94162",
  "title": "Lisek i księżyc",
  "author": "Mateusz Zając",
  "cover": "cover.jpg",
  "audio": "audio/narration.m4a",
  "chapters": [
    {
      "id": "7b1b2e74-2bd3-4770-8005-e71f3c95039b",
      "title": "Światło w lesie",
      "text": "chapters/01.md",
      "image": "chapters/01.jpg",
      "startTime": 0
    }
  ]
}
```

Structural fields `formatVersion`, `id`, and `title` are required; titles must be nonblank. UUIDs remain stable across intentional edits. All content and other metadata are optional, including the chapter list. A minimal book contains only those three fields. Optional `description` and `author` are strings. Optional `readingWordsPerMinute` records the preferred reading pace (the app offers 80–180, default 120); optional `illustrationGuide` stores shared character appearance and visual style for cover/chapter prompts. Older files omit these fields, and the format version remains 1. Local draft checkout fingerprints and account identifiers are never exported.

Chapters are ordered by the array, never by filename. Each needs a unique UUID. `title`, `text`, `image`, `audio`, and `startTime` are optional. Text is a UTF-8 `.txt` or `.md` file. Images use `.jpg`, `.jpeg`, `.png`, or `.heic`. Audio uses `.m4a`, `.mp3`, or `.wav`. File extensions are case-insensitive; referenced paths are case-sensitive and must resolve exactly.

Use either book-level `audio` or chapter-level `audio`, never both. Chapter audio plays in array order, skipping chapters without audio. With book-level audio, optional `startTime` timestamps are seconds, finite, nonnegative, strictly increasing, and supplied for every chapter or none. They must fall within the recording duration (checked when playing). No speech synthesis or word-level audio alignment is implied.

Paths are relative to the book root. No absolute paths, backslashes, colons, control characters, empty components, dot-prefixed components, `.`/`..`, symlinks, or special files. Asset names must not collide after Unicode NFC normalization and lowercasing. References to missing files prevent import/export, but an indexed book remains visible so missing media can be diagnosed without blocking other books.

A `.bedtimestory` is a single-disk ZIP32 archive, with stored (uncompressed) entries, UTF-8 filenames, local and central headers, CRC32 checksums, and `book.json` at the root. Do not wrap the book in an extra parent folder. No ZIP64, encryption, data descriptors, links, special files, duplicate paths, or overlapping entries. The standard Python `zipfile` writer with `ZIP_STORED` and `allowZip64=False` produces compatible files. The app exports referenced assets only; private progress and cache metadata are excluded.

Limits: 10,000 entries, 2 GiB total uncompressed content, 2 MB manifest, 9,999 chapters. The app displays text files up to 5 MB and encoded images up to 30 MB; images are downsampled for display. Import stages and validates before publishing; replacement requires confirmation for an existing book UUID.

Reading chapter and playback position are stored per device and library, never in the shared folder. “Keep Offline” pins a complete local copy. Deleting an offline copy does not delete the source book.
