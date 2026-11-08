# Newbee: Persistent Feeding Session Engine

Status: **Draft for approval** · Deliverable 11 · Highest-priority subsystem

## 1. Core idea

There is no timer. There are only **timestamps** and a **clock**.

```
feedingTime(now) = Σ closedSegments (endedAt − startedAt) + (openSegment ? now − openSegment.startedAt : 0)
sideTime(side, now) = same sum, filtered by side
```

The UI ticks by *re-rendering* that formula, using `TimelineView(.periodic(from:by: 1))` or `Text(timerInterval:)`. Nothing has to keep running for the numbers to stay right. That's why it survives backgrounding, suspension, termination, and reboot without special cases.

## 2. Components

| Component | Where | Role |
|---|---|---|
| `SessionEngine` | NewbeeKit (pure) | State machine: `apply(_ command: Command, to state: SessionSnapshot?, at now: Instant) throws -> Transition` |
| `AppClock` | NewbeeKit | `now`, `monotonic` (continuous since boot, includes sleep), `bootID` |
| `RecoveryPlanner`, `SessionValidator` | NewbeeKit (pure) | Recovery decisions; the invariants shared by the engine and manual edits |
| `FeedingSessionManager` | NewbeeKit `SessionManagement/`, `@MainActor @Observable` | Loads state, runs the engine, persists, publishes, fans out side effects |
| `RecoveryCoordinator` | NewbeeKit `SessionManagement/` | Launch and foreground reconciliation, the "still feeding?" flow |
| `FeedingRepository` | Protocol + `InMemoryFeedingRepository` in NewbeeKit; `SwiftDataFeedingRepository` in the app | Persistence for snapshots |

The manager and coordinator talk to storage and ActivityKit only through protocols (`FeedingRepository`, `LiveActivitySyncing`, `ReminderScheduling`), so they live in NewbeeKit and are tested on Linux with fakes. The app supplies the SwiftData repository and the ActivityKit coordinator.

### Value types (NewbeeKit)
```swift
enum Side: String { case left, right; var opposite: Side }
enum SessionStatus: String { case active, paused, completed }   // "notStarted" == no session
struct Instant { var wall: Date; var monotonic: Double?; var bootID: String? }
struct Segment { var id: UUID; var side: Side; var start: Date; var end: Date?; var startMonotonic: Double?; var startBootID: String? }
struct SessionSnapshot { var id: UUID; var status: SessionStatus; var segments: [Segment]; var startedAt: Date; var endedAt: Date?; var revision: Int; var timeZoneID: String }
enum Command { case start(Side), switchTo(Side), pause, resume, end, setEnd(Date) }
struct Transition { var snapshot: SessionSnapshot; var effects: Set<Effect> }   // .persist, .updateActivity, .endActivity, .rescheduleReminders, .haptic(...)
```

## 3. State machine

```
             start(side)
 (none) ───────────────────▶ ACTIVE ◀────────── resume ─────────┐
                              │  │ switchTo(other): close open seg,  │
                              │  │   open new seg on other side      │
                              │  └──────────────────────────────▶ PAUSED
                              │            pause: close open seg      │ switchTo(side): open seg on side → ACTIVE
                              │ end                                   │ end
                              ▼                                       ▼
                          COMPLETED ◀─────────────────────────────────┘
```

| From | Command | Result | Notes |
|---|---|---|---|
| none | `start(s)` | active, new session + open seg `s` | rejected if any active/paused session exists (`.alreadyActive(id)`) |
| active | `switchTo(s)` where s ≠ current | close seg at `now`, open seg `s` at `now` | |
| active | `switchTo(s)` where s == current | **no-op** (idempotent) | protects against double taps |
| active | `pause` | close seg; status paused | |
| paused | `pause` | no-op | |
| paused | `resume` | open seg on `lastSide` | |
| paused | `switchTo(s)` | open seg on `s`; status active | "resume on the other side" |
| active | `resume` | no-op | |
| active/paused | `end` | close any open seg; `endedAt = now` (paused: `endedAt` = last segment end) | |
| completed | anything | `.alreadyCompleted` → no-op for UI, ignored by intents | |
| any | (zero-length segment created by switch < 1 s after previous) | collapse/merge | avoids junk segments from rapid taps |

Every accepted transition increments `revision` by 1.

**Intents carry target state, not toggles.** "Switch to Right", not "toggle side". Replaying an intent twice can't flip the state back.

**Optional stale-check:** intents include `sessionID` and the `revision` they were rendered with. If `sessionID` doesn't match the active session, the command is ignored (stale Live Activity). For revision mismatches, target-state commands are still applied because they're idempotent. `end` is applied regardless.

## 4. Persistence flow (each command)

1. `let state = repository.activeSnapshot()` (fresh fetch, never cached UI state).
2. `let t = try engine.apply(cmd, to: state, at: clock.instant())`.
3. `repository.save(t.snapshot)` → `modelContext.save()` **synchronously before** any side effect. If the save throws: roll back, show error, no side effects.
4. Publish `activeSession = t.snapshot` (UI updates).
5. Fan out effects: `await liveActivity.sync(t.snapshot)`, `reminders.reschedule()`, haptics.

Writes are tiny, so saving on every command costs nothing and means a power loss at any moment loses at most the in-flight tap.

## 5. Recovery (launch, foreground, and `NSSystemClockDidChange`)

`RecoveryCoordinator.reconcile()` runs on `scenePhase == .active` and at launch:

1. **Fetch** all sessions with status `active` or `paused`.
2. **Duplicates (>1):** keep the newest by `startedAt`. Close the others at their last segment end, set `needsReview = true`. (This should be impossible; it's defense in depth.)
3. **Sanity checks** on the survivor:
   - **Negative or absurd elapsed** (open segment `startedAt > now`, i.e. the clock moved backwards): flag for review, show recovery sheet.
   - **Clock change within the same boot:** if `startBootID == clock.bootID` and `|wallElapsed − monotonicElapsed| > 60 s`, the wall clock changed. Trust monotonic elapsed for the *open* segment and offer "Fix start time" to `now − monotonicElapsed`. The fix shifts **every** timestamp of the session by the same offset (`SessionCommand.shiftTimestamps`), because all stored times are in the old clock frame; lengths and order are kept. Log `needsReview`.
   - **Different boot (device restarted):** monotonic data is unusable; trust wall timestamps (the normal case).
   - **Very long open segment** (> the "still feeding?" threshold, default 45 min, or > 3 h in any case): show the **recovery sheet**.
4. **Live Activity reconcile** (see `LIVE_ACTIVITIES.md` §6).
5. **Reschedule reminders.**

### Recovery sheet (never auto-discards)
> **Were you still feeding?** Started 2:15 AM on the left · running 3 h 12 min
> - **Keep going**: no change
> - **End at 2:41 AM**: pre-filled with a plausible end (segment start + median side duration for this baby, or the last interaction time), editable with a time picker
> - **End now**
> - **Discard session**: with undo toast

## 6. Time edge cases

| Case | Behavior |
|---|---|
| Crossing midnight | No special handling; durations are instant differences. Day attribution = start day. |
| DST change mid-feed | Same; absolute instants are unaffected. Display uses the current calendar. |
| Time-zone change mid-feed | Durations unaffected. Clock times show in the session's start `timeZoneID` in history, plus the current zone in active UI. |
| User sets clock back or forward | Same-boot: detected by monotonic comparison (above). Cross-boot: undetectable, but bounded by sanity checks and editable. |
| App killed mid-switch | Save happens before effects, so the store has either the old or the new state, never half. The Live Activity is fixed on next reconcile. |
| Double tap Start | Second `start` → `.alreadyActive`, treated as success by the UI (navigate to timer). |
| Intent arrives after End | `.alreadyCompleted` → ignored; the Live Activity is ended. |

## 7. Manual corrections

- **Edit session sheet:** adjust start, end, and each segment's side, start, and end; add or remove segments; convert "simple" edits (left 12 min, right 9 min) into segments automatically.
- Validation runs the same invariants as the engine (no overlaps, ordered, end ≥ start, not in the future beyond 1 min).
- Editing an *active* session is allowed for start times only. Ending it is done via End or recovery.
- Every edit bumps `revision` and `modifiedAt`, triggers Live Activity sync if active, and reminder rescheduling.

## 8. Clock abstraction (testability)

```swift
protocol AppClock: Sendable { func instant() -> Instant }
struct SystemClock: AppClock { /* Date.now, clock_gettime_nsec_np(CLOCK_MONOTONIC) [includes sleep on Darwin], boot ID from kern.boottime */ }
final class TestClock: AppClock { var wall: Date; var monotonic: Double; var bootID: String; func advance(_ s: Double) ; func jumpWall(_ s: Double) ; func reboot() }
```
`TestClock` lets every row in §3 and §6 become a deterministic unit test, including "reboot" and "user changed the clock".

> **To verify on device (Phase 5):** the exact monotonic source that keeps counting across sleep on iOS (`CLOCK_MONOTONIC` / `mach_continuous_time`) and reading the boot time via `sysctl kern.boottime`.

## 9. UI observation

- `BreastfeedingTimerView` observes `manager.activeSession` (a value). Elapsed labels use `TimelineView(.periodic(from: .now, by: 1))` computing from the snapshot, or `Text(timerInterval:)` for the running side, matching the Live Activity.
- No view holds its own `Timer`. Leaving the screen doesn't affect anything.
