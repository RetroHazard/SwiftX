// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE
//
// Validates .sxcu import against real-world files: a ShareX 14.1 export (the
// shape the in-app Import… button receives) and the null-heavy variant that
// ShareX embeds inside .sxb backups.

import Foundation
import Testing
@testable import SharedKit
@testable import UploadKit

// Serialized: importFile writes into CustomUploaderStore.directory, which
// derives from the global SettingsPaths.root the suite swaps out.
@Suite(.serialized)
struct SXCUImportTests {
    /// Field-for-field the user-facing export shape of ShareX 14.1.0+.
    private let exportedSXCU = """
    {
      "Version": "14.1.0",
      "Name": "RetroHazard Image Host",
      "DestinationType": "ImageUploader",
      "RequestMethod": "POST",
      "RequestURL": "https://www.example.jp/static/upload.php",
      "Body": "MultipartFormData",
      "Arguments": {
        "secret": "example-secret"
      },
      "FileFormName": "sharex"
    }
    """

    private func withTempRoot(_ body: (URL) throws -> Void) rethrows {
        let original = SettingsPaths.root
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("SXCUImportTests-\(UUID().uuidString)", isDirectory: true)
        SettingsPaths.root = temp
        defer {
            SettingsPaths.root = original
            try? FileManager.default.removeItem(at: temp)
        }
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        try body(temp)
    }

    @Test func decodesRealExportedFile() throws {
        let item = try JSONDecoder().decode(CustomUploaderItem.self, from: Data(exportedSXCU.utf8))
        #expect(item.version == "14.1.0")
        #expect(item.name == "RetroHazard Image Host")
        #expect(item.destinationType == "ImageUploader")
        #expect(item.requestMethod == "POST")
        #expect(item.requestURL == "https://www.example.jp/static/upload.php")
        #expect(item.body == .multipartFormData)
        #expect(item.arguments == ["secret": "example-secret"])
        #expect(item.fileFormName == "sharex")
        // absent response fields default to empty, not errors
        #expect(item.url.isEmpty)
        #expect(item.deletionURL.isEmpty)
        #expect(item.displayName == "RetroHazard Image Host")
    }

    @Test func importFileStoresAndLoads() throws {
        try withTempRoot { temp in
            let source = temp.appendingPathComponent("RetroHazard_Image_Host.sxcu")
            try Data(exportedSXCU.utf8).write(to: source)

            let stored = try CustomUploaderStore.importFile(from: source)
            #expect(stored == "RetroHazard_Image_Host.sxcu")
            #expect(CustomUploaderStore.list().contains(stored))

            let loaded = CustomUploaderStore.load(named: stored)
            #expect(loaded?.name == "RetroHazard Image Host")
            // the stored bytes match the source exactly (Windows round-trip safe)
            let original = try Data(contentsOf: source)
            let copy = try Data(contentsOf: CustomUploaderStore.directory.appendingPathComponent(stored))
            #expect(copy == original)
        }
    }

    @Test func importRejectsInvalidJSON() throws {
        try withTempRoot { temp in
            let source = temp.appendingPathComponent("broken.sxcu")
            try Data("not json".utf8).write(to: source)
            #expect(throws: (any Error).self) {
                try CustomUploaderStore.importFile(from: source)
            }
            #expect(CustomUploaderStore.list().isEmpty)
        }
    }

    /// The .sxb-embedded shape: explicit nulls for unused response fields and
    /// DestinationType "None" (ShareX only sets it on export, not in backups).
    @Test func decodesBackupEmbeddedShapeWithNulls() throws {
        let json = """
        {
          "Version": "14.1.0",
          "Name": "RetroHazard Image Host",
          "DestinationType": "None",
          "RequestMethod": "POST",
          "RequestURL": "https://www.example.jp/static/upload.php",
          "Body": "MultipartFormData",
          "Arguments": { "secret": "example-secret" },
          "FileFormName": "sharex",
          "URL": null,
          "ThumbnailURL": null,
          "DeletionURL": null,
          "ErrorMessage": null
        }
        """
        let item = try JSONDecoder().decode(CustomUploaderItem.self, from: Data(json.utf8))
        #expect(item.requestURL == "https://www.example.jp/static/upload.php")
        #expect(item.url.isEmpty)
        #expect(item.thumbnailURL.isEmpty)
        #expect(item.errorMessage.isEmpty)
    }

    /// Pre-13.7.1 files use $function$ syntax and must migrate on load.
    @Test func loadMigratesLegacySyntax() throws {
        try withTempRoot { _ in
            let legacy = """
            {
              "Version": "12.0.0",
              "Name": "Legacy Host",
              "RequestURL": "https://legacy.example/upload",
              "URL": "$json:url$"
            }
            """
            try FileManager.default.createDirectory(at: CustomUploaderStore.directory,
                                                    withIntermediateDirectories: true)
            try Data(legacy.utf8).write(
                to: CustomUploaderStore.directory.appendingPathComponent("legacy.sxcu"))
            let item = CustomUploaderStore.load(named: "legacy.sxcu")
            #expect(item?.url == "{json:url}")
        }
    }
}
