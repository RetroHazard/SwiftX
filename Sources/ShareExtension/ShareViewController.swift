// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE
//
// The macOS Share menu ("Share…" in Finder, Safari, Preview, Photos, and the
// share button in any app that has one) is driven by com.apple.share-services
// app extensions, not by NSServices — which is why the "Upload with SwiftX"
// Services entry never showed up there. This is that extension.
//
// It deliberately does no uploading of its own: destinations, credentials
// (Keychain), history and the after-upload chain all live in the app. The
// extension only confirms what is about to be uploaded, stages copies inside
// its sandbox container, and wakes the app — see SharedKit/ShareInbox.swift
// for the handoff contract.

import AppKit
import SharedKit
import UniformTypeIdentifiers

@MainActor
@objc(ShareViewController)
final class ShareViewController: NSViewController {
    /// One shared thing, already resolved to something we can stage.
    private enum Payload {
        case file(URL)
        case data(Data, name: String)
        case text(String)
        case webURL(URL)

        var displayName: String {
            switch self {
            case .file(let url): return url.lastPathComponent
            case .data(_, let name): return name
            case .webURL(let url): return url.absoluteString
            case .text(let text): return text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }

    private let titleLabel = NSTextField(labelWithString: "Upload with SwiftX")
    private let summaryLabel = NSTextField(wrappingLabelWithString: "Collecting…")
    private let spinner = NSProgressIndicator()
    private let uploadButton = NSButton(title: "Upload", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private var payloads: [Payload] = []

    // MARK: - View

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 176))

        titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)

        summaryLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        summaryLabel.textColor = .secondaryLabelColor
        summaryLabel.maximumNumberOfLines = 6
        summaryLabel.lineBreakMode = .byTruncatingMiddle
        summaryLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.startAnimation(nil)

        let icon = NSImageView()
        icon.image = Bundle.main.image(forResource: "SwiftX")
            ?? NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: nil)
        icon.imageScaling = .scaleProportionallyUpOrDown

        uploadButton.target = self
        uploadButton.action = #selector(upload)
        uploadButton.keyEquivalent = "\r"
        uploadButton.bezelStyle = .rounded
        uploadButton.isEnabled = false

        cancelButton.target = self
        cancelButton.action = #selector(cancel)
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.bezelStyle = .rounded

        let buttons = NSStackView(views: [cancelButton, uploadButton])
        buttons.orientation = .horizontal
        buttons.spacing = 12

        for subview in [icon, titleLabel, summaryLabel, spinner, buttons] as [NSView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(subview)
        }

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            icon.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            icon.widthAnchor.constraint(equalToConstant: 48),
            icon.heightAnchor.constraint(equalToConstant: 48),

            titleLabel.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            titleLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),

            summaryLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            summaryLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            summaryLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),

            spinner.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            spinner.centerYAnchor.constraint(equalTo: buttons.centerYAnchor),

            buttons.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            buttons.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
            buttons.topAnchor.constraint(greaterThanOrEqualTo: summaryLabel.bottomAnchor, constant: 16)
        ])

        view = root
        preferredContentSize = root.frame.size
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard payloads.isEmpty else { return } // the host may re-present the sheet
        Task { await collect() }
    }

    // MARK: - Actions

    private enum HandoffError: LocalizedError {
        case swiftXUnreachable

        var errorDescription: String? {
            "SwiftX could not be opened — check that SwiftX.app is still installed."
        }
    }

    @objc private func upload() {
        uploadButton.isEnabled = false
        cancelButton.isEnabled = false
        do {
            let directory = try stage(payloads)
            // Wakes (or launches) SwiftX, which resolves the id inside this
            // extension's container and runs the normal upload pipeline.
            guard let url = URL(string: "swiftx://\(ShareInbox.verb)/\(directory.lastPathComponent)"),
                  NSWorkspace.shared.open(url) else {
                try? FileManager.default.removeItem(at: directory) // don't leave user data behind
                throw HandoffError.swiftXUnreachable
            }
            extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        } catch {
            fail(error)
        }
    }

    @objc private func cancel() {
        extensionContext?.cancelRequest(
            withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
    }

    private func fail(_ error: Error) {
        spinner.stopAnimation(nil)
        spinner.isHidden = true
        cancelButton.isEnabled = true
        cancelButton.title = "Close"
        summaryLabel.stringValue = error.localizedDescription
    }

    // MARK: - Collecting

    private func collect() async {
        let providers = ((extensionContext?.inputItems as? [NSExtensionItem]) ?? [])
            .flatMap { $0.attachments ?? [] }

        var files: [Payload] = []
        var links: [Payload] = []
        var texts: [String] = []
        for provider in providers {
            guard let resolved = await payload(from: provider) else { continue }
            switch resolved {
            case .file, .data: files.append(resolved)
            case .webURL: links.append(resolved)
            case .text(let text): texts.append(text)
            }
        }

        // Precedence mirrors UploadActions.clipboardUpload: hosts routinely
        // attach a page title or a file name alongside the real payload, so
        // files win over links, and links win over loose text.
        if !files.isEmpty {
            payloads = files
        } else if let link = links.first {
            payloads = [link]
        } else {
            let joined = texts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            payloads = joined.isEmpty ? [] : [.text(joined)]
        }

        spinner.stopAnimation(nil)
        spinner.isHidden = true
        guard !payloads.isEmpty else {
            summaryLabel.stringValue = "Nothing here that SwiftX can upload."
            cancelButton.title = "Close"
            return
        }
        summaryLabel.stringValue = payloads.prefix(5).map(\.displayName).joined(separator: "\n")
            + (payloads.count > 5 ? "\nand \(payloads.count - 5) more…" : "")
        uploadButton.isEnabled = true
        view.window?.makeFirstResponder(uploadButton)
    }

    private func payload(from provider: NSItemProvider) async -> Payload? {
        // A file URL is the cheapest and highest-fidelity form: we copy the
        // bytes ourselves rather than round-tripping them through the host.
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
           let url = await loadURL(provider, type: UTType.fileURL.identifier), url.isFileURL {
            return .file(url)
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
           let url = await loadURL(provider, type: UTType.url.identifier) {
            if url.isFileURL { return .file(url) }
            if let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) {
                return .webURL(url)
            }
        }
        // Anything with bytes but no file behind it (a Photos image, a PDF page
        // selection) arrives as a data representation.
        if let type = dataType(for: provider),
           let data = await loadData(provider, type: type.identifier) {
            return .data(data, name: fileName(for: provider, type: type))
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
           let text = await loadText(provider), !text.isEmpty {
            return .text(text)
        }
        return nil
    }

    /// The most specific concrete type the provider offers, preferring images
    /// and movies so a screenshot keeps its own extension instead of `.dat`.
    private func dataType(for provider: NSItemProvider) -> UTType? {
        let identifiers = provider.registeredTypeIdentifiers.compactMap { UTType($0) }
        if let match = identifiers.first(where: { $0.conforms(to: .image) || $0.conforms(to: .movie) }) {
            return match
        }
        // Text and URLs conform to public.data too, but both are handled above
        // as their own payload kinds rather than staged as files.
        return identifiers.first {
            $0.conforms(to: .data) && !$0.conforms(to: .text) && !$0.conforms(to: .url)
        }
    }

    private func fileName(for provider: NSItemProvider, type: UTType) -> String {
        let suggested = (provider.suggestedName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let base = suggested.isEmpty ? "Shared" : suggested
        guard let ext = type.preferredFilenameExtension else { return base }
        return (base as NSString).pathExtension.caseInsensitiveCompare(ext) == .orderedSame
            ? base
            : base + "." + ext
    }

    // MARK: - NSItemProvider bridging

    private func loadURL(_ provider: NSItemProvider, type: String) async -> URL? {
        await withCheckedContinuation { continuation in
            // loadItem hands back a bridged Foundation object; which one
            // depends on the host, so all three shapes a URL arrives in are
            // accepted. Casting to the NS types keeps this a plain class
            // check rather than a bridging conversion off an existential.
            provider.loadItem(forTypeIdentifier: type, options: nil) { value, _ in
                if let url = value as? NSURL {
                    continuation.resume(returning: url as URL)
                } else if let data = value as? NSData {
                    continuation.resume(
                        returning: URL(dataRepresentation: data as Data, relativeTo: nil))
                } else if let string = value as? NSString {
                    continuation.resume(returning: URL(string: string as String))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func loadData(_ provider: NSItemProvider, type: String) async -> Data? {
        await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: type) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    private func loadText(_ provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { value, _ in
                if let string = value as? NSString {
                    continuation.resume(returning: string as String)
                } else if let data = value as? NSData {
                    continuation.resume(returning: String(data: data as Data, encoding: .utf8))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    // MARK: - Staging

    /// Copies every payload into a fresh request directory in this extension's
    /// sandbox container, writes the manifest the app reads back, and returns
    /// that directory (its name is the request id).
    private func stage(_ payloads: [Payload]) throws -> URL {
        let id = UUID()
        // Inside a sandboxed extension NSHomeDirectory() is the container's
        // Data directory, which is exactly what ShareInbox resolves from the
        // app side under the real home.
        let directory = ShareInbox
            .spoolRoot(containerHome: URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true))
            .appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var request = ShareInbox.Request()
        var used: Set<String> = []
        for payload in payloads {
            switch payload {
            case .file(let source):
                // Shared files come with a sandbox extension attached; the
                // startAccessing pair is a no-op when one was not needed.
                let scoped = source.startAccessingSecurityScopedResource()
                defer { if scoped { source.stopAccessingSecurityScopedResource() } }
                let name = uniqueName(source.lastPathComponent, used: &used)
                try FileManager.default.copyItem(at: source, to: directory.appendingPathComponent(name))
                request.files.append(name)
            case .data(let data, let suggested):
                let name = uniqueName(suggested, used: &used)
                try data.write(to: directory.appendingPathComponent(name))
                request.files.append(name)
            case .text(let text):
                request.text = text
            case .webURL(let url):
                request.webURL = url.absoluteString
            }
        }

        let manifest = directory.appendingPathComponent(ShareInbox.manifestName)
        try JSONEncoder().encode(request).write(to: manifest)
        return directory
    }

    /// Staged names must survive ``ShareInbox/isSafeStagedName(_:)`` and not
    /// collide — two Finder selections can easily both hold a `Screenshot.png`.
    private func uniqueName(_ proposed: String, used: inout Set<String>) -> String {
        var name = proposed.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while name.hasPrefix(".") { name.removeFirst() }
        if name.isEmpty { name = "Shared" }
        guard used.contains(name) else {
            used.insert(name)
            return name
        }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        for suffix in 2...999 {
            let candidate = ext.isEmpty ? "\(base) \(suffix)" : "\(base) \(suffix).\(ext)"
            if !used.contains(candidate) {
                used.insert(candidate)
                return candidate
            }
        }
        let fallback = UUID().uuidString
        used.insert(fallback)
        return fallback
    }
}
