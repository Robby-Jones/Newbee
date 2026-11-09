# v1.0 submission checklist (App Store Connect)

The repo side is done in the App Store prep PR. These steps happen in a browser and only Robby
can do them. Copy-paste text lives in [LISTING.md](LISTING.md) and
[PRIVACY_LABELS.md](PRIVACY_LABELS.md).

## 1. Before you start (one time)

- [ ] Create the support inbox `newbee.app.help@gmail.com` (or tell Claude a different address
      so the website is updated).
- [ ] GitHub → Newbee repo → Settings → Pages → Build and deployment → Source: **GitHub Actions**.
      Then Actions → Website → Run workflow. Check that
      https://robby-jones.github.io/Newbee/privacy.html and `/support.html` open.
- [ ] Actions → Screenshots → Run workflow. When it finishes, download the
      `app-store-screenshots` artifact (6 PNGs) from the run page.
- [ ] Wait for the TestFlight build of version **1.0.0** (built automatically when the PR merges)
      and give it a quick check on your iPhone.

## 2. App Store Connect → Newbee → App Information

- [ ] Name and subtitle (LISTING.md). If the name is taken, use a fallback from LISTING.md.
- [ ] Category: Health & Fitness, secondary Lifestyle.
- [ ] Content Rights: "No, it does not contain, show, or access third-party content."
- [ ] Age Rating → Edit: answer "None" / "No" to everything → **4+**.
- [ ] Privacy Policy URL: https://robby-jones.github.io/Newbee/privacy.html

## 3. Pricing and Availability

- [ ] Price: **Free** (USD 0.00).
- [ ] Availability: all countries and regions.

## 4. App Privacy

- [ ] Get Started → "No, we do not collect data from this app" → Save → **Publish**.
      Result: "Data Not Collected".

## 5. The 1.0 version page (iOS App → 1.0 Prepare for Submission)

- [ ] Previews and Screenshots → **iPhone with Dynamic Island (medium display)**: upload the
      6 screenshots (1206 x 2622) in order, 01 to 06. Skip iPhone Duo, iPad and Apple Watch.
- [ ] Promotional text, description, keywords (LISTING.md).
- [ ] Support URL: https://robby-jones.github.io/Newbee/support.html
- [ ] Marketing URL: optional, https://robby-jones.github.io/Newbee/
- [ ] Version: 1.0.0. Copyright: `2026 Robby Jones`.
- [ ] Build: click **+** and pick the 1.0.0 build from TestFlight.
      If asked about encryption: the app declares it uses none, so no documents are needed.
- [ ] App Review Information: sign-in **not required**; your name, phone and email;
      paste the reviewer notes from LISTING.md.
- [ ] Version Release: **Manually release this version**.

## 6. Submit (only when you're ready)

- [ ] Add for Review → Submit to App Review. Review usually takes 1 to 3 days.
- [ ] After approval, click **Release This Version**.

Claude never submits for review. That button is yours.
