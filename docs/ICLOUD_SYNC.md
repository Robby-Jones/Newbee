# iCloud sync

Newbee syncs feeds, the baby profile (photo included) and settings between the iPhones and iPads
signed in to the same Apple ID. Everything stays in the parent's own private iCloud. There is no
Newbee server, and nothing is collected (ADR-011 in `ARCHITECTURE.md`).

Sharing with a partner who uses a different Apple ID is the next step. SwiftData can't share
between Apple IDs, so that needs Core Data's `NSPersistentCloudKitContainer` sharing (`CKShare`).
The records it uses have the same `CD_` layout as today's, so synced data carries over.

## How it works

| What | Where it syncs | Code |
|---|---|---|
| Feeds, segments, bottles, pumping, baby profile and photo | CloudKit private database of `iCloud.com.robbyjones.newbee`, through SwiftData's CloudKit mirroring | `PersistenceController.open(.appGroup)` |
| Units, presets, reminders, quiet hours, "Still feeding?", appearance | iCloud key-value storage | `AppPreferences` (`Key.synced`) |
| Onboarding done | Not synced: each device runs its own first-run setup | |
| Running Live Activity, scheduled notifications | Not synced: rebuilt on each device from the synced feeds | `CloudSyncWiring` |

- **When it syncs.** Core Data's mirroring uploads each save and receives a silent push when
  another device changes something (the `remote-notification` background mode and
  `aps-environment` entitlement). Newbee shows the change within seconds when it's open, and on
  the next launch otherwise.
- **After changes arrive** (`CloudSyncMonitor` sees a finished import), `AppDependencies.cloudSyncDidImport()`
  merges duplicate baby profiles, reloads the photo, and reloads the session manager so the timer,
  Live Activity and reminders follow a feed started or ended on another device. `@Query` views
  update by themselves.
- **One baby.** Two devices that each made a profile before they first synced end up with two
  `Baby` rows. `BabyMerge` keeps the oldest (by `createdAt`, then `id`, so every device picks the
  same one), fills in its missing name, birth date or photo from the others, moves their feeds
  over and deletes them. `Baby.sessions` nullifies on delete (schema V3), so a feed that hasn't
  been moved yet is never deleted with its old baby; the next merge attaches it.
- **Settings.** At launch iCloud wins for each setting it has, and settings only this device has
  are sent up. After that, each change is sent as it's made, and changes from other devices are
  applied as they arrive.
- **Signed out of iCloud.** Everything keeps working on the device. Signing in later uploads the
  existing data.
- **Delete all data** deletes everywhere: the deletes sync like any other change.
- **Tests, previews and unsigned builds never touch iCloud.** CloudKit stops an app that uses it
  without the entitlement, so `AppConfiguration.cloudKitContainerID` is `nil` under unit and UI
  tests, and the CI test builds set `NEWBEE_CLOUDKIT_CONTAINER` empty.
- **If iCloud can't start** (an entitlement or account problem), the store opens without sync
  and Settings → iCloud says why. The next launch tries again.

Settings → iCloud shows the state: Up to date (with the last sync time), Syncing, Off (signed out
or restricted), Paused, or Not synced with the error.

## The CloudKit schema

TestFlight and App Store builds always use the CloudKit **production** environment, and
production only accepts record types and fields that were deployed to it from development. Apps
normally create the development schema by running a debug build from Xcode. Newbee is built by CI
instead, so the schema is a file:

- `cloudkit/schema.ckdb` describes the record types Core Data's mirroring writes for
  `NewbeeSchemaV3` (`CD_Baby`, `CD_FeedingSession`, and so on).
- `CloudKitSchemaTests` builds the same Core Data model SwiftData uses and fails if the file is
  missing a field or has one the models don't write.
- The **CloudKit schema** workflow uploads the file to development with `cktool`, then compares
  it with production and lists what still needs deploying.
- Deploying to production is a button in CloudKit Console.

**Production fields can never be removed or change type.** Every later schema version only adds.
Each model change needs a new schema version, an updated `schema.ckdb`, a run of the workflow and
a deploy, before the TestFlight build that uses it.

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
