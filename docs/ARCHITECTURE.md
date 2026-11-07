# Newbee: Technical Architecture

Status: **Draft for approval**
Covers deliverable 4 (technical architecture) and 8 (folder structure), plus the architecture decision records (ADRs).

---

## 1. Stack (confirmed)

| Concern | Choice | Notes |
|---|---|---|
| Language | Swift 6 language mode, strict concurrency | `@MainActor` default isolation for UI targets |
| UI | SwiftUI | UIKit only where SwiftUI lacks an API (for example the PDF context) |
| Pattern | MVVM with `@Observable` view models | No Combine except `NotificationCenter` bridging |
| Min iOS | **17.0** (changed from 18.0 on 2026-11-07) | Availability checks for 17.2+ and 18+ APIs; CI tests on an iOS 17 simulator |
| Persistence | SwiftData, `VersionedSchema` + `SchemaMigrationPlan` from v1 | CloudKit-compatible schema rules |
| Charts | Swift Charts | `SectorMark` (donut) available |
| Live Activities | ActivityKit + WidgetKit extension | |
| Interactivity | App Intents (`LiveActivityIntent`) | Buttons in Live Activities available on all supported devices |
| Notifications | UserNotifications (local only) | |
| Tests | Swift Testing for logic, XCTest for UI tests | |
| Project generation | **XcodeGen** (`project.yml`) | See ADR-006 |
| Dependencies | None at runtime. XcodeGen and SwiftLint are dev tools only | |

---

## 2. High-level structure

```
┌───────────────────────────── Newbee.app (main target) ─────────────────────────────┐
│  SwiftUI Views ──observe──▶ @Observable ViewModels ──call──▶ Services              │
│                                                              │                     │
│   FeedingSessionManager (@MainActor, single source of truth for active session)    │
│        │ uses                     │ notifies                    │ notifies          │
│        ▼                          ▼                             ▼                   │
│   FeedingRepository        LiveActivityCoordinator      ReminderScheduler           │
│   (SwiftData adapter)      (ActivityKit)                (UserNotifications)          │
│        │                                                                            │
│        ▼                                                                            │
│   ModelContainer (App Group container) ─────────────┐                               │
└─────────────────────────────────────────────────────│───────────────────────────────┘
                                                      │ shared file location
┌──── NewbeeWidgets.appex (widget extension) ─────────┴───┐
│  ActivityConfiguration views (Lock Screen, Dynamic Island)│
│  Renders ContentState only. No timing engine.             │
│  Button(intent:) ──▶ LiveActivityIntent (perform runs     │
│                       in the main app process)            │
└───────────────────────────────────────────────────────────┘

┌──── NewbeeKit (local Swift package, platform-independent) ───────────────────────┐
│  SessionEngine (pure state machine), Clock protocol, Analytics, Export (CSV),     │
│  Domain value types, date utilities.  Builds and tests on Linux with `swift test`.│
└───────────────────────────────────────────────────────────────────────────────────┘

┌──── NewbeeShared (framework or package target linked by app AND extension) ───────┐
│  FeedingActivityAttributes (+ ContentState), intent definitions, design tokens    │
└───────────────────────────────────────────────────────────────────────────────────┘
```

### Layer responsibilities

| Layer | Responsibility | May depend on |
|---|---|---|
| **NewbeeKit / Domain** | Value types (`SessionSnapshot`, `Segment`, `Side`, `SessionStatus`), the `SessionEngine` state machine, analytics, CSV, date math | Foundation only |
| **Persistence** | SwiftData `@Model` classes, schema versions, migrations, `FeedingRepository` protocol and SwiftData implementation, mapping between models and domain value types | Domain, SwiftData |
| **Services** | `FeedingSessionManager`, `LiveActivityCoordinator`, `ReminderScheduler`, `ExportService`, `PreferencesStore`, `HapticsService` | Domain, Persistence, Apple frameworks |
| **Features** | Views and view models per screen | Services (through protocols), Design System |
| **Design System** | Colors, typography, spacing, components | SwiftUI |
| **Widget extension** | Live Activity UI | NewbeeShared, Design System |

**Rule:** no business logic in views. A view model never touches `ModelContext` directly for writes. Writes go through the manager or repository so they can run validation, reminder rescheduling, and Live Activity sync. Reads for lists use `@Query` in views, where that is the idiomatic SwiftData path and keeps the code simple. Aggregations come from view models that call NewbeeKit analytics.

---

## 3. Key services

### `FeedingSessionManager` (`@MainActor @Observable`)
- Owns the one active or paused breastfeeding session.
- Public commands: `start(side:)`, `switch(to:)`, `pause()`, `resume()`, `end(at:)`, `discardActive()` (with undo), `recover()`.
- Each command does: load current state → `SessionEngine.apply(command, at: clock.now)` → persist → bump `revision` → notify `LiveActivityCoordinator` and `ReminderScheduler`.
- Exposes `activeSession: SessionSnapshot?` for UI observation.
- Details in `TIMER_ENGINE.md`.

### `LiveActivityCoordinator`
- Maps `SessionSnapshot` to `FeedingActivityAttributes.ContentState`.
- Requests, updates, and ends `Activity<FeedingActivityAttributes>`.
- On launch: reconciles `Activity.activities` against the persisted active session.
- Details in `LIVE_ACTIVITIES.md`.

### `ReminderScheduler`
- Reschedules the single "time since last feed" reminder whenever feeding data changes. It uses the last feed's start time, the user's interval, and quiet hours.
- Schedules and cancels the "still feeding?" safety notification while a session is active.
- Uses only pending-request identifiers it owns. It is idempotent.

### `FeedingRepository` (protocol)
- CRUD for sessions, segments, and bottle details. Exposes `activeSessions()` and `sessions(in: DateInterval)`.
- The SwiftData implementation lives in the app. An in-memory implementation lives in tests.

### `ExportService`
- CSV (NewbeeKit, pure) and PDF (app, `ImageRenderer`). Output goes to a temp file, then `ShareLink`.

### `PreferencesStore`
- `UserDefaults(suiteName: appGroup)` wrapped in a typed `@Observable` store.

### `AppClock` (protocol, in NewbeeKit)
- `now: Date` plus `monotonicNow: TimeInterval?` (continuous time since boot) and `bootID`. A `SystemClock` is used in the app and a `TestClock` in tests.

---

## 4. Concurrency model

- `FeedingSessionManager`, `LiveActivityCoordinator`, and the main `ModelContext` are `@MainActor`. Commands are tiny (one fetch, one save), so main-actor serialization is the simplest correct way to guarantee that two intents can't interleave.
- `LiveActivityIntent.perform()` is `@MainActor` and calls into the same shared manager instance (`AppDependencies.shared`), so app UI and Lock Screen buttons go through one serialized path.
- ActivityKit `update`/`end` are `async`. The coordinator awaits them after the data save, never before. Data is the source of truth; the activity is a projection.
- Analytics over large ranges run in a detached task over **value snapshots** (never `@Model` objects across actors).

---

## 5. Targets and App Group

| Target | Type | Contains |
|---|---|---|
| `Newbee` | iOS app | App, Features, Services, Persistence, Design System |
| `NewbeeWidgets` | Widget extension | Live Activity views (and future widgets) |
| `NewbeeKit` | Local Swift package | Domain, SessionEngine, Analytics, CSV |
| `NewbeeShared` | Local Swift package (iOS-only target) | ActivityAttributes, intents, design tokens |
| `NewbeeTests` | Unit + integration tests (Swift Testing) | |
| `NewbeeUITests` | XCUITest | |

- **App Group** `group.<bundle-id>`: the SwiftData store and UserDefaults live there from v1. Moving a store later is a risky migration. The extension doesn't need the store for the Live Activity today, but future widgets and controls will.
- **Info.plist:** `NSSupportsLiveActivities = YES`. `NSSupportsLiveActivitiesFrequentUpdates` is *not* needed (we update only on state changes).

---

## 6. Folder structure (deliverable 8)

Adjusted from the guide's §16 to match real target boundaries:

```
Newbee/
├── project.yml                     # XcodeGen spec (source of truth for the .xcodeproj)
├── Newbee.xcodeproj/               # generated by `xcodegen generate`; git-ignored
├── Config/                         # Base.xcconfig + git-ignored Signing.local.xcconfig
├── Packages/
│   ├── NewbeeKit/                  # pure Swift; Linux-testable
│   │   ├── Package.swift
│   │   ├── Sources/NewbeeKit/
│   │   │   ├── Domain/             # Side, SessionStatus, FeedingKind, SessionSnapshot, Segment, BottleEntry
│   │   │   ├── SessionEngine/      # SessionEngine, Command, EngineError, Reconciler
│   │   │   ├── Clock/              # AppClock, SystemClock, TestClock
│   │   │   ├── Analytics/          # DailySummary, IntervalStats, Rolling24h, Comparisons
│   │   │   ├── Export/             # CSVWriter
│   │   │   └── Utilities/          # DateInterval+Day, Duration formatting, Volume conversion
│   │   └── Tests/NewbeeKitTests/
│   └── NewbeeShared/               # iOS-only; linked by app + widget
│       └── Sources/NewbeeShared/
│           ├── LiveActivity/       # FeedingActivityAttributes, ContentState
│           ├── Intents/            # SwitchSideIntent, PauseIntent, ResumeIntent, EndIntent
│           └── DesignTokens/       # Colors, Typography, Spacing (shared look)
├── Newbee/                         # app target
│   ├── App/                        # NewbeeApp, AppDependencies, RootView, scene-phase handling
│   ├── Core/
│   │   ├── Persistence/            # Schema V1…, MigrationPlan, SwiftDataFeedingRepository, Mappers
│   │   ├── Services/               # LiveActivityCoordinator, ReminderScheduler, ExportService, PreferencesStore, Haptics
│   │   └── SessionManagement/      # FeedingSessionManager, RecoveryCoordinator
│   ├── Features/
│   │   ├── Onboarding/
│   │   ├── Dashboard/
│   │   ├── Breastfeeding/          # timer screen + edit segments
│   │   ├── BottleFeeding/
│   │   ├── Calendar/
│   │   ├── History/
│   │   ├── Insights/
│   │   ├── Tools/
│   │   └── Settings/
│   ├── Shared/
│   │   ├── Components/             # Card, StatTile, SideButton, TimerText, UndoToast, EmptyState…
│   │   ├── DesignSystem/           # app-only styles built on NewbeeShared tokens
│   │   └── Extensions/
│   └── Resources/                  # Assets.xcassets, Localizable.xcstrings, PrivacyInfo.xcprivacy
├── NewbeeWidgets/                  # widget extension target
│   ├── NewbeeWidgetsBundle.swift
│   └── LiveActivity/               # LockScreenView, DynamicIslandViews, previews
├── NewbeeTests/
│   ├── Integration/                # SwiftData repo, recovery, reminders, intents → manager
│   └── Support/                    # in-memory container, fixtures
├── NewbeeUITests/
├── docs/                           # this plan + CHECKLIST.md
└── .github/workflows/              # CI (see TESTING.md)
```

---

## 7. Architecture decision records

**ADR-001: Timestamps are the only source of truth for time.**
Durations are always derived from segment `startedAt`/`endedAt` and `now`. No stored counters, no background timers. *Why:* survives suspension, termination, and reboot by construction (guide rule 20).

**ADR-002: Store segments; derive per-side totals.**
`BreastfeedingDetails` is replaced by computed properties over `FeedingSegment`. *Why:* one fact stored once. Edits can't leave totals out of sync. *Trade-off:* analytics sum segments at query time. That is fine for thousands of rows; cache later only if profiling shows a need.

**ADR-003: Pure `SessionEngine` in a platform-independent package.**
The state machine takes `(state, command, now)` and returns `(newState, effects)` or an error. *Why:* exhaustively unit-testable, including on Linux CI, with no SwiftData or ActivityKit in the loop. *Trade-off:* a mapping layer between `@Model` and value types (small).

**ADR-004: Main-actor serialized commands with revision numbers.**
*Why:* Lock Screen intents, in-app taps, and launch recovery can race. One actor plus a monotonically increasing `revision` makes every command idempotent or rejectable. *Alternative considered:* a custom `actor` with a background `ModelContext`. Rejected because SwiftData's main-context ergonomics with `@Query` matter more and commands are cheap.

**ADR-005: CloudKit-compatible schema from v1, sync off.**
All attributes optional or defaulted, all relationships optional, no `@Attribute(.unique)`, no `.deny` delete rules. *Why:* turning on sync later becomes a container-configuration change, not a migration. *Trade-off:* uniqueness of "one active session" is enforced in code, not the store (the engine already does this).

**ADR-006: XcodeGen for the project file.**
*Why:* up to 3 parallel threads will add files. A hand-edited `project.pbxproj` creates constant merge conflicts and can't be generated on Linux. `project.yml` is reviewable text. The generated project is git-ignored (regenerate with `xcodegen generate` after pulling), which removes project-file merge conflicts entirely. *Alternative:* Tuist (heavier) or a plain Xcode project (conflict-prone).

**ADR-007: Preferences in App Group UserDefaults, not SwiftData.**
See PRD §4.2.

**ADR-008: Undo toasts over confirmation dialogs, except delete.**
See PRD §4.1.

**ADR-009: Local-only Live Activity updates (no push server).**
All transitions originate on the device (app or intent), so local `Activity.update` covers every case. *Trade-off:* we can't update an activity if the app process can't run. Acceptable, because nothing changes state without the user.

**ADR-010: No third-party runtime dependencies.**
