// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE
//
// Update orchestration: background checks on the configured cadence, manual
// checks from the status menu / Updates pane, and the install-relaunch flow.
// Homebrew installs are never self-replaced - brew upgrade --cask swiftx owns
// those - and any install failure falls back to the release page in the
// browser. Auto-install never relaunches by itself: yanking a menu-bar app
// mid-recording is unacceptable, so the swap happens silently and the user
// relaunches when convenient.

import AppKit
import Combine
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
        if case .downloading = state { return }
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
        case .upToDate:
            // also clears a stale "available" left by an out-of-band upgrade
            state = .upToDate(Date())
            AppLog.updates.info("background check: up to date")
        case .skipped(let update):
            lastUpdate = update // manual install from the Updates pane still works
            if case .available = state { state = .idle }
            AppLog.updates.info("background check: update skipped by user")
        case .available(let update):
            lastUpdate = update
            state = .available(update)
            AppLog.updates.info("update available: \(update.version, privacy: .public)")
            if isHomebrewManaged {
                Notifier.notifyUpdate(
                    title: L10n.t("update.notify.available_title", "\(update.version)"),
                    body: L10n.t("update.notify.available_body_brew", Self.brewUpgradeCommand),
                    version: "\(update.version)", url: update.release.htmlURL.absoluteString,
                    installed: false)
            } else if ApplicationConfig.load().updateAutoInstall {
                await autoInstall(update)
            } else {
                Notifier.notifyUpdate(
                    title: L10n.t("update.notify.available_title", "\(update.version)"),
                    body: L10n.t("update.notify.available_body", "\(current)"),
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

    /// Menu item / Updates-pane button. Ignores cadence and skipped-version: an
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
            let message = L10n.t("update.alert.no_version")
            state = .failed(message)
            presentFailureAlert(message)
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

    /// `versionHint` is the version a notification banner named; when the
    /// cache is gone (app relaunched) or names a different version (a later
    /// check superseded the banner), re-check and install what is actually
    /// latest instead of trusting stale state.
    func installCurrentUpdate(versionHint: String? = nil) {
        if let update = lastUpdate, versionHint == nil || "\(update.version)" == versionHint {
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
        skipVersion("\(update.version)")
    }

    /// Notification "Skip This Version" skips the version the banner named,
    /// not whatever a later background check may have cached since.
    func skipVersion(_ raw: String?) {
        guard let raw, CalVer(raw) != nil else {
            skipCurrentUpdate()
            return
        }
        var config = ApplicationConfig.load()
        config.updateSkippedVersion = raw
        try? config.save()
        if case .available(let update) = state, "\(update.version)" == raw { state = .idle }
        AppLog.updates.info("skipping version \(raw, privacy: .public)")
    }

    /// `urlHint` is the release URL a notification banner carried; it wins
    /// over the cached update so an old banner opens its own release page.
    func openReleasePage(urlHint: String? = nil) {
        let url = urlHint.flatMap(URL.init(string:))
            ?? lastUpdate?.release.htmlURL
            ?? Self.releasesFallbackURL
        NSWorkspace.shared.open(url)
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
                    title: L10n.t("update.notify.installed_title", "\(update.version)"),
                    body: L10n.t("update.notify.installed_body"),
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
                    title: L10n.t("update.notify.failed_title"),
                    body: error.localizedDescription,
                    version: "\(update.version)", url: update.release.htmlURL.absoluteString,
                    installed: false)
            }
        }
    }

    // MARK: - Alerts

    private func presentUpToDateAlert(current: CalVer) {
        let alert = NSAlert()
        alert.messageText = L10n.t("update.alert.up_to_date_title")
        alert.informativeText = L10n.t("update.alert.up_to_date_body", "\(current)")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func presentUpdateAlert(_ update: UpdateChecker.AvailableUpdate, current: CalVer) {
        let alert = NSAlert()
        alert.messageText = L10n.t("update.alert.available_title", "\(update.version)")
        var detail = L10n.t("update.alert.you_have", "\(current)")
        if let notes = update.release.body, !notes.isEmpty {
            detail += "\n\n" + String(notes.prefix(500))
        }
        alert.informativeText = detail
        if isHomebrewManaged {
            alert.addButton(withTitle: L10n.t("update.alert.copy_brew_command"))
            alert.informativeText += "\n\n" + L10n.t("update.alert.brew_managed_suffix", Self.brewUpgradeCommand)
        } else if canSelfInstall {
            alert.addButton(withTitle: L10n.t("update.alert.install_update"))
        } else {
            alert.addButton(withTitle: L10n.t("update.alert.open_release_page"))
        }
        alert.addButton(withTitle: L10n.t("update.alert.view_release_page"))
        alert.addButton(withTitle: L10n.t("update.alert.skip_version"))
        alert.addButton(withTitle: L10n.t("common.cancel"))
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
        alert.messageText = L10n.t("update.alert.brew_title")
        alert.informativeText = L10n.t("update.alert.brew_body", Self.brewUpgradeCommand)
        alert.addButton(withTitle: L10n.t("update.alert.copy_command"))
        alert.addButton(withTitle: L10n.t("common.cancel"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { copyBrewCommand() }
    }

    private func presentRelaunchAlert(_ version: CalVer) {
        let alert = NSAlert()
        alert.messageText = L10n.t("update.alert.installed_title", "\(version)")
        alert.informativeText = L10n.t("update.alert.installed_body")
        alert.addButton(withTitle: L10n.t("update.alert.relaunch_now"))
        alert.addButton(withTitle: L10n.t("update.alert.later"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { relaunchNow() }
    }

    private func presentInstallFailedAlert(_ message: String, update: UpdateChecker.AvailableUpdate) {
        let alert = NSAlert()
        alert.messageText = L10n.t("update.alert.install_failed_title")
        alert.informativeText = message + "\n\n" + L10n.t("update.alert.install_failed_suffix")
        alert.addButton(withTitle: L10n.t("update.alert.open_release_page"))
        alert.addButton(withTitle: L10n.t("common.cancel"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(update.release.htmlURL)
        }
    }

    private func presentFailureAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = L10n.t("update.alert.check_failed_title")
        alert.informativeText = message
        alert.addButton(withTitle: L10n.t("update.alert.open_releases_page"))
        alert.addButton(withTitle: L10n.t("common.cancel"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(Self.releasesFallbackURL)
        }
    }
}
