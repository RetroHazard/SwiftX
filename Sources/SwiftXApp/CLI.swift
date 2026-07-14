// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt
//
// CLI verbs (C# ShareXCLIManager): -HotkeyTypeName [file], -workflow name,
// -CustomUploader x.sxcu, -ImageEffect x.sxie, -NativeMessagingInput x.json,
// and bare paths/URLs which upload. A second instance forwards its arguments
// to the running one over distributed notifications and exits.

import AppKit
import EffectsKit
import SharedKit
import UploadKit

@MainActor
enum CLI {
    /// argv minus the executable and launch noise.
    nonisolated static func relevantArguments(_ argv: [String] = CommandLine.arguments) -> [String] {
        Array(argv.dropFirst()).filter { $0 != "--capture-selftest" && !$0.hasPrefix("-psn_") }
    }

    static func handle(_ args: [String]) async {
        for command in CLIParser.parse(args) {
            if command.isCommand {
                await run(command)
            } else if let url = URL(string: command.command),
                      ["http", "https"].contains(url.scheme?.lowercased()) {
                await UploadCoordinator.downloadAndUpload(url)
            } else {
                let path = absolutePath(command.command)
                if FileManager.default.fileExists(atPath: path) {
                    UploadCoordinator.uploadFile(at: URL(fileURLWithPath: path))
                }
            }
        }
    }

    private static func run(_ command: CLICommand) async {
        if command.matches("CustomUploader") {
            if let parameter = command.parameter, parameter.lowercased().hasSuffix(".sxcu") {
                _ = try? CustomUploaderStore.importFile(from: URL(fileURLWithPath: absolutePath(parameter)))
            }
        } else if command.matches("ImageEffect") {
            if let parameter = command.parameter, parameter.lowercased().hasSuffix(".sxie"),
               let data = try? Data(contentsOf: URL(fileURLWithPath: absolutePath(parameter))),
               let preset = try? ImageEffectPreset.fromConfigJSON(data) {
                ImageEffectsStore.shared.presets.append(preset)
                ImageEffectsStore.shared.save()
            }
        } else if command.matches("NativeMessagingInput") {
            if let parameter = command.parameter, parameter.lowercased().hasSuffix(".json") {
                await handleNativeMessagingInput(fileAt: URL(fileURLWithPath: absolutePath(parameter)))
            }
        } else if command.matches("workflow") {
            // C# matches configured hotkeys by name; ours are named by job type
            guard let name = command.parameter else { return }
            if let config = HotkeySettings.load().hotkeys.first(where: { $0.type?.rawValue == name }),
               let type = config.type, type != .none {
                execute(type, filePath: nil)
            }
        } else if let type = HotkeyType.allCases.first(where: { command.matches($0.rawValue) }) {
            var filePath: String?
            if let parameter = command.parameter {
                let path = absolutePath(parameter)
                guard FileManager.default.fileExists(atPath: path) else { return } // C# aborts the job
                filePath = path
            }
            execute(type, filePath: filePath)
        }
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
    /// deleted after reading, like C# HandleNativeMessagingInput.
    private static func handleNativeMessagingInput(fileAt url: URL) async {
        struct Input: Decodable {
            var URL: String?
            var Text: String?
        }
        defer { try? FileManager.default.removeItem(at: url) }
        guard let data = try? Data(contentsOf: url),
              let input = try? JSONDecoder().decode(Input.self, from: data) else { return }
        if let link = input.URL, let remote = Foundation.URL(string: link),
           ["http", "https"].contains(remote.scheme?.lowercased()) {
            await UploadCoordinator.downloadAndUpload(remote)
        } else if let text = input.Text, !text.isEmpty {
            UploadCoordinator.uploadText(text)
        }
    }

    private static func absolutePath(_ path: String) -> String {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath).path
    }
}

/// IPC between the running instance and later invocations.
enum CLIRelay {
    private static let notification = Notification.Name("com.getsharex.swiftx.cli")

    /// Primary instance: run arguments forwarded by later invocations.
    @MainActor static func startListening() {
        DistributedNotificationCenter.default().addObserver(
            forName: notification, object: nil, queue: .main
        ) { note in
            guard let json = note.object as? String,
                  let args = try? JSONDecoder().decode([String].self, from: Data(json.utf8)),
                  !args.isEmpty else { return }
            Task { @MainActor in await CLI.handle(args) }
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
