### SwiftX now updates itself — this one time, update by hand

From this release on, SwiftX checks for its own releases and can install them in
place (Check for Updates… in the menu bar; cadence and automatic installs in
Settings → About). Copies installed *before* this release have no updater in
them, so they cannot pick this one up on their own: update once the usual way —
download the DMG below, or `brew upgrade --cask swiftx` — and subsequent
releases will offer themselves.

The check asks GitHub for the latest release version and sends nothing about you
or your Mac; it can be set to weekly, monthly or off. Downloads are verified
against the SHA-256 published with each release and must carry the same Apple
Developer ID signature as the copy already running before anything is replaced.
Homebrew installs are detected and left to `brew upgrade --cask swiftx`.

*(Maintainers: delete this section once the pre-updater releases are far enough
back that nobody is upgrading across the gap.)*

---

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
