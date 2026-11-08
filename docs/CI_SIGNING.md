# CI signing certificate

The TestFlight workflow archives the app on a fresh GitHub Actions Mac every time. A fresh Mac
has an empty keychain, so with nothing else to go on, Xcode's automatic signing creates a brand
new **Apple Development** certificate on every run. Apple caps how many certificates a team can
have, so after about 10 builds the archive fails with:

> Choose a certificate to revoke. Your account has reached the maximum number of certificates.

The fix is to give CI one long-lived certificate (with its private key) that it imports on every
run. Xcode then reuses it and only refreshes provisioning profiles, so no new certificates are
created. The distribution signing for TestFlight is still cloud-managed by Apple, as before.

Until the two secrets below exist, the workflow keeps working the old way and prints a warning.

## One-time setup (works on macOS Ventura, no Xcode needed)

### 1. Create a certificate signing request

1. Open **Keychain Access** (Applications → Utilities).
2. Menu bar: **Keychain Access → Certificate Assistant → Request a Certificate From a Certificate Authority…**
3. Fill in:
   - **User Email Address:** your Apple ID email
   - **Common Name:** `Newbee CI`
   - **CA Email Address:** leave empty
   - Choose **Saved to disk**, then **Continue**, and save `CertificateSigningRequest.certSigningRequest` to the Desktop.

This also puts a new private key in your login keychain. That key is what CI needs, so do steps
1 to 3 on the same Mac.

### 2. Create the certificate on the developer portal

1. Go to [developer.apple.com/account/resources/certificates/add](https://developer.apple.com/account/resources/certificates/add).
   If you are at the limit, first revoke one of the old CI certificates (see step 6).
2. Choose **Apple Development**, then **Continue**.
3. Upload the `.certSigningRequest` file from step 1, then **Continue**.
4. **Download** the certificate (`development.cer`).

### 3. Export it as a .p12

1. Double-click `development.cer`. Keychain Access adds it to the **login** keychain.
2. In Keychain Access, pick **login** on the left and the **My Certificates** tab at the top.
3. Find **Apple Development: …** (today's date under Expires). Click the triangle next to it and
   check that a private key named `Newbee CI` is underneath. If there is no key, the certificate
   was made from a request created on another Mac; start again from step 1.
4. Right-click the certificate (not the key) → **Export "Apple Development: …"**.
5. File Format **Personal Information Exchange (.p12)**, name it `newbee-ci.p12`, save to the Desktop.
6. Choose a strong password when asked, and keep it for step 5. macOS may then ask for your Mac
   login password to allow the export.

### 4. Copy the .p12 as text

In **Terminal**:

```sh
base64 -i ~/Desktop/newbee-ci.p12 | pbcopy
```

The base64 text is now on the clipboard.

### 5. Add the two repository secrets

Go to [Newbee → Settings → Secrets and variables → Actions](https://github.com/Robby-Jones/Newbee/settings/secrets/actions)
and add two **New repository secrets**:

| Name | Value |
|---|---|
| `SIGNING_CERT_P12_BASE64` | Paste the clipboard from step 4 |
| `SIGNING_CERT_PASSWORD` | The password from step 3 |

Then delete `newbee-ci.p12` and the `.certSigningRequest` from the Desktop. The certificate and
key stay in your login keychain; that is fine and lets you export again later.

### 6. Check it and clean up

1. Run **Actions → TestFlight → Run workflow** on `main`.
2. In the **Install signing certificate** step, the log lists `1 valid identities found` with your
   `Apple Development` certificate. If it fails there, nothing was created on your account; the
   error says what is wrong with the secret.
3. Once the build uploads, open the [certificates list](https://developer.apple.com/account/resources/certificates/list).
   No new certificate should have appeared. Revoke the old Development certificates CI made
   before (they usually show as "Created via API"), but **keep the one you made in step 2**.
   Revoking old Development certificates does not affect TestFlight builds, which are signed
   for distribution.

## Once a year

Apple Development certificates last one year. The workflow prints a warning when the certificate
has less than 30 days left, and fails with a clear error once it has expired (it does not fall
back to creating new certificates). To renew, repeat steps 1 to 5 and replace both secrets, then
revoke the old certificate.

If you revoke the certificate in the secret by mistake, Xcode will go back to creating a new one
on each run. Repeat the setup to fix it.

## Why not auto-revoke old certificates?

A scheduled job could revoke certificates through the App Store Connect API, but it would be
treating the symptom: every build would still mint a certificate, and the job would have to guess
which certificates are safe to revoke (getting that wrong would also revoke the one on a Mac you
develop on). Reusing one certificate means nothing piles up in the first place.
