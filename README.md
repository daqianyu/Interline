# Interline

A local, native SwiftUI reader focused on Chinese long-form text.

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

Chapter content is currently hydrated into memory on launch; future very large
libraries may need lazy chapter loading. EPUB, online catalogs and cloud sync are
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
