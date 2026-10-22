# Interline

A local, native SwiftUI reader focused on Chinese long-form text.

## Development plan

All ongoing development follows [the plan index](plans/README.md) and the
repository's [agent instructions](AGENTS.md). The active improvement program has
requirements, development design, test/acceptance design, an evidence-based final
acceptance record, and an execution log. Unfinished work remains explicitly tracked.

## Build and test

- Xcode 27 with an iOS 27 simulator
- Swift 6
- XcodeGen (`brew install xcodegen`)

```sh
xcodegen generate
xcodebuild test -project Interline.xcodeproj -scheme Interline \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
```

Choose an installed iOS 27 iPhone simulator if the example device is unavailable.
CI uses GitHub's `xcode-27` image, checks the SDK, and selects an available simulator.
The deployment target is iOS 27, as required by `AGENTS.md`.

The `reader-verification` CI artifact contains `build.log`, the result bundle,
UI attachments, and `verification-summary/summary.json` / `summary.md`.
The summary links the checkout revision and workflow run, distinguishes observed
test assertions from build/runner failures, and never retries or waives failures.
Nested XCTest suite totals are listed separately, not added together. Missing logs
and cancellations do not imply a passing test run. To test the classifier locally:

```sh
python3 -m unittest discover -s scripts/tests -v
```

## Reader foundation

- Core Text measures and draws the same frames using the actual reading canvas.
- A reading location is a stable chapter ID plus a UTF-16 offset in
  `Chapter.readingText` (heading and paragraphs separated by two newlines).
- Resizing or changing typography resolves that original anchor in the new layout.
  Page turns install a new anchor. Progress counts through the visible page end;
  displaying the last page of the last chapter reaches 100%.
- Bookmarks store text anchors and a preview from the visible page.
- Only the current chapter is paginated. Its frames are reused when turning pages.
- Page turns write a small per-book reading record rather than encoding the catalog.
- The v1 catalog, preferences and bookmarks remain readable. New optional anchor
  fields decode from older data. Legacy page numbers are mapped to the new layout
  on first use; old exact text positions cannot be recovered because v1 did not
  store them.
- An intentionally empty shelf remains empty. Examples can be explicitly restored.
  Removing a book retains its reading record and bookmarks for undo/re-adding.
- Decode failures retain the original data and report an error instead of silently
  replacing the user's library with sample content.

## Verification

`InterlineTests` covers UTF-16/grapheme boundaries, complete pagination coverage,
empty chapters, small viewports, page/paragraph changes, typography and resize
anchors, chapter boundaries, bookmarks, progress seeking, relaunch, v1 decoding,
empty shelves, restored reading records, invalid indexes, search and independent record writes.

Before release, also check on a physical device:

1. Read a long chapter, turn pages in both directions and cross a chapter boundary.
2. Change font size, font family, spacing and background; rotate and reopen the app.
3. Create a bookmark mid-chapter, change typography, and return through the bookmark.
4. Seek to the start/end, delete all books, relaunch, restore examples and undo a deletion.
5. Use VoiceOver's reading actions and inspect small screens and landscape sheets.

## Local reading features

- Import TXT from Files with a preview, editable title/author, automatic UTF-8/BOM
  UTF-16/GB18030 decoding and manual encoding retry. Files are limited to 20 MB.
  Automatic detection is heuristic; inspect the preview before confirming.
- Recognize Chinese and English chapter headings. Unstructured text and very long
  chapters are divided into bounded sections without dropping paragraph content.
- Deduplicate normalized text across file names; re-import can repair missing
  content while retaining the previous reading anchor.
- Book details support metadata editing, chapter navigation, TXT export, removal
  with undo, and confirmed permanent deletion of content/records/bookmarks/notes.
- Debounced, cancellable full-book text search (up to 200 results) returns exact
  UTF-16 anchors. Search is local and case/diacritic insensitive.
- Long-press a reading page or tap the selection control to open a native selectable
  text surface. Use system copy/lookup, then highlight or write a note. Highlights
  are painted in the reading canvas without changing line layout. Notes can be
  edited, deleted, exported and used to return to the original text.
- App appearance follows the system by default and is independent of reading
  paper colors. Reader text can follow Dynamic Type. Controls support VoiceOver,
  reduced motion and reduced transparency; floating chrome uses native Liquid Glass.

## Storage and performance

Books migrate from the v1 UserDefaults catalog into an atomic file-backed v2
metadata catalog and separate immutable chapter files in Application Support.
The legacy catalog is retained as a recovery source; permanent deletion also
removes that book from the legacy backup. Missing/corrupt files are reported and
metadata remains visible so the book can be repaired or removed. Page turns still
write small per-book records; annotations have their own atomic file.

Import parsing, source reads, large imported-content writes, search and page-range
calculation run off the main actor with cancellation checks. Layout jobs carry a
generation token so stale work cannot replace a newer book/size/style. A bounded
six-entry range cache is reused across page turns and recent layout changes.
Core Text objects are created and used within their own work operation; only plain
Sendable ranges cross to the main actor, which creates the current drawing frame.

Production startup loads metadata and chapter summaries only. The current book is
loaded asynchronously on opening and released on close; inactive bodies are released
on memory warnings. Older catalogs acquire missing summaries in a bounded background
migration. Pagination ranges have a six-entry, 2 MiB estimated slice-storage budget;
oversized layouts remain usable without being retained in the range cache. EPUB, online catalogs and cloud sync are
not included. Import normalization does not preserve the original file's whitespace
formatting. Selection happens in a dedicated native sheet, rather than conflicting
with page-turn gestures on the canvas. Exact selection gestures and long-session
performance still need physical-device testing.

## Functional acceptance

The automated suite includes the original reader regressions, TXT/encoding and
chapter parsing, file migration/repair, duplicate import, asynchronous cancellation,
search navigation, Unicode annotation ranges, notes, deletion, metadata and Dynamic
Type. UI smoke tests exercise the bookshelf, reader, typography, search and selection
entry points and attach screenshots to the CI result bundle.

Manual acceptance on a signed device:

1. Import a UTF-8 and a GBK TXT from Files; inspect the preview and chapter list.
2. Import the same content under another name and verify the duplicate is detected.
3. Search a phrase, return to it, annotate a selection, add/edit/export its note.
4. Change typography and orientation, switch books rapidly, quit and reopen.
5. Export TXT, remove/undo, and separately confirm permanent deletion.
6. Test VoiceOver, larger accessibility text, reduced motion and transparency.

## iPhone device package

Run the **iPhone Device Package** workflow on `main` to archive a physical-device
Release build and download its unsigned IPA. Device packaging verifies arm64,
iPhoneOS, the minimum OS and ZIP integrity, and includes build metadata.
**An unsigned IPA is not directly installable.** See [installation and signing](docs/INSTALLATION.md).
The project allows automatic signing for local Xcode device runs; CI disables
signing explicitly. Apple credentials are not committed to the repository.


## Recovery safeguards

Before replacing an unreadable catalog or annotation file, Interline saves its
exact bytes under `Application Support/Interline/Recovery` with a unique name.
If that backup cannot be saved, the original file is left untouched and the
operation reports failure. Recovery copies are retained for manual recovery;
the app does not claim to reconstruct a malformed file automatically.
Unreadable UserDefaults bookmarks, preferences, and reading records receive the
same protection: a binary property-list archive retains the original key/value
(including exact Data bytes) before replacement. Failure to archive refuses the
write. Valid values keep their original formats without generating recovery copies.
These raw recovery files can be exported from Data and storage; they are not added
to the existing complete-library JSON backup automatically.
Missing book contents preserve saved reading anchors and prompt reimport rather
than opening an empty reader. Shelf removal and undo update the visible library
only after the catalog is saved. Text selection captures an immutable page and
anchor so orientation or typography changes cannot move an in-progress note.


## Library management and recovery

Open **Bookshelf > Sort/filter menu > Data and storage** to export or merge a
complete JSON backup (maximum 256 MiB). It includes active and removed books,
reading records, settings, bookmarks, annotations and note drafts. Backups contain
private reading content and are not encrypted. Merge restore keeps existing book
metadata and annotations with the same IDs; an empty library restores preferences.
Conflicting existing book bodies are rejected instead of overwritten.

Multi-file removal and restore operations write a rollback journal first. A new
launch restores the previous catalog, notes, drafts, maintenance state and reading
records if the operation was interrupted. Immutable newly staged bodies may remain
unreferenced after a failed operation; they do not replace existing bodies. A failed
rollback blocks subsequent writes until recovery succeeds.
If rollback itself fails, the app explicitly reports that recovery is still
pending, keeps the journal, and directs the user to retry instead of claiming the
previous data has already been restored.

Removed books remain accessible across launches. Permanent deletion first records
a durable cleanup task; partial cleanup can be retried without reimporting the book.
Original damaged files can be exported from the recovery section. Unreadable data
is retained, but malformed files cannot be guaranteed to reconstruct automatically.

Note editors coalesce draft input for 300 ms, encode and atomically save it off the
main actor, and show saving/saved/unsaved status with retry. Cancel, note submission,
and backup/restore wait for pending drafts; destructive maintenance refuses unsaved
input. App inactivity requests a flush, but forced termination before “saved” can
still lose the latest unsaved characters. Drafts can be resumed
from Data and storage. Selection has a one-tap paragraph action alongside native
selection handles. Search briefly highlights the matching range; explicit chapter,
bookmark, progress and search jumps can return through a bounded position history.
Shelf sorting/filtering works from metadata without loading all book bodies.
Margins, paragraph spacing and tap zones are adjustable. Appearance-only changes
reuse pagination rather than triggering a loading transition.

Automated checks include backup/merge, interrupted-operation recovery, cleanup retry,
note-save failure, lazy loading and close cancellation, a 100-book catalog fixture,
selection rotation, note creation/relaunch and background/foreground restoration.
Signed-device acceptance still covers actual Files/iCloud provider interaction,
VoiceOver speech/gestures, sustained memory/energy use and long-session comfort.
