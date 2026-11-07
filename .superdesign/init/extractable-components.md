# Extractable components

> Project: Newbee — native iOS 17+ app (SwiftUI, SwiftData, ActivityKit). NOT a web app: no React/Tailwind/CSS. Designs are iPhone screens (390×844 pt) and Live Activity surfaces. UI uses SF Pro / SF Pro Rounded, SF Symbols, system materials.

SwiftUI sources; convert to HTML only if a draft needs them repeated across pages.

#### Layout Components
## TabBar
- Source: `Newbee/App/RootView.swift`
- Category: layout
- Description: iOS tab bar with Home (house), History (clock.arrow.circlepath), Insights (chart.bar), Settings (gearshape)
- Extractable props: activeItem (string, default: "home")
- Hardcoded: tab labels, SF Symbol names, accent tint #6B6FD6

## ActiveSessionPill
- Source: `Newbee/Shared/Components/ActiveSessionPill.swift`
- Category: layout
- Description: floating capsule above the tab bar while a feed runs ("● L 12:05 · Total 18:42 ^")
- Extractable props: side (string, default: "left"), isPaused (boolean, default: false)
- Hardcoded: material background, side-colored outline

#### Basic Components
## FeedRow
- Source: `Newbee/Features/History/FeedFormatting.swift`
- Category: basic
- Description: timeline row with time, colored rail, title, L/R bar, note preview, gap label
- Extractable props: kind (string, default: "breast")

## SideBadge
- Source: `Newbee/Shared/Components/SideBadge.swift`
- Category: basic
- Description: L/R letter in a side-colored circle (filled or outlined)
- Extractable props: side (string, default: "left"), filled (boolean, default: true)
