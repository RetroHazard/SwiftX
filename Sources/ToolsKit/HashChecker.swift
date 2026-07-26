// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE.txt
//
// File hashing for the Hash Checker tool. Same algorithm set as the C#
// HashType enum. Files stream in 1 MB chunks so size doesn't matter.

import CryptoKit
import Foundation

public enum HashAlgorithm: String, CaseIterable, Sendable, Identifiable {
    case crc32 = "CRC-32"
    case md5 = "MD5"
    case sha1 = "SHA-1"
    case sha256 = "SHA-256"
    case sha384 = "SHA-384"
    case sha512 = "SHA-512"

    public var id: String { rawValue }
}

public enum HashChecker {
    /// Uppercase hex digest, like C# HashChecker results.
    public static func hash(_ data: Data, algorithm: HashAlgorithm) -> String {
        var hasher = Hasher(algorithm)
        hasher.update(data)
        return hasher.finalize()
    }

    public static func hashFile(at url: URL, algorithm: HashAlgorithm) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = Hasher(algorithm)
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(chunk)
        }
        return hasher.finalize()
    }

    /// One streaming interface over CryptoKit's five hashers + CRC32.
    private enum Hasher {
        case crc32(UInt32)
        case md5(Insecure.MD5)
        case sha1(Insecure.SHA1)
        case sha256(SHA256)
        case sha384(SHA384)
        case sha512(SHA512)

        init(_ algorithm: HashAlgorithm) {
            switch algorithm {
            case .crc32: self = .crc32(0xFFFF_FFFF)
            case .md5: self = .md5(Insecure.MD5())
            case .sha1: self = .sha1(Insecure.SHA1())
            case .sha256: self = .sha256(SHA256())
            case .sha384: self = .sha384(SHA384())
            case .sha512: self = .sha512(SHA512())
            }
        }

        mutating func update(_ data: Data) {
            switch self {
            case .crc32(var state):
                for byte in data {
                    state = (state >> 8) ^ Self.crcTable[Int((state ^ UInt32(byte)) & 0xFF)]
                }
                self = .crc32(state)
            case .md5(var hash): hash.update(data: data); self = .md5(hash)
            case .sha1(var hash): hash.update(data: data); self = .sha1(hash)
            case .sha256(var hash): hash.update(data: data); self = .sha256(hash)
            case .sha384(var hash): hash.update(data: data); self = .sha384(hash)
            case .sha512(var hash): hash.update(data: data); self = .sha512(hash)
            }
        }

        func finalize() -> String {
            switch self {
            case .crc32(let state):
                return String(format: "%08X", ~state)
            case .md5(let hash): return hex(hash.finalize())
            case .sha1(let hash): return hex(hash.finalize())
            case .sha256(let hash): return hex(hash.finalize())
            case .sha384(let hash): return hex(hash.finalize())
            case .sha512(let hash): return hex(hash.finalize())
            }
        }

        private func hex(_ digest: some Sequence<UInt8>) -> String {
            digest.map { String(format: "%02X", $0) }.joined()
        }

        /// Standard reflected CRC-32 (IEEE 802.3) table, polynomial 0xEDB88320.
        static let crcTable: [UInt32] = (0..<256).map { index in
            var value = UInt32(index)
            for _ in 0..<8 {
                value = value & 1 == 1 ? (value >> 1) ^ 0xEDB8_8320 : value >> 1
            }
            return value
        }
    }
}
