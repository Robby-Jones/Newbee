# Resubmission checklist: Newbee 1.0 (after the 4.3(a) rejection)

Written 2026-11-16. It replaces the first-submission checklist. Work top to bottom and submit
once, with everything in place. Apple's last message warned that repeated rejected submissions
get longer reviews, so nothing should be left for "next time".

Claude never submits. Every step in App Store Connect is yours.

The texts to paste are in [LISTING.md](LISTING.md) (product page) and
[APP_REVIEW_NOTES.md](APP_REVIEW_NOTES.md) (notes, reply to Apple, video shot list).

## A. Before you open App Store Connect

- [ ] **Merge the pull request that carries this checklist.** It updates the privacy policy and
      support page for sharing and Night Shift. Then check that both pages are live and mention
      sharing: <https://robby-jones.github.io/Newbee/privacy.html> and
      <https://robby-jones.github.io/Newbee/support.html>. The privacy page should say
      "Effective November 16, 2026".
- [ ] **Wait for the new TestFlight build.** Every merge to main uploads one. The build to submit
      is the one with the **highest number** (60 or later) once it shows as ready in TestFlight.
- [ ] **Confirm the CloudKit schema is in Production.** Sharing and Night Shift fail for everyone
      outside your family if it isn't. Actions → CloudKit schema → Run workflow on main; it
      should report nothing left to deploy. If it lists changes, deploy them in CloudKit Console →
      Deploy Schema Changes.
- [ ] **Test the exact build on two iPhones with two Apple Accounts** (yours and your wife's):
  - [ ] Fresh state on one phone: Settings → iCloud shows Sync with iCloud **off**.
  - [ ] Turn sync on, Settings → Sharing → invite, accept on the other phone.
  - [ ] A feed logged on one phone appears on the other.
  - [ ] After 6:00 PM: "Start your night shift" on one phone shows "Your partner is on duty" on the
        other, and Take over works.
  - [ ] A feeding reminder rings only on the on-duty phone.
  - [ ] Live Activity on the Lock Screen and Dynamic Island still works.
- [ ] **The support inbox works.** Send a test email to newbee.app.help@gmail.com and confirm you
      receive it. Apple checks that the support contact is real.
- [ ] **Record the demo video** on two iPhones in the evening (shot list in
      APP_REVIEW_NOTES.md, section 3).

## B. Select the latest build

1. Go to <https://appstoreconnect.apple.com> → **Apps** → **Newbee**.
2. In the left sidebar, under **iOS App**, click **1.0** (it shows "Rejected").
3. Scroll down to the **Build** section. It shows the build that was rejected.
4. Move the pointer over that build row and click the red **–** (remove) button on the right.
5. Click **Add Build** (or the blue **+** next to "Build").
6. In the list, select the build with the **highest number** and click **Done**. If the newest
   build isn't listed, it is still processing. Check the **TestFlight** tab; it usually takes 5
   to 15 minutes after the workflow finishes.
7. If asked about encryption, nothing is needed: the app already declares it uses none.
8. Click **Save** at the top right.
9. Check the Build section now shows the new number, and that the icon next to it is the
   bumblebee, not the old drop.

If the Build section has no remove button, the version is still attached to the old submission.
Open **App Review** in the sidebar, open the rejected submission, and the version becomes
editable from there. Do not create a version 1.0.1; the rejected 1.0 is the one to fix.

## C. Product page (version 1.0 page and App Information)

- [ ] **App Information → Name:** `Newbee: Nursing Timer & Log`
- [ ] **App Information → Subtitle:** `Feeds from your Lock Screen`
- [ ] **Promotional Text**, **Description**, **Keywords:** paste from LISTING.md.
- [ ] **Screenshots:** in the "iPhone with Dynamic Island (medium display)" tab, delete all the
      old ones and upload the seven from `newbee-screenshots-captioned.zip`, in number order.
      Skip the iPhone Duo, iPad and Apple Watch tabs.
- [ ] **App icon:** nothing to upload. It comes from the build. Confirm the page shows the bee.
- [ ] **Support URL** and **Privacy Policy URL:** unchanged. Open both once from the page.
- [ ] Category (Health & Fitness, Lifestyle), age rating (4+), price (Free) and availability
      stay as they are.

## D. App Privacy

- [ ] **App Privacy → Data Collection** stays **"No, we do not collect data from this app."**
      iCloud sync and sharing keep data in the parents' own iCloud, which the developer can't
      read, so nothing is collected. See [PRIVACY_LABELS.md](PRIVACY_LABELS.md).
- [ ] Nothing to change, but open the page and confirm it says **Data Not Collected**.

## E. App Review Information (bottom of the 1.0 page)

- [ ] **Sign-in required:** unchecked.
- [ ] **Contact:** your name, phone and email are still correct.
- [ ] **Notes:** replace the whole field with the text in APP_REVIEW_NOTES.md, section 1.
- [ ] **Attachment:** add the demo video. If it's too large, trim it, or attach it to the reply
      in step F instead.
- [ ] **Version Release:** Manually release this version.
- [ ] **Save.**

## F. Reply and resubmit

- [ ] **App Review** (sidebar) → open the rejected submission → **Reply** to the 4.3(a) message
      with the text in APP_REVIEW_NOTES.md, section 2, with your own sentences filled in.
- [ ] Read the whole 1.0 page once more from top to bottom.
- [ ] Click **Resubmit to App Review** (or **Add for Review** → **Submit**).

## Risks to acceptance, most serious first

1. **The reviewer can't see Night Shift on one phone.** It needs a partner on a second Apple
   Account and only appears after 6:00 PM. It is now the main argument against "spam", so if
   the reviewer can't find it, the argument fails. The two-phone video and the step-by-step notes
   are the mitigation. A stronger fix is a way to try Night Shift alone at any hour, which is a
   small app change and a new build. Ask if you want it before submitting.
2. **4.3(a) is a judgment call.** A better page and a real differentiator improve the odds a lot,
   but nobody can promise acceptance. If it comes back again, do not resubmit. File an appeal
   with the App Review Board (the rejection message has the link) and ask for a phone call.
3. **CloudKit schema not in Production.** Sharing would fail for the reviewer. Step A covers it.
4. **Page and build out of step.** The description promises sharing, Night Shift and optional
   iCloud sync. Submitting any build below 60 with this text is a rejection under 2.3.
5. **Screenshots that don't match the app.** Use only the new set. The old ones show the old icon
   and screens that have since changed.
6. **Privacy policy out of date.** The live page must describe sharing before you submit. Step A
   covers it.
7. **Another app's name inside Newbee.** The import screen says "Huckleberry". Naming an app to
   import its file is normally accepted, and the notes say Newbee isn't affiliated. Keep that
   name out of the name, subtitle, keywords and description, where Apple does reject it.
8. **Longer review.** The account is flagged for extended review, so allow several days.
