# Newbee: Phased Development Roadmap

Status: **Draft for approval** · Deliverable 10

## 1. Phases and gates

| Phase | Content | Exit gate |
|---|---|---|
| **1. Requirements** | `PRD.md` | ✅ Robby approves this plan |
| **2. Architecture** | `ARCHITECTURE.md`, `DATA_MODEL.md`, `TIMER_ENGINE.md`, `LIVE_ACTIVITIES.md` | ✅ same approval |
| **3. UI/UX design** | Design tokens finalised; high-fidelity mockups of timer, Lock Screen, 3 island modes, dashboard, calendar, history, insights (as SwiftUI previews in Phase 4–5, optionally a visual mock first) | Robby approves the look of timer + Live Activity |
| **4. Project initialisation** | XcodeGen `project.yml`, 4 targets + 2 packages, App Group, entitlements, Info.plist keys, privacy manifest, design system, DI container, test targets, CI | **Project builds and empty tests pass in CI and on Robby's Mac**; app launches on Robby's iPhone |
| **5a. Core subsystem** | Models + persistence → SessionEngine → manager → timer UI → ActivityKit → Lock Screen → Dynamic Island → intents → recovery | Unit and integration tests green; **device tests D1–D18 pass** (critical gate, guide §18) |
| **5b. Secondary features** | Bottle → Dashboard → History → Calendar → Insights → Notifications → Tools/Export → Settings/Onboarding | Each feature green in CI and smoke-tested on device |
| **6. Testing & refinement** | Full regression, performance (1 year of seeded data), accessibility audit, warnings zero, polish | Release candidate on TestFlight |
| **7. Deployment** | Icon, launch screen, display name, versioning, permission strings, privacy policy + App Privacy labels ("Data Not Collected"), screenshots, description, TestFlight + submission checklist | Submitted for review |

## 2. Work split across at most 3 parallel threads

Interfaces are agreed first (in Phase 4) so threads don't block each other: `SessionSnapshot`, `Command`, `AppClock`, `FeedingRepository`, `ContentState`, design tokens.

**Phase 4: 1 thread** (project skeleton must exist before parallel work; avoids project-file conflicts).

**Phase 5a: 3 threads**
| Thread | Scope | Depends on |
|---|---|---|
| A: Engine & persistence | NewbeeKit domain + `SessionEngine` + `TestClock` + unit tests; SwiftData schema V1 + repository + `FeedingSessionManager` + `RecoveryCoordinator` + integration tests | skeleton |
| B: Live Activity | `FeedingActivityAttributes` + mapping, widget views for all presentations with previews, intents, `LiveActivityCoordinator` | A's interface protocols (stubbed until merged) |
| C: Design system & timer UI | Tokens, components, `BreastfeedingTimerView`, Active Session Pill, recovery sheet, undo toast | A's `SessionSnapshot` (stubbed) |

Then one integration pass merges A+B+C, followed by **Robby's device run of D1–D18**.

**Phase 5b: 3 threads**
| Thread | Scope |
|---|---|
| A | Bottle logging, Edit/Manual entry, History timeline |
| B | Analytics in NewbeeKit (Linux-testable) + Insights screens + Calendar |
| C | Dashboard, Reminders/notifications, Tools, Export (CSV/PDF), Settings, Onboarding |

**Phases 6–7: 1–2 threads.**

## 3. What needs Robby's Mac / iPhone (threads run on Linux, no Xcode)

| Step | Where it can run |
|---|---|
| Writing Swift code, docs, `project.yml` | Any thread (Linux) |
| `swift test` for NewbeeKit (engine, analytics, CSV) | Linux thread (installs the Swift toolchain), or CI |
| Compile the iOS app, simulator unit/integration/UI tests | **GitHub Actions macOS runner** (recommended, automatic on every PR), *or* Robby's Mac via a **Remote Control session** (`xcodegen generate && xcodebuild test …`) |
| Generate `Newbee.xcodeproj` from `project.yml` | CI or Robby's Mac (XcodeGen via Homebrew) |
| Signing, provisioning, App Group + Live Activity capabilities, Apple Developer account setup | **Robby** (Xcode / developer portal), one-time in Phase 4 |
| Install on iPhone, all device tests D1–D18, Dynamic Island, lock, reboot | **Robby's iPhone** (Xcode run or TestFlight) |
| Xcode Previews review of designs | Robby's Mac (or screenshots from a CI simulator run) |
| Archive, TestFlight upload, App Store Connect | **Robby's Mac** (or later automated with an App Store Connect API key in CI, if Robby wants) |

**Recommended setup before Phase 4 starts:**
1. Robby confirms Apple Developer Program membership and the bundle ID.
2. Allow a GitHub Actions macOS workflow on the repo.
3. Optional: keep the Mac reachable for Remote Control sessions so a thread can run `xcodebuild` and report back.

## 4. Rough sizing

| Phase | Effort |
|---|---|
| 3 + 4 | 1–2 sessions |
| 5a | 3 parallel threads, then integration + device test round(s) |
| 5b | 3 parallel threads |
| 6–7 | 1–2 sessions + App Review wait |

Device-test feedback loops on Robby's side are the main schedule driver, not code volume.
