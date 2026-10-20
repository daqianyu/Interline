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
empty shelves, invalid indexes, search and independent record writes.

Before release, also check on a physical device:

1. Read a long chapter, turn pages in both directions and cross a chapter boundary.
2. Change font size, font family, spacing and background; rotate and reopen the app.
3. Create a bookmark mid-chapter, change typography, and return through the bookmark.
4. Seek to the start/end, delete all books, relaunch, restore examples and undo a deletion.
5. Use VoiceOver's reading actions and inspect small screens and landscape sheets.

## Remaining scope

This is the first reliability milestone. TXT import/encoding detection, EPUB,
text selection and annotation, full-text search, file-backed book content,
background/cancellable long-chapter layout, richer accessibility and native
Liquid Glass refinement remain future work. `demo.html` is a separate prototype;
it does not share persistence or runtime code with the iOS application.
