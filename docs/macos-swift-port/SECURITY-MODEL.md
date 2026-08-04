# SwiftX security model

This documents the trust boundaries SwiftX enforces and two deliberate posture
decisions (credential storage and the App Sandbox). It is developer-facing;
for reporting vulnerabilities see [`.github/SECURITY.md`](../../.github/SECURITY.md).

## Untrusted input boundary

SwiftX can be driven from three places that cross a security boundary we do not
control. Two of them are **untrusted**:

| Entry point | Trust | Why |
|-------------|-------|-----|
| Launch `argv` | trusted | Our own process launch — the user or a script they ran started it. |
| `swiftx://` / `sharex://` URL scheme | **untrusted** | Any web page the user visits can open one of these URLs. |
| Single-instance relay (`DistributedNotificationCenter`) | **untrusted** | This is a system-wide, unauthenticated channel; any local process running as the user can post to it. |
| Share extension handoff (`swiftx://ShareExtensionInput/<uuid>`) | **untrusted channel, authenticated payload** | Arrives over the URL scheme like anything else, but carries no data of its own — see below. |

`CLI.handle(_:source:)` takes a `CLISource`. Untrusted callers may trigger the
safe, parameterless verbs a user could already fire from the menu (start a
capture, open a tool), but anything that **reads or uploads a local file**,
**imports an uploader/effect preset**, or **downloads-and-uploads an arbitrary
URL** is either blocked outright (bare file/URL arguments) or gated behind an
explicit confirmation alert that shows the fully-resolved target and defaults to
Cancel. This is what stops a page from doing
`swiftx://FileUpload/~/.ssh/id_rsa` to exfiltrate a file, and stops a local
process from silently swapping the active custom uploader.

The browser native-messaging payload (`-NativeMessagingInput`) is also treated
as untrusted when it arrives over the relay: the actual URL/text is shown for
confirmation before anything leaves the machine, and `downloadAndUpload` caps
the transfer size.

### Share extension handoff

The Share menu entry (`SwiftXShare.appex`) uploads nothing itself. It stages
copies of what the user shared inside **its own App Sandbox container**, then
opens `swiftx://ShareExtensionInput/<uuid>`. The app takes only that UUID from
the caller and derives every path itself, under
`~/Library/Containers/com.retrohazard.swiftx.share/…` — so unlike a bare
`swiftx://FileUpload/<path>`, there is no attacker-chosen path to point at
`~/.ssh`. Three properties do the work (`ShareInbox`, `ShareRequests`):

- **Location authenticates it.** A web page cannot create a directory inside
  another process's sandbox container, so it cannot stage a request at all.
- **Freshness kills replay.** A request stamped more than five minutes ago is
  deleted unread, so a leaked URL cannot be re-fired later.
- **Reads consume.** The request directory is removed on the first read,
  valid or not.
- Manifest file names are validated as plain names (`isSafeStagedName`), so a
  tampered manifest cannot walk out of the request directory.

Because the payload is authenticated by construction — and the user already
chose SwiftX in the Share menu and confirmed the item list in the extension's
own sheet — the upload is not gated behind a third confirmation. The normal
multi-file and large-file warnings still apply.

The extension is the one part of SwiftX that **is** App-Sandboxed (macOS
requires app extensions to be, and it needs nothing the sandbox withholds:
read the shared items, copy them into its container, open a URL). That the app
is *not* sandboxed is what makes the handoff work at all — it can read straight
into the extension's container without an app group.

### Residual item

The relay still uses `DistributedNotificationCenter`, which cannot authenticate
its sender; we contain it by treating everything it delivers as untrusted rather
than by authenticating the peer. Replacing it with an `NSXPCConnection` whose
peer code-signing requirement is verified would let us drop the "any local
process can trigger a capture" surface entirely. Tracked as future hardening.

## Software update boundary

The in-app updater (`Sources/UpdateKit/`) downloads code from the network and
replaces the running application with it, so it is a trust boundary in its own
right: everything it installs must be proven to come from us before it is put
anywhere the user will launch it.

| Stage | Control |
|-------|---------|
| Which release to install | Only `releases/latest` from the SwiftX repository over HTTPS. Drafts and prereleases are never offered, and a tag that isn't CalVer is treated as "no update". |
| Download integrity | The DMG must match the SHA-256 published as that release's `.dmg.sha256` asset. A release with no checksum asset **fails closed** — the updater refuses rather than installing something it cannot verify. |
| Code authenticity | The mounted app must pass `SecStaticCodeCheckValidityWithErrors` (deep, all architectures) **and** carry the same Developer ID Team ID as the running process, plus the expected bundle identifier. Apple's Security framework is used rather than `spctl` because the question is "same publisher as me", not "what does Gatekeeper policy currently say". |
| Time-of-check/time-of-use | The signature is re-verified on the staged copy *after* it is copied off the read-only disk image, so a swap on the mount between verification and install does not go unnoticed. |
| Install atomicity | The bundle is replaced by two same-directory renames with rollback on failure; a crash mid-update leaves either the old or the new bundle in place, never a half-written one. Leftover staging is swept at next launch. |

Two cases deliberately refuse to self-update rather than trying harder:
**ad-hoc/dev builds** (no Team ID to match against) and **Homebrew installs**
(detected via the Caskroom, deferred to `brew upgrade --cask swiftx` so brew's
recorded version stays truthful). Any failure at any stage falls back to opening
the release page in the browser — the updater never degrades to installing
something unverified.

## Credential storage

Secrets never sit in cleartext on disk. OAuth tokens live in the login Keychain
(`OAuthTokenStore`), and every other credential — S3/B2 secret keys, Azure
access key, host passwords (ownCloud, Streamable, YOURLS), API tokens
(Pushbullet, Bitly, puush, Chevereto, Kutt, Lithiio, …) and the AI API key — is
routed through `SecretStore` (Keychain) by the `KeychainBackedSettings` layer in
`Settings.swift`. The JSON config files under Application Support keep only
non-secret identifiers (access-key IDs, usernames, hostnames, bucket names).

Migration is transparent and loss-safe: a config imported from Windows ShareX
(or written by an older SwiftX) still holds its secrets in JSON; on the next
`save()` each secret moves into the Keychain and is blanked from the JSON — but
only once the Keychain has accepted the write, so a locked or unavailable
Keychain degrades to the previous behavior instead of destroying credentials.

## App Sandbox

The *app* runs under the **hardened runtime but is not App-Sandboxed**, and this
is a deliberate, documented trade-off rather than an oversight. (The embedded
`SwiftXShare.appex` is sandboxed — `Resources/ShareExtension.entitlements` —
because macOS requires app extensions to be and it costs that extension
nothing.) Several core features are fundamentally incompatible with the sandbox:

- running external binaries the user chose (`ffmpeg`, and the `/bin/zsh` that
  executes user-configured Actions),
- installing browser native-messaging manifests into other apps' Application
  Support directories,
- the CLI/URL-scheme workflow of reading and uploading arbitrary user-selected
  files.

Adopting the sandbox would require re-architecting those into XPC helper tools
and security-scoped bookmarks. Until then the exposure the sandbox would
otherwise contain is closed at the source by the untrusted-input boundary above:
no external or web-originated input can read or upload a local file without an
explicit, path-revealing confirmation.
