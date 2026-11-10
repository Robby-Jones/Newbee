# Newbee: Data Model

Status: **Draft for approval** · Deliverable 5

## 1. Principles

1. **Absolute UTC timestamps** (`Date`) for every instant. Each session also stores the IANA `timeZoneID` where it started, so history shows "2:15 AM" as the parent experienced it even after travel.
2. **Store facts, derive totals.** Per-side durations, total feeding time, starting side, and intervals are computed, never stored (ADR-002).
3. **CloudKit-ready** (ADR-005): every property optional or defaulted, relationships optional, no unique constraints.
4. **Enums stored as raw `String`**, with typed computed accessors. *Why:* SwiftData `#Predicate` still filters unreliably on enum-typed properties, and raw strings are CloudKit-safe.
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
| `kindRaw` | `String` = `"breast"` | `breast`, `bottle`, `pump` (V2), `combo` *(future)* |
| `statusRaw` | `String` = `"completed"` | `active`, `paused`, `completed`. "Not started" is never persisted. |
| `startedAt` | `Date` | for breast: first segment start; for bottle: entered time |
| `endedAt` | `Date?` | nil while active or paused |
| `timeZoneID` | `String` | `TimeZone.current.identifier` at start |
| `notes` | `String` = `""` | |
| `sourceRaw` | `String` = `"timer"` | `timer`, `manual`, `recovered`, `imported` (from a Huckleberry export; "Remove imported data" deletes exactly these). Lets insights flag estimated data. |
| `needsReview` | `Bool` = `false` | set by recovery when data is ambiguous |
| `recoveryAcknowledgedAt` | `Date?` | when the parent last answered "Keep going"; recovery doesn't ask again about older data |
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

### `PumpDetails` (V2)
| Field | Type | Notes |
|---|---|---|
| `session` | `FeedingSession?` | inverse of `FeedingSession.pump` |
| `leftML` | `Double` = `0` | canonical; either side may be 0, total > 0, each side ≤ 500 |
| `rightML` | `Double` = `0` | canonical |
| `enteredUnitRaw` | `String` = `"ml"` | `ml`, `oz` |
| `durationSeconds` | `Double?` | optional, 1 min – 2 h |

A pumping session is a completed `FeedingSession` with `kind = pump`, `source = manual`, `PumpDetails` and no segments; `endedAt = startedAt + duration`. It is entered by hand like a bottle (the earlier plan to time it with `FeedingSegment`s was dropped for manual entry). **Pumping is not a feed**: `completedFeeds` queries exclude `kind = pump`, so it never counts toward feed totals, gaps, reminders, Insights or the suggested side. `completedPumps` reads pumping sessions.

### Future (designed now)
- **Combination feed**: one session with `kind = combo`, both segments *and* `BottleDetails`. No restructuring needed.
- **Diaper/sleep logs**: separate `@Model`s on `Baby`, not overloading `FeedingSession`.

### Not in SwiftData
- **AppPreferences**: App Group `UserDefaults` keys: `volumeUnit`, `bottlePresets` (JSON `[Double]` in mL), `reminder.enabled`, `reminder.intervalMinutes`, `reminder.quietStart`, `reminder.quietEnd`, `reminder.basis` (`start`/`end`), `stillFeeding.minutes`, `appearance`, `intervalDefinition`, `onboardingComplete`, `schemaVersionSeen`.
- **Bottle presets** are prefs, not entities.
- **Baby photo**: one JPEG (longest side 600 px) at `Application Support/BabyPhoto/photo.jpg`, app container only (not the App Group, not synced). Written by `BabyPhotoStore`; removed by "Delete all data".

## 3. Invariants (enforced by `SessionEngine` + repository, covered by tests)

1. At most **one** session with status `active` or `paused` across the store.
2. `active` ⇔ exactly one open segment. `paused` ⇔ zero open segments and ≥1 closed segment. `completed` ⇔ zero open segments and `endedAt != nil`.
3. Segments within a session don't overlap and are ordered by `startedAt`. Each `endedAt ≥ startedAt`.
4. `session.startedAt == first segment.startedAt` for breast sessions; `endedAt ≥ last segment.endedAt`.
5. Bottle sessions have `BottleDetails` and no segments (until `combo`); pump sessions have `PumpDetails` and no segments.
6. Editing re-validates 2 to 4; violations are surfaced in the editor and never saved.

## 4. Time handling

- **Day grouping** uses `Calendar.current` in the *current* time zone for calendar and dashboard views, with the session's `timeZoneID` used for displaying its own clock times. A feed belongs to the day it **started**.
- **DST:** durations are differences of absolute instants, so a 01:30→01:10 "fall back" feed still shows 40 min correctly. Day boundaries come from `Calendar.startOfDay`, which handles 23- and 25-hour days.
- **Rolling 24 h:** window `[now − 24h, now]`; a session counts if it *started* in the window. Feeding time inside the window is clipped to the window edges.

## 5. Indexing and performance

- V1 has no `#Index` (it was written for an iOS 17 floor; the floor is now iOS 18, so indexes are available). Expected volume is about 12 feeds/day (~4,400/year), which range fetches on `startedAt` handle without one. If profiling ever shows a need, add an index in a later schema version.
- Insights fetch the selected range once, map to value types, and compute off-main.

## 6. Deletion and integrity

- Delete session → removes its segments and bottle details. Always go through `FeedingSession.deleteWithChildren(from:)`, because SwiftData's `.cascade` rule didn't reliably delete children on iOS 17 (caught by the former iOS 17 CI job), and the explicit path is kept on iOS 18. The `.cascade` rules stay in the schema as a second line of defence. Confirmation dialog plus undo toast (soft-hold the snapshot in memory for undo; re-insert on undo).
- "Delete all data" in Settings → delete every session through `deleteWithChildren`, then every `Baby` (don't rely on `.cascade`; see above), end any Live Activity, cancel all notifications, reset prefs except appearance and `onboardingComplete` (deleting data doesn't replay onboarding). Requires typed confirmation.
- Deleting the active session also ends its Live Activity and reminders through the manager.

## 7. Migration plan

- `NewbeeSchemaV1` ships at 1.0. Every model change adds `NewbeeSchemaV(n+1)` plus a stage in `NewbeeMigrationPlan`.
- **V2** adds `PumpDetails` and `FeedingSession.pump`. V1 → V2 is a lightweight stage (new entity plus an optional relationship). V1 stays in the code, frozen, so older stores can migrate. `PumpPersistenceTests.versionOneStoreMigrates` writes a V1 store and opens it with V2.
- A test loads a V1 fixture store and migrates it (see `TESTING.md`).
