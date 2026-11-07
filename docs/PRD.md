# Newbee: Product Requirements Document

Status: **Draft for approval** · Last updated 2026-11-06
Covers planning deliverables 1 (product overview), 2 (MVP list), 3 (future enhancements), and the gap analysis.

---

## 1. Product overview

**Newbee** is a native iPhone app that helps exhausted new parents record and understand their newborn's feeding with as little interaction as possible.

The defining capability is a **breastfeeding timer that can't lose time**. It keeps running correctly when the phone is locked, when the app is suspended or killed, and when the phone restarts. It also shows live on the Lock Screen and in the Dynamic Island, where the parent can switch sides, pause, or end the feed without unlocking the phone.

Around that timer, Newbee provides:

- Quick bottle logging (breast milk, formula, or other; oz or mL; presets).
- A dashboard answering the 3 a.m. questions: *When did they last eat? Which side? How long ago?*
- A calendar and timeline history for looking back.
- Insights built only from recorded data, including rolling 24-hour stats, because newborns don't follow midnight-to-midnight days.
- Configurable, non-prescriptive reminders.
- CSV and PDF export for sharing with a healthcare provider.

**Principles**

1. **One hand, two taps.** Starting, switching, and ending a feed each take at most two taps from anywhere, including the Lock Screen.
2. **Timestamps, not tickers.** All durations come from stored absolute timestamps, never from a running counter.
3. **Private by default.** All data stays on the device. No account, analytics SDKs, or tracking. iCloud sync is opt-in (post-MVP).
4. **Calm, premium, native.** Follows Apple's Human Interface Guidelines, uses a soft palette, supports Dynamic Type and dark mode, and avoids clutter.
5. **Not medical advice.** Newbee describes what happened. It never says what should happen.

**Target user:** a parent or caregiver of a 0 to 12 month old, often tired, often using one hand, often in the dark.

---

## 2. Prioritized MVP feature list

Priority tiers: **P0** means the app is pointless without it. **P1** is required for the MVP release. **P2** ships with the MVP if time allows; otherwise it goes in the first update.

| # | Feature | Tier | Notes |
|---|---------|------|-------|
| 1 | Persistent feeding session engine (`FeedingSessionManager`): start, switch side, pause, resume, end; timestamp-based; crash- and reboot-safe | **P0** | See `TIMER_ENGINE.md` |
| 2 | SwiftData persistence with versioned schema and segment-level storage | **P0** | See `DATA_MODEL.md` |
| 3 | Breastfeeding timer screen (L/R, per-side and total time, suggested next side) | **P0** | |
| 4 | Live Activity on the Lock Screen | **P0** | See `LIVE_ACTIVITIES.md` |
| 5 | Dynamic Island in compact, minimal, and expanded layouts | **P0** | |
| 6 | Interactive Live Activity controls (switch, pause/resume, end) via App Intents | **P0** | |
| 7 | Launch recovery and reconciliation (interrupted, stale, or duplicate sessions) | **P0** | |
| 8 | Undo for end, switch, and delete actions; safe handling of double taps | **P0** | |
| 9 | Bottle feeding log with contents, amount, unit, time, notes, and presets | **P1** | |
| 10 | Manual entry and editing of past sessions, including breast segments | **P1** | |
| 11 | Delete with confirmation and undo | **P1** | |
| 12 | Dashboard: current status, today's summary, quick actions | **P1** | |
| 13 | History timeline grouped by day, with type filter | **P1** | |
| 14 | Calendar month view with per-day indicators and a day summary | **P1** | |
| 15 | Insights: frequency, intervals, breast and bottle stats, 7/14/30-day ranges, rolling 24 h, comparisons | **P1** | Swift Charts |
| 16 | Reminders: time since last feed, configurable interval, quiet hours, permission management | **P1** | |
| 17 | Settings: baby profile, units, bottle presets, reminders, appearance, delete all data | **P1** | |
| 18 | Onboarding: baby nickname (optional), units, Live Activity and notification explainer | **P1** | |
| 19 | CSV export through the share sheet | **P1** | |
| 20 | Tools: interval calculator, side tracker, quick stats | **P2** | Mostly reuses dashboard and insights pieces |
| 21 | PDF summary export | **P2** | Built with `ImageRenderer` and PDF context |
| 22 | "Long-running session" safety notification for a timer that may have been forgotten | **P1** | New; see gaps below |

**Release gate:** items 1 to 8 must be validated on a physical iPhone before work on items 9 and later is considered done. This follows guide §18, Phase 5.

---

## 3. Recommended future enhancements

Roughly in order of value:

1. **iCloud sync (CloudKit) and caregiver sharing.** Two parents tracking the same baby is the most common real-world need. The schema is CloudKit-compatible from day one (see `DATA_MODEL.md`). Sharing between different Apple IDs needs `CKShare`, which SwiftData does not support natively. That is a significant piece of work.
2. **Pumping sessions**, with left and right volume and duration. The model already supports this.
3. **Combination and supplementary feeds**, meaning breast followed by a top-up bottle in one feeding. The model already supports this.
4. **Home Screen and Lock Screen widgets** (time since last feed, last side) plus a **Control Center control** to start a feed (`ControlWidget`, available on our iOS 18 floor).
5. **Siri and Shortcuts**: "Start feeding on the left", "Log 90 mL formula". The App Intents built for the Live Activity make this cheap.
6. **Apple Watch**: Live Activities already appear in the watchOS Smart Stack. A full watch app comes later.
7. **Multiple babies (twins)**. The model is ready; this needs a baby switcher in the UI.
8. **Other baby logs**: diapers, sleep, growth, solids. Out of scope for a *feeding* app now, but don't paint ourselves into a corner.
9. **Cluster-feeding grouping**: optionally treat feeds less than N minutes apart as one feeding when computing intervals.
10. **Night mode**: a dimmed, red-shifted theme for 3 a.m. use.
11. **Localization**, starting with the strings catalog from day one.
12. **Server push for Live Activities**, only if a real gap shows up in device testing. It needs a backend, which conflicts with the privacy-first principle.

---

## 4. Gaps, conflicts, and decisions in the original spec

### 4.1 Missing considerations (recommended additions)

| Gap | Recommendation |
|-----|----------------|
| **Forgotten timer.** A parent falls asleep with the timer running. This is the single most common real-world failure for feeding timers. | Add a "still feeding?" local notification after a configurable time (default 45 min of a single segment). On reopen, offer "End at last activity" with an editable end time. |
| **Live Activity 8-hour cap.** iOS ends a Live Activity after at most 8 hours active, then keeps it on the Lock Screen for up to 4 more. | Handle it explicitly. The session stays active in data; the app re-requests the activity next time it's in the foreground and flags the session for review. |
| **Undo instead of confirmations.** Spec asks for confirmation dialogs; exhausted parents dismiss dialogs on autopilot. | Use destructive confirmation only for *delete*. For *end*, *switch*, and *edit*, show a 5–8 s undo toast. End requires a deliberate control (not adjacent to the side buttons). |
| **Definition of "interval".** Start-to-start or end-to-start? | Default to **start-to-start**, which matches common pediatric usage. Label it in the UI and make it a setting. |
| **Midnight attribution.** Which day owns a 23:50–00:20 feed? | A session belongs to the **day it started** for counts and calendar dots. Rolling 24 h stats avoid the issue entirely. |
| **"Total duration" with pauses.** Spec example: Total = L + R = 21 min. | Define **feeding time** = sum of segment durations (pauses excluded), and **session span** = end − start. Show feeding time by default. |
| **Multiple caregivers / devices.** | Post-MVP via CloudKit. Schema rules enforced now. |
| **Multiple babies (twins).** | `Baby` entity exists from v1; UI assumes one baby until the switcher ships. |
| **Accessibility of side colors.** | Never rely on color alone. Always show "L"/"R" letters and use VoiceOver labels ("Left side, active, 12 minutes"). |
| **Medical disclaimer / App Store category.** | Add an in-app "not medical advice" note in onboarding and Insights. Submit under *Health & Fitness*. Do **not** use HealthKit in MVP (it adds review scrutiny and has no infant-feeding types). |
| **Data backup.** Local-only data dies with the phone. | MVP: CSV export plus the user's normal device backup (SwiftData store is included in iCloud/iTunes device backups). Explain this in Settings. |
| **Clock tampering / time-zone travel.** | Detect within the same boot using a monotonic clock (see `TIMER_ENGINE.md`). Store each session's time zone so history shows the local time it happened. |
| **Haptics and feedback.** | Light haptic on start/switch/pause, success haptic on end. |
| **Privacy manifest.** | `PrivacyInfo.xcprivacy` is required (UserDefaults and file-timestamp API reasons). |
| **App name and bundle ID.** | Needed before Phase 4. Proposal: display name *Newbee*, bundle ID `com.<you>.newbee`. |

### 4.2 Conflicts and ambiguities in the spec

1. **"Pause" semantics.** The spec lists Not Started → Active → Paused → Completed, but the Live Activity also needs "which side was active when paused". Decision: pausing closes the current segment and keeps `lastSide`; resuming opens a new segment on the same side. Resuming on the *other* side is just "switch while paused".
2. **`BreastfeedingDetails` entity vs "avoid redundant calculated values".** Per-side durations and the starting breast can all be derived from segments. Decision: **drop the separate entity** and derive these values. This removes a whole class of data-drift bugs. Cached totals can be added later only if profiling demands them.
3. **"Device restarted, where recovery is possible."** With absolute timestamps, recovery is *always* possible for the data. Only the Live Activity UI is lost if iOS doesn't restore it, and it comes back on next foreground.
4. **Live Activity interactivity "where supported".** With the iOS 17 deployment target, every supported device gets Live Activity buttons. Dynamic Island needs iPhone 14 Pro or newer; other iPhones get the Lock Screen presentation and banner only.
5. **AppPreferences in SwiftData vs UserDefaults.** Decision: use **UserDefaults in the App Group**, because preferences are needed by the widget extension, are tiny, and shouldn't sync blindly with feeding data.
6. **Five tabs plus a settings home.** Decision: 5 tabs as suggested. Settings is reached from a gear on Home and from Tools.

### 4.3 Decisions (answered by Robby, 2026-11-07)

1. **Minimum iOS: 17.0.** Robby first chose 18.0, then lowered it to 17.0 on 2026-11-07 to reach more devices. The cost: no SwiftData `#Index`, and iOS 18 features such as a Control Center control need availability checks. CI runs an extra iOS 17 simulator job.
2. **Apple Developer Program: yes**, Robby has a paid membership.
3. **Name and bundle ID:** display name **Newbee**, bundle ID `com.<team>.newbee`. The exact team prefix is set during Phase 4 signing.
4. **iCloud sync: after the first release.** The schema stays CloudKit-ready.
5. **Single-baby UI for MVP**, with a model that's ready for more babies (default, not objected to).
6. **Validation:** GitHub Actions macOS CI for builds. Robby's Mac and iPhone handle signing and device tests (`ROADMAP.md` §3).
