# ADR-004 — Anki `.apkg` import: scope, dependencies and module placement

Status: Accepted
Date: 2026-08-11
Bead: `fu-apkg-import` (new; no source bead — this decision creates the work)
Deciders: owner (explicit decision, 2026-08-11); implementation agent

## Context

`flash-up-architecture-brief.md` lists `.apkg` as deferred in two places — line 239
("Deferred: Anki `.apkg` import and export") and line 459 ("Anki `.apkg` compatibility") —
and lists media attachments as deferred at lines 135 and 455.

`AGENTS.md` requires that a conflict between the brief and the implementation be recorded as
an ADR, and that a decision of this weight must not be absorbed silently into a batch. The
owner asked for `.apkg` import on 2026-08-11 and chose, explicitly and against the
conservative option in each case:

1. **both** container generations (legacy and modern), not legacy only;
2. media **imported**, not stripped or rejected;
3. field mapping **chosen by the user**, not a fixed heuristic;
4. this ADR plus a brief/spec amendment.

Choice 2 reopens "Media attachments", which is why this ADR covers both. That is the
consequence the owner accepted, not a scope expansion by the implementer.

## 1. Decision: import only, never export

Flash Up **reads** `.apkg`. It does not write it, now or as a follow-up.

Writing `.apkg` means generating note types, card templates and a scheduling state that
Anki will accept, i.e. owning a compatibility surface against a moving target we do not
control. Reading is a one-way, best-effort translation into our own model, where a
misunderstanding costs a badly mapped field the user can see and fix in the preview — not
a corrupted collection in someone else's app.

Brief lines 239/459 are amended to "import only".

## 2. What an `.apkg` actually is

A ZIP containing a SQLite database plus media blobs, in two generations:

| | legacy (< 2.1.50, or "support older Anki versions") | modern (2.1.50+, today's default) |
| --- | --- | --- |
| database entry | `collection.anki2` / `collection.anki21`, plain SQLite | `collection.anki21b`, **zstd**-compressed |
| ZIP entry method | deflate | stored (zstd does the compressing) |
| media index | `media`, JSON `{"0": "photo.jpg"}` | `media`, **protobuf** |
| media blobs | numbered entries, plain | numbered entries, each zstd-compressed |

Inside the database, two schema generations must both be handled — the number is in
`col.ver`:

- **schema 11**: note types and decks are JSON blobs in the `col.models` / `col.decks` columns;
- **schema 18**: real `notetypes` / `fields` / `templates` / `decks` tables.

Common to both: `notes.flds` is the fields concatenated with `0x1F` (unit separator),
`notes.tags` is space-separated, `cards.nid`/`cards.did` give the note → deck mapping, and a
note type is cloze when its `type == 1`.

Field text is **HTML**, not Markdown.

**This schema variance is the main risk in the whole feature**, and it is why implementation
starts from real exported files rather than from synthesised fixtures.

## 3. Decision: hand-written ZIP and SQLite, external dependency only for zstd

| Piece | How | Why |
| --- | --- | --- |
| ZIP (stored + deflate) | hand-written reader over Apple's `Compression` (`COMPRESSION_ZLIB` is raw deflate) | Already on the system. A general-purpose ZIP package would carry writing, encryption and format variants we will never use, for ~200 lines we do need. |
| SQLite | system `libsqlite3`, `.linkedLibrary("sqlite3")` + `import SQLite3` | Already on the system; not a package. A Swift SQLite wrapper would add a dependency for six read-only queries. |
| zstd | **external dependency** | Apple ships no zstd. There is no system alternative. |

zstd is therefore the only new package. Pinned as `facebook/zstd`, `exact: "1.5.7"` — upstream
itself, not a third-party wrapper, so there is no intermediary to go stale.

**Verified by building a probe package** (same method as ADR-003 §1):

```
compressed 6500 -> 31, isError=0
declared content size = 6500
roundtrip ok = true
sqlite version = 3.51.0, open rc = 0
```

`facebook/zstd` v1.5.7 publishes a `Package.swift` exporting the `libzstd` product; it builds
under swift-tools 5.10 with `.iOS(.v17)`/`.macOS(.v14)` platforms, and `libsqlite3` links in
the same target. Alternatives rejected: `aperedera/SwiftZSTD` and `awxkee/zstd.swift` are
third-party wrappers over the same C library, adding a maintainer without adding capability;
vendoring the C amalgamation takes on permanent maintenance of code we do not own, which is
what §0.2's dependency list exists to prevent.

**Consequence to accept:** the pin is exact, so zstd never moves under us silently, and it
must be re-checked at `fu-15-release` like the FSRS pin.

## 4. Decision: the reader lives in `FlashUpData`, the mapping in `FlashUpDomain`

`AGENTS.md`: "`FlashUpDomain` remains pure and portable". ZIP, zstd, SQLite and the
filesystem are none of those things.

```
FlashUpData/Apkg/      ZipArchive, ZstdDecoder, ApkgArchive, AnkiMediaMap,
                       AnkiCollectionReader        -> produces ApkgCollection
FlashUpDomain/Import/  HTMLTextExtractor, FieldMapping, FieldMappingDefaults,
                       ApkgRowMapper               -> produces CSVParseOutcome
```

The dependency on zstd is declared on the `FlashUpData` target only. `FlashUpDomain` gains no
new dependency and keeps building for macOS, so the mapping and HTML logic — the part with
the interesting edge cases — stays testable with `swift test`, no simulator.

`ApkgCollection` and friends describe *Anki*, not Flash Up, so they are `FlashUpData` types.
`FieldMapping` describes a *user decision* and is pure, so it is a `FlashUpDomain` type.

## 5. Decision: converge on the existing CSV pipeline, do not fork it

`ApkgRowMapper` returns a `CSVParseOutcome` — exactly what `CSVParser.parse` returns.
Everything downstream is therefore untouched: `ImportPlanner.plan`, duplicate detection via
`ContentFingerprint`, `commitImport`, and undo via `ImportBatch`.

The alternative — a parallel `.apkg` commit path — would duplicate the duplicate-detection
and undo semantics, which are the two places in the import flow where a bug destroys user
data. One pipeline, two front ends.

The type name `CSVParseOutcome` becomes slightly inaccurate. Renaming it would touch every
CSV call site and its tests for zero behavioural gain; the name stays, and this paragraph is
the explanation.

## 6. Decision: media are stored as blobs, referenced as text

Reopening media (owner choice 2) needs a representation that does not break content
fingerprinting, CSV export or backup — all of which operate on strings.

Media are referenced **inside** the note text with a Markdown-compatible URI:

```
![](flashup-media://<uuid>)          image
[audio](flashup-media://<uuid>)      audio
```

and stored **outside** it as blobs, content-addressed by SHA-256 under
`Application Support/Media/`, behind a pure `MediaStore` protocol in Domain with a
`FileMediaStore` actor in Data.

Consequences:

- `ContentFingerprint` needs no change — the reference is text, so two notes carrying the
  same image still deduplicate correctly;
- content addressing deduplicates blobs across decks for free;
- `Note`/`NoteDraft` gain `mediaIDs: [UUID] = []`; the default keeps every existing call site
  source-compatible;
- `CardGenerator` needs no change; references travel inside `front`/`back` as text.

Accepted formats: `png/jpg/jpeg/gif/webp/heic`, `mp3/m4a/wav/ogg`. **Video is not supported**
and its notes are rejected with a visible reason.

**Garbage collection:** a blob is deleted only when no *live* note references it — swept on
`deleteAllData()` and after emptying the trash, and deliberately **not** on import undo, where
notes are soft-deleted and can come back. Deleting blobs there would be data loss, which
`AGENTS.md` forbids outright.

## 7. Decision: backup keeps media references, not media bytes

`BackupDocument` goes to `version: 2` (v1 still decodes), `BackupNote` gains `mediaIDs`, and
the document gains the `MediaAsset` records. **The blobs stay out of the JSON.**

A backup of a media-heavy collection would otherwise be hundreds of megabytes of base64 in a
single JSON file — slow to write, slow to parse, and prone to failing on the devices that
need it most. A restore whose blob is missing renders a placeholder rather than failing the
note.

This is a real limitation, and it must be visible: it is stated in the backup screen copy,
not only here.

## 8. Hard limits

An `ApkgLimits`, injectable like `CSVLimits`, covering: max notes (10 000, matching CSV), max
file bytes, **max decompressed bytes**, max media count, max bytes per media.

The decompressed-bytes cap is not a nicety. An `.apkg` is untrusted input from the internet,
and both deflate and zstd can expand a tiny archive into gigabytes. Every decompression path
is capped, and every offset read from the ZIP structures is bounds-checked — SwiftLint's
`force_unwrapping` rule is an error outside tests, which enforces this mechanically.

Parse failures name the note index, never the note content (`AGENTS.md`: card text never
reaches logs).

## 9. Amendments this ADR makes

| File | Change |
| --- | --- |
| `flash-up-architecture-brief.md:135` | media: deferred → supported (images + audio; video deferred) |
| `flash-up-architecture-brief.md:239` | `.apkg` import and export deferred → import supported, export deferred |
| `flash-up-architecture-brief.md:455` | remove "Media attachments" from Explicitly deferred |
| `flash-up-architecture-brief.md:459` | `.apkg` compatibility → `.apkg` **export** compatibility |
| `flash-up-implementation-spec.md` §A9 | new §A9.5 with the `.apkg` contract and limits (§A9.4 is taken by CSV export) |

## 10. Evidence

To be completed as the phases land:

- probe build of `facebook/zstd` 1.5.7 + `libsqlite3` — **done**, output in §3;
- `ApkgReaderTests` against real `.apkg` fixtures, one per container generation and one per
  database schema generation;
- `HTMLTextExtractorTests`, `FieldMappingDefaultsTests`, `ApkgRowMapperTests`;
- an end-to-end test in `LibraryFlowTests` proving `.apkg` import and undo behave exactly as
  the CSV path already does;
- a real AnkiWeb deck imported by hand in the simulator — the check that synthetic fixtures
  cannot replace.
