# App Review notes and screen recording (Guideline 2.1)

Apple asked for more information before reviewing version 1.0 (Guideline 2.1, Information
Needed, 2026-11-10). This file holds the answer: the text for the **Notes** field and the shot
list for the screen recording Apple asked for.

## Where it goes

1. App Store Connect → Newbee → the 1.0 version page → **App Review Information** → **Notes**:
   paste the text below (it replaces the short note from `LISTING.md`). The field holds 4,000
   characters; the text is about 3,300.
2. Same section → **Attachment**: add the screen recording. If the file is too big, reply to
   Apple's message in **App Review** (the message thread accepts attachments) or trim the
   recording.
3. Reply to Apple's message with one line, for example: "Thank you. The requested information
   is now in the App Review Information notes, and the screen recording is attached."
4. Resubmit. The build doesn't need to change.

## Which build

The answers depend on the build that is in review (App Store Connect shows its number on the
version page, under Build):

| Build | Huckleberry import | iCloud sync |
| --- | --- | --- |
| 42 or lower | No | No |
| 43 to 46 | Yes | No |
| later builds with iCloud sync | Yes | Yes: the notes need an iCloud line first |

The Import line in item 3 starts with **[Build 43+ only]**. For build 42 or lower, delete that
whole line before pasting. For builds 43 to 46, keep the line and delete only the marker. No build
with iCloud sync has been uploaded as of 2026-11-10, so "no external services" is accurate for
every build that can be in review today. If a build with iCloud sync is ever submitted, item 4
must say that the app uses Apple's iCloud (CloudKit private database) to sync between the
user's own devices.

## Notes field text

```
Thank you for reviewing Newbee. The information you asked for (Guideline 2.1):

1. SCREEN RECORDING
Attached. It was recorded on a physical iPhone running the latest iOS, starts with launching the app, and shows the typical flow. Newbee has no account registration, login or account deletion, no user-generated content shared between users (so no reporting or blocking), and no purchases, subscriptions or paid content. The only permission prompt is for notifications, and it appears only if the parent turns on a feeding reminder.

2. PURPOSE AND AUDIENCE
Newbee is a simple feeding log for parents and caregivers of newborns and infants. Parents are asked many times a day when the baby last ate, on which side, and how much. Newbee answers that: it times breastfeeds per side, logs bottles and pumping sessions, shows the time since the last feed, and summarizes the day and week. It is used by adults; it is not directed at children.

3. SETUP AND MAIN FEATURES
No login, account or sample file is needed. On first launch there are three short onboarding screens (all skippable): welcome, optional baby name/birth date/photo, and an optional feeding reminder.
- Breastfeed timer: Home tab → Breastfeed → choose L or R. Switch sides, Pause/Resume, End feed.
- Live Activity: while a feed runs, lock the phone. The timer is on the Lock Screen and in the Dynamic Island. After the feed ends it shows the time since the last feed.
- Bottle: Home → Bottle → pick an amount → Save.
- Pump: Home → Pump → enter amounts → Save.
- History tab: list of feeds; tap one to edit or delete. The Calendar switch shows week and month views.
- Insights tab: daily totals and charts.
- Settings tab: units, bottle presets, reminders, appearance; Your data → Export feeding report (PDF), Export feeds (CSV), Delete all data.
[Build 43+ only] - Import: Settings → Your data → Import from Huckleberry reads a CSV exported from the Huckleberry app, for parents who are switching. It is optional and not needed to use the app. The file is read on the device only.

4. EXTERNAL SERVICES
None. Newbee has no server, no account system, no analytics, no advertising, no third-party SDKs, no payment processing and no AI services. It uses only Apple frameworks on the device (SwiftUI, SwiftData, ActivityKit/WidgetKit for the Live Activity, local notifications, the system photo picker for the optional baby photo). All data stays on the device unless the user exports a PDF or CSV with the share sheet. The privacy label is "Data Not Collected".

5. REGIONAL DIFFERENCES
None. The app works the same in every region. It is in English, makes no network requests, and has no region-specific content or features. Dates, times and units (oz or mL) follow the device and the user's settings.

6. REGULATED INDUSTRY / THIRD-PARTY MATERIAL
Not applicable. Newbee is a record-keeping tool, not a medical device. It gives no diagnosis, treatment or feeding advice, and says so in onboarding and in Settings ("Newbee is a log, not medical advice. Ask your pediatrician about feeding concerns."). It contains no third-party content, trademarks or licensed material; all artwork and code are our own.

Support: https://robby-jones.github.io/Newbee/support.html
Privacy policy: https://robby-jones.github.io/Newbee/privacy.html
```

## Screen recording shot list

Apple wants a recording made on a real iPhone, on the latest iOS, that **starts with launching
the app**. Aim for 2 to 3 minutes.

Before recording:

- Update the iPhone to the latest iOS (Settings → General → Software Update).
- Use the TestFlight build that is in review.
- Add Screen Recording to Control Center if it isn't there (Settings → Control Center).
- Turn on Do Not Disturb so no personal notifications appear.
- Close Newbee from the app switcher so the recording shows a fresh launch.
- Don't delete the app to show onboarding: that erases the feeds on the phone. Onboarding is
  described in the notes, which is enough.
- The recording shows the baby's name and photo. Remove the photo first (Settings → Baby) if
  you'd rather Apple not see it.

Shots, in order:

1. **Launch.** Start the recording from Control Center, go to the Home Screen, tap Newbee.
   Pause two seconds on Home (time since last feed, the three buttons).
2. **Breastfeed timer.** Tap Breastfeed, choose L. Let it run about ten seconds. Tap R to
   switch sides. Tap Pause, then Resume.
3. **Live Activity.** Lock the phone, wake it and show the timer on the Lock Screen. Unlock,
   go to the Home Screen and show the Dynamic Island; touch and hold it to expand.
4. **End the feed.** Open Newbee, tap End feed. Show the Home screen with the new feed.
5. **Bottle.** Tap Bottle, pick an amount, Save.
6. **Pump.** Tap Pump, enter amounts for each side, Save.
7. **History.** Open History, scroll the list, tap a feed to show the edit screen, go back.
   Switch to Calendar and show Week and Month.
8. **Insights.** Open Insights and scroll through the charts.
9. **Settings.** Open Settings and scroll slowly from top to bottom. Tap Export feeding report
   (PDF) so the preview or share sheet shows, then close it. Scroll to Delete all data, tap it
   to show the confirmation, then **Cancel**.
10. Stop the recording. It saves to Photos.

Getting it to Apple: AirDrop or iCloud the video to the Mac and attach it in App Store Connect
(see "Where it goes"). If it's over the size limit, trim it in Photos or record a shorter take.
