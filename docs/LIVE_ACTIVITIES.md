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
| A Live Activity can be active for **up to 8 hours**. After it ends it can stay on the Lock Screen for up to 4 hours (12 h total). | Forgotten timers will outlive the activity; handled in §6. |
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
```
┌──────────────────────────────────────────────────────────┐
│ 🍼 Feeding · Left              Paused ▌▌ (if paused)     │
│                                                          │
│   18:42                     L  12:05   ◀ active (bold)   │
│   total                     R   6:37                     │
│                                                          │
│  [  L  ]  [  R  ]        [ ⏸ Pause ]     [ ■ End ]       │
└──────────────────────────────────────────────────────────┘
```
- Big total on the left; per-side breakdown on the right with the active side highlighted (tint + bold + "●").
- Buttons: `Button(intent: SwitchSideIntent(.left))`, `.right`, `PauseIntent` / `ResumeIntent` (one slot that flips), `EndIntent`. **End** is visually separated and uses a distinct shape so it isn't hit by accident. Undo is available in-app.
- `activityBackgroundTint` is a soft neutral that works in light and dark. `activitySystemActionForegroundColor` uses the accent color.

### 3.2 Dynamic Island: expanded
- **Leading:** side badge ("L" in a lavender circle) + "Left".
- **Trailing:** total timer (live).
- **Center:** status line ("Feeding · 12:05 on left").
- **Bottom:** `[ Switch to R ]` (primary, large), `[⏸]`, `[■ End]`. Only the *other* side is offered, to reduce choice in a small space.

### 3.3 Dynamic Island: compact
- **Leading:** side badge "L" (tinted circle).
- **Trailing:** total timer, live, monospaced, `.frame(maxWidth: 48)` so it doesn't push the island wide. When paused: "⏸" + static time.

### 3.4 Dynamic Island: minimal
- Tinted circle with a tiny bottle/drop glyph, tinted by the active side. A paused state uses a hollow ring.

### 3.5 Ended state
- On End, update to `.ended` with final L/R/total and `dismissalPolicy: .after(now + 15 min)`, so the parent can glance at the result, then it disappears. The policy is configurable: immediate / 15 min / default.

## 4. App Intents

| Intent | Params | Behaviour |
|---|---|---|
| `SwitchSideIntent: LiveActivityIntent` | `sessionID`, `side` | `manager.switch(to:)` (works from paused too = resume on side) |
| `PauseIntent` | `sessionID` | `manager.pause()` |
| `ResumeIntent` | `sessionID` | `manager.resume()` |
| `EndSessionIntent` | `sessionID` | `manager.end()` |
| *(future)* `StartFeedingIntent: AppIntent` | `side` | Siri/Shortcuts/Control. Opens app or starts in background (to verify). |

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
- activity exists and `content.state.revision < snapshot.revision` → `update(ActivityContent(state:, staleDate: segmentStart + 8h))`.
- snapshot completed or nil → `end(finalContent, dismissalPolicy:)` for every activity of ours.
- any activity whose `sessionID` ≠ active session → end it immediately.
- Observes `activity.activityStateUpdates`: if the user dismissed it (`.dismissed`) while the session is active, respect that until the next state change (don't fight the user).
- Observes `ActivityAuthorizationInfo().activityEnablementUpdates` to refresh the Settings hint.

## 6. Synchronization and recovery

Order of truth: **SwiftData → manager snapshot → Live Activity**. Never the reverse.

On launch and every foreground (`RecoveryCoordinator`):
1. Reconcile data (see `TIMER_ENGINE.md` §5).
2. `await liveActivity.sync(activeSnapshot)`. This covers:
   - App killed, activity still shown → revision equal → nothing to do (or update if behind).
   - Device rebooted, activity gone → re-request (foreground).
   - 8-hour expiry while still feeding → re-request + recovery sheet ("still feeding?").
   - Activity for a session deleted from another screen → ended.
   - Two activities (shouldn't happen) → keep the matching one, end the rest.

Background gap: if the activity is gone and the app is never opened, nothing can recreate it without a push server (ADR-009). The data is still correct; only the glanceable view is missing. The "still feeding?" local notification covers the main real-world risk.

## 7. Configuration checklist

- [ ] Widget Extension target `NewbeeWidgets` with `ActivityConfiguration(for: FeedingActivityAttributes.self)`
- [ ] `NSSupportsLiveActivities = YES` in the app's Info.plist
- [ ] Intents + attributes compiled into both targets (via `NewbeeShared`)
- [ ] App Group entitlement on both targets
- [ ] Settings screen row: "Live Activities: On / Off in iOS Settings" with deep link
- [ ] Previews for all presentations: `#Preview(as: .dynamicIsland(.expanded), using: attrs) { … } contentStates: { … }` (all 3 island modes + Lock Screen, active/paused/ended, light/dark, large Dynamic Type)

## 8. Device test matrix

To be run on Robby's iPhone. Needs an iPhone 14 Pro or newer for the Dynamic Island, and ideally a non-Pro or older iPhone for the Lock Screen-only path. The full list from guide §5.7 lives in `TESTING.md` §5 with expected results.
