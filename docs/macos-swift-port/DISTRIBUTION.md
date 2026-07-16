# SwiftX Distribution (Phase 11)

Ship SwiftX via a **personal Homebrew tap first**, with the **official
`homebrew/cask` repo as a real follow-up goal** — not a closed door.

```
brew install --cask retrohazard/swiftx/swiftx
```

SwiftX has a strong case for eventual official inclusion: ShareX has no macOS
build at all, so this fills a genuine gap rather than duplicating an existing
cask (duplication is a common rejection reason; a void is the opposite). The
reasons to *start* on a personal tap are mechanical, not about worthiness:

1. **It must be notarized first.** The interim unsigned build relies on a
   `postflight` that strips `com.apple.quarantine` — and `brew audit --new`
   for the official repo **rejects quarantine-removal workarounds**. So the
   official cask is blocked until the paid Developer ID + notarization land
   (see "Signing status" below). This is the hard prerequisite.
2. **The automated notability check keys off repo metrics.** `brew audit --new`
   scores GitHub stars/forks/watchers; a just-published repo trips it regardless
   of how useful the app is. Filling a void helps a maintainer's judgement, but
   it does not bypass the automated metric — that clears with a little time and
   visibility.

**Path to the official cask:** enroll → notarize (deletes the `xattr` hack) →
accumulate some traction → submit via `brew bump-cask-pr` / a new-cask PR and
let `brew audit --new` pass clean. Until then, the personal tap is identical UX
for users and fully in your control.

## One-time setup

1. Create a public GitHub repo named **`RetroHazard/homebrew-swiftx`** (the
   `homebrew-` prefix is what makes `brew tap` find it).
2. Copy `Casks/swiftx.rb` from this repo into `Casks/swiftx.rb` in that tap repo.
   Keep this repo's copy as the source of truth and update the tap on release.

## Per-release runbook

Versions default to `0.1.0`; pass an explicit version to every script.

```bash
Scripts/make-app.sh 0.1.0            # build + bundle build/SwiftX.app
Scripts/make-dmg.sh 0.1.0            # -> build/SwiftX-0.1.0.dmg, prints sha256
# Scripts/notarize.sh build/SwiftX-0.1.0.dmg   # once a Developer ID exists (see below)
```

Then:

3. `gh release create v0.1.0 build/SwiftX-0.1.0.dmg --title "SwiftX 0.1.0" --notes "…"`
4. Edit `Casks/swiftx.rb`: bump `version`, paste the `sha256` from make-dmg.sh.
5. Copy the updated cask into the tap repo and push.
6. Verify: `brew update && brew install --cask retrohazard/swiftx/swiftx`.

## Signing status

**Now — interim, unsigned.** With only a free Apple ID (an "Apple Development"
cert), builds cannot be notarized. Gatekeeper quarantines the download, so the
cask's `postflight` runs `xattr -dr com.apple.quarantine` to let the app launch.
This is a deliberate, documented workaround, not a permanent state.

**Later — notarized.** Once enrolled in the **paid Apple Developer Program**
($99/yr) and a **"Developer ID Application"** certificate is installed:

1. `make-app.sh` already signs with the first Developer ID / Apple Development
   identity it finds and already sets `--options runtime` (hardened runtime,
   required for notarization). With a Developer ID cert in the keychain it will
   use it automatically — no script change needed.
2. Store notary credentials once:
   `xcrun notarytool store-credentials swiftx-notary --apple-id <id> --team-id <TEAMID> --password <app-specific-pw>`
3. Add `Scripts/notarize.sh build/SwiftX-<version>.dmg` to the runbook (step 2½).
4. **Delete the `postflight` de-quarantine block** from `Casks/swiftx.rb` — a
   notarized, stapled DMG passes Gatekeeper with no help.

## Updates

`brew upgrade --cask swiftx` is the update mechanism. No Sparkle integration is
needed for Homebrew users; add it only if a non-Homebrew (direct-download)
channel is introduced later.
