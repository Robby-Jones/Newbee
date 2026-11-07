# Newbee: Navigation & Screen-by-Screen UX Spec

Status: **Draft for approval** · Deliverables 6 (navigation) and 7 (preliminary UI/UX spec)

---

## 1. Navigation structure

```
TabView
├── Home        (house)          ← default tab
├── Calendar    (calendar)
├── History     (list.bullet)
├── Insights    (chart.bar)
└── Tools       (wrench.and.screwdriver) → Settings lives here too
```

**Global elements**
- **Active Session Pill**: when a breastfeeding session is active or paused, a compact pill floats above the tab bar on *every* tab ("● L 12:05 · total 18:42", side-tinted). Tap opens the timer sheet. Built with `safeAreaInset(edge: .bottom)` on iOS 18; adopt the system tab-bar accessory API on newer iOS via availability checks.
- **Settings** gear on Home (top-right) and a row in Tools.

**Modal presentation choices** (keeps navigation depth at most 2)

| Flow | Presentation | Why |
|---|---|---|
| Breastfeeding timer | **Full-screen cover**, swipe-down/"Minimise" to dismiss (session keeps running) | Focus, one-handed, big targets |
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
| `text.primary / secondary` | | system label colors | |
| `accent` | Primary actions | soft indigo `#6B6FD6` | `#8E91F0` |
| `side.left` | Left breast | lavender `#9C8CE0` | `#B3A6F0` |
| `side.right` | Right breast | teal `#4FB3A9` | `#6FCFC4` |
| `feed.bottle.breastMilk` | Bottle (EBM) | peach `#F2A37B` | `#F5B593` |
| `feed.bottle.formula` | Bottle (formula) | butter `#E8C25A` | `#EDD07A` |
| `state.paused` | Paused | system gray | |
| `state.destructive` | Delete/End emphasis | muted rose `#D9667A` | `#E88092` |

Exact values are refined in Phase 3. Side and feed colors are always paired with a letter or icon.

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
1. **Welcome**: "Track feeds in two taps." Privacy line: "Your data stays on this iPhone."
2. **Baby**: nickname (optional), birth date (optional). Units: mL / oz.
3. **Stay in the loop**: explains Live Activities (illustration of the Lock Screen) and asks for notification permission *only if* the parent turns on reminders here. "Not medical advice" footnote.

### 3.2 Home / Dashboard
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
[ 7 feeds ] [ 1 h 48 m breast ] [ 180 mL bottle ] [ avg 2 h 51 m ]
Last 24 h: 9 feeds · avg interval 2 h 40 m  (rolling)
Shortcuts: Calendar · History
```
- **Active state:** the "Last feed" card becomes a live **Active Session card** (side, per-side and total timers, Pause / Open timer). Start buttons are replaced by "Switch to R".
- **Empty state:** "No feeds yet. Start your first one below." Start buttons remain.
- **Error state:** store failed to load → full-screen message with Retry and "Export data" (never silently reset).

### 3.3 Breastfeeding Timer (full-screen cover)
```
 ⌄ Minimise                         ⋯ (Edit start time, Add note, Discard)
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
- **Paused:** whole screen desaturates, the total shows "Paused", Pause turns into a filled **Resume**, and tapping a side resumes on that side.
- **After End:** summary sheet ("21 min · L 12 · R 9") with Add note / Edit / Done, plus a 6 s undo toast.
- **Live Activities disabled:** subtle footer link "Show on Lock Screen: turn on Live Activities".

### 3.4 Log Bottle (sheet)
- Segmented contents: **Breast milk · Formula · Other**.
- Amount: preset chips (e.g. 60 / 90 / 120 mL or 2 / 3 / 4 oz, editable in Settings), plus a stepper and numeric field. Unit toggle mL/oz (defaults to preference).
- Time: "Now" by default; tap to change start. Optional duration or end time.
- Notes (collapsed).
- **Save** is primary at the bottom, reachable one-handed. Validation: amount > 0 and ≤ 500 mL.
- Two-tap path: open sheet → tap preset → Save (preset tap can auto-focus Save).

### 3.5 Calendar
- Month grid (custom SwiftUI `LazyVGrid`), swipe or chevrons to change month, "Today" button.
- Each day: up to 3 dots (lavender/teal for breast sides used, peach for bottle). Background intensity scales with feed count (5 steps, subtle). Today has a ring.
- Selecting a day shows an inline **Day Summary** card below the grid: feeds, breast time (L/R `SegmentBar`), bottle volume, avg interval. Then the day's `FeedRow`s, then "Open day" pushes the full day timeline.
- **Empty month:** "No feeds this month" with a muted grid. Future days are dimmed.

### 3.6 History / Timeline
- Vertical timeline grouped by day (sticky headers "Today", "Yesterday", "Tue 4 Nov").
- `FeedRow`: time column, colored rail, icon, title ("Breast · 21 min" / "Bottle · 90 mL formula"), `SegmentBar` for L/R, note preview, **gap label** between rows ("2 h 40 m later") so intervals are visible at a glance.
- Filter chips: All · Breast · Bottle. Jump-to-date via a date picker toolbar button.
- Swipe actions: Edit, Delete (confirmation + undo). Tap opens Edit.
- Rows with `needsReview` show a small amber "Review" badge.
- **Empty:** illustration + "Your feeds will appear here".

### 3.7 Edit / Manual Entry (sheet)
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
  5. Comparisons: today vs yesterday, this week vs last week (delta chips).
  6. Activity heatmap (hour-of-day × day).
- Footer on every card: "Based on your recorded feeds. Not medical advice." Values from `manual`/`recovered` sessions are marked "includes estimated entries" when present.
- **Insufficient data state:** "Insights appear after a couple of days of tracking". Show what exists.

### 3.9 Tools
- Interval calculator (since last feed; between two chosen feeds).
- Side tracker (last side, suggested next, last 5 sessions' starting sides).
- Quick stats (today / this week).
- Manual entry (opens 3.7).
- Export (CSV / PDF with a date range, then the share sheet).
- Settings.

### 3.10 Settings
Baby profile · Units · Bottle presets · Reminders (enable, interval, basis start/end, quiet hours, "still feeding?" threshold) · Live Activities status + dismissal policy · Interval definition · Appearance (system/light/dark) · Data (export, how backup works, **Delete all data** with typed confirmation) · About / privacy / disclaimer.

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
