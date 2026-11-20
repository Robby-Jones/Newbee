# App Review notes, reply and demo video (resubmission of 1.0)

History: Apple asked for information under Guideline 2.1 (2026-11-10), then rejected 1.0 under
Guideline 4.3(a) Spam (2026-11-13). Since then the app gained partner sharing and On-Call Shift,
and iCloud sync became optional. This file holds the three texts for the resubmission. The
steps are in [SUBMISSION_CHECKLIST.md](SUBMISSION_CHECKLIST.md).

All of it describes TestFlight **build 60 or later**.

## 1. Notes field (App Review Information → Notes)

Replace everything in the field with this. It is about 3,500 of the 4,000 characters allowed.

```
Thank you for reviewing Newbee again. Since the last review I added two features (partner sharing and On-Call Shift) and rewrote the product page. A demo video recorded on two physical iPhones is attached.

PURPOSE AND AUDIENCE
Newbee is a feeding log for parents of newborns. It times breastfeeds per side, logs bottles and pumping, and shows the time since the last feed. It is for adults and is not directed at children.

NO SIGN-IN
There is no account, login, purchase, subscription or ad. Everything works right after the three skippable onboarding screens.

MAIN FEATURES (ONE DEVICE)
- Timer: Home > Breastfeed > L or R. Tap the other side to switch, tap the running side to pause, End feed to finish.
- Live Activity: during a feed, lock the phone. The timer and its buttons are on the Lock Screen and in the Dynamic Island. Between feeds it shows the time since the last feed.
- Bottle and Pumping: the other two buttons on Home.
- History (list and calendar), Insights (charts), Settings > Your data (PDF report, CSV export, Delete all data).
- Settings > Your data > Import from Huckleberry reads a CSV file exported from that app, on the device, for parents who are switching. It is optional. Newbee is not affiliated with Huckleberry.

ICLOUD SYNC AND PARTNER SHARING (OPTIONAL, NEEDS ICLOUD)
- Sync is off on a new install. Settings > iCloud > Sync with iCloud turns it on. The device must be signed in to iCloud.
- Settings > Sharing > invite uses Apple's standard iCloud sharing sheet. The partner opens the link on an iPhone signed in to a different Apple Account with Newbee installed, and both parents then see and log the same feeds.
- Sharing is private between the two invited parents. There is no public or user-generated content, so there is nothing to report or block. Either parent can stop sharing in Settings > Sharing.

NIGHT SHIFT (NEEDS TWO DEVICES, TWO APPLE ACCOUNTS)
On-Call Shift appears only after a partner has joined the shared log, and its card on Home is offered between the shift start time (6:00 PM by default) and the end time (7:00 AM by default), both set in Settings > On-Call Shift.
1. Share the log between two iPhones as described above.
2. After 6:00 PM, on phone A, tap "Start on-call" on Home.
3. Phone A shows "You're on call". Phone B shows "Your partner is on call" with Take over. Feeding reminders (Settings > Notifications) now ring only on phone A.
4. When the shift ends (End, Take over, or the morning time), phone B shows "While you slept" with the night's feeds.
Because this needs two accounts and an evening clock, the attached video shows the whole flow.

PERMISSIONS
Notifications are requested only when the parent turns on a feeding reminder. Alarms (AlarmKit, iOS 26) are requested only if the parent turns on Settings > On-Call Shift > Ring as alarm. The baby photo uses the system photo picker, so there is no photo library permission.

EXTERNAL SERVICES
Only Apple's iCloud (CloudKit and iCloud key-value storage), and only when the user turns on sync or sharing. There is no server of ours, no analytics, no advertising, no third-party SDK, no payment processing and no AI service. The developer cannot see any user data. The privacy label is "Data Not Collected".

REGIONS
The app works the same in every region. English only.

REGULATED CONTENT
Not a medical device. It gives no diagnosis or feeding advice and says so in onboarding and Settings. No third-party content or licensed material.

Support: https://robby-jones.github.io/Newbee/support.html
Privacy: https://robby-jones.github.io/Newbee/privacy.html
```

## 2. Reply to the 4.3(a) message (App Review → the rejection → Reply)

Fill in the bracketed sentence in your own words and check the personal details. If you prefer
the shorter reply you already have, use that one. Send only one.

```
Hi there,

Thank you for taking the time to look at Newbee. I understand why a baby feeding tracker raises a flag. There are a lot of them. I took the feedback seriously, went back to work, and I'd like to ask you to take another look.

I'm a new dad. [ONE OR TWO SENTENCES IN YOUR OWN WORDS: what the nights were like, and why you built this.] Newbee is the only app on my account. Everything in it was made for this app. There is no template, no purchased code and no third-party SDK.

Here is what I believe no other feeding tracker does:

On-Call Shift. My wife and I share one feeding log, and in the evening one of us taps "Start on-call". From then until morning, feeding reminders ring only on that parent's iPhone, and the other phone stays quiet so that parent can actually sleep. In the morning, the parent who slept gets a "While you slept" summary of the night. I looked for an app that does this before building it and couldn't find one.

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

Apple asked for a recording on a physical device that starts with launching the app. On-Call Shift
can't be shown on one phone, so film both phones side by side with a third device, or record
each screen and put the recordings next to each other. Film in the evening (after 6:00 PM), or
the On-Call Shift card won't be offered.

Before recording: both phones on the latest iOS and the latest TestFlight build, Do Not Disturb
on, Newbee closed in the app switcher, sharing already accepted on the second phone.

1. **Launch** Newbee on phone A from the Home Screen.
2. **Timer.** Breastfeed, choose L, switch to R, tap R to pause and again to resume.
3. **Lock Screen and Dynamic Island.** Lock phone A and show the timer. Unlock, go to the Home
   Screen, touch and hold the Dynamic Island.
4. **End the feed.** Show that the feed appears on phone B too.
5. **Bottle** on phone B. Show it appear on phone A.
6. **On-Call Shift.** On phone A tap "Start on-call". Show "You're on call" on A and "Your
   partner is on call" on B.
7. **Take over** on phone B, or End on phone A. Show "While you slept" on the other phone.
8. **Settings** on phone A: scroll through iCloud, Sharing, On-Call Shift, Reminders and Your data.
   Open Export feeding report (PDF), close it. Tap Delete all data to show the confirmation, then
   **Cancel**.

Don't delete the app to show onboarding. That erases the feeds on the phone if sync is off.
