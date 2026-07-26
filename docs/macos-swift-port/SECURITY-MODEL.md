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

### Residual item

The relay still uses `DistributedNotificationCenter`, which cannot authenticate
its sender; we contain it by treating everything it delivers as untrusted rather
than by authenticating the peer. Replacing it with an `NSXPCConnection` whose
peer code-signing requirement is verified would let us drop the "any local
process can trigger a capture" surface entirely. Tracked as future hardening.

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

SwiftX runs under the **hardened runtime but is not App-Sandboxed**, and this is
a deliberate, documented trade-off rather than an oversight. Several core
features are fundamentally incompatible with the sandbox:

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
