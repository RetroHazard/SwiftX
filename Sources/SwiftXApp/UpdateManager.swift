// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE
//
// Update orchestration: background checks on the configured cadence, manual
// checks from the status menu / About pane, and the install-relaunch flow.
// Homebrew installs are never self-replaced - brew upgrade --cask swiftx owns
// those - and any install failure falls back to the release page in the
// browser. Auto-install never relaunches by itself: yanking a menu-bar app
// mid-recording is unacceptable, so the swap happens silently and the user
// relaunches when convenient.

import AppKit
import SharedKit
import UpdateKit

@MainActor
final class UpdateManager: ObservableObject {
    static let shared = UpdateManager()

    enum State {
        case idle
        case checking
        case upToDate(Date)
        case available(UpdateChecker.AvailableUpdate)
        case downloading
        /// Swap finished; the new version runs on next launch.
        case installed(CalVer)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    let isHomebrewManaged = HomebrewDetector.isHomebrewManaged()

    private var loop: Task<Void, Never>?
    private var installInFlight = false
    /// Last update seen by any check; lets notification actions work without
    /// round-tripping release JSON through userInfo.
    private var lastUpdate: UpdateChecker.AvailableUpdate?

    static let brewUpgradeCommand = "brew upgrade --cask swiftx"
    static let releasesFallbackURL = URL(string: "https://github.com/RetroHazard/SwiftX/releases")!

    /// SWIFTX_UPDATE_TEST_VERSION overrides the bundle version so the full
    /// flow can be exercised against the real latest release.
    static func currentVersion() -> CalVer? {
        if let fake = ProcessInfo.processInfo.environment["SWIFTX_UPDATE_TEST_VERSION"],
           let version = CalVer(fake) {
            return version
        }
        return (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
            .flatMap(CalVer.init)
    }

    /// True when this copy can replace itself (Developer ID signed .app in a
    /// writable location, not Homebrew-managed).
    var canSelfInstall: Bool {
        guard !isHomebrewManaged else { return false }
        return (try? UpdateInstaller.preflightCheck()) != nil
    }

    // MARK: - Background loop

    func startBackgroundChecks() {
        UpdateInstaller.sweepStaleArtifacts()
        guard loop == nil else { return }
        loop = Task { [weak self] in
            try? await Task.sleep(for: .seconds(60)) // let launch settle
            while !Task.isCancelled {
                await self?.backgroundCheckIfDue()
                try? await Task.sleep(for: .seconds(3600)) // re-evaluate hourly
            }
        }
    }

    private func backgroundCheckIfDue() async {
        if case .installed = state { return } // waiting on a relaunch
        let config = ApplicationConfig.load()
        guard let interval = UpdateCheckFrequency(rawValue: config.updateCheckFrequency)?.interval,
              Date().timeIntervalSince1970 - config.updateLastCheckTime > interval
        else { return }
        await backgroundCheck()
    }

    private func backgroundCheck() async {
        guard let current = Self.currentVersion() else { return }
        let outcome: UpdateChecker.Outcome
        do {
            let release = try await UpdateChecker.fetchLatestRelease()
            var config = ApplicationConfig.load()
            config.updateLastCheckTime = Date().timeIntervalSince1970
            try? config.save()
            outcome = try UpdateChecker.evaluate(current: current, release: release,
                                                 skippedVersion: config.updateSkippedVersion)
        } catch {
            AppLog.updates.error("background check failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        switch outcome {
        case .upToDate, .skipped:
            AppLog.updates.info("background check: no actionable update")
        case .available(let update):
            lastUpdate = update
            state = .available(update)
            AppLog.updates.info("update available: \(update.version, privacy: .public)")
            if isHomebrewManaged {
                Notifier.notifyUpdate(
                    title: "SwiftX \(update.version) is available",
                    body: "Update with \(Self.brewUpgradeCommand)",
                    version: "\(update.version)", url: update.release.htmlURL.absoluteString,
                    installed: false)
            } else if ApplicationConfig.load().updateAutoInstall {
                await autoInstall(update)
            } else {
                Notifier.notifyUpdate(
                    title: "SwiftX \(update.version) is available",
                    body: "You have \(current). Install now or view the release notes.",
                    version: "\(update.version)", url: update.release.htmlURL.absoluteString,
                    installed: false)
            }
        }
    }

    private func autoInstall(_ update: UpdateChecker.AvailableUpdate) async {
        // Never yank the bundle out from under active work; the hourly loop
        // retries once things quiet down.
        guard !RecordingCoordinator.shared.isRecording, !UploadTaskCenter.shared.isBusy else {
            AppLog.updates.info("auto-install deferred: recording or uploads in flight")
            return
        }
        await performInstall(update, interactive: false)
    }

    // MARK: - Manual check

    /// Menu item / About-pane button. Ignores cadence and skipped-version: an
    /// explicit check always answers.
    func checkFromMenu() {
        if case .checking = state { return }
        if case .downloading = state { return }
        state = .checking
        Task { [weak self] in
            await self?.manualCheck()
        }
    }

    private func manualCheck() async {
        guard let current = Self.currentVersion() else {
            state = .failed("This build has no version, so updates cannot be compared.")
            presentFailureAlert("This build has no version, so updates cannot be compared.")
            return
        }
        do {
            let release = try await UpdateChecker.fetchLatestRelease()
            var config = ApplicationConfig.load()
            config.updateLastCheckTime = Date().timeIntervalSince1970
            try? config.save()
            let outcome = try UpdateChecker.evaluate(current: current, release: release,
                                                     skippedVersion: "")
            switch outcome {
            case .upToDate:
                state = .upToDate(Date())
                presentUpToDateAlert(current: current)
            case .available(let update), .skipped(let update):
                lastUpdate = update
                state = .available(update)
                presentUpdateAlert(update, current: current)
            }
        } catch {
            state = .failed(error.localizedDescription)
            presentFailureAlert(error.localizedDescription)
        }
    }

    // MARK: - Actions

    /// Notification actions can arrive after a relaunch wiped the cached
    /// update; re-check first in that case.
    func installCurrentUpdate() {
        if let update = lastUpdate {
            Task { await performInstall(update, interactive: true) }
            return
        }
        Task { [weak self] in
            guard let self, let current = Self.currentVersion() else { return }
            guard let release = try? await UpdateChecker.fetchLatestRelease(),
                  case .available(let update) = try? UpdateChecker.evaluate(
                      current: current, release: release, skippedVersion: "")
            else { return }
            self.lastUpdate = update
            await self.performInstall(update, interactive: true)
        }
    }

    func skipCurrentUpdate() {
        guard let update = lastUpdate else { return }
        var config = ApplicationConfig.load()
        config.updateSkippedVersion = "\(update.version)"
        try? config.save()
        if case .available = state { state = .idle }
        AppLog.updates.info("skipping version \(update.version, privacy: .public)")
    }

    func openReleasePage() {
        NSWorkspace.shared.open(lastUpdate?.release.htmlURL ?? Self.releasesFallbackURL)
    }

    func relaunchNow() {
        guard case .installed = state else { return }
        UpdateInstaller.spawnRelaunchHelper(appAt: Bundle.main.bundleURL.resolvingSymlinksInPath())
        NSApp.terminate(nil)
    }

    func copyBrewCommand() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(Self.brewUpgradeCommand, forType: .string)
    }

    // MARK: - Install

    private func performInstall(_ update: UpdateChecker.AvailableUpdate, interactive: Bool) async {
        guard !installInFlight else { return }
        if isHomebrewManaged {
            if interactive { presentBrewAlert(update) }
            return
        }
        installInFlight = true
        state = .downloading
        defer { installInFlight = false }
        do {
            // Hashing, mounting and copying are heavy; keep them off the main actor.
            _ = try await Task.detached(priority: .userInitiated) {
                try await UpdateInstaller.install(update: update)
            }.value
            state = .installed(update.version)
            if interactive {
                presentRelaunchAlert(update.version)
            } else {
                Notifier.notifyUpdate(
                    title: "SwiftX \(update.version) installed",
                    body: "Relaunch to finish updating.",
                    version: "\(update.version)", url: update.release.htmlURL.absoluteString,
                    installed: true)
            }
        } catch {
            AppLog.updates.error("install failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
            if interactive {
                presentInstallFailedAlert(error.localizedDescription, update: update)
            } else {
                Notifier.notifyUpdate(
                    title: "SwiftX update failed",
                    body: error.localizedDescription,
                    version: "\(update.version)", url: update.release.htmlURL.absoluteString,
                    installed: false)
            }
        }
    }

    // MARK: - Alerts

    private func presentUpToDateAlert(current: CalVer) {
        let alert = NSAlert()
        alert.messageText = "SwiftX is up to date"
        alert.informativeText = "Version \(current) is the latest release."
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func presentUpdateAlert(_ update: UpdateChecker.AvailableUpdate, current: CalVer) {
        let alert = NSAlert()
        alert.messageText = "SwiftX \(update.version) is available"
        var detail = "You have \(current)."
        if let notes = update.release.body, !notes.isEmpty {
            detail += "\n\n" + String(notes.prefix(500))
        }
        alert.informativeText = detail
        if isHomebrewManaged {
            alert.addButton(withTitle: "Copy brew Command")
            alert.informativeText += "\n\nThis copy is managed by Homebrew; update with \(Self.brewUpgradeCommand)."
        } else if canSelfInstall {
            alert.addButton(withTitle: "Install Update")
        } else {
            alert.addButton(withTitle: "Open Release Page")
        }
        alert.addButton(withTitle: "View Release Page")
        alert.addButton(withTitle: "Skip This Version")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if isHomebrewManaged {
                copyBrewCommand()
            } else if canSelfInstall {
                installCurrentUpdate()
            } else {
                openReleasePage()
            }
        case .alertSecondButtonReturn:
            openReleasePage()
        case .alertThirdButtonReturn:
            skipCurrentUpdate()
        default:
            break
        }
    }

    private func presentBrewAlert(_ update: UpdateChecker.AvailableUpdate) {
        let alert = NSAlert()
        alert.messageText = "Update with Homebrew"
        alert.informativeText = "This copy of SwiftX is managed by Homebrew. "
            + "Update it with:\n\n\(Self.brewUpgradeCommand)"
        alert.addButton(withTitle: "Copy Command")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { copyBrewCommand() }
    }

    private func presentRelaunchAlert(_ version: CalVer) {
        let alert = NSAlert()
        alert.messageText = "SwiftX \(version) installed"
        alert.informativeText = "The update takes effect after a relaunch."
        alert.addButton(withTitle: "Relaunch Now")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { relaunchNow() }
    }

    private func presentInstallFailedAlert(_ message: String, update: UpdateChecker.AvailableUpdate) {
        let alert = NSAlert()
        alert.messageText = "Update could not be installed"
        alert.informativeText = message + "\n\nYou can download the update from the release page instead."
        alert.addButton(withTitle: "Open Release Page")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(update.release.htmlURL)
        }
    }

    private func presentFailureAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Update check failed"
        alert.informativeText = message
        alert.addButton(withTitle: "Open Releases Page")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(Self.releasesFallbackURL)
        }
    }
}
