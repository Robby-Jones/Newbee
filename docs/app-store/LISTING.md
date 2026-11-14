# App Store listing (v1.0)

Draft copy for App Store Connect → Newbee → App Information and the 1.0 version page.
American English. Character limits are Apple's; counts are noted where they are tight.

## App Information

| Field | Value | Limit |
|---|---|---|
| Name | Newbee: Nursing Timer & Log | 27 / 30 |
| Subtitle | Feeds from your Lock Screen | 27 / 30 |
| Primary category | Health & Fitness | |
| Secondary category | Lifestyle | |
| Content rights | Does not contain, show, or access third-party content | |
| Age rating | 4+ (every content question answered "None") | |
| Price | Free, no in-app purchases | |
| Availability | All countries and regions, English (U.S.) listing | |

The name and subtitle lead with what sets Newbee apart (the Lock Screen timer) instead of the
generic category words. They were changed after Apple's 4.3(a) rejection on 2026-11-13; the first
submission used "Newbee: Baby Feeding Tracker" and "Breastfeeding timer & bottles". The name on
the Home Screen stays "Newbee" either way (`CFBundleDisplayName`).

## Version 1.0

### Promotional text (170)

> Run the whole breastfeeding timer from your Lock Screen and Dynamic Island. Switch sides, pause and end a feed without opening the app. No account. No subscription.

164 / 170.

### Description (4,000)

> Newbee puts your baby's feeds on your Lock Screen. Start a breastfeed with one tap, then switch sides, pause and end it from the Lock Screen or Dynamic Island at 3 a.m., without opening an app. Between feeds it keeps counting the time since your baby last ate, right where you can see it.
>
> No account. No ads. No subscription. Nothing you enter is collected by us.
>
> ON YOUR LOCK SCREEN AND DYNAMIC ISLAND
> • Switch sides, pause and end a feed without opening the app
> • A "since last feed" clock between feeds
> • Time stays exact if the app closes, your iPhone restarts, or you change time zones
> • Fell asleep with the timer running? Newbee asks and helps you fix the entry
>
> EVERY KIND OF FEED
> • Breastfeeding by side, with a suggestion for which side to start on next
> • Bottle feeds: breast milk, formula, or other, in oz or mL, with quick presets
> • Pumping sessions with left and right amounts
> • Add or edit past feeds anytime, with notes
> • Undo for accidental taps
>
> SEE THE PATTERNS
> • Home shows the last feed, last side, and today at a glance
> • History with filters and a calendar view
> • Insights: how often, how long, and how much over 7, 14, or 30 days, plus the last 24 hours
>
> MADE FOR 3 A.M.
> • Big, one-handed controls
> • Dark mode and Dynamic Type
> • Gentle reminders since the last feed, with quiet hours
>
> A REPORT FOR YOUR PEDIATRICIAN
> • Export a clean PDF feeding report or a CSV file
>
> BRING YOUR HISTORY, KEEP IT IN SYNC
> • Switching trackers? Import your feeds from a CSV export
> • Syncs between your own iPhones and iPads through your private iCloud
>
> PRIVATE BY DESIGN
> • No account, no ads, no tracking
> • Your data stays on your devices and in your own iCloud. It is never collected by us
>
> Newbee is a log, not medical advice. Always talk to your pediatrician about feeding concerns.

The "BRING YOUR HISTORY" section is true only for a build with the import (43+) and iCloud sync
(47+). Remove it if an older build is submitted.

### Keywords (100)

```
baby,feeding,tracker,breastfeeding,bottle,newborn,pumping,formula,infant,lactation,feed,diary,milk
```
98 / 100. These now carry the category words that left the name and subtitle. Words in the name
and subtitle (nursing, timer, log, feeds, lock, screen) are indexed anyway. No competitor names
(Apple rejects them).

### What's New in This Version

> First release. Welcome to Newbee!

### URLs

| Field | Value |
|---|---|
| Support URL | https://robby-jones.github.io/Newbee/support.html |
| Marketing URL | https://robby-jones.github.io/Newbee/ (optional) |
| Privacy Policy URL | https://robby-jones.github.io/Newbee/privacy.html |

### Copyright

`2026 Robby Jones`

## App Review information

- **Sign-in required:** No (there is no account).
- **Contact:** Robby's name, phone and email (only Apple sees these).
- **Notes for the reviewer:**

> Newbee has no account and no server. All data stays on the device.
> To try the main feature: tap Breastfeed on Home, choose Left or Right, then lock the phone.
> The timer appears as a Live Activity on the Lock Screen and in the Dynamic Island, where you
> can switch sides, pause, or end the feed. Bottle and Pump on Home log other feeds.
> Settings → Your data exports a PDF report or CSV. Notifications are optional and only used
> for feeding reminders the parent sets up.

## Screenshots

Six captioned screenshots, 1206 x 2622, in this order. The first three show the Lock Screen and
Dynamic Island, which a plain app screen can't, and come from a real iPhone.

1. Lock Screen with the timer running: "Your feeding timer, on the Lock Screen"
2. Dynamic Island expanded: "Switch sides without opening the app"
3. Lock Screen between feeds: "Always know when your baby last ate"
4. Home: "Breast, bottle and pumping in two taps"
5. Insights: "See the pattern"
6. History: "Every feed, ready for your pediatrician"

Shots 4 to 6 start from the **Screenshots** workflow output (Actions → Screenshots → Run
workflow, artifact `app-store-screenshots`, 6.3" iPhone Pro simulator with two weeks of sample
feeds). `scripts/caption-screenshots.py` adds the caption and background to any screenshot.

Upload them to the **iPhone with Dynamic Island (medium display)** tab. Apple scales them for
other iPhones. Skip the iPhone Duo, iPad and Apple Watch tabs: Newbee is iPhone-only.
