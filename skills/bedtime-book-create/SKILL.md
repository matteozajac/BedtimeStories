---
name: bedtime-book-create
description: Package supplied bedtime story text, illustrations, and recordings into editable book folders and shareable .bedtimestory files for Bedtime Stories. Use for creating or validating books, not for generating images or narration.
---

# Create a Bedtime Book

Read [the book format](references/book-format.md) before creating or changing a book.
Use `scripts/book.py` for deterministic creation, validation, and export. It needs Python 3 and no external libraries.

Accept the user's title and supplied text/media. Preserve wording and language; do not rewrite, translate, invent chapters, generate media, or infer audio timestamps. A title-only book is valid. Ask for the title only if it cannot be determined from the user's request.

Explicit Markdown `#` and `##` headings become chapters. Text without these headings becomes one chapter. If headings describe sections rather than chapters, prepare a chapter-media map or an explicit book folder instead of silently changing the user's structure. Keep supplied media optional.

Example:

```sh
python3 scripts/book.py create --title 'Lisek i księżyc' --text /absolute/story.md --output /absolute/Lisek --archive /absolute/Lisek.bedtimestory
```

Optional flags: `--cover`, `--audio` (one full-book recording), `--author`, `--description`, `--chapter-media`, and `--id` (reuse a book UUID for an intentional update). `--chapter-media` reads JSON keyed by 1-based chapter numbers, e.g. `{"1":{"image":"/absolute/fox.jpg","audio":"/absolute/one.m4a"}}`. For a full-book recording, use `startTime` instead of chapter audio. Media-only chapters are supported. Preserve chapter UUIDs in updates using each entry's `id`.

Create output in the user's requested location, otherwise the current task output directory. The helper refuses existing output paths. Keep an existing book's ID only when explicitly updating that book. Do not replace an existing book or write into a shared iCloud folder unless requested. Package text/media as files, never links. Do not embed administrative credentials, private progress, or absolute asset paths in books.

Validate the folder and archive, then return links to both:

```sh
python3 scripts/book.py validate /absolute/Lisek
python3 scripts/book.py validate /absolute/Lisek.bedtimestory
```

When hand-authoring a folder, use generated UUIDs and the reference contract. Export with `python3 scripts/book.py export FOLDER OUTPUT.bedtimestory`. Do not use a default compressed ZIP: the app's v1 format requires stored entries.
