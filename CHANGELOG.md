# Changelog

This repository's published history begins with a squashed `Initial commit`,
because the work leading up to it was done on a private branch that still holds
device-specific identifiers. That baseline therefore hides a lot: 171 commits
on top of the upstream project. This file lists what went into it, so the
squash does not erase the record.

Commits made after the baseline are published one by one, so they appear in the
git log on their own — except any that touch only files this repository does
not carry (the publishing tooling and its templates), which drop out as empty.

## Baseline — bundled into `Initial commit`

### Capture and polish
- Quick-capture path that turns one fragment into a typed timeline card without
  going through the heavyweight multi-agent flow.
- `PolishService` producing a plain and a more literary rewrite, with graceful
  degradation when the model returns nothing usable.
- Three-column compare dialog and an editable confirm step before anything is
  saved; the original text is stored and can be toggled on the card.
- Voice notes: on-device transcription, playback, verbatim transcript.

### Search
- Keyword retrieval with date and tag filters, plus a card search screen and a
  timeline entry point.
- Semantic retrieval on local `bge-m3` embeddings, fused with keyword results
  via RRF; a `card_embeddings` table with its own migration and an incremental
  index task that mirrors the FTS one, with backfill.
- An agent tool that answers from cards and returns tappable source cards.

### Summaries and reminders
- A generic rollup engine with a period abstraction, driving daily, weekly,
  monthly (hybrid weekly+daily collection) and yearly narrative summaries.
- Local reminders on a single exclusive chain — year > month > week > day, so
  Dec 31 offers the annual summary rather than the monthly one — plus a
  settings toggle. Reminder copy is currently Chinese only.

### Backups and data safety
- Prominent export entry, recorded export time, and a home banner that nudges
  an external export once it is overdue.
- Safety snapshots taken before wiping data and before a database migration,
  written outside the directory a wipe removes so they survive it.
- An iCloud Drive folder picker with a security-scoped bookmark, and a daily
  rolling backup (idempotent per day, two copies kept) that survives an app
  reinstall; restore and delete go through the same scoped channel.
- Per-file iCloud upload status surfaced in settings.

### Memory book export
- A cover plus timeline PDF over a date range, with bundled CJK fonts, image
  collection and limits, and delivery through the system share sheet.

### Cards
- Media cards for books, films, shows, music and podcasts: detection during
  quick capture, a native template, status and rating endpoints, detail badges,
  and a browsable media library.
- Goal cards: a goals table with its own migration, DAO and service, list and
  form screens, and an entry point from settings.
- Goal suggestions detected during quick capture, surfaced as an inline confirm
  card in chat, applying an atomic progress increment when accepted.
- Calendar sync for card due dates; manual entry for to-dos and media.

### Insight and navigation
- A deterministic mood curve in activity stats, with a date axis.
- Activity stats trimmed to what the numbers can actually support.
- Insight moved into the bottom-right navigation slot; the timeline swipe tab
  strip dropped in favour of full-page navigation, with a clear-filter
  affordance.
- A thin top progress bar in place of a floating status pill.

### Removed or hidden
Features that depend on a large multi-agent loop do not work on a locally
hosted model — in testing, a single turn exposing 23 tools either timed out or
came back empty. Rather than ship dead ends, these were removed or hidden
behind a flag: AI knowledge insights, the knowledge-base tab, persona chat,
AI card comments (default off), the calendar month view, the action-center
bell, and the schedule entry points. Health and step tracking were removed
outright, along with their dependencies and platform permissions.
