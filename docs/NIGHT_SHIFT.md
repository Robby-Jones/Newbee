# Night Shift

Two parents, one baby, one night. Night Shift lets one parent say "I'm on duty tonight" so only
their iPhone reminds them about the next feed, and the other parent can sleep. In the morning the
parent who slept sees what happened: "While you slept".

It needs a shared log (Settings → Sharing, `docs/ICLOUD_SYNC.md`). Without a partner on the log,
Night Shift doesn't appear anywhere.

## Decisions (Robby, 2026-11-15)

| Question | Decision |
|---|---|
| How a shift starts | One tap on Home, "I'm on duty tonight", offered from 6:00 PM until the morning time |
| How it ends | By itself at the morning time (Settings → Night Shift → Shift ends at, 7:00 AM by default), when the parent on duty taps End, or when the other parent taps Take over |
| Reminders on duty | The normal feeding reminder (Settings → Reminders), on the on-duty iPhone only. Quiet hours don't hold it back during the shift |
| Ring as alarm | Optional switch, iOS 26 and later (AlarmKit): the reminder rings like an alarm, also in Silent mode. On older iOS it stays a notification and the switch isn't shown |
| The other phone | No feeding reminder while the shift runs |
| "Still feeding?" | Only on the phone that started the timer, shift or not |
| "While you slept" | A notification on the sleeping parent's phone when the shift ends, and a card on Home until dismissed (or 12 hours) |
| Who is who | Just two parents: "You" and "Your partner", no names |

A reminder that falls after the shift ends follows the usual rules on both phones (quiet hours
included). Turning the feeding reminder off in Settings turns it off on duty too; the card then
says so.

## Home

One card under the three big buttons, and only when there is something to say:

| When | Card | Control |
|---|---|---|
| Evening or night, nobody on duty | 🌙 **I'm on duty tonight** · "Feed reminders ring only on your iPhone until 7:00 AM." | The whole card is the button |
| This parent is on duty | 🌙 **You're on duty** · "Until 7:00 AM. Feed reminders ring only on this iPhone." | End |
| The partner is on duty | 💤 **Your partner is on duty** · "Until 7:00 AM. This iPhone stays quiet." | Take over |
| Morning, the partner was on duty | ☀️ **While you slept** · "3 feeds, the last at 5:10 AM" · "32 min nursing · 4 oz by bottle" | ✕ (dismiss) |

The card sits below the buttons so they never move under a thumb at 3 a.m.

## Settings → Night Shift

Shown once a partner is on the log, under Sharing: **Shift ends at** (time) and **Ring as alarm**
(iOS 26 and later). The footer explains the feature in one sentence.

## How it works

- **The shift is one record.** `NightShift` (NewbeeKit) holds who is on duty, when the shift
  started and ends, and when it was ended early. It travels as the one `NightShift` record of the
  shared zone (record name `current`) through the same sync layer as feeds, so the later change
  wins if both parents tap at once. On the phone it lives in `UserDefaults`
  (`NightShiftStore`), not SwiftData, so no schema migration was needed.
- **Who is who.** Each parent is identified by their iCloud user record name
  (`CKContainer.userRecordID()`), which is the same on all of that parent's devices and means
  nothing outside the container.
- **The rules are pure.** `NightShift.duty(for:at:)`, `NightShiftCard.current(...)`,
  `NightSummary` and `ReminderPlanner.plan(..., duty:)` are in NewbeeKit and tested on Linux.
- **Reminders.** `ReminderScheduler` asks `NightShiftModel` for tonight's context on every pass.
  On duty with Ring as alarm, the reminder goes to `SystemNightAlarmClient` (AlarmKit) instead of
  UserNotifications; if the alarm can't be set it stays a notification. Off duty, the scheduler
  adds the "While you slept" notification at the shift's end, written from the feeds the phone
  knows of at that moment. The Home card is always complete. If the partner ends the shift
  early, the scheduled notification goes with it, so the phone announces the summary right away,
  once, when the change arrives (within half an hour).
- **Delete all data** clears the shift too.

## Limits

- A notification can't be changed after it is scheduled without the app running, so the
  "While you slept" notification counts the feeds synced before the phone last ran Newbee. The
  card on Home counts everything.
- Live Activities stay per phone (see `ICLOUD_SYNC.md`).
- AlarmKit alarms need permission ("Allow alarms"). If it's refused, Settings says so and the
  reminder stays a notification.
