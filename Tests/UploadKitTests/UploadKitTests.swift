// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE

import Foundation
import Testing
@testable import UploadKit

struct SyntaxParserTests {
    @Test func plainTextPassesThrough() throws {
        #expect(try CustomUploaderSyntaxParser().parse("hello world") == "hello world")
    }

    @Test func filenameFunction() throws {
        let parser = CustomUploaderSyntaxParser(fileName: "shot.png")
        #expect(try parser.parse("{filename}") == "shot.png")
        parser.urlEncode = true
        parser.fileName = "my shot.png"
        #expect(try parser.parse("{filename}") == "my%20shot.png")
    }

    @Test func jsonOverResponse() throws {
        let response = SyntaxResponse(statusCode: 200, text: #"{"data": {"link": "https://i.example/abc.png"}, "success": true}"#, url: "")
        let parser = CustomUploaderSyntaxParser(response: response)
        #expect(try parser.parse("{json:data.link}") == "https://i.example/abc.png")
        #expect(try parser.parse("{json:$.data.link}") == "https://i.example/abc.png")
        #expect(try parser.parse("{json:success}") == "true")
    }

    @Test func jsonArrayAndQuotedKeys() throws {
        let response = SyntaxResponse(statusCode: 200, text: #"{"files": [{"url": "https://x/1"}, {"url": "https://x/2"}], "weird-key": "v"}"#, url: "")
        let parser = CustomUploaderSyntaxParser(response: response)
        #expect(try parser.parse("{json:files[1].url}") == "https://x/2")
        #expect(try parser.parse("{json:['weird-key']}") == "v")
    }

    @Test func regexWithGroup() throws {
        let response = SyntaxResponse(statusCode: 200, text: "url=https://example.com/xyz123 done", url: "")
        let parser = CustomUploaderSyntaxParser(response: response)
        // backslash is the syntax escape char, so regex backslashes are doubled - same as Windows ShareX
        #expect(try parser.parse(#"{regex:url=(\\S+)|1}"#) == "https://example.com/xyz123")
    }

    @Test func nestingAndConcatenation() throws {
        let response = SyntaxResponse(statusCode: 200, text: #"{"id": "abc"}"#, url: "")
        let parser = CustomUploaderSyntaxParser(response: response)
        #expect(try parser.parse("https://host/{json:id}/view") == "https://host/abc/view")
    }

    @Test func base64AndNesting() throws {
        let parser = CustomUploaderSyntaxParser(fileName: "a.png")
        #expect(try parser.parse("{base64:{filename}}") == Data("a.png".utf8).base64EncodedString())
    }

    @Test func escapingBraces() throws {
        let parser = CustomUploaderSyntaxParser()
        #expect(try parser.parse(#"\{filename\}"#) == "{filename}")
    }

    @Test func responseFunctions() throws {
        let response = SyntaxResponse(statusCode: 200, text: "BODY", url: "https://final.example/x",
                                      headers: ["Location": "https://loc.example"])
        let parser = CustomUploaderSyntaxParser(response: response)
        #expect(try parser.parse("{response}") == "BODY")
        #expect(try parser.parse("{responseurl}") == "https://final.example/x")
        #expect(try parser.parse("{header:location}") == "https://loc.example")
    }

    @Test func unknownFunctionThrows() {
        #expect(throws: SyntaxError.self) {
            try CustomUploaderSyntaxParser().parse("{nosuchfunction}")
        }
    }

    @Test func responseFunctionInRequestPhaseThrows() {
        #expect(throws: SyntaxError.self) {
            try CustomUploaderSyntaxParser().parse("{response}")
        }
    }

    @Test func selectTakesFirstOptionHeadlessly() throws {
        #expect(try CustomUploaderSyntaxParser().parse("{select:public|private}") == "public")
    }

    @Test func xmlOverResponse() throws {
        let response = SyntaxResponse(
            statusCode: 200,
            text: "<files><file url=\"https://img.example/a.png\"><name>a.png</name></file></files>",
            url: ""
        )
        let parser = CustomUploaderSyntaxParser(response: response)
        #expect(try parser.parse("{xml:/files/file/name}") == "a.png")
        #expect(try parser.parse("{xml://file/@url}") == "https://img.example/a.png")
        #expect(try parser.parse("{xml:/files/missing}") == "")
    }

    @Test func legacySyntaxMigrates() {
        // $ pairs become braces, literal braces get escaped, \x escapes drop
        #expect(CustomUploaderItem.migrateOldSyntax("$json:url$") == "{json:url}")
        #expect(CustomUploaderItem.migrateOldSyntax("a{b}c") == "a\\{b\\}c")
        #expect(CustomUploaderItem.migrateOldSyntax("pre $regex:x$ post") == "pre {regex:x} post")

        var item = CustomUploaderItem()
        item.version = "13.0.0"
        item.url = "$json:data.link$"
        item.data = "text=$input$&name=$FILENAME$"
        item.migrateLegacySyntaxIfNeeded()
        #expect(item.url == "{json:data.link}")
        #expect(item.data == "text={input}&name={filename}")

        // modern files are untouched
        var modern = CustomUploaderItem()
        modern.version = "14.1.0"
        modern.url = "$json:data.link$" // pathological but must not be rewritten
        modern.migrateLegacySyntaxIfNeeded()
        #expect(modern.url == "$json:data.link$")

        // no version: leave alone (hand-written modern files)
        var unversioned = CustomUploaderItem()
        unversioned.url = "{json:url}"
        unversioned.migrateLegacySyntaxIfNeeded()
        #expect(unversioned.url == "{json:url}")
    }

    @Test func versionComparison() {
        #expect(CustomUploaderItem.compareVersion("13.7.0", "13.7.1") < 0)
        #expect(CustomUploaderItem.compareVersion("13.7.1", "13.7.1") == 0)
        #expect(CustomUploaderItem.compareVersion("14.0", "13.7.1") > 0)
        #expect(CustomUploaderItem.compareVersion("13.7.1.1", "13.7.1") > 0)
    }
}

struct CustomUploaderItemTests {
    @Test func decodesRealWorldSxcu() throws {
        let sxcu = """
        {
          "Version": "14.1.0",
          "Name": "example host",
          "DestinationType": "ImageUploader, FileUploader",
          "RequestMethod": "POST",
          "RequestURL": "https://example.com/api/upload",
          "Headers": {"Authorization": "Bearer TOKEN"},
          "Body": "MultipartFormData",
          "Arguments": {"format": "json"},
          "FileFormName": "file",
          "URL": "{json:files[0].url}",
          "ErrorMessage": "{json:description}"
        }
        """
        let item = try JSONDecoder().decode(CustomUploaderItem.self, from: sxcu.data(using: .utf8)!)
        #expect(item.name == "example host")
        #expect(item.body == .multipartFormData)
        #expect(item.fileFormName == "file")
        #expect(item.url == "{json:files[0].url}")
        #expect(item.displayName == "example host")
    }

    @Test func minimalSxcuGetsDefaults() throws {
        let item = try JSONDecoder().decode(CustomUploaderItem.self,
                                            from: #"{"RequestURL": "https://0x0.example/up"}"#.data(using: .utf8)!)
        #expect(item.requestMethod == "POST")
        #expect(item.body == .multipartFormData)
        #expect(item.displayName == "0x0.example")
    }
}

struct CustomUploaderServiceTests {
    private var testFile: UploadFile {
        UploadFile(data: Data("PNGDATA".utf8), fileName: "shot.png", mimeType: "image/png")
    }

    private var multipartItem: CustomUploaderItem {
        var item = CustomUploaderItem()
        item.requestURL = "https://example.com/api/upload"
        item.parameters = ["key": "abc"]
        item.headers = ["Authorization": "Bearer T"]
        item.arguments = ["format": "json", "name": "{filename}"]
        item.fileFormName = "file"
        item.url = "{json:link}"
        return item
    }

    @Test func buildsMultipartRequest() throws {
        let request = try CustomUploaderService.buildRequest(item: multipartItem, file: testFile)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://example.com/api/upload?key=abc")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer T")

        let contentType = try #require(request.value(forHTTPHeaderField: "Content-Type"))
        #expect(contentType.hasPrefix("multipart/form-data; boundary="))
        let boundary = String(contentType.dropFirst("multipart/form-data; boundary=".count))

        let body = String(data: try #require(request.httpBody), encoding: .utf8)!
        #expect(body.contains("--\(boundary)\r\n"))
        #expect(body.contains("Content-Disposition: form-data; name=\"format\"\r\n\r\njson"))
        #expect(body.contains("Content-Disposition: form-data; name=\"name\"\r\n\r\nshot.png"))
        #expect(body.contains("Content-Disposition: form-data; name=\"file\"; filename=\"shot.png\""))
        #expect(body.contains("Content-Type: image/png"))
        #expect(body.contains("PNGDATA"))
        #expect(body.hasSuffix("--\(boundary)--\r\n"))
    }

    @Test func buildsJSONBodyRequest() throws {
        var item = CustomUploaderItem()
        item.requestURL = "https://example.com/api"
        item.body = .json
        // raw JSON braces must survive; only {filename}/{input} are replaced (literally, like C# GetData)
        item.data = #"{"name": "{filename}", "nested": {"keep": true}}"#
        let request = try CustomUploaderService.buildRequest(item: item, file: testFile)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(String(data: request.httpBody!, encoding: .utf8) == #"{"name": "shot.png", "nested": {"keep": true}}"#)
    }

    @Test func jsonBodyEscapesFileName() throws {
        var item = CustomUploaderItem()
        item.requestURL = "https://example.com/api"
        item.body = .json
        item.data = #"{"name": "{filename}"}"#
        let file = UploadFile(data: Data(), fileName: "a\"b.png", mimeType: "image/png")
        let request = try CustomUploaderService.buildRequest(item: item, file: file)
        #expect(String(data: request.httpBody!, encoding: .utf8) == #"{"name": "a\"b.png"}"#)
    }

    @Test func buildsBinaryRequest() throws {
        var item = CustomUploaderItem()
        item.requestURL = "https://example.com/api"
        item.body = .binary
        let request = try CustomUploaderService.buildRequest(item: item, file: testFile)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "image/png")
        #expect(request.httpBody == Data("PNGDATA".utf8))
    }

    @Test func parsesSuccessResult() throws {
        let response = SyntaxResponse(statusCode: 200, text: #"{"link": "https://i.example/abc.png"}"#, url: "")
        let result = try CustomUploaderService.parseResult(item: multipartItem, response: response, file: testFile)
        #expect(result.url == "https://i.example/abc.png")
    }

    @Test func emptyURLFieldFallsBackToResponseText() throws {
        var item = multipartItem
        item.url = ""
        let response = SyntaxResponse(statusCode: 200, text: "  https://direct.example/x.png\n", url: "")
        let result = try CustomUploaderService.parseResult(item: item, response: response, file: testFile)
        #expect(result.url == "https://direct.example/x.png")
    }

    @Test func httpErrorUsesParsedErrorMessage() {
        var item = multipartItem
        item.errorMessage = "{json:error.message}"
        let response = SyntaxResponse(statusCode: 400, text: #"{"error": {"message": "file too large"}}"#, url: "")
        #expect(throws: UploadError.self) {
            try CustomUploaderService.parseResult(item: item, response: response, file: testFile)
        }
        do {
            _ = try CustomUploaderService.parseResult(item: item, response: response, file: testFile)
        } catch let UploadError.httpError(statusCode, message) {
            #expect(statusCode == 400)
            #expect(message == "file too large")
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }
}
