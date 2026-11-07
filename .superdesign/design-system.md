# Newbee design system

## Product
Newbee is a native iPhone app (iOS 17+, SwiftUI) for tracking a newborn's feeds: a breastfeeding timer that can't lose time, quick bottle logging, history, insights and reminders. Users are tired parents, often one-handed, often in the dark at 3 a.m. Private by default: everything stays on the phone.

Jobs to be done:
- See at a glance when the baby last ate, how long ago, and which side to start on.
- Start, switch side, pause and end a breastfeed in one tap — including from the Lock Screen and Dynamic Island (Live Activity).
- Log a bottle in two taps.
- Look back over the day/week (calendar, timeline) and jot or read notes about feeds.

Navigation: 4-tab iOS tab bar — Home, History (List | Calendar), Insights, Settings. Timer is a full-screen cover; bottle log and edit screens are sheets. An "active session pill" floats above the tab bar while a feed runs.

## Layout direction (this redesign)
Model the **layout, spacing and information density** on Huckleberry, the popular baby tracker, while keeping Newbee's own name, colors and type. Do NOT copy Huckleberry's logo, name, mascot, illustrations or exact colors.

Huckleberry-style layout patterns to follow:
- **Generous, calm screens**: few elements per screen, big rounded tap targets, lots of breathing room, content centered in the thumb zone.
- **Home**: baby name + age at the top; one large "time since last feed" summary; a row of big rounded activity buttons (Breastfeed L / R, Bottle) each with a small "last: 2h 10m ago" caption; a compact list of today's recent entries underneath.
- **Calendar / history**: a **day-columns timeline** — one vertical column per day (e.g. 7 days across), a 24-hour vertical time axis, and each feed drawn as a rounded colored block at its time and length (lavender = left, teal = right, peach = bottle). Tap a day to see that day's list. A compact week/month switcher at top.
- **Notes**: notes get real space — a full-width multiline notes area (several lines tall) on each feed's detail/edit screen, an "Add note" affordance right after ending a feed, and note text shown on its own line (not truncated to a tiny preview) in the history list.
- **Timer**: two big circular L / R buttons side by side with the elapsed time inside each, a large total at the top, "Last side" hint, and Pause / Finish below.
- **Live Activity**: minimal — fewer labels, fewer outlines, one clean line of information plus the controls.

## Colors (keep Newbee's palette exactly)
| Token | Light | Dark | Use |
|---|---|---|---|
| canvas | #FAF8F5 | #0F0F12 | app background |
| card | #FFFFFF | #1B1B20 | cards, sheets |
| accent | #6B6FD6 | #8E91F0 | primary actions, tab tint |
| side.left (lavender) | #9C8CE0 | #B3A6F0 | left breast |
| side.right (teal) | #4FB3A9 | #6FCFC4 | right breast |
| bottle.breastMilk (peach) | #F2A37B | #F5B593 | bottle of breast milk |
| bottle.formula (butter) | #E8C25A | #EDD07A | bottle of formula |
| destructive (muted rose) | #D9667A | #E88092 | delete, End |
| text | iOS label / secondaryLabel / tertiaryLabel | | |

Side and feed colors are always paired with a letter (L / R) or an icon — color never carries meaning alone. Text on a filled side color is dark (#1B1B20), never white.

The Dynamic Island is always black. The Lock Screen Live Activity sits on the system's translucent dark/light background.

## Typography
- SF Pro for body text, using iOS semantic sizes (largeTitle 34, title2 22, title3 20, headline 17 semibold, body 17, subheadline 15, footnote 13, caption 12).
- SF Pro Rounded for numerals, timers and headings. Timers use monospaced digits.
- No other fonts.

## Shape, spacing, depth
- 4-pt grid: 4 / 8 / 12 / 16 / 24 / 32.
- Card radius 20 (continuous corners); controls radius 16; circular buttons for L / R.
- Light mode: soft shadow (y 2, blur 8, 6% black). Dark mode: 1 pt hairline border (white 8%), no shadow.
- Minimum tap target 44 pt; primary timer controls at least 88 pt.
- Icons: SF Symbols only (house, clock.arrow.circlepath, chart.bar, gearshape, waterbottle.fill, heart.fill, pause.fill, play.fill, stop.fill, note.text, calendar).

## Device
iPhone, 390 × 844 pt, with status bar, home indicator and the iOS tab bar where the screen has one. Show dark mode for the Live Activity and night-use screens; light mode is fine elsewhere.
