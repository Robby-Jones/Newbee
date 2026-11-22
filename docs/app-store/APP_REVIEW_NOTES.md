# App Review notes, reply and demo video (resubmission of 1.0)

History: Apple asked for information under Guideline 2.1 (2026-11-10), then rejected 1.0 under
Guideline 4.3(a) Spam (2026-11-13). Build 61 was resubmitted on 2026-11-16 and sat in Waiting for
Review for 6 days. On 2026-11-22 it is replaced with the newest TestFlight build. This file holds
the three texts for that resubmission. The steps are in
[SUBMISSION_CHECKLIST.md](SUBMISSION_CHECKLIST.md).

All of it describes the **newest TestFlight build from main on or after 2026-11-22** (after PR #92).

What changed since build 61 that the reviewer can see: Night Shift is now called On-Call Shift and
starts at any hour from a "Start on-call" card with an end-time picker; Settings > Reminders is
now Settings > Notifications; iCloud, Notifications, Appearance, Your data and About open their
own pages; color themes with matching app icons; a Live Activity color and Dynamic Island icon
setting; Day, Week and Month calendars in History; a Pumping card in Insights; a starting-side
setting; and many fixes.

## 1. Notes field (App Review Information → Notes)

Replace everything in the field with this. It is about 3,900 of the 4,000 characters allowed.

```
Thank you for reviewing Newbee. This replaces build 61, which was waiting for review, with a newer build with fixes and the features below. A demo video recorded on two physical iPhones is attached.

PURPOSE AND AUDIENCE
Newbee is a feeding log for parents of newborns. It times breastfeeds per side, logs bottles and pumping, and shows the time since the last feed. It is for adults, not children.

WHAT SETS IT APART (GUIDELINE 4.3)
- On-Call Shift: two parents share one log. One taps "Start on-call", and until the end time they pick, feeding reminders ring only on that iPhone, so the other parent can sleep and later sees a "While you slept" summary.
- The breastfeeding timer runs from the Lock Screen and Dynamic Island, and between feeds the Live Activity counts the time since the last feed.
- The timer stays exact if the app closes, the phone restarts or the clock changes.
- All code and art were made for this app. No template and no third-party SDK.

NO SIGN-IN
No account, login, purchase, subscription or ad. Everything works after three skippable onboarding screens.

MAIN FEATURES (ONE DEVICE)
- Timer: Home > Breastfeed > L or R. Tap the other side to switch, tap the running side to pause, End feed to finish.
- Live Activity: during a feed, lock the phone to see the timer and its buttons on the Lock Screen and in the Dynamic Island.
- Bottle and Pumping: the other two buttons on Home.
- History (list, plus Day, Week and Month calendars) and Insights (charts).
- Settings > Appearance: color themes, each with a matching app icon (iOS shows its standard icon change alert), and Live Activity colors.
- Settings > Your data: PDF report, CSV export, Import from Huckleberry, Delete all data. The import reads a CSV file exported from that app, on the device, for parents who are switching. Newbee is not affiliated with Huckleberry.

ICLOUD SYNC AND PARTNER SHARING (OPTIONAL)
- Sync is off on a new install. Settings > iCloud > Sync with iCloud turns it on. The device must be signed in to iCloud.
- Settings > Share with your partner uses Apple's standard iCloud sharing sheet (it turns sync on first). The partner opens the link on an iPhone with a different Apple Account and Newbee installed, and both see and log the same feeds.
- Sharing is private between the two parents. There is no public or user-generated content to report or block. Either parent can stop sharing in Settings.

ON-CALL SHIFT (NEEDS TWO IPHONES, TWO APPLE ACCOUNTS)
The card appears on Home, below Today, once a partner has joined the shared log. It works at any hour.
1. Share the log between two iPhones as above.
2. On phone A, tap "Start on-call" on Home, pick an end time, tap Start on-call.
3. A shows "You're on call". B shows "Your partner is on call" with Take over. Feeding reminders (Settings > Notifications) now ring only on A.
4. When the shift ends (End, Take over or the end time), B shows "While you slept".
The attached video shows the whole flow.

PERMISSIONS
Notifications are requested only when the parent turns on a feeding reminder. Alarms (AlarmKit, iOS 26) only if the parent turns on Settings > On-Call Shift > Ring as alarm. The baby photo uses the system photo picker, so no photo library access.

EXTERNAL SERVICES
Only Apple's iCloud, and only after the user turns on sync or sharing: CloudKit (private database, and CKShare for partner sharing), iCloud key-value storage for settings, and CloudKit's silent pushes. No server of ours, analytics, ads, third-party SDK, payments or AI. The developer cannot see any user data. Privacy label: Data Not Collected.

REGIONS
Works the same in every region. English only.

REGULATED CONTENT
Not a medical device. No diagnosis or feeding advice, as onboarding and Settings say. No third-party content.

Support: https://robby-jones.github.io/Newbee/support.html
Privacy: https://robby-jones.github.io/Newbee/privacy.html
```

## 2. Reply to the 4.3(a) message (App Review → the rejection → Reply)

If you already sent this reply with build 61, don't send it again: the 4.3 points are now in the
Notes above, so the reviewer sees them with the new build. Send it only if it never went out, or
if Apple raises 4.3 again. Fill in the bracketed sentence in your own words and check the
personal details.

```
Hi there,

Thank you for taking the time to look at Newbee. I understand why a baby feeding tracker raises a flag. There are a lot of them. I took the feedback seriously, went back to work, and I'd like to ask you to take another look.

I'm a new dad. [ONE OR TWO SENTENCES IN YOUR OWN WORDS: what the nights were like, and why you built this.] Newbee is the only app on my account. Everything in it was made for this app. There is no template, no purchased code and no third-party SDK.

Here is what I believe no other feeding tracker does:

On-Call Shift. My wife and I share one feeding log, and at night one of us taps "Start on-call" and picks when the shift ends. Until then, feeding reminders ring only on that parent's iPhone, and the other phone stays quiet so that parent can actually sleep. When the shift ends, the parent who slept gets a "While you slept" summary of the night. I looked for an app that does this before building it and couldn't find one.

The whole timer runs from the Lock Screen. With one free thumb and a sleeping baby, you can switch sides, pause and end a feed from the Lock Screen or Dynamic Island without opening the app. Between feeds it keeps counting the time since the baby last ate.

A timer that doesn't lose time. It stays exact if the app closes, the phone restarts, or the clock changes, and if you fall asleep with it running, it helps you fix the entry.

It asks for nothing. No account, no ads, no subscription, no purchases, no analytics. Sharing and sync go through the parents' own iCloud, and I can't see any of it.

I've also rewritten the product page. The name, subtitle, description and screenshots now show these things instead of generic category words, and the review notes include a video of On-Call Shift running on two iPhones.

I'd be glad to answer questions or get on a call. Thank you for reading, and for the work you do.

Robby Jones
```

Before sending:

- "I looked for an app that does this before building it and couldn't find one" is based on a
  search of App Store listings on 2026-11-14. Say only what you're comfortable standing behind.
- "My wife and I share one feeding log" should be true on your phones by the time you send it.

## 3. Demo video shot list (two iPhones, 2 to 3 minutes)

Record it again on the new build. A video made on build 61 shows the old Night Shift card ("I'm on
duty tonight") and Settings > Reminders, which no longer match what the reviewer will see.

Apple asked for a recording on a physical device that starts with launching the app. On-Call Shift
can't be shown on one phone, so film both phones side by side with a third device, or record
each screen and put the recordings next to each other. Any time of day works.

Before recording: both phones on the latest iOS and the newest TestFlight build, Do Not Disturb
on, Newbee closed in the app switcher, sharing already accepted on the second phone.

1. **Launch** Newbee on phone A from the Home Screen.
2. **Timer.** Breastfeed, choose L, switch to R, tap R to pause and again to resume.
3. **Lock Screen and Dynamic Island.** Lock phone A and show the timer. Unlock, go to the Home
   Screen, touch and hold the Dynamic Island.
4. **End the feed.** Show that the feed appears on phone B too.
5. **Bottle** on phone B. Show it appear on phone A.
6. **On-Call Shift.** On phone A tap "Start on-call", pick an end time, tap Start on-call. Show
   "You're on call" on A and "Your partner is on call" on B.
7. **End** on phone A (or Take over on phone B). Show "While you slept" on phone B.
8. **Settings** on phone A: show Share with your partner and On-Call Shift on the main page, then
   open iCloud, Notifications and Your data. In Your data, open Export feeding report (PDF) and
   close it. Tap Delete all data to show the confirmation, then **Cancel**.

Don't delete the app to show onboarding. That erases the feeds on the phone if sync is off.
