# Page dependency trees

> Project: Newbee — native iOS 17+ app (SwiftUI, SwiftData, ActivityKit). NOT a web app: no React/Tailwind/CSS. Designs are iPhone screens (390×844 pt) and Live Activity surfaces. UI uses SF Pro / SF Pro Rounded, SF Symbols, system materials.

## Live Activity (Lock Screen + Dynamic Island)
Entry: `NewbeeWidgets/LiveActivity/FeedingLiveActivity.swift`
- `NewbeeWidgets/LiveActivity/LockScreenFeedingView.swift`
  - `NewbeeWidgets/LiveActivity/LiveActivityComponents.swift` (SideBadge, TotalTimerText, SideRow, ActivityControlLabel, EndControlLabel, PauseResumeButton, EndButton, SideSwitchButton, ActivitySidesAndControls, UndoEndButton)
- `NewbeeWidgets/LiveActivity/DynamicIslandViews.swift`
- `Packages/NewbeeShared/Sources/NewbeeShared/DesignTokens/DesignTokens.swift`

## History → Calendar mode
Entry: `Newbee/Features/History/HistoryView.swift`
- `Newbee/Features/Calendar/CalendarView.swift` (CalendarMonthView, MonthGrid, DayCell, DaySummaryCard, DayTotalsRow, MiniStat, MonthSummary)
  - `Newbee/Features/History/FeedFormatting.swift` (FeedRow, FeedText)
  - `Newbee/Shared/Components/Card.swift`
  - `Newbee/Shared/Components/SegmentBar.swift`
- `Newbee/Features/Calendar/DayFeedsView.swift`
- `Newbee/Features/History/BreastFeedEditSheet.swift`

## History → List mode
Entry: `Newbee/Features/History/HistoryView.swift`
- `Newbee/Features/History/FeedFormatting.swift` (FeedRow, ReviewBadge)
  - `Newbee/Shared/Components/SegmentBar.swift`

## Edit breastfeed (notes)
Entry: `Newbee/Features/History/BreastFeedEditSheet.swift`
- `Newbee/Shared/Components/SideBadge.swift`

## Log bottle (notes)
Entry: `Newbee/Features/BottleFeeding/LogBottleSheet.swift`
- `Newbee/Shared/Components/Card.swift`

## Home
Entry: `Newbee/Features/Dashboard/DashboardView.swift`
- `Newbee/Features/BottleFeeding/BottleLogPresentation.swift`
- `Newbee/Shared/Components/SideButton.swift`, `SideBadge.swift`, `TimerText.swift`, `Card.swift`

## Breastfeeding timer
Entry: `Newbee/Features/Breastfeeding/BreastfeedingTimerView.swift`
- `Newbee/Features/Breastfeeding/SessionSummaryView.swift`
- `Newbee/Shared/Components/SideButton.swift`, `TimerText.swift`, `SegmentBar.swift`, `SideBadge.swift`
