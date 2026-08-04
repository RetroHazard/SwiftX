// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Contains code derived from ShareX, Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE
//
// CLI verbs (C# ShareXCLIManager): -HotkeyTypeName [file], -workflow name,
// -CustomUploader x.sxcu, -ImageEffect x.sxie, -NativeMessagingInput x.json,
// and bare paths/URLs which upload. A second instance forwards its arguments
// to the running one over distributed notifications and exits.

import AppKit
import EffectsKit
import SharedKit
import UploadKit

/// Where a batch of CLI arguments came from, which decides how much we trust
/// them. `trusted` is our own process launch argv. `untrusted` is anything that
/// crosses a process/security boundary we don't control: the `swiftx://` URL
/// scheme (any web page can open one) and the cross-process single-instance
/// relay (any local process can post to it). Untrusted input may trigger the
/// safe, parameterless verbs a user could already fire from the menu, but it
/// must never silently read or upload a local file, import an uploader/effect
/// preset, or download-and-upload an arbitrary URL — each of those requires an
/// explicit confirmation showing exactly what was asked.
enum CLISource {
    case trusted
    case untrusted
}

@MainActor
enum CLI {
    /// argv minus the executable and launch noise.
    nonisolated static func relevantArguments(_ argv: [String] = CommandLine.arguments) -> [String] {
        Array(argv.dropFirst()).filter { $0 != "--capture-selftest" && !$0.hasPrefix("-psn_") }
    }

    static func handle(_ args: [String], source: CLISource = .trusted) async {
        for command in CLIParser.parse(args) {
            if command.isCommand {
                await run(command, source: source)
            } else if let url = URL(string: command.command),
                      ["http", "https"].contains(url.scheme?.lowercased()) {
                // A bare URL means "download this and upload it" — never on
                // behalf of an untrusted caller (SSRF / exfil relay).
                guard source == .trusted else {
                    denied(L10n.t("notification.cli.action_download_and_upload", url.absoluteString))
                    continue
                }
                await UploadCoordinator.downloadAndUpload(url)
            } else {
                // A bare path means "upload this local file" — the classic
                // exfil primitive; only our own launch argv may do it.
                guard source == .trusted else {
                    denied(L10n.t("notification.cli.action_upload_local_file", command.command))
                    continue
                }
                let path = absolutePath(command.command)
                if FileManager.default.fileExists(atPath: path) {
                    UploadCoordinator.uploadFile(at: URL(fileURLWithPath: path))
                }
            }
        }
    }

    private static func run(_ command: CLICommand, source: CLISource) async {
        if command.matches("CustomUploader") {
            guard let parameter = command.parameter, parameter.lowercased().hasSuffix(".sxcu") else { return }
            let url = URL(fileURLWithPath: absolutePath(parameter))
            guard await confirmIfUntrusted(source,
                action: L10n.t("alert.cli.action_import_custom_uploader", url.path)) else { return }
            _ = try? CustomUploaderStore.importFile(from: url)
        } else if command.matches("ImageEffect") {
            guard let parameter = command.parameter, parameter.lowercased().hasSuffix(".sxie") else { return }
            let url = URL(fileURLWithPath: absolutePath(parameter))
            guard await confirmIfUntrusted(source,
                action: L10n.t("alert.cli.action_import_image_effect", url.path)) else { return }
            if let data = try? Data(contentsOf: url),
               let preset = try? ImageEffectPreset.fromConfigJSON(data) {
                ImageEffectsStore.shared.presets.append(preset)
                ImageEffectsStore.shared.save()
            }
        } else if command.matches(ShareInbox.verb) {
            // Share extension handoff. The parameter is a UUID naming a request
            // directory inside the extension's sandbox container; ShareRequests
            // derives every path itself, so an untrusted caller cannot aim this
            // at a file of its choosing (see ShareRequests.swift).
            if let parameter = command.parameter {
                ShareRequests.handle(id: parameter)
            }
        } else if command.matches("NativeMessagingInput") {
            if let parameter = command.parameter, parameter.lowercased().hasSuffix(".json") {
                await handleNativeMessagingInput(fileAt: URL(fileURLWithPath: absolutePath(parameter)), source: source)
            }
        } else if command.matches("workflow") {
            // C# matches configured hotkeys by name; ours are named by job type
            guard let name = command.parameter else { return }
            if let config = HotkeySettings.load().hotkeys.first(where: { $0.type?.rawValue == name }),
               let type = config.type, type != .none {
                await executeGated(type, filePath: nil, source: source)
            }
        } else if let type = HotkeyType.allCases.first(where: { command.matches($0.rawValue) }) {
            var filePath: String?
            if let parameter = command.parameter {
                let path = absolutePath(parameter)
                guard FileManager.default.fileExists(atPath: path) else { return } // C# aborts the job
                filePath = path
            }
            await executeGated(type, filePath: filePath, source: source)
        }
    }

    /// Parameterless verbs that still send local data off the machine with no
    /// UI of their own, so an untrusted caller must confirm. (ClipboardUpload
    /// silently uploads whatever is on the pasteboard — which can be a password;
    /// the *WithContentViewer* variant shows its own preview + confirm, so it is
    /// not listed here.)
    private static let silentExfilVerbs: Set<HotkeyType> = [.clipboardUpload]

    /// Runs a verb, gating anything that reads/exfiltrates local data when the
    /// caller is untrusted: a verb carrying a local file path (the path is shown
    /// in the prompt), or a silent data-out verb like ClipboardUpload.
    private static func executeGated(_ type: HotkeyType, filePath: String?, source: CLISource) async {
        if let filePath {
            guard await confirmIfUntrusted(source,
                action: L10n.t("alert.cli.action_run_on_file", type.rawValue, filePath)) else { return }
        } else if silentExfilVerbs.contains(type) {
            guard await confirmIfUntrusted(source,
                action: L10n.t("alert.cli.action_run_clipboard_upload", type.rawValue)) else { return }
        }
        execute(type, filePath: filePath)
    }

    /// Returns true if the action may proceed. Trusted callers always may;
    /// untrusted callers get a warning alert defaulting to Cancel.
    private static func confirmIfUntrusted(_ source: CLISource, action: String) async -> Bool {
        guard source == .untrusted else { return true }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.t("alert.cli.allow_action_question")
        alert.informativeText = L10n.t("alert.cli.allow_action_info", action)
        // First button is the default; make Cancel the default so a stray
        // Return keypress denies rather than approves.
        alert.addButton(withTitle: L10n.t("common.cancel"))
        alert.addButton(withTitle: L10n.t("common.continue"))
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertSecondButtonReturn
    }

    private static func denied(_ action: String) {
        AppLog.app.warning("Ignored an untrusted request to \(action, privacy: .public)")
        Notifier.notify(title: L10n.t("notification.cli.blocked_request"),
                        body: L10n.t("notification.cli.blocked_request_body", action))
    }

    private static func execute(_ type: HotkeyType, filePath: String?) {
        // ponytail: C# threads filePath into every job; only file upload uses
        // it here - extend the switch when other jobs need a file argument
        if let filePath, type == .fileUpload {
            UploadCoordinator.uploadFile(at: URL(fileURLWithPath: filePath))
            return
        }
        HotkeyDispatcher.execute(type)
    }

    /// Browser extension payload: {Action, URL, Text}. The temp file is
    /// deleted after reading, like C# HandleNativeMessagingInput. The payload
    /// reaches us through the cross-process relay, so it is untrusted: the
    /// actual URL/text is shown for confirmation before anything leaves the
    /// machine (the browser-manifest allowed_origins gate is not by itself a
    /// user consent).
    private static func handleNativeMessagingInput(fileAt url: URL, source: CLISource) async {
        struct Input: Decodable {
            var URL: String?
            var Text: String?
        }
        defer { try? FileManager.default.removeItem(at: url) }
        guard let data = try? Data(contentsOf: url),
              let input = try? JSONDecoder().decode(Input.self, from: data) else { return }
        if let link = input.URL, let remote = Foundation.URL(string: link),
           ["http", "https"].contains(remote.scheme?.lowercased()) {
            guard await confirmIfUntrusted(source,
                action: L10n.t("alert.cli.action_browser_download_upload", remote.absoluteString)) else { return }
            await UploadCoordinator.downloadAndUpload(remote)
        } else if let text = input.Text, !text.isEmpty {
            guard await confirmIfUntrusted(source,
                action: L10n.t("alert.cli.action_browser_upload_text")) else { return }
            UploadCoordinator.uploadText(text)
        }
    }

    private static func absolutePath(_ path: String) -> String {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath).path
    }
}

/// IPC between the running instance and later invocations.
enum CLIRelay {
    private static let notification = Notification.Name("com.retrohazard.swiftx.cli")

    /// Primary instance: run arguments forwarded by later invocations.
    @MainActor static func startListening() {
        DistributedNotificationCenter.default().addObserver(
            forName: notification, object: nil, queue: .main
        ) { note in
            guard let json = note.object as? String,
                  let args = try? JSONDecoder().decode([String].self, from: Data(json.utf8)),
                  !args.isEmpty else { return }
            // DistributedNotificationCenter is a system-wide, unauthenticated
            // channel — any local process can post here — so forwarded argv is
            // untrusted and cannot silently touch local files.
            Task { @MainActor in await CLI.handle(args, source: .untrusted) }
        }
    }

    /// Secondary instance: hand argv to the primary before exiting.
    static func forward(_ args: [String]) {
        guard !args.isEmpty, let data = try? JSONEncoder().encode(args) else { return }
        DistributedNotificationCenter.default().postNotificationName(
            notification, object: String(decoding: data, as: UTF8.self),
            userInfo: nil, deliverImmediately: true)
    }
}
