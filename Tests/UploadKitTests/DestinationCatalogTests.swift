// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE
//
// The catalog decides which hosts each destination picker offers, so a gap
// here silently removes a working host from the UI (or offers one that can't
// serve the slot). These tests pin both the coverage and the per-kind rules.

import Foundation
import Testing
@testable import SharedKit
@testable import UploadKit

struct DestinationCatalogTests {
    /// A host added to either enum but not the catalog would vanish from every
    /// picker while still routing fine — the failure mode this guards.
    @Test func catalogCoversEverySimpleHostAndOAuthProvider() {
        for host in SimpleHostDestination.allCases {
            #expect(DestinationCatalog.destination(id: host.rawValue) != nil,
                    "SimpleHostDestination.\(host.rawValue) is missing from the catalog")
        }
        for provider in OAuthProviderID.allCases {
            #expect(DestinationCatalog.destination(id: provider.rawValue) != nil,
                    "OAuthProviderID.\(provider.rawValue) is missing from the catalog")
        }
    }

    @Test func everyDestinationServesAtLeastOneKind() {
        for destination in DestinationCatalog.all {
            #expect(!destination.kinds.isEmpty, "\(destination.id) serves no upload kind")
        }
    }

    @Test func catalogIDsAreUnique() {
        let ids = DestinationCatalog.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    /// The point of the split: video hosts only appear for file uploads.
    @Test func videoHostsAreFileOnly() {
        for id in [OAuthProviderID.youTube.rawValue, SimpleHostDestination.streamable.rawValue] {
            #expect(DestinationCatalog.supports(id, kind: .file))
            #expect(!DestinationCatalog.supports(id, kind: .text))
            #expect(!DestinationCatalog.supports(id, kind: .image))
        }
    }

    @Test func imageHostsAreImageOnly() {
        for id in [SimpleHostDestination.chevereto.rawValue, SimpleHostDestination.vgyme.rawValue] {
            #expect(DestinationCatalog.supports(id, kind: .image))
            #expect(!DestinationCatalog.supports(id, kind: .text))
            #expect(!DestinationCatalog.supports(id, kind: .file))
        }
    }

    /// General storage takes anything, including text (sent as a .txt file).
    @Test func generalStorageServesEveryKind() {
        let general = ["AmazonS3", "BackblazeB2", "AzureStorage", "OwnCloud", "Seafile",
                       "Pushbullet", OAuthProviderID.googleDrive.rawValue,
                       OAuthProviderID.oneDrive.rawValue, SimpleHostDestination.uguu.rawValue]
        for id in general {
            for kind in UploadKind.allCases {
                #expect(DestinationCatalog.supports(id, kind: kind),
                        "\(id) should serve \(kind.displayName) uploads")
            }
        }
    }

    /// Each slot offers its own custom-uploader sentinel and no other slot's.
    @Test func customUploaderSentinelsAreScopedToTheirSlot() {
        #expect(DestinationCatalog.supports("CustomImageUploader", kind: .image))
        #expect(!DestinationCatalog.supports("CustomImageUploader", kind: .text))
        #expect(DestinationCatalog.supports("CustomTextUploader", kind: .text))
        #expect(!DestinationCatalog.supports("CustomTextUploader", kind: .file))
        #expect(DestinationCatalog.supports("CustomFileUploader", kind: .file))
        #expect(!DestinationCatalog.supports("CustomFileUploader", kind: .image))

        for kind in UploadKind.allCases {
            let sentinels = DestinationCatalog.available(for: kind)
                .filter { DestinationCatalog.customUploaderTags.contains($0.id) }
            #expect(sentinels.count == 1, "\(kind.displayName) needs exactly one custom-uploader row")
        }
    }

    @Test func availableListsAreFilteredAndOrdered() {
        let textIDs = DestinationCatalog.available(for: .text).map(\.id)
        #expect(!textIDs.contains(OAuthProviderID.youTube.rawValue))
        #expect(textIDs.contains("AmazonS3"))
        // catalog order is picker order: the slot's custom uploader leads
        #expect(textIDs.first == "CustomTextUploader")

        let fileIDs = DestinationCatalog.available(for: .file).map(\.id)
        #expect(fileIDs.contains(OAuthProviderID.youTube.rawValue))
        #expect(!fileIDs.contains(SimpleHostDestination.vgyme.rawValue))
    }

    /// An unknown id (a Windows config naming a host SwiftX doesn't implement)
    /// isn't reported as unsupported — routing rejects it with a clearer error.
    @Test func unknownDestinationsAreNotReportedUnsupported() {
        #expect(DestinationCatalog.supports("Imgur", kind: .image))
        #expect(DestinationCatalog.destination(id: "Imgur") == nil)
        #expect(DestinationCatalog.displayName(for: "Imgur") == "Imgur")
    }

    @Test func displayNamesComeFromTheUnderlyingEnums() {
        #expect(DestinationCatalog.displayName(for: "OwnCloud") == "ownCloud / Nextcloud")
        #expect(DestinationCatalog.displayName(for: SimpleHostDestination.vgyme.rawValue) == "vgy.me")
        #expect(DestinationCatalog.displayName(for: OAuthProviderID.googleDrive.rawValue) == "Google Drive")
    }

    /// Classification moved modules with UploadKind; its behaviour shouldn't.
    @Test func classifyRoutesByExtension() {
        #expect(UploadKind.classify(fileExtension: "PNG") == .image)
        #expect(UploadKind.classify(fileExtension: "swift") == .text)
        #expect(UploadKind.classify(fileExtension: "mp4") == .file)
        #expect(UploadKind.classify(fileExtension: "") == .file)
    }
}
