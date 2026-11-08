# App Privacy answers (App Store Connect → App Privacy)

Newbee has no server, no account, no analytics or crash SDKs, no ads, and no third-party
packages. Everything is stored on the device (SwiftData and App Group `UserDefaults`). Data
only leaves the phone when the parent exports a PDF or CSV and shares it themselves through the
share sheet, which Apple does not count as collection.

## Data collection

**"Do you or your third-party partners collect data from this app?" → No, we do not collect data from this app.**

The App Store then shows **Data Not Collected**.

Why each likely category is "not collected":

| Data | Where it lives | Collected? |
|---|---|---|
| Feeds, pumping, notes (Health & Fitness) | On device only | No |
| Baby's nickname and photo | On device only (photo chosen with the system picker, no library permission) | No |
| Settings and reminders | On device only | No |
| Crash reports | Apple's own opt-in diagnostics only; no SDK in the app | No |

If iCloud sync is added later, data stored in the user's own private iCloud database is still
not "collected" by us, but these answers should be reviewed again then.

## Tracking

**Does this app track users? → No.** `NSPrivacyTracking` is `false` and there are no tracking domains.

## Privacy manifests

- `Newbee/Resources/PrivacyInfo.xcprivacy` (app)
- `NewbeeWidgets/PrivacyInfo.xcprivacy` (Live Activity extension)

Required-reason APIs declared:

| API category | Reason | Why |
|---|---|---|
| User defaults | `1C8F.1` | Settings shared with the Live Activity extension through the App Group |
| User defaults | `CA92.1` | Fallback to the app's own defaults if the App Group is unavailable |
| System boot time | `35F9.1` | The timer measures elapsed time across sleep and detects reboots (`AppClock.swift`) |

No data types are declared in `NSPrivacyCollectedDataTypes` because none are collected.
