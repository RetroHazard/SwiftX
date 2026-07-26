// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE

import Foundation
import Testing
@testable import ToolsKit

struct HashCheckerTests {
    static let fox = Data("The quick brown fox jumps over the lazy dog".utf8)

    // reference digests from macOS md5/shasum/zlib
    @Test(arguments: [
        (HashAlgorithm.crc32, "414FA339"),
        (.md5, "9E107D9D372BB6826BD81D3542A419D6"),
        (.sha1, "2FD4E1C67A2D28FCED849EE1BB76E7391B93EB12"),
        (.sha256, "D7A8FBB307D7809469CA9ABCB0082E4F8D5651E46D3CDB762D02D0BF37C9E592"),
        (.sha384, "CA737F1014A48F4C0B6DD43CB177B0AFD9E5169367544C494011E3317DBF9A509CB1E5DC1E85A941BBEE3D7F2AFBC9B1"),
        (.sha512, "07E547D9586F6A73F73FBAC0435ED76951218FB7D0C8D788A309D785436BBB642E93A252A954F23912547D1E8A3B5ED6E1BFD7097821233FA0538F3DB854FEE6")
    ])
    func matchesKnownVectors(algorithm: HashAlgorithm, expected: String) {
        #expect(HashChecker.hash(Self.fox, algorithm: algorithm) == expected)
    }

    @Test func fileHashingStreamsInChunks() throws {
        // 3 MB forces multiple 1 MB reads; equality with the one-shot API
        // proves chunked state carries over correctly
        let data = Data(repeating: 0xAB, count: 3 * (1 << 20) + 17)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sharex-hash-test-\(UUID().uuidString)")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try HashChecker.hashFile(at: url, algorithm: .sha256)
            == HashChecker.hash(data, algorithm: .sha256))
        #expect(try HashChecker.hashFile(at: url, algorithm: .crc32)
            == HashChecker.hash(data, algorithm: .crc32))
    }
}
