# iCloud edit checkout repair — 4 October 2026

The supplied build-15 device logs show Edit Book waiting 45 seconds on the fourth
asset, an image, while `not_downloaded`, local file presence and an idle provider
remain unchanged. The manifest and first three assets had already opened.

The download loop repeatedly queried the same URL's cached resource values.
Apple documents that [resourceValues(forKeys:)](https://developer.apple.com/documentation/foundation/url/resourcevalues(forkeys:).md)
returns cached attributes and that background callers must explicitly clear them
to read changes from the backing store. A deterministic test exercised the actual
checkout, with a provider that delivers an image after the first availability
check. Before the repair, the cached size/status prevented checkout from noticing
delivery and the test failed with `LibraryDownloadTimeout`; after the repair the
same checkout succeeds and its copied image contains the delivered bytes.

`LibraryDownloadProvider.liveState` now clears cached resource values before
every provider query. Asset-cache comparison also refreshes source attributes.
The shared download path covers edit, asset loading, offline preparation,
import, export and migration. It still requires a current iCloud version:
[downloaded](https://developer.apple.com/documentation/foundation/urlubiquitousitemdownloadingstatus/downloaded.md)
means a stale local copy, which is unsuitable for an editing baseline.

Diagnostics now retain the failing phase and its metadata in the single operation
error, including asset index, hashed asset key, chapter identity, byte size,
upload/download activity, conflicts and provider error identities. Timeout errors
preserve available upload/attribute causes. Known iCloud and File Provider codes
have readable technical explanations throughout the console. Filenames, titles,
story text, paths, credentials and arbitrary provider descriptions remain excluded.
Reporting stacks remain labeled as reporting stacks.

Validation:

- The original checkout regression failed before the repair and passed afterward.
- 63 optimized Internal app tests passed on each dedicated iPhone and iPad simulator.
- 9 Swift core tests and 6 Python authoring tests passed.
- The full Local binary SDK isolation audit passed.
- Additional tests verify an idle-provider timeout keeps its asset/chapter and
  quota cause, stale downloaded copies remain protected, original nested errors
  remain intact, and cancellation remains cancellation.

The captured trace does not establish whether iCloud itself also stalled on the
physical device. Reopen the affected book after installing the new build; any
remaining provider failure will now retain fresh state and available causes.
Physical iCloud downloads, cross-device edits and device installation require
separate acceptance. Release processing and distribution are recorded in
[TESTFLIGHT.md](TESTFLIGHT.md).
