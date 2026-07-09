// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt

import Foundation
import Testing
@testable import UploadKit

struct CustomUploaderStoreTests {
    private func withTempDirectory(_ body: (URL) throws -> Void) rethrows {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShareXUploaderTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        try body(temp)
    }

    @Test func savedUploaderRoundTrips() throws {
        try withTempDirectory { dir in
            var item = CustomUploaderItem()
            item.name = "My Host"
            item.requestURL = "https://img.example/upload"
            item.headers = ["Authorization": "Bearer x"]
            item.arguments = ["key": "v"]
            item.url = "{json:url}"
            try CustomUploaderStore.save(item, as: "my-host.sxcu", in: dir)

            let loaded = CustomUploaderStore.load(named: "my-host.sxcu", in: dir)
            #expect(loaded == item)
            // file must stay Windows-compatible: PascalCase keys on disk
            let raw = String(data: try Data(contentsOf: dir.appendingPathComponent("my-host.sxcu")), encoding: .utf8) ?? ""
            #expect(raw.contains("\"RequestURL\""))
            #expect(raw.contains("\"Headers\""))
        }
    }

    @Test func createGeneratesUniqueFileNames() throws {
        try withTempDirectory { dir in
            let first = try CustomUploaderStore.create(named: "New Uploader", in: dir)
            let second = try CustomUploaderStore.create(named: "New Uploader", in: dir)
            #expect(first == "New Uploader.sxcu")
            #expect(second == "New Uploader 2.sxcu")
            #expect(CustomUploaderStore.list(in: dir).count == 2)
            #expect(CustomUploaderStore.load(named: first, in: dir)?.name == "New Uploader")
        }
    }

    @Test func renameMovesFileAndUniquifies() throws {
        try withTempDirectory { dir in
            let original = try CustomUploaderStore.create(named: "New Uploader", in: dir)
            let renamed = try CustomUploaderStore.rename(original, toBaseName: "My Host", in: dir)
            #expect(renamed == "My Host.sxcu")
            #expect(CustomUploaderStore.list(in: dir) == ["My Host.sxcu"])

            // collision with an existing file gets a numbered suffix
            let other = try CustomUploaderStore.create(named: "Other", in: dir)
            #expect(try CustomUploaderStore.rename(other, toBaseName: "My Host", in: dir) == "My Host 2.sxcu")

            // same name, slashes and empty names are no-ops / sanitized
            #expect(try CustomUploaderStore.rename("My Host.sxcu", toBaseName: "My Host", in: dir) == "My Host.sxcu")
            #expect(try CustomUploaderStore.rename("My Host.sxcu", toBaseName: "", in: dir) == "My Host.sxcu")
            #expect(try CustomUploaderStore.rename("My Host.sxcu", toBaseName: "a/b", in: dir) == "a-b.sxcu")
        }
    }

    @Test func deleteRemovesFile() throws {
        try withTempDirectory { dir in
            let name = try CustomUploaderStore.create(named: "Temp", in: dir)
            try CustomUploaderStore.delete(named: name, in: dir)
            #expect(CustomUploaderStore.list(in: dir).isEmpty)
        }
    }
}
