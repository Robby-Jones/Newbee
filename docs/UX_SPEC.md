# Newbee: Navigation & Screen-by-Screen UX Spec

Status: **Draft for approval** · Deliverables 6 (navigation) and 7 (preliminary UI/UX spec)

---

## 1. Navigation structure

```
TabView
├── Home        (house)                   ← default tab
├── History     (clock.arrow.circlepath)  → List | Calendar switch at the top
├── Insights    (chart.bar)
└── Settings    (gearshape)
```

**Why four tabs (revised 2026-11-07).** The first build had five: Home, Calendar, History,
Insights, Tools. In use they overlapped. Calendar and History were two views of the same past
feeds, and every Tools card repeated something already elsewhere: "since last feed" (Home),
the side tracker (Home's suggested side, Insights' L/R split), quick stats (Home's Today tiles and
Insights), and the interval calculator (the gap labels between History rows). Popular feeding
trackers keep one place for "now", one for "looking back" and one for trends, plus
settings/profile: Huckleberry, Baby Tracker and Glow Baby all have a single history screen with
a list/calendar switch, and Apple Fitness puts its calendar inside History. So:
- Calendar is History's second mode, and replaces History's old "Jump to date" sheet.
- Tools is gone. Its kit code (`IntervalCalculator`, `SideTracker`, `QuickStats`) was deleted with it.
- Settings is a tab, the only route to it. The Home gear and the Tools link are gone.

**Global elements**
- **Active Session Pill**: when a breastfeeding session is active or paused, a compact pill floats above the tab bar on *every* tab ("● L 12:05 · total 18:42", side-tinted). Tap opens the timer sheet. Built with `safeAreaInset(edge: .bottom)`; adopt the system tab-bar accessory API on newer iOS via availability checks.
- **Settings** is its own tab, with no second entry point.

**Modal presentation choices** (keeps navigation depth at most 2)

| Flow | Presentation | Why |
|---|---|---|
| Breastfeeding timer | **Full-screen cover**, swipe-down/"Minimize" to dismiss (session keeps running) | Focus, one-handed, big targets |
| Log bottle | **Sheet** with `.medium`/`.large` detents | Fast, contextual |
| Edit / manual entry | Sheet, `.large` | Form-based |
| Day detail (from Calendar) | Inline below the month grid, then push to a full day list | Keeps context |
| Recovery ("Were you still feeding?") | Sheet, not dismissible by swipe; must pick an option | Data integrity |
| Delete confirmation | `confirmationDialog` | Destructive |
| End / switch / delete feedback | Undo toast (6 s) | Speed |
| Onboarding | Full-screen, 3 steps, skippable | |

---

## 2. Design system

**Tone:** calm, warm, premium. Like Apple Health crossed with Journal: lots of whitespace and soft cards.

### Color tokens (light / dark, all checked for WCAG AA on their backgrounds)
| Token | Use | Light | Dark |
|---|---|---|---|
| `bg.canvas` | App background | warm off-white `#FAF8F5` | `#0F0F12` |
| `bg.card` | Cards | `#FFFFFF` | `#1B1B20` |
| `text.primary` | | system label color | |
| `secondaryText` | Secondary text (replaces system `.secondary`, which is ~3.3:1 on the canvas) | `#66666C` | `#A1A1AA` |
| `accent` | Primary actions, text, fill under white text | indigo `#5054C2` | `#8E91F0` |
| `side.left` | Left breast | lavender `#9C8CE0` | `#B3A6F0` |
| `side.right` | Right breast | teal `#4FB3A9` | `#6FCFC4` |
| `feed.bottle.breastMilk` | Bottle (EBM) | peach `#F2A37B` | `#F5B593` |
| `feed.bottle.formula` | Bottle (formula) | butter `#E8C25A` | `#EDD07A` |
| `state.paused` | Paused | system gray | |
| `state.destructive` | Delete/End emphasis | rose `#AE2F4B` | `#E88092` |

Side, feed and pump colors are soft pastels for fills, chart marks and borders; text on them uses `onSide` (`#1B1B20`). When one of these colors is the text or icon color itself, use its ink variant, which reaches at least 4.5:1 on the canvas, the card and a light tint of itself:

| Ink token | Light | Dark |
|---|---|---|
| `leftInk` | `#6A58C4` | `#B3A6F0` |
| `rightInk` | `#26706A` | `#6FCFC4` |
| `bottleBreastMilkInk` | `#A9522A` | `#F5B593` |
| `bottleFormulaInk` | `#846510` | `#EDD07A` |
| `pumpInk` | `#A8436A` | `#F0A8C2` |
| `reviewInk` (Review badge) | `#8F5200` | `#FF9F0A` |

Side and feed colors are always paired with a letter or icon.

### Typography
- SF Pro **Rounded** for numerals and headings; SF Pro for body.
- Timer: `.system(size: 64, weight: .semibold, design: .rounded).monospacedDigit()`, scales with Dynamic Type via `@ScaledMetric`.
- Everything else uses semantic text styles (`.title2`, `.headline`, `.subheadline`, `.footnote`). No fixed sizes outside the timer.

### Spacing, shape, motion
- 4-pt grid; standard paddings 8/12/16/24.
- Card radius 20 (continuous), 1-pt hairline border in dark mode, soft shadow `y:2 blur:8 opacity:0.06` in light mode only.
- Minimum hit target 44×44; primary timer controls at least 88 pt tall.
- Animations: `.snappy` springs for state changes, `contentTransition(.numericText())` for numbers. Respect Reduce Motion.
- Haptics: `.impact(.light)` on start/switch/pause, `.success` on end, `.warning` on rejected action.

### Components (reusable, `Shared/Components`)
`Card`, `StatTile`, `SideButton`, `TimerText`, `SideBadge`, `FeedRow` (timeline row), `DayDots`, `SegmentBar` (horizontal L/R proportion bar), `UndoToast`, `EmptyStateView`, `PresetChip`, `SectionHeader`, `ActiveSessionPill`.

---

## 3. Screens

Each screen covers: purpose · layout · states (empty / loading / error / active).

### 3.1 Onboarding (3 steps, all skippable)
1. **Welcome**: "Track feeds in two taps." Privacy line: "Your data stays on this iPhone." A small "Coming from Huckleberry? Import your feeds" link under Get started opens the import sheet (§3.10).
2. **Baby**: photo, nickname and birth date (all optional). Units: mL / oz.
3. **Stay in the loop**: explains Live Activities (illustration of the Lock Screen) and asks for notification permission *only if* the parent turns on reminders here. "Not medical advice" footnote.

Skip (steps 1 and 2) and Start tracking both save whatever was entered. Shown once: `onboardingComplete` is set when it closes, and it's skipped automatically when the store already has a baby or any feed (people updating from an earlier build). UI tests skip it unless launched with `-showOnboarding`.

### 3.2 Home / Dashboard

*Revised 2026-11-07 (Superdesign round, Huckleberry-style layout, Newbee colors):* baby avatar,
name and age at the top; a centered **Time since last feed** card ("2 h 14 min", "Breast · L 12 min · R 9 min ·
9:41 PM"); three big round buttons **Left / Right / Bottle**, each captioned with when it was last
used ("2 h ago"), the suggested side filled and tagged "Suggested"; Today's totals in one compact
card; and the three most recent entries with their notes. While a feed runs, the Time since last feed card
becomes the live feed card and Left/Right open the timer instead of switching sides. The sketch
below is the earlier layout.

```
Good evening                                   ⚙︎
┌ Last feed ─────────────────────────────────┐
│ 2 h 14 m ago                               │  ← large, relative, live
│ 9:41 PM · Breast · L 12m R 9m               │
│ Next side: ● R  (suggested)                 │
└─────────────────────────────────────────────┘
┌──────────────┐ ┌──────────────┐
│  ▶ Start L   │ │  ▶ Start R   │   ← suggested side visually emphasised
└──────────────┘ └──────────────┘
┌ 🍼 Log bottle ───────────────────────────────┐
Today ───────────────────────────────────────────
[ ● Feeds 7 ] [ ♥ Breastfeeding 1 h 48 m ] [ 🍼 Bottles 180 mL ] [ ◷ Average gap 2 h 51 m ]
Last 24 h: 9 feeds · avg interval 2 h 40 m  (rolling)
```
- The baby's name and age from Settings show under the greeting ("Ava · 3 wk 2 d old").
- The suggested next side is shown once, on its Start button ("Suggested"), not repeated in the
  Last feed card.
- Log bottle is a single row with today's bottle count. Past bottles are in History, not listed on Home.
- Tiles follow Apple Health's summary style: a tinted symbol and label, then the value.
- **Active state:** the "Last feed" card becomes a live **Active Session card** (side, per-side and total timers, Pause / Open timer). Start buttons are replaced by "Switch to R".
- **Empty state:** "No feeds yet. Start your first one below." Start buttons remain.
- **Error state:** store failed to load → full-screen message with Retry and "Export data" (never silently reset).

### 3.3 Breastfeeding Timer (full-screen cover)

*Revised 2026-11-07:* two big **round** L / R buttons (up to 168 pt) with each side's time inside,
the running side filled with a soft halo; the total and start time above; the L/R bar under the
circles; full-width **Pause** and **End feed**, then **Add note** (writes the note to the running
feed). **Edit start** in the top bar moves the whole feed's start (the running side gains the
difference). In dark mode the dark tokens give a dim night look. The sketch below is the earlier
layout.

*Revised 2026-11-08:* the "Minimize" button is gone. Dragging down anywhere above **Pause**
minimizes the timer: the screen follows the finger and minimizes past ~120 pt (or on a quick
flick), otherwise it springs back. A grabber at the top hints at the gesture and is itself a
**Minimize** button (VoiceOver, and at large text sizes where the screen scrolls and the drag is
off). A drag never also counts as a tap on a side button.

*Revised 2026-11-11:* the **Pause** button is gone. Tapping the running side ("Tap to pause")
pauses the feed; while paused, tapping either side resumes on that side. **End feed** and
**Add note** stay below the circles, and the minimize drag covers everything above them.

```
 ⌄ Minimize                         ⋯ (Edit start time, Add note, Discard)
            Total
           18:42                      ← huge, rounded, monospaced
      Started 2:15 AM
┌─────────────────────┐ ┌─────────────────────┐
│        L            │ │        R            │
│      12:05          │ │       6:37          │
│   ● ACTIVE          │ │   tap to switch     │
└─────────────────────┘ └─────────────────────┘   ← each ≥ 160 pt tall, thumb zone
 [ ⏸ Pause ]                       [ End feed ]   ← End is outlined + rose; hold-to-confirm 0.6 s OR tap → undo toast
```
- **Not started:** both side buttons say "Start", the suggested side carries a "Suggested" tag and is pre-tinted. Last side and time are shown above.
- **Active:** active side filled with its tint, pulsing dot (static under Reduce Motion). Inactive side is an outline with "Switch".
- **Paused:** whole screen desaturates, the total shows "Paused", and tapping a side resumes on that side. (Since 2026-11-11 there is no separate Pause / Resume button: tapping the running side pauses.)
- **After End:** summary sheet ("21 min · L 12 · R 9") with Add note / Edit / Done, plus a 6 s undo toast.
- **Live Activities disabled:** subtle footer link "Show on Lock Screen: turn on Live Activities".

### 3.4 Log Bottle (sheet)
- Segmented contents: **Breast milk · Formula · Other**.
- Amount: preset chips (e.g. 60 / 90 / 120 mL or 2 / 3 / 4 oz, editable in Settings), plus a stepper and numeric field. Unit toggle mL/oz (defaults to preference).
- Time: "Now" by default; tap to change start. Optional duration or end time.
- Notes (collapsed).
- **Save** is primary at the bottom, reachable one-handed. Validation: amount > 0 and ≤ 500 mL.
- Two-tap path: open sheet → tap preset → Save (preset tap can auto-focus Save).

### 3.5 Calendar (History → Calendar)

*Revised 2026-11-07:* a **Week | Month** switch, Week by default. Week shows seven day columns on a
24-hour axis (labels every 3 hours) with each feed drawn as a block at its time, as tall as it
lasted: breastfeeds split lavender/teal by side (first side on top), bottles as small peach/butter
capsules. Tap a day's header or column to see its summary below, with "Open day". Month is the
grid described here.

- Month grid (custom SwiftUI `LazyVGrid`), swipe or chevrons to change month, "Today" button.
- Each day: up to 3 dots (lavender/teal for breast sides used, peach for bottle). Background intensity scales with feed count (5 steps, subtle). Today has a ring.
- Selecting a day shows an inline **Day Summary** card below the grid: feeds, breast time (L/R `SegmentBar`), bottle volume, avg interval. Then the day's `FeedRow`s, then "Open day" pushes the full day timeline.
- **Empty month:** "No feeds this month" with a muted grid. Future days are dimmed.

### 3.6 History / Timeline
- Vertical timeline grouped by day (sticky headers "Today", "Yesterday", "Tue 4 Nov").
- `FeedRow`: time column, colored rail, icon, title ("Breast · 21 min" / "Bottle · 90 mL formula"), `SegmentBar` for L/R, note preview, **gap label** between rows ("2 h 40 m later") so intervals are visible at a glance.
- **List | Calendar** switch at the top (Calendar is §3.5).
- Filter menu in the toolbar: All feeds, plus Breastfeeds · Bottles · Pumping toggles that combine (at least one stays on); the menu stays open while toggling and its icon fills when a filter is on.
  Picking a date is done in Calendar mode.
- Swipe actions: Edit, Delete (confirmation + undo). Tap opens Edit.
- Rows with `needsReview` show a small amber "Review" badge.
- **Empty:** illustration + "Your feeds will appear here".

### 3.7 Edit / Manual Entry (sheet)

*Revised 2026-11-07 — notes get real space:* the sheet opens with a header (feed type icon, "Breastfeed",
"Today · 2:15 – 2:36 AM") and Save is a prominent button pinned at the bottom. Notes use a shared
`NotesEditor`: a multi-line box showing several lines before anything is typed, with one-tap tags
(Sleepy, Fussy, Good latch, Spit up, Hiccups; bottle sheet: Finished it, Left some, Spit up…). The
same editor appears on the **Feed saved** summary ("Add a note…", saved on Done) and from the timer's
**Add note**. History rows show notes in a soft tinted block of up to 6 lines instead of a 2-line
preview.

- Type picker (Breast / Bottle). Start date-time, end date-time.
- Breast: **Simple mode** (Left minutes, Right minutes, which side first) or **Segments mode** (list of side/start/end rows, add/remove). Live validation messages inline.
- Notes. Delete button at the bottom for existing entries.

### 3.8 Insights
- Range picker: **24 h (rolling) · 7 d · 14 d · 30 d**.
- Cards, each with a chart and a one-line plain-language summary ("Avg 8.4 feeds/day, up from 7.9 last week"):
  1. Feeds per day (bar) + avg line.
  2. Intervals: avg / shortest / longest + scatter of intervals by time of day.
  3. Breastfeeding: avg session, avg L vs R, L/R distribution (donut).
  4. Bottle: daily volume (stacked bar breast milk vs formula), avg bottle.
  5. Activity heatmap (hour-of-day × day).
- Comparisons with the previous period are part of each card's one-line summary. The former
  "Compared with before" card was removed: it ignored the range picker and repeated the Feeds
  card and Home's Today tiles.
- One footer under all the cards: "Based on your recorded feeds. Not medical advice." Values from `manual`/`recovered` sessions are marked "includes estimated entries" when present.
- **Insufficient data state:** "Insights appear after a couple of days of tracking". Show what exists.

### 3.9 Tools (removed)
Folded into other screens (see §1): time since last feed is on Home, side balance in Insights,
today and week totals on Home and in Insights, gaps between feeds in History, manual entry under
History's **+**, and export in Settings.

### 3.10 Settings
Baby profile · Bottle and pumping (a unit for each, shown everywhere including past entries, and each one's presets in a dropdown) · Reminders (enable, interval, basis start/end, quiet hours, "still feeding?" threshold) · Live Activities status + dismissal policy · Interval definition · Appearance (system/light/dark) · Data (export, how backup works, **Import from Huckleberry**, **Remove imported data** (shown only when something was imported; simple alert), **Delete all data** with typed confirmation) · About / privacy / disclaimer.

**Import from Huckleberry.** Huckleberry emails one CSV per child ("Export tracking data as CSV"). The sheet explains how to get the file, then Choose File opens Files. Nothing is saved until the preview's Import button:
- Ready to import: breastfeeds, bottles and pumping sessions, with the date range.
- Skipped: rows already in Newbee (same kind starting in the same minute, so importing again is safe) and the count of each Huckleberry type Newbee doesn't track (Sleep, Diaper, Growth…).
- Couldn't import: rows Newbee can't read or wouldn't accept if typed in (bottle over 500 mL, nursing over 4 hours, future times), each with a reason.
Format details: Huckleberry gives minutes per side but not the order, so feeds that used both sides start on Left. "Mixed" bottles are saved as Other with the note "Mixed breast milk and formula". A pumping row with one amount and no side ("3oz", how a total is logged) is split evenly between Left and Right. Times are read in the phone's time zone. Parser: NewbeeKit `HuckleberryCSV`, `ImportPlan`.

### 3.11 Recovery sheet
See `TIMER_ENGINE.md` §5.

---

## 4. Key user flows (tap counts)

| Flow | Taps |
|---|---|
| Start feed from Home | 1 (Start L/R) |
| Switch side from Lock Screen | 1 |
| End feed from Lock Screen | 1 |
| Log a preset bottle | 3 (Log bottle → preset → Save) |
| See time since last feed | 0 (open app) |
| Fix a forgotten timer | 2 (open app → "End at 2:41 AM") |

## 5. Accessibility

- Full VoiceOver labels ("Left side, active, 12 minutes 5 seconds"); timers expose `accessibilityValue` updated each minute, not each second.
- Dynamic Type up to AX5: timer screen switches L/R to a vertical stack at accessibility sizes.
- Color never sole carrier of meaning; Increase Contrast variants of tokens; Reduce Motion respected.
- Large-hit-area controls; End uses hold-to-confirm *or* undo, so it doesn't rely on precise taps.
