# Newbee: Data Model

Status: **Draft for approval** · Deliverable 5

## 1. Principles

1. **Absolute UTC timestamps** (`Date`) for every instant. Each session also stores the IANA `timeZoneID` where it started, so history shows "2:15 AM" as the parent experienced it even after travel.
2. **Store facts, derive totals.** Per-side durations, total feeding time, starting side, and intervals are computed, never stored (ADR-002).
3. **CloudKit-ready** (ADR-005): every property optional or defaulted, relationships optional, no unique constraints.
4. **Enums stored as raw `String`**, with typed computed accessors. *Why:* SwiftData `#Predicate` on iOS 17 can't reliably filter on enum-typed properties.
5. **Canonical units.** Volume is stored in mL (`Double`). The unit the parent typed is stored too, so editing shows their original entry.
6. **`VersionedSchema` from day one**, so every later change is a planned migration.

## 2. Entities (SwiftData `@Model`, schema V1)

### `Baby`
| Field | Type | Notes |
|---|---|---|
| `id` | `UUID` = `UUID()` | stable identity (not `.unique`, see ADR-005) |
| `name` | `String` = `""` | nickname; optional in onboarding |
| `birthDate` | `Date?` | |
| `createdAt` | `Date` = `.now` | |
| `sessions` | `[FeedingSession]?` | inverse; delete rule `.cascade` |

### `FeedingSession`
One feeding event of any kind.

| Field | Type | Notes |
|---|---|---|
| `id` | `UUID` | |
| `baby` | `Baby?` | |
| `kindRaw` | `String` = `"breast"` | `breast`, `bottle`, `pump` *(future)*, `combo` *(future)* |
| `statusRaw` | `String` = `"completed"` | `active`, `paused`, `completed`. "Not started" is never persisted. |
| `startedAt` | `Date` | for breast: first segment start; for bottle: entered time |
| `endedAt` | `Date?` | nil while active or paused |
| `timeZoneID` | `String` | `TimeZone.current.identifier` at start |
| `notes` | `String` = `""` | |
| `sourceRaw` | `String` = `"timer"` | `timer`, `manual`, `recovered`. Lets insights flag estimated data. |
| `needsReview` | `Bool` = `false` | set by recovery when data is ambiguous |
| `revision` | `Int` = `0` | bumped on every mutation; used for intent idempotency |
| `createdAt` / `modifiedAt` | `Date` | |
| `segments` | `[FeedingSegment]?` | `.cascade` |
| `bottle` | `BottleDetails?` | `.cascade` |

Computed (not stored): `kind`, `status`, `orderedSegments`, `leftDuration(now:)`, `rightDuration(now:)`, `feedingDuration(now:)` (sum of segments), `span` (`endedAt − startedAt`), `startingSide`, `lastSide`, `openSegment`.

### `FeedingSegment`
One continuous stretch on one breast. Pauses are *gaps between segments*, not separate records.

| Field | Type | Notes |
|---|---|---|
| `id` | `UUID` | |
| `session` | `FeedingSession?` | inverse |
| `sideRaw` | `String` = `"left"` | `left`, `right` |
| `startedAt` | `Date` | |
| `endedAt` | `Date?` | nil = currently open (at most one per session) |
| `startMonotonic` | `Double?` | continuous-clock seconds at start (same-boot clock-change detection) |
| `startBootID` | `String?` | boot identifier at start |

The spec's example (2:15 L 12 min → R 9 min → end 2:36) is stored as 1 session plus 2 segments:
`[L 02:15–02:27] [R 02:27–02:36]`. Feeding time = 21 min, span = 21 min.

### `BottleDetails`
| Field | Type | Notes |
|---|---|---|
| `session` | `FeedingSession?` | inverse |
| `contentsRaw` | `String` = `"breastMilk"` | `breastMilk`, `formula`, `other` (`mixed` reserved) |
| `amountML` | `Double` = `0` | canonical; validated 0 < x ≤ 500 |
| `enteredUnitRaw` | `String` = `"ml"` | `ml`, `oz` |
| `durationSeconds` | `Double?` | optional; or derive from session start/end |

### Future (no V1 table, designed now)
- **`PumpDetails`** (`leftML`, `rightML`, reuses `FeedingSegment` for timing): `kind = pump`.
- **Combination feed**: one session with `kind = combo`, both segments *and* `BottleDetails`. No restructuring needed.
- **Diaper/sleep logs**: separate `@Model`s on `Baby`, not overloading `FeedingSession`.

### Not in SwiftData
- **AppPreferences**: App Group `UserDefaults` keys: `volumeUnit`, `bottlePresets` (JSON `[Double]` in mL), `reminder.enabled`, `reminder.intervalMinutes`, `reminder.quietStart`, `reminder.quietEnd`, `reminder.basis` (`start`/`end`), `stillFeeding.minutes`, `appearance`, `intervalDefinition`, `onboardingComplete`, `schemaVersionSeen`.
- **Bottle presets** are prefs, not entities.

## 3. Invariants (enforced by `SessionEngine` + repository, covered by tests)

1. At most **one** session with status `active` or `paused` across the store.
2. `active` ⇔ exactly one open segment. `paused` ⇔ zero open segments and ≥1 closed segment. `completed` ⇔ zero open segments and `endedAt != nil`.
3. Segments within a session don't overlap and are ordered by `startedAt`. Each `endedAt ≥ startedAt`.
4. `session.startedAt == first segment.startedAt` for breast sessions; `endedAt ≥ last segment.endedAt`.
5. Bottle sessions have `BottleDetails` and no segments (until `combo`).
6. Editing re-validates 2 to 4; violations are surfaced in the editor and never saved.

## 4. Time handling

- **Day grouping** uses `Calendar.current` in the *current* time zone for calendar and dashboard views, with the session's `timeZoneID` used for displaying its own clock times. A feed belongs to the day it **started**.
- **DST:** durations are differences of absolute instants, so a 01:30→01:10 "fall back" feed still shows 40 min correctly. Day boundaries come from `Calendar.startOfDay`, which handles 23- and 25-hour days.
- **Rolling 24 h:** window `[now − 24h, now]`; a session counts if it *started* in the window. Feeding time inside the window is clipped to the window edges.

## 5. Indexing and performance

- iOS 17 lacks `#Index`. Expected volume is about 12 feeds/day, roughly 4,400/year, roughly 9,000 segments. Fetching by `startedAt` range is fast enough without indexes. Add `#Index([\.startedAt])` behind `if #available(iOS 18)` in schema V2 if profiling shows a need.
- Insights fetch the selected range once, map to value types, and compute off-main.

## 6. Deletion and integrity

- Delete session → cascades segments and bottle details. Confirmation dialog plus undo toast (soft-hold the snapshot in memory for undo; re-insert on undo).
- "Delete all data" in Settings → delete all `Baby` (cascades), end any Live Activity, cancel all notifications, reset prefs except appearance. Requires typed confirmation.
- Deleting the active session also ends its Live Activity and reminders through the manager.

## 7. Migration plan

- `NewbeeSchemaV1` ships at 1.0. Every model change adds `NewbeeSchemaV(n+1)` plus a stage in `NewbeeMigrationPlan`.
- A test loads a V1 fixture store and migrates it (see `TESTING.md`).
