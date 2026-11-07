# Newbee

Newborn feeding tracker + insights app for iOS 17+. SwiftUI, SwiftData, ActivityKit (Live Activities and Dynamic Island).

Planning docs: [docs/README.md](docs/README.md). Progress: [docs/CHECKLIST.md](docs/CHECKLIST.md).

## Getting started (Mac)

1. Install Xcode 26 or newer and XcodeGen: `brew install xcodegen`
2. Create your signing config:
   ```sh
   cp Config/Signing.local.xcconfig.example Config/Signing.local.xcconfig
   ```
   Set `NEWBEE_DEVELOPMENT_TEAM` to your Apple Developer Team ID.
3. Generate and open the project:
   ```sh
   xcodegen generate && open Newbee.xcodeproj
   ```
   Re-run `xcodegen generate` after pulling changes that add or move files. The `.xcodeproj` is generated and not committed.
4. Choose the **Newbee** scheme and run on your iPhone. With automatic signing, Xcode registers the App Group (`group.<bundle id>`) the first time.

## Getting it on an iPhone without a local Mac (TestFlight)

Building needs Xcode 26 (macOS 15.6+), which App Store uploads also require. Without a Mac that runs it, the **TestFlight** workflow
(`.github/workflows/testflight.yml`) archives, signs and uploads the app from GitHub Actions on
every push to `main` (or manually from **Actions → TestFlight → Run workflow**). Install builds
with the TestFlight app on the iPhone.

One-time setup:
1. developer.apple.com → Identifiers: register App Group `group.com.robbyjones.newbee`, and App IDs
   `com.robbyjones.newbee` and `com.robbyjones.newbee.widgets`, both with that App Group.
2. App Store Connect → Apps → New App with bundle ID `com.robbyjones.newbee`.
3. App Store Connect → Users and Access → Integrations → App Store Connect API: create a Team Key
   with the **Admin** role (needed for cloud-managed signing) and download the `.p8`.
4. Repository secrets: `APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (the `.p8` contents).
5. App Store Connect → TestFlight: add yourself to an internal testing group.

Without the secrets the workflow skips instead of failing.

## Layout

| Path | What |
|---|---|
| `Packages/NewbeeKit` | Platform-independent domain logic (session engine, analytics). Tests run on Linux and macOS: `cd Packages/NewbeeKit && swift test` |
| `Packages/NewbeeShared` | Code shared by the app and widget extension (Live Activity attributes, design tokens) |
| `Newbee/` | App target |
| `NewbeeWidgets/` | Widget extension (Live Activities) |
| `NewbeeTests/`, `NewbeeUITests/` | App unit/integration tests (Swift Testing) and UI tests (XCTest) |
| `project.yml` | XcodeGen project spec |

## CI

`.github/workflows/ci.yml` runs NewbeeKit tests on Linux and builds and tests the app on an iOS simulator (macOS runner, unsigned).
