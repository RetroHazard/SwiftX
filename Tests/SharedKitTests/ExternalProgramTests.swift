// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE

import Foundation
import Testing
@testable import SharedKit

struct ExternalProgramTests {
    private func program(args: String = "", outputExtension: String = "", extensions: String = "") -> ExternalProgramSettings {
        var p = ExternalProgramSettings()
        p.isActive = true
        p.path = "/bin/echo"
        p.args = args
        p.outputExtension = outputExtension
        p.extensions = extensions
        return p
    }

    @Test func placeholdersSubstitute() {
        let (command, output) = ExternalProgramRunner.commandLine(
            for: program(args: "$input -> %output", outputExtension: "webp"),
            inputPath: "/tmp/shot.png"
        )
        #expect(output == "/tmp/shot.webp")
        // $input/$output are shell-quoted just like %input/%output so a hostile
        // file name can't inject commands into zsh -c
        #expect(command == "'/bin/echo' '/tmp/shot.png' -> '/tmp/shot.webp'")
    }

    @Test func inputPlaceholderIsQuotedAgainstCommandInjection() {
        // a file name carrying a backtick command substitution stays inside its
        // single-quoted argument and can never execute
        let (command, _) = ExternalProgramRunner.commandLine(
            for: program(args: "process $input"),
            inputPath: "/tmp/`touch pwned`.png"
        )
        #expect(command == "'/bin/echo' process '/tmp/`touch pwned`.png'")
    }

    @Test func emptyArgsPassTheQuotedInput() {
        let (command, output) = ExternalProgramRunner.commandLine(for: program(), inputPath: "/tmp/it's.png")
        #expect(output == "/tmp/it's.png")
        // single quotes in the path survive shell quoting
        #expect(command == "'/bin/echo' '/tmp/it'\\''s.png'")
    }

    @Test func extensionFilterIsCaseInsensitiveAndSeparatorAgnostic() {
        #expect(ExternalProgramRunner.matchesExtension(program(extensions: "png, jpg"), inputPath: "/a/b.PNG"))
        #expect(ExternalProgramRunner.matchesExtension(program(extensions: "png jpg"), inputPath: "/a/b.jpg"))
        #expect(!ExternalProgramRunner.matchesExtension(program(extensions: "png"), inputPath: "/a/b.mp4"))
        #expect(ExternalProgramRunner.matchesExtension(program(), inputPath: "/a/b.anything"))
    }

    @Test func runChainsToTheOutputFile() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShareXActionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = dir.appendingPathComponent("shot.png")
        try Data("fake".utf8).write(to: input)

        var copy = program(args: "%input %output", outputExtension: "bak")
        copy.path = "/bin/cp"
        let result = try await ExternalProgramRunner.runAll([copy], on: input)
        #expect(result.lastPathComponent == "shot.bak")
        #expect(FileManager.default.fileExists(atPath: result.path))
        // deleteInputFile off: original stays
        #expect(FileManager.default.fileExists(atPath: input.path))
    }

    @Test func inactiveProgramsAreSkipped() async throws {
        var p = program()
        p.isActive = false
        p.path = "/nonexistent/tool" // would throw if it ran
        let url = URL(fileURLWithPath: "/tmp/x.png")
        #expect(try await ExternalProgramRunner.runAll([p], on: url) == url)
    }

    @Test func decodesWindowsConfigShape() throws {
        let json = """
        {"IsActive": true, "Name": "optimize", "Path": "C:\\\\tools\\\\opt.exe",
         "Args": "%input", "Extensions": "png", "DeleteInputFile": true, "HiddenWindow": true}
        """
        let decoded = try JSONDecoder().decode(ExternalProgramSettings.self, from: Data(json.utf8))
        #expect(decoded.isActive)
        #expect(decoded.name == "optimize")
        #expect(decoded.deleteInputFile)
        #expect(decoded.hiddenWindow)
    }
}
