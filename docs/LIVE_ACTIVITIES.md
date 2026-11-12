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
| Behavior after force-quit and device restart is **not guaranteed** by docs. | Must be validated on device; reconciliation covers both outcomes. |

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
- Since last feed (after End): "Since last feed" over a large stopwatch ("4:12", "2:15:03"), the main focus, with
  one round **+** on the right that opens the app on Home (`Link` to `NewbeeLink.home`,
  `newbee://home`; the whole activity has the same `widgetURL`). A footnote gives the last feed's
  side times and end time. See §3.5.
- **Colors.** Text uses `ActivityColor` (adaptive, like `NBColor.card`), never the system's
  `.primary` / `.secondary`: on device those were drawn for the opposite appearance from the
  card, which hid the big number (white on white in light mode, black on dark at night). Side text
  uses `ActivityColor.sideInk`, darker than the side fill colors, for AA contrast on its tint.
- **Appearance.** The activity follows the app's Light / Dark / System setting:
  `ContentState.appearance` carries it (the coordinator reads `AppPreferences.appearance` at every
  sync, and a change in Settings re-syncs). Light or dark forces that color scheme and a fixed
  background; System uses the adaptive `NBColor.card`. `activitySystemActionForegroundColor` uses
  the accent color. The Dynamic Island is always drawn in the dark scheme with fixed white / gray
  text (`IslandColor`).

### 3.2 Dynamic Island: expanded
- **Bottom only.** The island draws the Lock Screen's own layouts (`ActivityFeedingContent`,
  `ActivitySinceLastFeedContent`) in its bottom region at a smaller scale
  (`ActivityLayoutStyle.island`: total 28 pt, since-last-feed clock 36 pt, + 44 pt), in fixed
  white / gray text.
- **Why not leading / trailing:** the regions beside the camera are only about 100 pt wide. With the
  status and clock there, a device showed "Since last…" and "1:00:…" (2026-11-08). The bottom
  region spans the island's full width.
- Live timer text takes all the width it's offered, so every clock gets a cap of 5× its font
  size (`ActivityLayoutStyle.timerWidth`), which fits "12:05:00".

### 3.3 Dynamic Island: compact
- **Leading:** side badge "L" (tinted circle).
- **Trailing:** total timer, live, monospaced, capped at 50 pt ("45:12") or 64 pt past an hour and
  for the time since the last feed ("1:02:03"), so it doesn't push the island wide. When paused:
  "⏸" + static time. Once ended: a clock glyph leading and the time since the last feed trailing.

### 3.4 Dynamic Island: minimal
- Tinted circle with a tiny bottle/drop glyph, tinted by the active side. A paused state uses a hollow ring.

### 3.5 Since last feed (after End)
- On End, from the Lock Screen or in the app, the **same activity stays** and updates to `.ended`:
  the header counts up from the feed's start or end, per Settings' **Count from**
  (`ContentState.countFrom`, `sinceLastFeedStart`), and the footnote keeps the feed's L/R times
  with "started 3:20 PM" or "ended 3:40 PM" to match. There is no Undo on the activity any more (removed with this change);
  Undo on the in-app "Feed saved" summary covers an End tapped by mistake, and puts the feed back on the activity, paused.
- The count is a stopwatch with seconds: "4:12", then "2:15:03" (`SinceLastFeedText`, the same
  `Text(timerInterval:)` as the side pills and the total, which draws correctly on the Lock Screen).
  - **Why not `hh:mm`:** iOS has no live format that shows hours and minutes as digits without
    seconds (`SystemFormatStyle.Stopwatch` switches to words like "1 hour, 23 minutes" at minute
    precision). Two builds drew a clock with seconds and clipped them off; both looked right in
    simulator tests but drew shifted on a real Lock Screen (")0:04:"), because the system lays out a
    live date text at its own width and position. Don't retry clipping.
  - A true `hh:mm` would need the activity updated every minute, which only a push server can do
    while the app isn't running (ActivityKit push updates). Not built: Newbee has no server.
  - The content's `staleDate` is the one-hour mark (a harmless redraw); "Still feeding?" never
    shows in this state.
- **Count from.** One setting (Settings → Time since last feed, stored as `reminder.basis`) for
  Home's "Time since last feed", this count and feeding reminders. The coordinator reads it at
  every sync like the appearance, and a change re-syncs (`NewbeeApp`), so the activity redraws at
  once. `nil` in content means the end (older builds); a bottle counts from its start or end the
  same way.
- **Bottles count too.** The count runs from the latest feed of either kind, by start time, with
  a breastfeed winning a tie (`LatestFinishedFeed`, the same rule reminders use). A bottle that
  ends later than the last breastfeed only takes over if it also *started* later; a bottle logged
  now with an earlier time doesn't. For a bottle, `ContentState.lastBottle` holds the amount, the
  footnote reads "Last feed bottle 90 mL · ended 3:40 PM" ("at" when no duration was entered), and
  `currentSide` stays the last breastfeed's side.
- The manager syncs `activeSession ?? lastCompletedSession` plus the latest bottle, so every
  foreground keeps the count right. Logging, editing, deleting or undoing a bottle calls
  `manager.bottlesDidChange(logged:)` (from the bottle model's `onChange`). Adding, editing or deleting
  the latest feed of either kind moves the count to whichever feed is now the latest; discarding a
  running feed goes back to counting from the previous one. A bottle never changes a running feed.
- **+** opens the app on Home (`RootView.onOpenURL`) to start or log the next feed there. (Start
  Left / Right buttons on the activity were replaced by it, so the count is the focus.)
- **Time limit.** ActivityKit ends an activity 8 h after it was requested, then may leave it on
  the Lock Screen up to 4 h more. To get the most out of that window:
  - Every new feed requests a **fresh** activity (a new 8 h window) and only then ends the old
    since-last-feed one (`LiveActivityAction.request(..., replacing:)`), so there's no gap.
  - If iOS refuses the request (the app is in the background, e.g. relaunched by an intent), the
    coordinator updates the old activity to the new feed instead, so the parent keeps it. Its
    content then names the new session (`ContentState.sessionID`), so its buttons act on the new
    feed; it keeps the old activity's remaining time.
  - Opening the app doesn't bring back an activity the parent swiped away or one that hit the
    limit (`LiveActivitySyncMode.update`). What does:
    - starting a feed (always a fresh request);
    - entering a feed that is now the latest: a new bottle (`bottlesDidChange(logged:)`) or a
      breastfeed added by hand (`manager.addFeed(_:)`), which sync with `.show`. One entered for
      earlier than the latest feed doesn't. Edits, deletes and undo never bring it back;
    - Settings → Live Activities → **Refresh Live Activity** (`manager.refreshLiveActivity()`,
      `.refresh`): a fresh request for the running feed or the count, replacing whatever is
      showing, even after a swipe.
  - Typical newborn gaps (2–4 h) fit easily. A gap over about 8 h minus the feed's length (a long
    night) outlives the activity: the system ends it, and it may stay up to 4 h more with the
    count still drawn. It is replaced at the next feed.

## 4. App Intents

| Intent | Params | Behavior |
|---|---|---|
| `SwitchSideIntent: LiveActivityIntent` | `sessionID`, `side` | `manager.switch(to:)` (works from paused too = resume on side) |
| `PauseIntent` | `sessionID` | `manager.pause()` |
| `ResumeIntent` | `sessionID` | `manager.resume()` |
| `EndSessionIntent` | `sessionID` | `manager.end()` |
| *(future)* Siri/Shortcuts/Control start | `side` | Not built; the since-last-feed "+" opens the app instead (§3.5). |

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
| Intents (`SwitchFeedingSideIntent`, `PauseFeedingIntent`, `ResumeFeedingIntent`, `EndFeedingIntent`) and `SinceLastFeedText` | `LiveActivityIntents/`, compiled into **both** targets via `project.yml` | CI build + `SinceLastFeedRenderTests`; device (the Lock Screen draws live text differently) |
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
