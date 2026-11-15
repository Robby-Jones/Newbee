# iCloud sync and sharing

Newbee syncs feeds, the baby profile (photo included) and settings between the iPhones and iPads
signed in to the same Apple ID, and lets one parent share the feeding log with the other, who uses
their own Apple ID. Everything stays in the parents' own iCloud. There is no Newbee server, and
nothing is collected (ADR-011 in `ARCHITECTURE.md`).

## How it works

| What | Where it syncs | Code |
|---|---|---|
| Feeds, segments, bottles, pumping, baby profile and photo | The "Family" zone of `iCloud.com.robbyjones.newbee`: in the parent's private database, or in the other parent's once the log is shared | `CloudSyncEngine`, `SyncCore` |
| Units, presets, reminders, quiet hours, "Still feeding?", appearance | iCloud key-value storage, per Apple ID (each parent keeps their own) | `AppPreferences` (`Key.synced`) |
| Onboarding done | Not synced: each device runs its own first-run setup | |
| Running Live Activity, scheduled notifications | Not synced: rebuilt on each device from the synced feeds | `CloudSyncWiring` |

**SwiftData keeps every feed on the phone and never talks to CloudKit.** Sync is a layer beside
it, in three parts:

- **`SyncCore`** (NewbeeKit, no CloudKit in it) decides what to send and what to do with what
  arrives. It keeps a **ledger**: for each feed, a fingerprint of what the phone holds, a
  fingerprint of what iCloud holds, and when the content last changed. Comparing the store with
  the ledger finds every insert, edit and delete, whichever screen, Lock Screen button or import
  made it. Nothing has to remember to tell sync, and what is waiting to be sent is always worked
  out again from the store, so a crash or a failed send can't lose a change.
- **`SwiftDataSyncStore`** turns feeds and the baby profile into payloads and back. A feed
  travels as one record with its segments and its bottle or pump details, so it always arrives
  whole.
- **`CloudSyncEngine`** moves records with Apple's `CKSyncEngine`, which handles pushes, batching
  and retries after network errors.

- **When it syncs.** A save is sent within a second while the app is open, and before iOS
  suspends the app when it goes to the background (also after a Lock Screen button). Another
  phone's change arrives by silent push (the `remote-notification` background mode and
  `aps-environment` entitlement); opening the app also checks.
- **After changes arrive**, `AppDependencies.cloudSyncDidImport()` merges duplicate baby profiles,
  reloads the photo, and reloads the session manager so the timer, Live Activity and reminders
  follow a feed started or ended on another phone. `@Query` views update by themselves.
- **Two phones changed the same feed.** The later change wins on both. An edit that hasn't been
  sent yet is never thrown away by a delete made elsewhere before it: the feed comes back with
  the edit. Changes to different feeds never conflict.
- **One baby.** Two phones that each made a profile end up with two `Baby` rows once they sync or
  share. `BabyMerge` keeps the oldest (by `createdAt`, then `id`, so every phone picks the same
  one), fills in its missing name, birth date or photo from the others, and deletes them. Feeds
  don't record which profile they belong to in iCloud: every phone attaches them to the one
  profile.
- **Signed out of iCloud.** Everything keeps working on the device. Signing in later uploads the
  existing data. The same happens after switching Apple IDs, or if the zone is deleted from
  iCloud settings: the phone still has every feed and uploads them again.
- **Delete all data** depends on who shares the log. For the parent who shared it (and for a log nobody else is on), it deletes everywhere: the deletes sync like any other change, so the partner's phone loses the feeds too. For the invited parent, it first leaves the shared log (`CloudSharing.leaveBeforeDeletingEverything`, which deletes their copy of the share) and then clears only that phone. The partner keeps every feed. If iCloud can't be reached the sheet says so and nothing is deleted. One edge: an invited parent with a second device on the same Apple ID keeps a copy on that device when they leave, and it syncs back.
- **Tests, previews and unsigned builds never touch iCloud.** CloudKit stops an app that uses it
  without the entitlement, so `AppConfiguration.cloudKitContainerID` is `nil` under unit and UI
  tests, and the CI test builds set `NEWBEE_CLOUDKIT_CONTAINER` empty.
- **If a record can't be sent** (the schema isn't deployed yet, iCloud storage is full),
  Settings → iCloud says why, the feed stays on the phone, and Newbee tries again: after 30
  seconds, then less often, and every time the app is opened.

Settings → iCloud shows the state: Up to date (with the last sync time), Syncing, Off (signed out
or restricted), Paused, or Not synced with the reason.

## Sharing with the other parent

One parent taps **Settings → Sharing → Share with your partner**. Newbee shares their whole
"Family" zone (a zone-wide `CKShare`) and opens Apple's sharing sheet to send the invitation,
usually by Messages. Only the people invited can open it, and they can read and write.

The other parent taps the link. iOS opens Newbee (`SceneDelegate`), which accepts the share. From
then on that phone syncs with the first parent's zone through the shared database, instead of
its own:

- **Both see one log.** Either can add, change and delete feeds, and the baby profile.
- **The joining parent's own feeds are merged in.** Everything already on their phone is uploaded
  to the shared log. Where both parents have the same feed, the one changed last wins. Their two
  baby profiles are merged into one (`BabyMerge`).
- **Their own zone is deleted** once everything in it is in the shared log, so it can't bring
  back deleted feeds later.
- **Settings stay separate**: units, presets and reminders are each parent's own.
- **Live Activities are per phone.** A feed started on one phone shows as a running timer in the
  other's app. iOS only lets an app start a Live Activity while it is in use (ADR-009), so the
  other phone's Lock Screen shows it once Newbee is opened there. A Live Activity that is already
  showing does update and end from the background.
- **If sharing stops**, because the first parent stops it or the second leaves (both from the
  same Sharing row), the second parent keeps a copy of every feed so far. Their phone goes back
  to syncing with their own iCloud, and the two logs are separate from then on.

Settings → Sharing shows **Invited** until the partner joins, then **Sharing** on both phones.

## The CloudKit schema

TestFlight and App Store builds always use the CloudKit **production** environment, and
production only accepts record types and fields that were deployed to it from development. Apps
normally create the development schema by running a debug build from Xcode. Newbee is built by CI
instead, so the schema is a file:

- `cloudkit/schema.ckdb` declares the record types sync writes: `Baby`, `Feed` and `NightShift`.
  Each has the same few fields: the item as JSON in `payload`, `changedAt`, and the payload
  format `v` (`CloudRecordCoding`). **New properties go inside the JSON, so they don't need a
  schema change.** Only a new kind of record does.
- It also declares **`cloudkit.share`**, CloudKit's own record type for shares. CloudKit creates
  it by itself only in development, the first time a share is saved there. Production refuses to
  save a share ("Cannot create new type cloudkit.share in production schema") until the type has
  been deployed, and Newbee never runs against development, so the file carries it.
- `CloudKitSchemaTests` fails if the file is missing a record type or field the code writes.
- The **CloudKit schema** workflow validates the file, uploads it to development with `cktool`,
  then compares it with production and lists what still needs deploying. With **Upload** off it
  only validates and compares, which is safe to run from a branch.
- Deploying to production is a button in CloudKit Console.

**Production types and fields can never be removed.** The `CD_` types are from the first version
of sync, which went through SwiftData's own CloudKit mirroring (builds 47 to the last one before
sharing). Nothing writes them any more, but they stay in the file.

### Updating from a build that synced through SwiftData

Nothing is converted on the phone: the store is the same file, opened without CloudKit. The first
launch of a build with the new sync uploads everything on the phone to the "Family" zone. A
second device that already has the same feeds uploads nothing twice: identical feeds are simply
matched. The old `com.apple.coredata.cloudkit.zone` is left alone (deleting it would make a
device that is still on an old build erase its store), and a device on an old build no longer
syncs with updated ones until it updates too.

One limit: feeds that exist **only** in the old zone, because the app was deleted and reinstalled
before ever running a build with the new sync, are not brought back. A phone that still has its
feeds is not affected.

## One-time setup (Robby)

All of this is on the web; no Xcode needed.

### Before merging the iCloud sync PR

TestFlight builds can't be signed until the App ID has the new capabilities.

1. **Create the iCloud container.** Go to
   [Certificates, Identifiers & Profiles → Identifiers](https://developer.apple.com/account/resources/identifiers/list/cloudContainer)
   (the filter at the top right should say **iCloud Containers**). Click **+**, choose
   **iCloud Containers**, **Continue**. Description `Newbee`, identifier
   `iCloud.com.robbyjones.newbee`. **Continue**, then **Register**.
2. **Turn on iCloud for the app.** Switch the filter to **App IDs** and open
   `com.robbyjones.newbee`. Under **Capabilities**:
   - Check **iCloud**, choose **Include CloudKit support**, click **Edit** (or **Configure**) next
     to it, select `iCloud.com.robbyjones.newbee`, **Continue**, **Save**.
   - Check **Push Notifications** (no certificate is needed; leave its **Configure** alone).
   - Click **Save** at the top right and confirm. Existing provisioning profiles become invalid;
     CI makes new ones on the next build.

### After merging

3. **Create a CloudKit management token.** Open [CloudKit Console](https://icloud.developer.apple.com/dashboard/)
   and sign in. Open the account menu at the top right and choose **Manage Tokens** (in some
   versions: **Settings → Tokens & Keys**). Create a **Management Token** named `Newbee CI` and
   copy it. It's shown only once.
4. **Add it to GitHub.** [Newbee → Settings → Secrets and variables → Actions](https://github.com/Robby-Jones/Newbee/settings/secrets/actions)
   → **New repository secret**: name `CLOUDKIT_MANAGEMENT_TOKEN`, value the token.
5. **Upload the schema.** [Actions → CloudKit schema](https://github.com/Robby-Jones/Newbee/actions/workflows/cloudkit-schema.yml)
   → **Run workflow** on `main`. The run's summary lists what production is missing.
6. **Deploy to production.** In [CloudKit Console](https://icloud.developer.apple.com/dashboard/),
   open **CloudKit Database**, pick `iCloud.com.robbyjones.newbee` at the top, then
   **Deploy Schema Changes…** → **Deploy**. Run the workflow again with **Upload** off: it should
   say "Production has the whole schema."
7. **Try it.** Install the newest TestFlight build, open Settings → iCloud and check it says
   **Up to date**. With a second device on the same Apple ID (an iPad works), log a bottle on one
   and watch it appear on the other.

A TestFlight build installed before step 6 shows **Not synced** in Settings. Nothing is lost:
feeds stay on the phone and upload once the schema is deployed.

The management token is only needed when the schema changes. Apple may expire it; if the workflow
says the token is invalid, repeat steps 3 and 4.

## Setting up sharing (Robby, once)

The sharing update adds record types, so the schema has to be deployed again before a TestFlight
build with sharing can sync. A build installed earlier shows **Not synced** and keeps every feed
on the phone until then.

1. **Upload the schema.** [Actions → CloudKit schema](https://github.com/Robby-Jones/Newbee/actions/workflows/cloudkit-schema.yml)
   → **Run workflow** on `main`. The summary should list `Baby`, `Feed`, `NightShift` and
   `cloudkit.share` as missing from production.
2. **Deploy to production.** In [CloudKit Console](https://icloud.developer.apple.com/dashboard/),
   open **CloudKit Database**, pick `iCloud.com.robbyjones.newbee`, then
   **Deploy Schema Changes…** → **Deploy**. Run the workflow again with **Upload** off: it should
   say "Production has the whole schema."
3. **Update both phones** to the newest TestFlight build and open Newbee on each. Settings →
   iCloud should say **Up to date** after the first upload (a long history takes a minute).
4. **Share.** On one phone: Settings → Sharing → **Share with your partner**, and send the
   invitation by Messages. On the other phone, tap the link and choose to open it in Newbee.
   Both phones then show Sharing → **Sharing**, and a bottle logged on one appears on the other.

If step 4 fails with "Cannot create new type cloudkit.share in production schema", the share type
didn't reach production: check that step 2's second run reports nothing missing.
