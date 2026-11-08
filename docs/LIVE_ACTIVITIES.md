# Newbee: Live Activities & Dynamic Island Plan

Status: **Draft for approval** · Deliverable 12

## 1. Platform facts this plan relies on

Re-verify each item against current Apple docs and on device in Phase 5.

| Fact | Impact |
|---|---|
| ActivityKit Live Activities: iOS 16.1+. **Interactive buttons/toggles via App Intents: iOS 17+.** | Our iOS 18 floor gets full interactivity. |
| Dynamic Island exists only on iPhone 14 Pro and later. | Others get the Lock Screen presentation and a banner on update with an alert. |
| `Activity.request` generally must be called while the app is in the **foreground** (push-to-start is 17.2+ and needs a server). | Sessions started in-app are fine. Starting from Siri or a Control (future) needs checking: `LiveActivityIntent` should allow it. |
| `LiveActivityIntent.perform()` runs **in the app's process** (launched in the background if needed), even when the button lives in the widget extension. | Intents can use the same `FeedingSessionManager` and SwiftData store. The intent type must be compiled into both the app and extension targets. |
| A Live Activity can be active for **up to 8 hours**. After it ends it can stay on the Lock Screen for up to 4 hours (12 h total). | Forgotten timers will outlive the activity; handled in §6. The since-last-feed count shares the feed's activity, so a gap longer than about 8 h outlives it too (§3.5). |
| `ContentState` payload limit is about 4 KB. | Ours is around 150 bytes. |
| Widget views can't run timers or code over time, but `Text(timerInterval:pauseTime:countsDown:showsHours:)` and `Text(_:style: .timer)` render live-ticking text driven by the system. | This is how the timer progresses with zero updates. |
| Update budget: local updates are not strictly rate-limited like push, but should be sparing. | We update only on state changes (start, switch, pause, resume, end). |
| `staleDate` marks content as outdated; `context.isStale` is readable in views. | Used as a safety net for long sessions. |
| Behaviour after force-quit and device restart is **not guaranteed** by docs. | Must be validated on device; reconciliation covers both outcomes. |

## 2. Shared model (`NewbeeShared`)

```swift
struct FeedingActivityAttributes: ActivityAttributes {
    // Static: identity + stable info
    var sessionID: UUID
    var babyName: String          // "" → generic "Feeding"
    var schemaVersion: Int = 1    // versioned for forward-compat

    struct ContentState: Codable, Hashable {
        var status: Status              // .active, .paused, .ended
        var currentSide: Side           // active side, or last side while paused
        var sessionStart: Date
        var currentSegmentStart: Date?  // nil when paused/ended
        var leftAccumulated: TimeInterval   // closed segments only
        var rightAccumulated: TimeInterval  // closed segments only
        var pausedAt: Date?
        var revision: Int
        // Derived helpers (computed, not encoded):
        // runningSideStart  = currentSegmentStart − accumulated(currentSide)
        // runningTotalStart = currentSegmentStart − (left + right)
    }
}
```

Mapping comes from `SessionSnapshot` in one pure function (`ContentState(snapshot:)`), so it's unit-testable.

**The live-ticking trick:** for the active side, render `Text(timerInterval: runningSideStart...Date.distantFuture, countsDown: false)`. The system advances it, and because the start is shifted back by the already-accumulated time, it shows *total* time on that side. The total timer uses `runningTotalStart`. The inactive side is a static formatted duration. When paused, every value is static (`Text(Duration.seconds(x), format: .time(pattern: .minuteSecond))`) and `pauseTime` is set.

## 3. Presentations

Colors and typography come from the shared design tokens so the Live Activity matches the in-app timer. **Left = lavender**, **Right = teal**; always paired with the letters "L"/"R".

### 3.1 Lock Screen / banner
Mirrors the expanded Dynamic Island (§3.2) so the activity reads and works the same everywhere. The
side pills and controls are one shared view (`ActivitySidesAndControls`). Minimal by design
(revised 2026-11-07): one line of information, then the controls.
```
┌──────────────────────────────────────────────────────────┐
│ 18:42                                       Feeding 💧   │
│                                                          │
│  [   L 12:05   ]  [   R 6:37   ]      (⏸)      (■)      │
└──────────────────────────────────────────────────────────┘
```
- Header: the total on the left (dimmed when paused) and a quiet status with a glyph on the right
  ("Feeding", "Paused", "Since last feed", or "Still feeding?" when stale).
- Side pills: each shows its own time. The running side is filled with its color; the other is a
  tint. Each pill is a `SwitchSideIntent` for its side: tapping the other side switches (or resumes
  on it when paused); tapping the running side changes nothing, because the intent targets a state.
- `PauseIntent` / `ResumeIntent` in one round slot that flips, then `EndIntent`. **End** is the only
  control in the destructive color and sits last with extra space before it, so it isn't hit by
  accident.
- Since last feed (after End): the header counts up the time since the feed ended as `hh:mm`, two
  **Start** pills (`StartFeedingIntent`, one per side, the suggested next side tinted stronger)
  replace the side pills and controls, and a footnote gives the last feed's side times and end time.
  See §3.5.
- `activityBackgroundTint` is a soft neutral that works in light and dark. `activitySystemActionForegroundColor` uses the accent color.

### 3.2 Dynamic Island: expanded
- **Leading:** total timer (live).
- **Trailing:** status with glyph.
- **Bottom:** the same side pills, pause/resume and end as the Lock Screen.

### 3.3 Dynamic Island: compact
- **Leading:** side badge "L" (tinted circle).
- **Trailing:** total timer, live, monospaced, `.frame(maxWidth: 48)` so it doesn't push the island wide. When paused: "⏸" + static time.

### 3.4 Dynamic Island: minimal
- Tinted circle with a tiny bottle/drop glyph, tinted by the active side. A paused state uses a hollow ring.

### 3.5 Since last feed (after End)
- On End, from the Lock Screen or in the app, the **same activity stays** and updates to `.ended`:
  the header counts up from the end of the feed (`ContentState.lastFeedEndedAt`), and the footnote
  keeps the feed's L/R times. There is no Undo on the activity any more (removed with this change);
  the in-app undo toast still covers an End tapped by mistake.
- The count is `hh:mm` ("00:45", "02:15"). iOS 18's live clock format (`SystemFormatStyle.Stopwatch`)
  can't leave out seconds (with fewer fields or minute precision it switches to words like
  "1 hour, 23 minutes"), and it has no hours field under an hour. So `SinceLastFeedFormat` draws
  "00:" + a ticking `mm:ss` for the first hour, then a ticking `hh:mm:ss`, and the view clips it to
  the width of "00:00", hiding the trailing ":ss". The clock ticks each second for that reason.
  The content's `staleDate` is the one-hour mark, so the system redraws the activity there and the
  view switches phase without the app running. ("Still feeding?" never shows in this state.) The
  strings are pinned by `SinceLastFeedFormatTests` on the simulator.
- The manager syncs `activeSession ?? lastCompletedSession`, so every foreground keeps the count
  right. Deleting or editing the latest feed moves the count to the new latest; discarding a
  running feed goes back to counting from the previous one.
- **Start** (`StartFeedingIntent` → `manager.applyRemoteStart(side:)`) begins the next feed. A
  no-op if a feed is already running.
- **Time limit.** ActivityKit ends an activity 8 h after it was requested, then may leave it on
  the Lock Screen up to 4 h more. To get the most out of that window:
  - Every new feed requests a **fresh** activity (a new 8 h window) and only then ends the old
    since-last-feed one (`LiveActivityAction.request(..., replacing:)`), so there's no gap.
  - If iOS refuses the request (the app is in the background, e.g. Start on the Lock Screen), the
    coordinator updates the old activity to the new feed instead, so the parent keeps it. Its
    content then names the new session (`ContentState.sessionID`), so its buttons act on the new
    feed; it keeps the old activity's remaining time.
  - The since-last-feed state is never requested on its own: opening the app doesn't bring back an
    activity the parent swiped away or one that hit the limit. The next feed brings it back.
  - Typical newborn gaps (2–4 h) fit easily. A gap over about 8 h minus the feed's length (a long
    night) outlives the activity: the system ends it, and it may stay up to 4 h more with the
    count still drawn. It is replaced at the next feed.

## 4. App Intents

| Intent | Params | Behaviour |
|---|---|---|
| `SwitchSideIntent: LiveActivityIntent` | `sessionID`, `side` | `manager.switch(to:)` (works from paused too = resume on side) |
| `PauseIntent` | `sessionID` | `manager.pause()` |
| `ResumeIntent` | `sessionID` | `manager.resume()` |
| `EndSessionIntent` | `sessionID` | `manager.end()` |
| `StartFeedingIntent` | `sessionID` (the finished feed shown), `side` | `manager.applyRemoteStart(side:)` (§3.5) |
| *(future)* Siri/Shortcuts/Control start | `side` | Could reuse `StartFeedingIntent`'s path. |

All `perform()`s are `@MainActor` and go through the single `FeedingSessionManager` (from `AppDependencies.shared`, created lazily if the app was launched just for the intent). They return `.result()` after the manager has saved **and** awaited `activity.update`.
- Unknown or old `sessionID` → no-op + end that stale activity.
- Duplicate invocation → engine no-op (target-state commands, §3 of `TIMER_ENGINE.md`).

## 5. `LiveActivityCoordinator`

```swift
@MainActor final class LiveActivityCoordinator {
    func sync(_ snapshot: SessionSnapshot?) async   // the only entry point
}
```
`sync` makes the system match the snapshot:
- snapshot active/paused and no activity for its id → `Activity.request(attributes:content:pushType: nil)` (only if `ActivityAuthorizationInfo().areActivitiesEnabled`, otherwise record "disabled" for a gentle in-app hint).
- activity exists and `content.state.revision < snapshot.revision` → `update(ActivityContent(state:, staleDate: segmentStart (or pausedAt) + the "still feeding?" threshold))`.
- snapshot completed or nil → `end(finalContent, dismissalPolicy:)` for every activity of ours.
- any activity whose `sessionID` ≠ active session → end it immediately.
- Observes `activity.activityStateUpdates`: if the user dismissed it (`.dismissed`) while the session is active, respect that until the next state change (don't fight the user).
- Observes `ActivityAuthorizationInfo().activityEnablementUpdates` to refresh the Settings hint.

## 6. Synchronization and recovery

Order of truth: **SwiftData → manager snapshot → Live Activity**. Never the reverse.

On launch and every foreground (`RecoveryCoordinator`):
1. Reconcile data (see `TIMER_ENGINE.md` §5).
2. `await liveActivity.sync(activeSnapshot ?? lastCompletedSnapshot)`. This covers:
   - App killed, activity still shown → revision equal → nothing to do (or update if behind).
   - Device rebooted, activity gone → re-request (foreground).
   - 8-hour expiry while still feeding → re-request + recovery sheet ("still feeding?").
   - Activity for a session deleted from another screen → ended.
   - Two activities (shouldn't happen) → keep the matching one, end the rest.
   - No feed running → the existing activity keeps counting since the last feed; none is requested.

Background gap: if the activity is gone and the app is never opened, nothing can recreate it without a push server (ADR-009). The data is still correct; only the glanceable view is missing. The "still feeding?" local notification covers the main real-world risk.

## 7. Configuration checklist

- [ ] Widget Extension target `NewbeeWidgets` with `ActivityConfiguration(for: FeedingActivityAttributes.self)`
- [ ] `NSSupportsLiveActivities = YES` in the app's Info.plist
- [ ] Intents + attributes compiled into both targets (via `NewbeeShared`)
- [ ] App Group entitlement on both targets
- [ ] Settings screen row: "Live Activities: On / Off in iOS Settings" with deep link
- [ ] Previews for all presentations: `#Preview(as: .dynamicIsland(.expanded), using: attrs) { … } contentStates: { … }` (all 3 island modes + Lock Screen, active/paused/ended, light/dark, large Dynamic Type)

## 8. Implementation map (Phase 5a)

| Piece | Where | Tested by |
|---|---|---|
| `FeedingActivityAttributes` + `ContentState(snapshot:)` mapping | `Packages/NewbeeShared/.../LiveActivity/` | `NewbeeSharedTests` (Linux + CI) |
| `LiveActivityPlanner`: request / update / end decisions for every case in §5–6 | same | `NewbeeSharedTests` |
| `LiveActivityFormat`: static durations and VoiceOver text | same | `NewbeeSharedTests` |
| `LiveActivityCommand`, `LiveActivityCommandHandling`, `LiveActivityIntentRouter` | same | `NewbeeSharedTests` |
| Intents (`SwitchFeedingSideIntent`, `PauseFeedingIntent`, `ResumeFeedingIntent`, `EndFeedingIntent`, `StartFeedingIntent`) and `SinceLastFeedFormat` | `LiveActivityIntents/`, compiled into **both** targets via `project.yml` | CI build + `SinceLastFeedFormatTests`; device |
| `LiveActivityCoordinator` + `ActivityKitClient` | `Newbee/Core/Services/` | `NewbeeTests/LiveActivity` with a fake client |
| Views + previews for all presentations | `NewbeeWidgets/LiveActivity/` | Xcode previews; device |

Notes:
- The `ActivityAttributes` conformance is an extension under `#if canImport(ActivityKit)`, so the
  struct and its mapping build and test on Linux.
- Intents live in a source folder shared by both targets, not in the `NewbeeShared` package:
  App Intents metadata is extracted per target, and target-membership in both is Apple's
  documented pattern for `LiveActivityIntent`. Their `perform()` only calls
  `LiveActivityIntentRouter`; there is no timing logic outside the session engine.
- `LiveActivityCoordinator.sync(_:)` queues calls so ActivityKit updates never interleave, even
  when several Lock Screen taps arrive at once.
- A parent swiping the activity away (active → dismissed) is remembered per session revision; the
  activity comes back on the next state change, not on the next foreground. The system ending it
  (8-hour limit, reboot) is not treated as a dismissal, so recovery re-requests it.
- Records have three phases: live, ended (still on screen: an activity the system ended at 8 h,
  or an older build's "Feed complete" summary) and dismissed. Whenever a session is active or
  paused, every ended record is removed immediately, so a next feed never leaves two activities
  on the Lock Screen.
- A record's `sessionID` is its content's session (`ContentState.sessionID`), falling back to the
  attributes', because an activity can be carried over to another feed (§3.5).
- `staleDate` is the open segment's start (or the pause) plus the "still feeding?" threshold, so
  the Lock Screen shows "Still feeding? Open Newbee" at the same moment the app would ask. In the
  since-last-feed state it is the one-hour mark instead (§3.5).

Integration wiring (done; see `Newbee/Core/Services/LiveActivityWiring.swift`, `AppDependencies`, `NewbeeApp.init`, tested in `NewbeeTests/LiveActivity/LiveActivityWiringTests.swift`):
1. `FeedingSessionManager` conforms to `LiveActivityCommandHandling` in the app target by
   mapping `LiveActivityCommand` to its `applyRemote(_:sessionID:)`.
2. `LiveActivityCoordinator` conforms to the engine's `LiveActivitySyncing` protocol (its
   `sync(_:)` already matches), and `AppDependencies` uses it instead of the no-op.
3. `NewbeeApp.init` calls `LiveActivityIntentRouter.register(dependencies.sessionManager)`, so
   intents work when iOS launches the app in the background just to run one (not a view `.task`:
   a background launch may never build the view tree).
4. Build the coordinator with `LiveActivityPlanner(staleAfter: RecoveryPolicy().effectiveThreshold)`
   (or the user's configured policy) so the stale hint matches the recovery prompt.

## 9. Device test matrix

To be run on Robby's iPhone. Needs an iPhone 14 Pro or newer for the Dynamic Island, and ideally a non-Pro or older iPhone for the Lock Screen-only path. The full list from guide §5.7 lives in `TESTING.md` §5 with expected results.
