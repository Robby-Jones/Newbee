# Newbee: Development Checklist

Legend: `[x]` done · `[ ]` pending · `[!]` blocked (reason noted). Updated by every thread as work lands.

## Phase 1–2: Planning
- [x] PRD: overview, MVP, future, gaps (`PRD.md`)
- [x] Architecture + ADRs + folder structure (`ARCHITECTURE.md`)
- [x] Data model (`DATA_MODEL.md`)
- [x] Persistent timer architecture (`TIMER_ENGINE.md`)
- [x] Live Activity / Dynamic Island plan (`LIVE_ACTIVITIES.md`)
- [x] Navigation + screen spec + design system draft (`UX_SPEC.md`)
- [x] Testing strategy (`TESTING.md`)
- [x] Roadmap + parallel split (`ROADMAP.md`)
- [x] Risks (`RISKS.md`)
- [x] **Robby approval** of the plan (2026-11-07)
- [x] Open decisions answered (PRD §4.3): iOS 18, Newbee / com.<team>.newbee, paid developer account, CloudKit post-MVP

## Phase 3: UI/UX design
- [ ] Final color tokens + typography
- [ ] Timer screen mockup approved
- [ ] Lock Screen + Dynamic Island (expanded/compact/minimal) mockups approved
- [ ] Dashboard, Calendar, History, Insights mockups

## Phase 4: Project initialisation
- [x] `project.yml` (app, widget ext, unit tests, UI tests) + NewbeeKit + NewbeeShared packages
- [x] App Group, Live Activities Info.plist key, entitlements, privacy manifest
- [x] Design tokens (draft palette), composition root (`AppDependencies`), 5-tab shell
- [x] SwiftData schema V1 + migration plan + App Group store
- [x] Domain contract types (`SessionSnapshot`, `Segment`, enums), `AppClock`/`SystemClock`/`TestClock`
- [x] Baseline Live Activity (proves extension + shared attributes + system timer)
- [x] NewbeeKit tests pass on Linux (Swift 6.2)
- [x] CI: core-linux + ios jobs green (11 NewbeeKit tests on Linux; 3 persistence tests + 1 UI launch test on iOS simulator)
- [ ] Builds on Robby's Mac; launches on Robby's iPhone (Robby)

## Phase 5a: Core subsystem (critical gate)
- [x] Domain types + SessionEngine + TestClock + unit tests (state table, rapid taps, midnight/DST, clock jumps, reboot; Linux)
- [x] SwiftData schema V1 + repository + migration plan (`SwiftDataFeedingRepository`, snapshot mapping)
- [x] FeedingSessionManager + integration tests (save-before-effects, ordered effects, undo via restore, stale intents, termination/relaunch)
- [ ] Breastfeeding timer UI + pill + undo
- [ ] ActivityAttributes + LiveActivityCoordinator
- [ ] Lock Screen presentation
- [ ] Dynamic Island compact / minimal / expanded
- [ ] Interactive intents
- [ ] RecoveryCoordinator + recovery sheet + "still feeding?" notification (coordinator + `RecoveryPrompt` done; sheet in timer UI thread; notification with reminders in 5b)
- [ ] Device tests D1–D18 passed (Robby)

## Phase 5b: Secondary features
- [ ] Bottle logging + presets
- [ ] Manual entry / edit / delete
- [ ] Dashboard
- [ ] History timeline
- [ ] Calendar
- [ ] Analytics (NewbeeKit) + Insights
- [ ] Reminders + quiet hours
- [ ] Tools
- [ ] CSV / PDF export
- [ ] Settings + onboarding + delete all data

## Phase 6: Testing & refinement
- [ ] Full regression, 0 warnings, perf with 1 year of data, accessibility audit

## Phase 7: Deployment
- [ ] Icon, launch, name, versioning, permission strings
- [ ] Privacy policy + App Privacy labels
- [ ] Screenshots, description
- [ ] TestFlight build
- [ ] App Store submission
