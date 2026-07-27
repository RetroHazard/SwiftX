// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE
//
// macOS Services provider: puts "Upload with SwiftX" in the Services section
// of the context menu system-wide — Finder file selections and selected text
// in any app. The service itself is declared in the app bundle's Info.plist
// (NSServices, written by Scripts/make-app.sh); this class receives the calls.
//
// This is the right-click Services flow only. The "Share…" menu is a separate
// system — com.apple.share-services extensions — handled by the embedded
// SwiftXShare.appex (Sources/ShareExtension) and ShareRequests.

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
