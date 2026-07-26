// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Contains code derived from ShareX, Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE
//
// Port of ShareXSyntaxParser + ShareXCustomUploaderSyntaxParser:
// {function:param1|param2} with backslash escaping and full nesting.
// Interactive functions (select shows a dialog on Windows) degrade gracefully;
// legacy $var$ syntax is migrated at load time (CustomUploaderItem), as in C#.

import Foundation

public enum SyntaxError: LocalizedError {
    case emptyFunctionName
    case unknownFunction(String)
    case missingParameters(function: String, minimum: Int)
    case unsupportedFunction(String)
    case noResponseAvailable(function: String)

    public var errorDescription: String? {
        switch self {
        case .emptyFunctionName:
            return "Function name cannot be empty."
        case .unknownFunction(let name):
            return "Invalid function name: \(name)"
        case .missingParameters(let function, let minimum):
            return "Minimum parameter count for function \"\(function)\" is \(minimum)."
        case .unsupportedFunction(let name):
            return "Function \"\(name)\" is not supported on macOS yet."
        case .noResponseAvailable(let function):
            return "Function \"\(function)\" requires a response and cannot be used in a request."
        }
    }
}

/// Response data available to functions during the response-parsing phase.
public struct SyntaxResponse {
    public let statusCode: Int
    public let text: String
    public let url: String
    public let headers: [String: String]

    public init(statusCode: Int, text: String, url: String, headers: [String: String] = [:]) {
        self.statusCode = statusCode
        self.text = text
        self.url = url
        self.headers = headers
    }

    public func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

public final class CustomUploaderSyntaxParser {
    public var fileName: String
    public var input: String
    public var response: SyntaxResponse?
    /// Only URL-encodes {filename} and {input}, mirroring the C# behavior.
    public var urlEncode = false

    public init(fileName: String = "", input: String = "", response: SyntaxResponse? = nil) {
        self.fileName = fileName
        self.input = input
        self.response = response
    }

    public func parse(_ text: String) throws -> String {
        guard !text.isEmpty else { return "" }
        let chars = Array(text)
        var end = 0
        return try parse(chars, isFunction: false, startPosition: 0, endPosition: &end)
    }

    // MARK: - Recursive descent (mirrors ShareXSyntaxParser.cs)

    private func parse(_ text: [Character], isFunction: Bool, startPosition: Int, endPosition: inout Int) throws -> String {
        var output = ""
        var escape = false
        var i = startPosition

        while i < text.count {
            let c = text[i]
            if !escape {
                if c == "{" {
                    var innerEnd = 0
                    output += try parse(text, isFunction: true, startPosition: i + 1, endPosition: &innerEnd)
                    i = innerEnd + 1
                    continue
                } else if c == "}" || c == "|" {
                    break
                } else if c == "\\" {
                    escape = true
                    i += 1
                    continue
                } else if isFunction, c == ":" {
                    var parameters: [String] = []
                    var end = i
                    repeat {
                        var innerEnd = 0
                        let parsed = try parse(text, isFunction: false, startPosition: end + 1, endPosition: &innerEnd)
                        parameters.append(parsed)
                        end = innerEnd
                    } while end < text.count && text[end] == "|"
                    endPosition = end
                    return try callFunction(output, parameters: parameters)
                }
            }
            escape = false
            output.append(c)
            i += 1
        }

        endPosition = i
        if isFunction {
            return try callFunction(output, parameters: [])
        }
        return output
    }

    // MARK: - Functions

    private func callFunction(_ name: String, parameters: [String]) throws -> String {
        guard !name.isEmpty else { throw SyntaxError.emptyFunctionName }

        switch name.lowercased() {
        case "response":
            return try requireResponse(name).text
        case "responseurl":
            return try requireResponse(name).url
        case "header":
            try requireParameters(name, parameters, minimum: 1)
            return try requireResponse(name).header(parameters[0]) ?? ""
        case "json":
            // {json:jsonPath} over the response, or {json:input|jsonPath}
            try requireParameters(name, parameters, minimum: 1)
            let (input, path) = parameters.count > 1
                ? (parameters[0], parameters[1])
                : (try requireResponse(name).text, parameters[0])
            return JSONPath.query(jsonText: input, path: path) ?? ""
        case "xml":
            // {xml:xpath} over the response, or {xml:input|xpath}
            try requireParameters(name, parameters, minimum: 1)
            let (input, xpath) = parameters.count > 1
                ? (parameters[0], parameters[1])
                : (try requireResponse(name).text, parameters[0])
            return XMLPath.query(xmlText: input, xpath: xpath) ?? ""
        case "regex":
            try requireParameters(name, parameters, minimum: 1)
            return try regex(parameters)
        case "filename":
            return urlEncode ? Self.urlEncoded(fileName) : fileName
        case "input":
            return urlEncode ? Self.urlEncoded(input) : input
        case "base64":
            try requireParameters(name, parameters, minimum: 1)
            return Data(parameters[0].utf8).base64EncodedString()
        case "random":
            try requireParameters(name, parameters, minimum: 1)
            return parameters.randomElement() ?? ""
        case "select":
            // Windows shows a picker dialog; take the first option headlessly
            try requireParameters(name, parameters, minimum: 1)
            return parameters[0]
        case "prompt", "inputbox", "outputbox":
            // interactive input/output boxes - not applicable headlessly
            return ""
        default:
            throw SyntaxError.unknownFunction(name)
        }
    }

    private func regex(_ parameters: [String]) throws -> String {
        let input: String, pattern: String, group: String
        if parameters.count > 2 {
            (input, pattern, group) = (parameters[0], parameters[1], parameters[2])
        } else {
            input = try requireResponse("regex").text
            pattern = parameters[0]
            group = parameters.count > 1 ? parameters[1] : ""
        }

        guard let expression = try? NSRegularExpression(pattern: pattern) else { return "" }
        let range = NSRange(input.startIndex..., in: input)
        guard let match = expression.firstMatch(in: input, range: range) else { return "" }

        let matchRange: NSRange
        if group.isEmpty {
            matchRange = match.range
        } else if let index = Int(group) {
            matchRange = match.range(at: index)
        } else {
            matchRange = match.range(withName: group)
        }
        guard matchRange.location != NSNotFound, let swiftRange = Range(matchRange, in: input) else { return "" }
        return String(input[swiftRange])
    }

    private func requireResponse(_ function: String) throws -> SyntaxResponse {
        guard let response else { throw SyntaxError.noResponseAvailable(function: function) }
        return response
    }

    private func requireParameters(_ function: String, _ parameters: [String], minimum: Int) throws {
        guard parameters.count >= minimum else {
            throw SyntaxError.missingParameters(function: function, minimum: minimum)
        }
    }

    static func urlEncoded(_ string: String) -> String {
        string.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? string
    }
}

/// XPath over an XML document; C# uses XPathNavigator.SelectSingleNode,
/// XMLDocument.nodes(forXPath:) is the same engine class on macOS.
enum XMLPath {
    static func query(xmlText: String, xpath: String) -> String? {
        guard !xmlText.isEmpty, !xpath.isEmpty,
              let document = try? XMLDocument(xmlString: xmlText),
              let node = (try? document.nodes(forXPath: xpath))?.first else {
            return nil
        }
        return node.stringValue
    }
}

/// Minimal JSONPath subset covering real-world .sxcu files:
/// dot notation, [index], ['key'], optional "$." prefix.
enum JSONPath {
    static func query(jsonText: String, path: String) -> String? {
        guard let data = jsonText.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return nil
        }
        var current: Any = root
        for token in tokenize(path) {
            switch token {
            case .key(let key):
                guard let dict = current as? [String: Any], let next = dict[key] else { return nil }
                current = next
            case .index(let index):
                guard let array = current as? [Any], array.indices.contains(index) else { return nil }
                current = array[index]
            }
        }
        return stringify(current)
    }

    private enum Token {
        case key(String)
        case index(Int)
    }

    private static func tokenize(_ path: String) -> [Token] {
        var normalized = path
        if normalized.hasPrefix("$") {
            normalized = String(normalized.dropFirst())
        }
        var tokens: [Token] = []
        var current = ""
        var i = normalized.startIndex

        func flush() {
            if !current.isEmpty {
                tokens.append(.key(current))
                current = ""
            }
        }

        while i < normalized.endIndex {
            let c = normalized[i]
            if c == "." {
                flush()
            } else if c == "[" {
                flush()
                guard let close = normalized[i...].firstIndex(of: "]") else { break }
                var inner = String(normalized[normalized.index(after: i)..<close])
                if inner.hasPrefix("'") || inner.hasPrefix("\"") {
                    inner = String(inner.dropFirst().dropLast())
                    tokens.append(.key(inner))
                } else if let index = Int(inner) {
                    tokens.append(.index(index))
                }
                i = close
            } else {
                current.append(c)
            }
            i = normalized.index(after: i)
        }
        flush()
        return tokens
    }

    private static func stringify(_ value: Any) -> String? {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            // distinguish booleans from numbers (both are NSNumber via JSONSerialization)
            return CFGetTypeID(number) == CFBooleanGetTypeID() ? (number.boolValue ? "true" : "false") : number.stringValue
        case is NSNull:
            return nil
        default:
            guard let data = try? JSONSerialization.data(withJSONObject: value) else { return nil }
            return String(data: data, encoding: .utf8)
        }
    }
}
