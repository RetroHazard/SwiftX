// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE
//
// Self-update for DMG installs: download the release disk image, verify the
// published sha256, mount, verify the new bundle is validly signed by the
// same Team ID as the running app (Security.framework, not spctl - the
// property needed is "same publisher", not Gatekeeper policy), atomically
// swap the installed bundle, then relaunch. Homebrew installs never reach
// this path, and every error surfaces as a browser fallback to the release
// page. Dev builds (ad-hoc signed, no Team ID) refuse self-update.

import CryptoKit
import Foundation
import Security
import SharedKit

public enum UpdateInstaller {
    public enum InstallError: LocalizedError {
        case notAnAppBundle
        case translocated
        case devSignedBuild
        case destinationNotWritable(String)
        case downloadFailed(Int)
        case checksumUnavailable
        case checksumMismatch
        case mountFailed(String)
        case appMissingInDMG
        case signatureInvalid(String)
        case teamIDMismatch(String?, String)
        case swapFailed(String)

        public var errorDescription: String? {
            switch self {
            case .notAnAppBundle:
                return L10n.t("update.error.not_app_bundle")
            case .translocated:
                return L10n.t("update.error.translocated")
            case .devSignedBuild:
                return L10n.t("update.error.dev_signed")
            case .destinationNotWritable(let path):
                return L10n.t("update.error.not_writable", path)
            case .downloadFailed(let status):
                return L10n.t("update.error.download_failed", "\(status)")
            case .checksumUnavailable:
                return L10n.t("update.error.checksum_unavailable")
            case .checksumMismatch:
                return L10n.t("update.error.checksum_mismatch")
            case .mountFailed(let detail):
                return L10n.t("update.error.mount_failed", detail)
            case .appMissingInDMG:
                return L10n.t("update.error.app_missing_in_dmg")
            case .signatureInvalid(let detail):
                return L10n.t("update.error.signature_invalid", detail)
            case .teamIDMismatch(let got, let expected):
                return L10n.t("update.error.team_id_mismatch",
                              got ?? L10n.t("update.error.unknown_team"), expected)
            case .swapFailed(let detail):
                return L10n.t("update.error.swap_failed", detail)
            }
        }
    }

    static let bundleIdentifier = "com.retrohazard.swiftx"

    // MARK: - Preflight

    /// The installed bundle to replace plus the Team ID new bundles must
    /// match. Throws when self-update is impossible from this copy.
    public static func preflightCheck() throws -> (bundleURL: URL, teamID: String) {
        guard Bundle.main.bundleIdentifier == bundleIdentifier,
              Bundle.main.bundleURL.pathExtension == "app"
        else { throw InstallError.notAnAppBundle }

        let bundleURL = Bundle.main.bundleURL.resolvingSymlinksInPath()
        let path = bundleURL.path
        if path.contains("/AppTranslocation/") || path.hasPrefix("/Volumes/") {
            throw InstallError.translocated
        }

        guard let teamID = currentTeamID() else { throw InstallError.devSignedBuild }

        let parent = bundleURL.deletingLastPathComponent()
        let fm = FileManager.default
        guard fm.isWritableFile(atPath: parent.path), fm.isWritableFile(atPath: path) else {
            throw InstallError.destinationNotWritable(parent.path)
        }
        return (bundleURL, teamID)
    }

    /// Team ID of the running process; nil for ad-hoc/unsigned dev builds.
    public static func currentTeamID() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf(SecCSFlags(), &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess,
              let staticCode else { return nil }
        return signingInfo(of: staticCode)?[kSecCodeInfoTeamIdentifier as String] as? String
    }

    // MARK: - Download & checksum

    /// The .sha256 asset holds the bare digest (shasum | awk '{print $1}');
    /// tolerate a trailing "  filename" in case the format ever gains one.
    static func expectedDigest(fromChecksumFile text: String) -> String? {
        guard let token = text.split(whereSeparator: \.isWhitespace).first.map(String.init)?.lowercased(),
              token.count == 64, token.allSatisfy(\.isHexDigit)
        else { return nil }
        return token
    }

    static func sha256Hex(ofFileAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Downloads the DMG into `staging` and verifies it against the release's
    /// published checksum. Fails closed when the checksum asset is missing.
    static func downloadAndVerify(update: UpdateChecker.AvailableUpdate,
                                  staging: URL, session: URLSession = .shared) async throws -> URL {
        guard let checksumAsset = update.checksum else { throw InstallError.checksumUnavailable }

        let dmgURL = staging.appendingPathComponent(update.dmg.name)
        let (downloaded, dmgResponse) = try await session.download(from: update.dmg.browserDownloadURL)
        if let http = dmgResponse as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw InstallError.downloadFailed(http.statusCode)
        }
        try FileManager.default.moveItem(at: downloaded, to: dmgURL)

        let (checksumData, checksumResponse) = try await session.data(from: checksumAsset.browserDownloadURL)
        if let http = checksumResponse as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw InstallError.downloadFailed(http.statusCode)
        }
        guard let text = String(data: checksumData, encoding: .utf8),
              let expected = expectedDigest(fromChecksumFile: text)
        else { throw InstallError.checksumUnavailable }

        guard try sha256Hex(ofFileAt: dmgURL) == expected else {
            throw InstallError.checksumMismatch
        }
        return dmgURL
    }

    // MARK: - Mount & signature verification

    static func mountPoint(fromHdiutilPlist data: Data) -> String? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]]
        else { return nil }
        return entities.compactMap { $0["mount-point"] as? String }.first
    }

    static func attach(dmgAt url: URL) throws -> String {
        let result: (status: Int32, stdout: Data, stderr: String)
        do {
            result = try run("/usr/bin/hdiutil",
                             ["attach", url.path, "-nobrowse", "-noautoopen", "-readonly", "-plist"])
        } catch {
            throw InstallError.mountFailed(error.localizedDescription)
        }
        guard result.status == 0 else { throw InstallError.mountFailed(result.stderr) }
        guard let mount = mountPoint(fromHdiutilPlist: result.stdout) else {
            throw InstallError.mountFailed("no mount point in hdiutil output")
        }
        return mount
    }

    static func detach(mountPoint: String) {
        _ = try? run("/usr/bin/hdiutil", ["detach", mountPoint, "-force"])
    }

    /// codesign --deep --strict equivalent plus identifier and Team ID match.
    static func verify(bundleAt url: URL, matchesTeamID expected: String) throws {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, SecCSFlags(), &staticCode) == errSecSuccess,
              let staticCode
        else { throw InstallError.signatureInvalid("cannot read code signature") }

        let flags = SecCSFlags(rawValue: UInt32(kSecCSCheckAllArchitectures | kSecCSCheckNestedCode))
        var error: Unmanaged<CFError>?
        guard SecStaticCodeCheckValidityWithErrors(staticCode, flags, nil, &error) == errSecSuccess else {
            let detail = (error?.takeRetainedValue()).map(String.init(describing:)) ?? "invalid signature"
            throw InstallError.signatureInvalid(detail)
        }

        let info = signingInfo(of: staticCode)
        guard info?[kSecCodeInfoIdentifier as String] as? String == bundleIdentifier else {
            throw InstallError.signatureInvalid("unexpected bundle identifier")
        }
        let team = info?[kSecCodeInfoTeamIdentifier as String] as? String
        guard team == expected else { throw InstallError.teamIDMismatch(team, expected) }
    }

    private static func signingInfo(of staticCode: SecStaticCode) -> [String: Any]? {
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode, SecCSFlags(rawValue: UInt32(kSecCSSigningInformation)), &info
        ) == errSecSuccess else { return nil }
        return info as? [String: Any]
    }

    // MARK: - Swap & relaunch

    static func swap(newBundleAt mountedApp: URL, into target: URL, teamID: String) throws {
        let fm = FileManager.default
        let parent = target.deletingLastPathComponent()
        let uuid = UUID().uuidString
        let stagedNew = parent.appendingPathComponent(".SwiftX.app.new-\(uuid)")
        let oldAside = parent.appendingPathComponent(".SwiftX.app.old-\(uuid)")

        // ditto preserves signatures, resource forks and permissions; staging
        // next to the target keeps the final renames same-volume atomic.
        let copy = try run("/usr/bin/ditto", [mountedApp.path, stagedNew.path])
        guard copy.status == 0 else { throw InstallError.swapFailed(copy.stderr) }
        do {
            // Re-verify the staged copy: defeats a swap on the (attacker
            // readable) mount between verification and copy.
            try verify(bundleAt: stagedNew, matchesTeamID: teamID)
        } catch {
            try? fm.removeItem(at: stagedNew)
            throw error
        }

        do {
            try fm.moveItem(at: target, to: oldAside)
        } catch {
            try? fm.removeItem(at: stagedNew)
            throw InstallError.swapFailed(error.localizedDescription)
        }
        do {
            try fm.moveItem(at: stagedNew, to: target)
        } catch {
            try? fm.moveItem(at: oldAside, to: target)
            try? fm.removeItem(at: stagedNew)
            throw InstallError.swapFailed(error.localizedDescription)
        }

        if (try? fm.removeItem(at: oldAside)) == nil {
            try? fm.trashItem(at: oldAside, resultingItemURL: nil)
        }
    }

    /// Removes leftover swap staging from a crashed update; call at launch.
    public static func sweepStaleArtifacts() {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        let parent = Bundle.main.bundleURL.resolvingSymlinksInPath().deletingLastPathComponent()
        let fm = FileManager.default
        guard let siblings = try? fm.contentsOfDirectory(atPath: parent.path) else { return }
        for name in siblings where name.hasPrefix(".SwiftX.app.old-") || name.hasPrefix(".SwiftX.app.new-") {
            try? fm.removeItem(at: parent.appendingPathComponent(name))
            AppLog.updates.info("removed stale update artifact \(name, privacy: .public)")
        }
    }

    /// Spawns a detached helper that waits for this process to exit (also
    /// releasing the single-instance lock) before opening the new bundle.
    /// The caller terminates the app after this returns.
    public static func spawnRelaunchHelper(appAt url: URL) {
        let pid = ProcessInfo.processInfo.processIdentifier
        // The path travels as $0, never interpolated into the script, so no
        // character in it can break out of the quoting.
        let script = "while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.2; done; " +
                     "exec /usr/bin/open \"$0\""
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = ["-c", script, url.path]
        try? helper.run()
    }

    // MARK: - Full flow

    /// Runs the entire download-verify-swap sequence and returns the installed
    /// bundle URL (for the relaunch helper). Does NOT relaunch by itself.
    public static func install(update: UpdateChecker.AvailableUpdate) async throws -> URL {
        let (target, teamID) = try preflightCheck()

        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftx-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }

        AppLog.updates.info("downloading \(update.dmg.name, privacy: .public)")
        let dmgURL = try await downloadAndVerify(update: update, staging: staging)
        AppLog.updates.info("checksum verified for \(update.dmg.name, privacy: .public)")

        let mount = try attach(dmgAt: dmgURL)
        defer { detach(mountPoint: mount) }
        AppLog.updates.info("mounted at \(mount, privacy: .public)")

        let mountedApp = URL(fileURLWithPath: mount).appendingPathComponent("SwiftX.app")
        guard FileManager.default.fileExists(atPath: mountedApp.path) else {
            throw InstallError.appMissingInDMG
        }
        try verify(bundleAt: mountedApp, matchesTeamID: teamID)
        AppLog.updates.info("signature verified; swapping into \(target.path, privacy: .public)")

        try swap(newBundleAt: mountedApp, into: target, teamID: teamID)
        AppLog.updates.info("installed \(update.version, privacy: .public)")
        return target
    }

    // MARK: - Subprocess helper

    @discardableResult
    private static func run(_ tool: String, _ arguments: [String])
        throws -> (status: Int32, stdout: Data, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        // Drain stderr concurrently: reading the pipes one after the other
        // deadlocks if the child fills the second pipe's buffer first.
        var stderrData = Data()
        let drained = DispatchGroup()
        drained.enter()
        DispatchQueue.global(qos: .utility).async {
            stderrData = err.fileHandleForReading.readDataToEndOfFile()
            drained.leave()
        }
        try process.run()
        let stdout = out.fileHandleForReading.readDataToEndOfFile()
        drained.wait()
        process.waitUntilExit()
        return (process.terminationStatus, stdout,
                String(data: stderrData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
    }
}
