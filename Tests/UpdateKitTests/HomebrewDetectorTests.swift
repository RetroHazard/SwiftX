// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE

import Foundation
import Testing
@testable import UpdateKit

struct HomebrewDetectorTests {
    @Test func detectsCaskroomDirectory() throws {
        let prefix = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftx-brew-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: prefix) }

        #expect(!HomebrewDetector.isHomebrewManaged(prefixes: [prefix.path]))

        try FileManager.default.createDirectory(
            at: prefix.appendingPathComponent("Caskroom/swiftx"),
            withIntermediateDirectories: true)
        #expect(HomebrewDetector.isHomebrewManaged(prefixes: [prefix.path]))
    }

    @Test func emptyPrefixListIsNotManaged() {
        #expect(!HomebrewDetector.isHomebrewManaged(prefixes: []))
    }
}
