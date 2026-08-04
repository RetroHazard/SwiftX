// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE

import Foundation
import Testing
@testable import UpdateKit

struct UpdateInstallerTests {
    // Cut-down `hdiutil attach -plist` output: the dmg produces several
    // system-entities but only the Apple_HFS one carries a mount point.
    private let hdiutilPlist = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>system-entities</key>
        <array>
            <dict>
                <key>content-hint</key>
                <string>GUID_partition_scheme</string>
                <key>dev-entry</key>
                <string>/dev/disk4</string>
            </dict>
            <dict>
                <key>content-hint</key>
                <string>Apple_HFS</string>
                <key>dev-entry</key>
                <string>/dev/disk4s1</string>
                <key>mount-point</key>
                <string>/Volumes/SwiftX</string>
            </dict>
        </array>
    </dict>
    </plist>
    """

    @Test func parsesMountPointFromHdiutilPlist() {
        let mount = UpdateInstaller.mountPoint(fromHdiutilPlist: Data(hdiutilPlist.utf8))
        #expect(mount == "/Volumes/SwiftX")
    }

    @Test func rejectsGarbagePlist() {
        #expect(UpdateInstaller.mountPoint(fromHdiutilPlist: Data("not a plist".utf8)) == nil)
        #expect(UpdateInstaller.mountPoint(fromHdiutilPlist: Data()) == nil)
        let noEntities = "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict/></plist>"
        #expect(UpdateInstaller.mountPoint(fromHdiutilPlist: Data(noEntities.utf8)) == nil)
    }

    @Test func parsesBareDigestChecksumFile() {
        // release.yml publishes the bare digest + newline
        let digest = String(repeating: "ab", count: 32)
        #expect(UpdateInstaller.expectedDigest(fromChecksumFile: digest + "\n") == digest)
        // tolerate shasum's "digest  filename" form and uppercase hex
        #expect(UpdateInstaller.expectedDigest(
            fromChecksumFile: digest.uppercased() + "  SwiftX-2026.8.1.dmg\n") == digest)
    }

    @Test func rejectsMalformedChecksumFiles() {
        #expect(UpdateInstaller.expectedDigest(fromChecksumFile: "") == nil)
        #expect(UpdateInstaller.expectedDigest(fromChecksumFile: "abc123") == nil) // too short
        #expect(UpdateInstaller.expectedDigest(
            fromChecksumFile: String(repeating: "g", count: 64)) == nil) // not hex
        #expect(UpdateInstaller.expectedDigest(fromChecksumFile: "<html>Not Found</html>") == nil)
    }

    @Test func streamingSHA256MatchesKnownVector() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftx-sha-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("hello".utf8).write(to: file)
        #expect(try UpdateInstaller.sha256Hex(ofFileAt: file)
            == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
    }
}
