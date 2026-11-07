# Newbee: Testing Strategy

Status: **Draft for approval** · Deliverable 9

## 1. Pyramid and where each layer runs

| Layer | Framework | Target | Runs on | Who can run it |
|---|---|---|---|---|
| Engine / analytics / CSV unit tests | Swift Testing | `NewbeeKit` package | **Linux** (`swift test`) + macOS CI | Any thread (after installing the Swift Linux toolchain), CI |
| Persistence / recovery / reminders / intent→manager integration | Swift Testing | `NewbeeTests` | iOS Simulator | macOS CI, Robby's Mac |
| UI flows | XCUITest | `NewbeeUITests` | iOS Simulator | macOS CI, Robby's Mac |
| Snapshot-style preview review | Xcode Previews | app + widget | Xcode | Robby's Mac |
| Live Activity, Dynamic Island, lock, reboot, clock | Manual scripted checklist | — | **Physical iPhone** | Robby only |

## 2. Unit tests (NewbeeKit, deterministic with `TestClock`)

- **Engine transitions:** every row of the state table in `TIMER_ENGINE.md` §3, including no-ops and rejections; revision increments; zero-length segment merge.
- **Durations:** the spec example (2:15 L12 → R9 → 2:36 = 21 min); multiple switches; pause gaps excluded from feeding time but included in span.
- **Time edge cases:** crossing midnight; DST spring-forward and fall-back (Europe/London, America/New_York fixtures); time-zone change mid-session; wall-clock jump forward/back within the same boot (detected); reboot (bootID change, not flagged).
- **Recovery decisions:** duplicates, future start, overlong segment, ambiguous data → correct recommendation.
- **Analytics:** feeds/day, rolling 24 h with window clipping, intervals (start-to-start and end-to-start), shortest/longest, L/R averages and distribution, bottle totals by contents, 7/14/30-day ranges, week-over-week deltas, day attribution of midnight-crossing feeds, empty data.
- **Units:** mL↔oz conversion and rounding (1 US fl oz = 29.5735 mL), display vs stored precision.
- **CSV:** header, escaping of notes with commas, quotes, and newlines, time-zone column, stable ordering.
- **ContentState mapping:** snapshot → `ContentState` (active, paused, ended; accumulated sides; shifted start dates).

Target: **≥ 95 % line coverage** on `SessionEngine` and `Analytics`.

## 3. Integration tests (app target, in-memory `ModelContainer`)

- Repository round-trips: session + segments + bottle; cascade delete; invariants rejected on save.
- `FeedingSessionManager` with in-memory store + `TestClock` + **fake** `LiveActivityCoordinator` / `ReminderScheduler` (protocols): every command persists *before* side effects; failure on save causes no side effects.
- Simulated termination: run commands, drop the manager and context, build new ones from the same on-disk store → identical snapshot.
- Recovery on launch with seeded corrupt states.
- Intents: `SwitchSideIntent().perform()` against the manager; duplicate invocations; stale `sessionID`.
- Reminder scheduler: computes the correct trigger date with quiet hours (spanning midnight), basis start/end, disabled, and permission denied. Uses a fake `UNUserNotificationCenter` wrapper.
- Schema migration: V1 fixture store opens with the current plan (once V2 exists).
- Export: CSV file written and readable; PDF renders non-empty with expected page count.

## 4. UI tests (XCUITest, launch argument `-uiTesting` → in-memory store + fixed clock)

Start feed → switch → pause → resume → end → verify summary; undo end; log bottle via preset; edit a historical entry's segments; delete with confirm + undo; calendar month navigation and day selection; dashboard updates after a log; history filter; recovery sheet appears with a seeded stale session; Dynamic Type XXXL smoke test of the timer screen.

## 5. Physical device test plan (Robby's iPhone)

Run each case on an **iPhone 14 Pro or later** (Dynamic Island). Where marked †, also run on a non-Dynamic-Island iPhone if one is available. Each row records Pass/Fail plus notes in `docs/CHECKLIST.md`.

| # | Scenario | Expected |
|---|---|---|
| D1 | Start feed in app† | Live Activity appears on Lock Screen and island within 1 s |
| D2 | Lock phone 5 min† | Lock Screen timer kept ticking; matches app on unlock ±1 s |
| D3 | Switch side from Lock Screen ×5 rapidly† | Final side correct; no duplicate segments; app agrees |
| D4 | Pause / resume from island expanded | State and timers frozen and resumed correctly |
| D5 | End from Lock Screen† | Activity shows final summary, dismisses after the policy; session completed in History |
| D5b | Within 15 min of D5: tap Undo in the app, or start the next feed† | The "Feed complete" summary disappears at once; only one activity is on the Lock Screen / island |
| D6 | Double-tap End | One completed session, no errors |
| D7 | Background app, open 3 other apps, return | Timer accurate |
| D8 | Force-quit during active feed | Record what iOS does with the activity; reopening restores the session; activity reconciled |
| D9 | Restart iPhone during active feed | Record whether the activity survives; on open, session restored and activity re-requested; durations correct |
| D10 | Feed across midnight | Calendar dot on start day; durations correct |
| D11 | Change time zone mid-feed | Durations unchanged; history times sensible |
| D12 | Manually set clock +1 h mid-feed (same boot) | Recovery detects it and offers a correction |
| D13 | Leave a feed running 8 h+ | Activity ends by system; "still feeding?" notification fired earlier; on open, recovery sheet + activity re-requested |
| D14 | Disable Live Activities in iOS Settings, start feed | App works; gentle hint shown; no crash |
| D15 | Compact / minimal island with another app's activity (e.g. a timer) | Minimal presentation renders correctly |
| D16 | Dark mode, large Dynamic Type, VoiceOver on Lock Screen activity | Readable; buttons labelled |
| D17 | Low Power Mode | Timer still accurate (rendered by system) |
| D18 | Reminder fires after configured interval; suppressed in quiet hours | As configured |

## 6. CI (proposed)

`.github/workflows/ci.yml`:
1. **linux-core** (`ubuntu-latest`, `swift-actions/setup-swift`): `swift test` in `Packages/NewbeeKit`. Fast, cheap, runs on every push.
2. **ios** (`macos-latest`, latest stable Xcode): `xcodegen generate` → `xcodebuild build-for-testing` + `test-without-building` on an iPhone 15 Pro simulator for `NewbeeTests` and `NewbeeUITests`; warnings-as-errors for our targets.

macOS runner minutes cost 10× Linux on private repos. Keep the iOS job to PRs plus `main`.

## 7. Definition of done (per feature)

Unit and integration tests written and green in CI. Builds without warnings. Previews for all states. Accessibility labels. Checklist row updated. Device rows (if any) passed on Robby's iPhone. **No feature is called complete without its behaviour being tested** (guide rule 17).
