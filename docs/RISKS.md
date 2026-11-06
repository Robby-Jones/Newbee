# Newbee: iOS Limitations & Technical Risks

Status: **Draft for approval** · Deliverable 13

Likelihood / impact: H, M, L.

| # | Risk / limitation | L | I | Mitigation |
|---|---|---|---|---|
| R1 | **Live Activity 8-hour maximum** (then up to 4 h on Lock Screen); forgotten timers outlive it | H | M | Data unaffected; "still feeding?" notification; re-request + recovery on next foreground (`LIVE_ACTIVITIES.md` §6) |
| R2 | **Activities can't be started from the background** without push-to-start (server) | M | M | Sessions start in-app (foreground). Siri/Control starts are post-MVP and verified first |
| R3 | **Force-quit / reboot behaviour of Live Activities is undocumented / may change** | M | M | Reconcile on every launch/foreground; device tests D8–D9 record actual behaviour |
| R4 | **User disables Live Activities** (globally or per app) or dismisses one | M | L | App fully functional without them; gentle hint; respect dismissal until next state change |
| R5 | **No Dynamic Island** on pre-14-Pro / non-Pro older models | H | L | Lock Screen presentation + banner; design tested on both |
| R6 | **SwiftData maturity on iOS 17** (predicate limits on enums/optionals, occasional crashes, no `#Index`) | M | M | Raw-string enums, simple predicates, value-type mapping, repository protocol (swap possible), consider iOS 18 floor (PRD §4.3) |
| R7 | **CloudKit later constrains schema** (optional everything, no unique) | L | M | Enforced from V1 (ADR-005) |
| R8 | **Caregiver sharing across Apple IDs** isn't supported by SwiftData+CloudKit out of the box | H | M | Post-MVP; may require `NSPersistentCloudKitContainer` sharing or a CKShare layer. Scope separately |
| R9 | **Wall-clock changes across reboot are undetectable** | L | L | Sanity checks + editable sessions + `needsReview` flag |
| R10 | **Intent races** (Lock Screen tap + in-app tap) | M | H | Main-actor serialization, target-state commands, revision, save-before-effects (ADR-004) |
| R11 | **Widget extension memory limits (~30 MB) / no networking** | L | L | Views are static layouts over a tiny ContentState |
| R12 | **Notification permission denied** | M | L | Reminders show "off: enable in Settings" with deep link; core app unaffected |
| R13 | **Linux-only dev threads can't compile the iOS app** | H | H | Platform-independent NewbeeKit tested on Linux; macOS CI for every PR; Remote Control on Robby's Mac; XcodeGen avoids pbxproj conflicts |
| R14 | **Parallel threads conflict** (project file, shared files) | M | M | XcodeGen, agreed interfaces in Phase 4, feature folders owned by one thread |
| R15 | **App Review: health-adjacent claims** | M | M | No medical recommendations; disclaimer; "Data Not Collected" privacy label; accurate description |
| R16 | **Data loss** (local only, phone lost) | M | H | CSV export; explain device backup; iCloud sync next |
| R17 | **Accidental End / switch** at 3 a.m. | H | M | Separated End control, hold-to-confirm or undo; engine idempotency |
| R18 | **Timer text in widgets** may render width-jumping or show hours unexpectedly | M | L | Monospaced digits, fixed frames, `showsHours` tuned, previews at all sizes |
| R19 | **Battery / performance** of per-second UI | L | L | `TimelineView`/`Text(timerInterval:)` only while visible; no background work at all |
| R20 | **API drift**: newer iOS versions add/rename Live Activity and tab APIs | M | L | Availability checks; verify against docs at implementation time (guide rule 16) |
| R21 | **Apple Developer account / signing** not ready blocks device testing | M | H | Resolve before Phase 4 (PRD §4.3 #5) |
