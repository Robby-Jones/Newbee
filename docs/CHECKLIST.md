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
- [ ] **Robby approval** of the plan
- [ ] Open decisions answered (PRD §4.3): min iOS, bundle ID, developer account, CloudKit timing, single-baby UI

## Phase 3: UI/UX design
- [ ] Final color tokens + typography
- [ ] Timer screen mockup approved
- [ ] Lock Screen + Dynamic Island (expanded/compact/minimal) mockups approved
- [ ] Dashboard, Calendar, History, Insights mockups

## Phase 4: Project initialisation
- [ ] `project.yml` (app, widget ext, unit tests, UI tests) + NewbeeKit + NewbeeShared packages
- [ ] App Group, Live Activities Info.plist key, entitlements, privacy manifest
- [ ] Design system skeleton, DI container
- [ ] CI: linux-core + ios jobs green
- [ ] Builds on Robby's Mac; launches on Robby's iPhone

## Phase 5a: Core subsystem (critical gate)
- [ ] Domain types + SessionEngine + TestClock + unit tests
- [ ] SwiftData schema V1 + repository + migration plan
- [ ] FeedingSessionManager + integration tests
- [ ] Breastfeeding timer UI + pill + undo
- [ ] ActivityAttributes + LiveActivityCoordinator
- [ ] Lock Screen presentation
- [ ] Dynamic Island compact / minimal / expanded
- [ ] Interactive intents
- [ ] RecoveryCoordinator + recovery sheet + "still feeding?" notification
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
