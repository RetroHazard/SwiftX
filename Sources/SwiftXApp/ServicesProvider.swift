// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE
//
// macOS Services provider: puts "Upload with SwiftX" in the Services section
// of the context menu system-wide — Finder file selections and selected text
// in any app. The service itself is declared in the app bundle's Info.plist
// (NSServices, written by Scripts/make-app.sh); this class receives the calls.
// A true Share-sheet extension (.appex) needs an embedded extension bundle,
// which the SPM bundling pipeline doesn't produce yet — Services give the
// same right-click flow without one.

import AppKit

final class ServicesProvider: NSObject {
    /// Selector name "uploadFiles" matches NSMessage in the NSServices entry;
    /// AppKit resolves it to uploadFiles:userData:error:. Handles both send
    /// types the service declares: file URLs and plain text.
    @MainActor
    @objc func uploadFiles(_ pasteboard: NSPasteboard, userData: String,
                           error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let urls = (pasteboard.readObjects(forClasses: [NSURL.self],
                                           options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        if !urls.isEmpty {
            guard UploadCoordinator.confirmMultiUpload(count: urls.count) else { return }
            urls.forEach { UploadCoordinator.uploadFile(at: $0) }
            return
        }
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            UploadCoordinator.uploadText(text)
            return
        }
        error.pointee = "Nothing to upload: the selection has no files or text." as NSString
    }
}
