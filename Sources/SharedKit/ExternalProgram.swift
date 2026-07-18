// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Contains code derived from ShareX, Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt
//
// "Actions": user-configured external programs run on captured files.
// JSON shape matches C# ExternalProgram so Windows configs import.
// Placeholders $input/$output and %input/%output all expand to the file path
// SHELL-QUOTED. The `args` template is user-authored (trusted) so pipes and
// redirection still work, but the substituted path is untrusted data — a file
// name derived from a window title or a downloaded file can contain shell
// metacharacters, so it must never be interpolated raw into `zsh -c`.

import Foundation

public struct ExternalProgramSettings: Codable, Equatable {
    public var isActive = false
    public var name = ""
    public var path = ""
    public var args = ""
    /// Replaces the input file's extension to form $output; the task continues
    /// with the output file when the program creates it.
    public var outputExtension = ""
    /// Only run for these input extensions (any separator); empty = all files.
    public var extensions = ""
    /// Windows-only; kept so Windows configs round-trip.
    public var hiddenWindow = false
    public var deleteInputFile = false

    public init() {}

    enum CodingKeys: String, CodingKey {
        case isActive = "IsActive"
        case name = "Name"
        case path = "Path"
        case args = "Args"
        case outputExtension = "OutputExtension"
        case extensions = "Extensions"
        case hiddenWindow = "HiddenWindow"
        case deleteInputFile = "DeleteInputFile"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isActive = try c.decodeIfPresent(Bool.self, forKey: .isActive) ?? false
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        path = try c.decodeIfPresent(String.self, forKey: .path) ?? ""
        args = try c.decodeIfPresent(String.self, forKey: .args) ?? ""
        outputExtension = try c.decodeIfPresent(String.self, forKey: .outputExtension) ?? ""
        extensions = try c.decodeIfPresent(String.self, forKey: .extensions) ?? ""
        hiddenWindow = try c.decodeIfPresent(Bool.self, forKey: .hiddenWindow) ?? false
        deleteInputFile = try c.decodeIfPresent(Bool.self, forKey: .deleteInputFile) ?? false
    }
}

public enum ExternalProgramRunner {
    /// Builds the shell command line and the expected output path.
    /// ponytail: runs through zsh -c so args behave like one command line
    /// (C# hands a single argument string to CreateProcess); pipes work free.
    /// Path substitutions are always shell-quoted — see the file header.
    public static func commandLine(for program: ExternalProgramSettings, inputPath: String) -> (command: String, outputPath: String) {
        var outputPath = inputPath
        let arguments: String
        if program.args.isEmpty {
            arguments = shellQuoted(inputPath)
        } else {
            if !program.outputExtension.isEmpty {
                let ext = program.outputExtension.hasPrefix(".")
                    ? String(program.outputExtension.dropFirst()) : program.outputExtension
                outputPath = (inputPath as NSString).deletingPathExtension + "." + ext
            }
            // Every path substitution is shell-quoted so a hostile file name
            // (e.g. a backtick-laden window title baked into the name) can't
            // break out of its argument and inject commands into zsh -c.
            arguments = program.args
                .replacingOccurrences(of: "%input", with: shellQuoted(inputPath))
                .replacingOccurrences(of: "$input", with: shellQuoted(inputPath))
                .replacingOccurrences(of: "%output", with: shellQuoted(outputPath))
                .replacingOccurrences(of: "$output", with: shellQuoted(outputPath))
        }
        return (shellQuoted(program.path) + " " + arguments, outputPath)
    }

    /// C# CheckExtension: empty list allows everything; separators are anything
    /// non-alphanumeric ("png, jpg" and "png jpg" both work).
    public static func matchesExtension(_ program: ExternalProgramSettings, inputPath: String) -> Bool {
        let allowed = program.extensions
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        guard !allowed.isEmpty else { return true }
        let ext = (inputPath as NSString).pathExtension
        return allowed.contains { $0.caseInsensitiveCompare(ext) == .orderedSame }
    }

    /// Runs one program; returns the file the task should continue with.
    public static func run(_ program: ExternalProgramSettings, on url: URL) async throws -> URL {
        guard FileManager.default.fileExists(atPath: program.path) else {
            throw ExternalProgramError.programNotFound(program.path)
        }
        guard matchesExtension(program, inputPath: url.path) else { return url }

        let (command, outputPath) = commandLine(for: program, inputPath: url.path)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        try process.run()
        await withCheckedContinuation { continuation in
            process.terminationHandler = { _ in continuation.resume() }
        }

        if outputPath != url.path, FileManager.default.fileExists(atPath: outputPath) {
            if program.deleteInputFile {
                try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
            }
            return URL(fileURLWithPath: outputPath)
        }
        return url
    }

    /// Runs every active program in order, chaining outputs into inputs.
    public static func runAll(_ programs: [ExternalProgramSettings], on url: URL) async throws -> URL {
        var current = url
        for program in programs where program.isActive {
            current = try await run(program, on: current)
        }
        return current
    }

    private static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

public enum ExternalProgramError: LocalizedError {
    case programNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .programNotFound(let path):
            return "Action program not found: \(path.isEmpty ? "(no path set)" : path)"
        }
    }
}
