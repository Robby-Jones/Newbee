# Routes / screens

> Project: Newbee — native iOS 18+ app (SwiftUI, SwiftData, ActivityKit). NOT a web app: no React/Tailwind/CSS. Designs are iPhone screens (390×844 pt) and Live Activity surfaces. UI uses SF Pro / SF Pro Rounded, SF Symbols, system materials.

No URL routing. Screen map (tab → screen → pushed/presented):

| Screen | File | Presentation |
|---|---|---|
| Home (dashboard) | `Newbee/Features/Dashboard/DashboardView.swift` | Tab 1 root, large title greeting |
| Breastfeeding timer | `Newbee/Features/Breastfeeding/BreastfeedingTimerView.swift` | Full-screen cover from Home Start L/R or the pill |
| Feed saved summary | `Newbee/Features/Breastfeeding/SessionSummaryView.swift` | Inside the timer cover after End |
| Log / edit bottle | `Newbee/Features/BottleFeeding/LogBottleSheet.swift` | Sheet (.medium/.large) |
| History (List mode) | `Newbee/Features/History/HistoryView.swift` | Tab 2 root; List / Calendar segmented switch on top |
| History (Calendar mode) | `Newbee/Features/Calendar/CalendarView.swift` | Month grid + selected day summary |
| Day detail | `Newbee/Features/Calendar/DayFeedsView.swift` | Pushed from Calendar "Open day" |
| Edit / add breastfeed (incl. Notes) | `Newbee/Features/History/BreastFeedEditSheet.swift` | Sheet from a History row or + menu |
| Insights | `Newbee/Features/Insights/InsightsView.swift` | Tab 3 root, range picker 24h/7d/14d/30d |
| Settings | `Newbee/Features/Settings/SettingsView.swift` | Tab 4 root, grouped Form |
| Live Activity — Lock Screen | `NewbeeWidgets/LiveActivity/LockScreenFeedingView.swift` | Lock Screen / banner (widget extension) |
| Live Activity — Dynamic Island | `NewbeeWidgets/LiveActivity/DynamicIslandViews.swift`, `FeedingLiveActivity.swift` | Expanded / compact / minimal |

Notes today: a plain text field per feed (bottle sheet "Notes" disclosure; breastfeed edit sheet), previewed as 2 lines in History rows. There is no dedicated notes view.
