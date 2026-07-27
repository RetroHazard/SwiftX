### OAuth destinations show an "unverified app" warning

Google Drive, YouTube and OneDrive work normally, but both app registrations are
still going through provider review, so the sign-in screen warns that the app
has not been verified:

- **Google** (Google Drive, YouTube) — submitted for verification, review pending.
- **Microsoft** (OneDrive) — not yet submitted; publisher verification requires a
  Microsoft Partner Center account.

The warning is about SwiftX's registration status with the provider, not about
what the app does with your data. Uploads go straight from your Mac to your own
account and the access tokens stay in your login Keychain — there is no SwiftX
server anywhere in the path. On Google's screen, choose **Advanced → Go to
SwiftX (unsafe)** to continue.

Every other destination — S3, Backblaze B2, Azure, ownCloud/Nextcloud, Seafile,
custom `.sxcu` uploaders, the keyless hosts — is unaffected.

---
