// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Contains code derived from ShareX, Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE

import AppKit
import CaptureKit
import HistoryKit
import SharedKit
import UniformTypeIdentifiers
import UploadKit

// UploadKind and the destination capability table live in UploadKit
// (DestinationCatalog.swift), shared with the settings pickers.

@MainActor
enum UploadCoordinator {
    /// `settings` overrides the stored TaskSettings for this run (quick task
    /// presets, before-upload destination change); nil loads from disk.
    static func uploadImage(_ image: CGImage, fileName: String, filePath: String? = nil,
                            format: ImageFileFormat = .png, jpegQuality: Int = 90,
                            settings: TaskSettings? = nil) {
        guard let data = ImageWriter.data(image, format: format, jpegQuality: jpegQuality) else {
            Notifier.notify(title: L10n.t("notification.upload.failed"),
                            body: L10n.t("notification.upload.could_not_encode_image"), event: .error)
            return
        }
        upload(UploadFile(data: data, fileName: fileName, mimeType: format.mimeType),
               kind: .image, filePath: filePath, settingsOverride: settings)
    }

    /// Uploads an existing file (recordings, GIFs, arbitrary files), routed by
    /// extension: images use ImageDestination, text files TextDestination and
    /// everything else FileDestination — same split as Windows ShareX.
    static func uploadFile(at url: URL, settings: TaskSettings? = nil,
                           kind: UploadKind? = nil) {
        guard let data = try? Data(contentsOf: url) else {
            Notifier.notify(title: L10n.t("notification.upload.failed"),
                            body: L10n.t("notification.upload.could_not_read", url.lastPathComponent),
                            event: .error)
            return
        }
        let task = settings ?? TaskSettings.load()
        if ApplicationConfig.load().showLargeFileSizeWarning, data.count > largeFileWarningBytes {
            let alert = NSAlert()
            alert.messageText = L10n.t("alert.upload.large_file_question")
            alert.informativeText = L10n.t(
                "alert.upload.large_file_info", url.lastPathComponent,
                ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))
            alert.addButton(withTitle: L10n.t("alert.upload.upload_button"))
            alert.addButton(withTitle: L10n.t("common.cancel"))
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        upload(UploadFile(data: data, fileName: uploadName(for: url, task: task), mimeType:
                UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"),
               kind: kind ?? UploadKind.classify(fileExtension: url.pathExtension),
               filePath: url.path, settingsOverride: settings)
    }

    /// C# FileUploadUseNamePattern / FileUploadReplaceProblematicCharacters:
    /// the uploaded name (not the file on disk) follows the name pattern.
    static func uploadName(for url: URL, task: TaskSettings) -> String {
        var name = url.lastPathComponent
        if task.fileUploadUseNamePattern {
            let parser = NameParser.forTask(.fileName, settings: task)
            let parsed = parser.parse(task.nameFormatPattern)
            if !parsed.isEmpty {
                name = url.pathExtension.isEmpty ? parsed : parsed + "." + url.pathExtension
            }
        }
        if task.fileUploadReplaceProblematicCharacters {
            name = ResultURL.problematicCharactersReplaced(name)
        }
        return name
    }

    /// C# ShowMultiUploadWarning: confirm before firing a big batch. Callers
    /// pass the batch size; below the C# threshold (10) it never prompts.
    static func confirmMultiUpload(count: Int) -> Bool {
        guard count > 10, ApplicationConfig.load().showMultiUploadWarning else { return true }
        let alert = NSAlert()
        alert.messageText = L10n.t("alert.upload.multi_question", count)
        alert.informativeText = L10n.t("alert.upload.multi_info", count)
        alert.addButton(withTitle: L10n.t("alert.upload.upload_all_button"))
        alert.addButton(withTitle: L10n.t("common.cancel"))
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// C# LargeFileSizeWarning threshold (100 MB).
    private static let largeFileWarningBytes = 100 * 1024 * 1024

    /// Text uploads go out as a .txt file through the text destination;
    /// dedicated pastebin-style hosts are benched.
    static func uploadText(_ text: String) {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftx-\(UUID().uuidString).txt")
        try? Data(text.utf8).write(to: temp)
        uploadFile(at: temp, kind: .text)
    }

    /// Downloads a remote file into temp, then uploads it.
    static func downloadAndUpload(_ url: URL) async {
        guard let (data, response) = try? await URLSession.shared.data(from: url) else { return }
        // Cap the relay so a hostile or runaway URL can't spill a huge file to
        // disk or push it on to the upload destination.
        guard data.count <= maxDownloadBytes else {
            Notifier.notify(title: L10n.t("notification.upload.download_too_large"),
                            body: L10n.t("notification.upload.download_too_large_body",
                                         url.lastPathComponent, maxDownloadBytes / (1024 * 1024)))
            return
        }
        // suggestedFilename is attacker-influenced; keep only the last path
        // component so it can't steer the write outside the temp directory.
        let suggested = (response.suggestedFilename as NSString?)?.lastPathComponent
        let fallback = url.lastPathComponent.isEmpty ? "download" : url.lastPathComponent
        let name = (suggested?.isEmpty == false ? suggested! : fallback)
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        let destination = temp.appendingPathComponent(name)
        guard (try? data.write(to: destination)) != nil else { return }
        uploadFile(at: destination)
    }

    /// Ceiling for the browser/CLI download-and-upload relay (256 MB).
    private static let maxDownloadBytes = 256 * 1024 * 1024

    enum RoutingError: LocalizedError {
        case noCustomUploader
        case notImplemented(String)

        var errorDescription: String? {
            switch self {
            case .noCustomUploader:
                return L10n.t("notification.upload.error_no_custom_uploader")
            case .notImplemented(let destination):
                return L10n.t("notification.upload.error_not_implemented", destination)
            }
        }
    }

    /// Destination setting for an upload kind. Historical configs predate the
    /// text/file split, so text/file fall back to the image destination when
    /// they still hold their untouched "CustomTextUploader"/"CustomFileUploader"
    /// defaults but no matching custom uploader is configured — that keeps
    /// pre-split behavior (everything through the image destination) intact.
    static func destination(for kind: UploadKind, settings: TaskSettings,
                            config: UploadersConfig) -> String {
        switch kind {
        case .image:
            return settings.imageDestination
        case .text:
            if settings.textDestination == "CustomTextUploader",
               activeCustomUploaderName(for: .text, config: config).isEmpty {
                return settings.imageDestination
            }
            return settings.textDestination
        case .file:
            if settings.fileDestination == "CustomFileUploader",
               activeCustomUploaderName(for: .file, config: config).isEmpty {
                return settings.imageDestination
            }
            return settings.fileDestination
        }
    }

    /// Per-kind active .sxcu file name; text/file fall back to the image one.
    static func activeCustomUploaderName(for kind: UploadKind, config: UploadersConfig) -> String {
        switch kind {
        case .image:
            return config.activeCustomUploader
        case .text:
            return config.activeTextCustomUploader.isEmpty
                ? config.activeCustomUploader : config.activeTextCustomUploader
        case .file:
            return config.activeFileCustomUploader.isEmpty
                ? config.activeCustomUploader : config.activeFileCustomUploader
        }
    }

    private static func route(_ file: UploadFile, kind: UploadKind, settings: TaskSettings,
                              config: UploadersConfig) async throws -> (UploadResult, String) {
        switch destination(for: kind, settings: settings, config: config) {
        case "AmazonS3":
            return (try await AmazonS3Uploader.upload(file: file, settings: config.amazonS3), "Amazon S3")
        case "BackblazeB2":
            return (try await BackblazeB2Uploader.upload(file: file, config: config), "Backblaze B2")
        case "AzureStorage":
            return (try await AzureStorageUploader.upload(file: file, config: config), "Azure Storage")
        case "OwnCloud":
            return (try await OwnCloudUploader.upload(file: file, config: config), "ownCloud / Nextcloud")
        case "Seafile":
            return (try await SeafileUploader.upload(file: file, config: config), "Seafile")
        case "Pushbullet":
            return (try await PushbulletUploader.upload(file: file, config: config), "Pushbullet")
        case let dest where OAuthProviderID(rawValue: dest) != nil:
            // OAuth2 hosts: the uploader enforces the configured/authenticated
            // gate and throws a clear error until credentials + a connection exist.
            let id = OAuthProviderID(rawValue: dest)!
            return (try await OAuthUploaderRegistry.upload(id: id, file: file, config: config), id.displayName)
        case "CustomImageUploader", "CustomTextUploader", "CustomFileUploader":
            let name = activeCustomUploaderName(for: kind, config: config)
            guard let item = CustomUploaderStore.load(named: name) else {
                throw RoutingError.noCustomUploader
            }
            return (try await CustomUploaderService.upload(file: file, with: item), item.displayName)
        case let other:
            guard let destination = SimpleHostDestination(rawValue: other) else {
                throw RoutingError.notImplemented(other)
            }
            return (try await SimpleHostUploader.upload(file: file, destination: destination, config: config),
                    destination.displayName)
        }
    }

    private static func upload(_ file: UploadFile, kind: UploadKind, filePath: String?,
                               settingsOverride: TaskSettings? = nil, attempt: Int = 0) {
        let settings = settingsOverride ?? TaskSettings.load()
        let appConfig = ApplicationConfig.load()

        // C# DisableUpload master switch: tasks silently no-op (tray shows state)
        if appConfig.disableUpload {
            Notifier.notify(title: L10n.t("notification.upload.skipped"),
                            body: L10n.t("notification.upload.disabled_in_tray"))
            return
        }

        // C# WorkerTask: the before-upload window intercepts every upload
        // source (captures, recordings, files) right before dispatch
        if attempt == 0, settings.afterCaptureJob.contains(.showBeforeUploadWindow) {
            Task {
                guard var chosen = await BeforeUploadWindow.present(
                    fileName: file.fileName, previewData: file.data, settings: settings) else { return }
                chosen.afterCaptureJob.remove(.showBeforeUploadWindow)
                upload(file, kind: kind, filePath: filePath, settingsOverride: chosen)
            }
            return
        }

        let config = UploadersConfig.load()
        let entryID = UploadTaskCenter.shared.begin(
            fileName: file.fileName,
            host: destination(for: kind, settings: settings, config: config))
        let reporter = UploadProgressReporter { sent, expected in
            Task { @MainActor in
                UploadTaskCenter.shared.progress(entryID, sent: sent, expected: expected)
            }
        }

        let task = Task {
            // C# UploadLimit: bounded parallelism; extra tasks wait their turn
            await UploadGate.shared.acquire(limit: appConfig.uploadLimit)
            defer { UploadGate.shared.release() }
            do {
                let (result, hostName) = try await UploadProgressReporter.$current.withValue(reporter) {
                    try await route(file, kind: kind, settings: settings, config: config)
                }
                if let filePath {
                    await MainActor.run {
                        HistoryStore.shared.updateUploadURLs(
                            filePath: filePath, host: hostName, url: result.url,
                            thumbnailURL: result.thumbnailURL, deletionURL: result.deletionURL
                        )
                    }
                }
                await MainActor.run {
                    UploadTaskCenter.shared.finish(entryID, state: .completed(url: result.url))
                }
                try await afterUpload(result, settings: settings)
            } catch {
                if error is CancellationError || (error as? URLError)?.code == .cancelled {
                    await MainActor.run {
                        UploadTaskCenter.shared.finish(entryID, state: .failed(message: L10n.t("notification.upload.stopped")))
                    }
                    return
                }
                // misconfiguration won't fix itself in one second; only
                // transport/host failures earn a retry (C# MaxUploadFailRetry)
                let retryLimit = appConfig.retryUpload ? max(0, appConfig.maxUploadFailRetry) : 0
                if attempt < retryLimit, !(error is RoutingError) {
                    AppLog.upload.warning("Upload failed (\(error.localizedDescription, privacy: .public)); retry \(attempt + 1) of \(retryLimit)")
                    await MainActor.run {
                        UploadTaskCenter.shared.finish(entryID, state: .retrying)
                    }
                    try? await Task.sleep(for: .seconds(1))
                    await MainActor.run {
                        upload(file, kind: kind, filePath: filePath, settingsOverride: settingsOverride,
                               attempt: attempt + 1)
                    }
                    return
                }
                await MainActor.run {
                    UploadTaskCenter.shared.finish(entryID, state: .failed(message: error.localizedDescription))
                    Notifier.notify(title: L10n.t("notification.upload.failed"),
                                    body: error.localizedDescription, event: .error)
                }
            }
        }
        UploadTaskCenter.shared.register(entryID, task: task)
    }

    private static func afterUpload(_ result: UploadResult, settings: TaskSettings) async throws {
        let tasks = settings.afterUploadJob
        var finalURL = result.url

        // C# EarlyCopyURL: the raw URL lands on the clipboard the moment the
        // upload finishes, before shortening/post-processing can delay it.
        // The final (processed) copy below overwrites it.
        if settings.earlyCopyURL, tasks.contains(.copyURLToClipboard), !finalURL.isEmpty {
            copyString(finalURL)
        }

        // C# post-processing order: regex replace, force HTTPS, then shorten
        if settings.urlRegexReplace {
            finalURL = ResultURL.regexReplaced(finalURL, pattern: settings.urlRegexReplacePattern,
                                               replacement: settings.urlRegexReplaceReplacement)
        }
        if settings.resultForceHTTPS {
            finalURL = ResultURL.forcedHTTPS(finalURL)
        }

        let autoShorten = settings.autoShortenURLLength > 0 && finalURL.count > settings.autoShortenURLLength
        if tasks.contains(.useURLShortener) || autoShorten {
            let type = URLShortenerType(rawValue: settings.urlShortenerDestination) ?? .isgd
            do {
                finalURL = try await URLShortener.shorten(finalURL, type: type)
            } catch {
                Notifier.notify(title: L10n.t("notification.url_shortener.failed"),
                                body: error.localizedDescription,
                                event: .error)
            }
        }

        if tasks.contains(.copyURLToClipboard), !finalURL.isEmpty {
            // C# ClipboardContentFormat: $result template (Markdown, BBCode, …)
            copyString(ResultURL.format(settings.clipboardContentFormat, result: finalURL))
        }
        if tasks.contains(.openURL),
           let url = URL(string: ResultURL.format(settings.openURLFormat, result: finalURL)) {
            NSWorkspace.shared.open(url)
        }
        if tasks.contains(.shareURL) {
            let service = URLSharingService(rawValue: settings.urlSharingServiceDestination) ?? .email
            if let url = service.shareURL(for: finalURL) {
                NSWorkspace.shared.open(url)
            }
        }

        if tasks.contains(.showQRCode), !finalURL.isEmpty {
            ToolWindows.showQRCode(text: finalURL)
        }
        if tasks.contains(.showAfterUploadWindow) {
            AfterUploadWindow.present(result: result, finalURL: finalURL)
        }

        Notifier.notify(title: L10n.t("notification.upload.complete"),
                        body: ResultURL.format(settings.balloonTipContentFormat, result: finalURL),
                        sound: settings.playSoundAfterUpload, url: finalURL, event: .taskCompleted)
    }

    private static func copyString(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }
}

/// C# UploadLimit: a MainActor counting gate. Tasks over the limit suspend in
/// FIFO order until a running upload releases its slot.
@MainActor
final class UploadGate {
    static let shared = UploadGate()

    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire(limit: Int) async {
        if active < max(1, limit) {
            active += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
        active += 1
    }

    func release() {
        active = max(0, active - 1)
        if !waiters.isEmpty {
            waiters.removeFirst().resume()
        }
    }
}
