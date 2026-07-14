// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt
//
// Port of C# CLIManager.ParseCommands: "-Verb parameter" pairs plus bare
// arguments (file paths or URLs to upload).

import Foundation

public struct CLICommand: Equatable, Sendable {
    /// True for "-Verb" arguments; false for bare paths/URLs.
    public var isCommand = false
    public var command = ""
    public var parameter: String?

    public init(isCommand: Bool = false, command: String = "", parameter: String? = nil) {
        self.isCommand = isCommand
        self.command = command
        self.parameter = parameter
    }

    /// Case-insensitive verb check (C# CLICommand.CheckCommand).
    public func matches(_ name: String) -> Bool {
        isCommand && command.caseInsensitiveCompare(name) == .orderedSame
    }
}

public enum CLIParser {
    /// A bare argument following a "-Verb" becomes that verb's parameter;
    /// otherwise it stands alone (a path or URL to upload).
    public static func parse(_ arguments: [String]) -> [CLICommand] {
        var commands: [CLICommand] = []
        var openVerbIndex: Int?
        for argument in arguments where !argument.isEmpty {
            if argument.hasPrefix("-") {
                commands.append(CLICommand(isCommand: true, command: String(argument.dropFirst())))
                openVerbIndex = commands.count - 1
            } else if let index = openVerbIndex {
                commands[index].parameter = argument
                openVerbIndex = nil
            } else {
                commands.append(CLICommand(command: argument))
            }
        }
        return commands
    }
}
