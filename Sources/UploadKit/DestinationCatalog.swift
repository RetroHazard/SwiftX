// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Contains code derived from ShareX, Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE
//
// One table of every selectable upload destination and the upload kinds it
// accepts. The image/text/file destination pickers all read from here, so a
// host only appears in the slots it can actually serve — YouTube takes video,
// not a .txt, and image hosts reject archives.
//
// Kinds follow ShareX's uploader-type split: hosts ShareX lists only under
// EImageUploaderType stay image-only, the video hosts it lists only under
// EFileUploaderType stay file-only, and general file storage takes all three.
// SwiftX sends text as a .txt file, so any host that accepts arbitrary files
// serves the text slot too (dedicated pastebins are benched — see
// UploadCoordinator.uploadText).

import Foundation
import SharedKit

/// Which destination setting an upload routes through, mirroring the C#
/// ImageDestination / TextDestination / FileDestination split.
public enum UploadKind: String, CaseIterable, Sendable {
    case image, text, file

    /// Label for the slot, used where a destination has to explain itself.
    public var displayName: String {
        switch self {
        case .image: return L10n.t("destination.kind.image")
        case .text: return L10n.t("destination.kind.text")
        case .file: return L10n.t("destination.kind.file")
        }
    }

    /// C# EDataType-style classification by extension: captures and pictures
    /// route as images, text-y files as text, everything else (recordings,
    /// archives, …) as files.
    public static func classify(fileExtension ext: String) -> UploadKind {
        let lowered = ext.lowercased()
        if imageExtensions.contains(lowered) { return .image }
        if textExtensions.contains(lowered) { return .text }
        return .file
    }

    /// C# TaskSettingsAdvanced.ImageExtensions / TextExtensions defaults.
    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "bmp", "ico", "tif", "tiff", "webp", "heic"
    ]
    private static let textExtensions: Set<String> = [
        "txt", "log", "nfo", "md", "json", "xml", "csv", "html", "htm", "css",
        "js", "ts", "c", "cpp", "cc", "h", "hpp", "cs", "java", "kt", "swift",
        "py", "rb", "php", "pl", "sh", "zsh", "bash", "yaml", "yml", "toml", "ini"
    ]
}

/// A destination as the settings pickers see it: the string persisted in
/// TaskSettings, its label, and the slots it can serve.
public struct UploadDestination: Sendable, Hashable, Identifiable {
    /// The raw value stored in TaskSettings.imageDestination and friends.
    public let id: String
    public let displayName: String
    public let kinds: Set<UploadKind>

    public init(id: String, displayName: String, kinds: Set<UploadKind>) {
        self.id = id
        self.displayName = displayName
        self.kinds = kinds
    }

    public func supports(_ kind: UploadKind) -> Bool { kinds.contains(kind) }
}

public enum DestinationCatalog {
    /// Hosts that take arbitrary files, so they serve every slot.
    private static let anyFile = Set(UploadKind.allCases)

    /// The per-slot custom-uploader sentinels (C# enum member names). Each is
    /// offered only in its own slot; the .sxcu behind it decides what it takes.
    public static let customUploaderTags: Set<String> = [
        "CustomImageUploader", "CustomTextUploader", "CustomFileUploader"
    ]

    /// Every destination, in picker order. The custom-uploader sentinel for a
    /// slot leads, then general storage, then the specialised hosts.
    public static let all: [UploadDestination] = [
        UploadDestination(id: "CustomImageUploader", displayName: L10n.t("destination.custom_uploader"), kinds: [.image]),
        UploadDestination(id: "CustomTextUploader", displayName: L10n.t("destination.custom_uploader"), kinds: [.text]),
        UploadDestination(id: "CustomFileUploader", displayName: L10n.t("destination.custom_uploader"), kinds: [.file]),

        // General-purpose storage and file hosts: any kind.
        UploadDestination(id: "AmazonS3", displayName: "Amazon S3", kinds: anyFile),
        UploadDestination(id: "BackblazeB2", displayName: "Backblaze B2", kinds: anyFile),
        UploadDestination(id: "AzureStorage", displayName: "Azure Storage", kinds: anyFile),
        UploadDestination(id: "OwnCloud", displayName: "ownCloud / Nextcloud", kinds: anyFile),
        UploadDestination(id: "Seafile", displayName: "Seafile", kinds: anyFile),
        UploadDestination(id: "Pushbullet", displayName: "Pushbullet", kinds: anyFile),
        UploadDestination(id: OAuthProviderID.googleDrive.rawValue,
                          displayName: OAuthProviderID.googleDrive.displayName, kinds: anyFile),
        UploadDestination(id: OAuthProviderID.oneDrive.rawValue,
                          displayName: OAuthProviderID.oneDrive.displayName, kinds: anyFile),
        UploadDestination(id: SimpleHostDestination.uguu.rawValue,
                          displayName: SimpleHostDestination.uguu.displayName, kinds: anyFile),
        UploadDestination(id: SimpleHostDestination.pomf.rawValue,
                          displayName: SimpleHostDestination.pomf.displayName, kinds: anyFile),
        UploadDestination(id: SimpleHostDestination.sul.rawValue,
                          displayName: SimpleHostDestination.sul.displayName, kinds: anyFile),
        UploadDestination(id: SimpleHostDestination.lobfile.rawValue,
                          displayName: SimpleHostDestination.lobfile.displayName, kinds: anyFile),
        UploadDestination(id: SimpleHostDestination.puush.rawValue,
                          displayName: SimpleHostDestination.puush.displayName, kinds: anyFile),

        // Image hosts: they reject anything that isn't a picture.
        UploadDestination(id: SimpleHostDestination.chevereto.rawValue,
                          displayName: SimpleHostDestination.chevereto.displayName, kinds: [.image]),
        UploadDestination(id: SimpleHostDestination.vgyme.rawValue,
                          displayName: SimpleHostDestination.vgyme.displayName, kinds: [.image]),

        // Video hosts: recordings and other media arrive as file uploads.
        UploadDestination(id: OAuthProviderID.youTube.rawValue,
                          displayName: OAuthProviderID.youTube.displayName, kinds: [.file]),
        UploadDestination(id: SimpleHostDestination.streamable.rawValue,
                          displayName: SimpleHostDestination.streamable.displayName, kinds: [.file])
    ]

    private static let byID: [String: UploadDestination] =
        Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

    public static func destination(id: String) -> UploadDestination? { byID[id] }

    /// The destinations offered in a slot's picker, in catalog order.
    public static func available(for kind: UploadKind) -> [UploadDestination] {
        all.filter { $0.supports(kind) }
    }

    /// False only for a destination we know can't serve the slot. Unknown ids
    /// (a Windows config naming a host SwiftX doesn't implement, say) are left
    /// alone rather than reported as unsupported — routing already rejects them
    /// with a clearer error.
    public static func supports(_ id: String, kind: UploadKind) -> Bool {
        byID[id]?.supports(kind) ?? true
    }

    /// Catalog label, falling back to the raw id for anything unrecognised.
    public static func displayName(for id: String) -> String {
        byID[id]?.displayName ?? id
    }
}
