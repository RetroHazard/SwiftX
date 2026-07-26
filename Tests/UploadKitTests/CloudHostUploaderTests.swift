// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE.txt

import Foundation
import Testing
@testable import UploadKit
import SharedKit

struct BackblazeB2Tests {
    let file = UploadFile(data: Data("png".utf8), fileName: "a shot.png", mimeType: "image/png")

    @Test func uploadRequestCarriesTokenNameAndSha1() {
        let request = BackblazeB2Uploader.uploadRequest(
            uploadURL: URL(string: "https://pod.backblaze.com/u")!,
            token: "tok", file: file, destinationPath: "ShareX/2026/a shot.png"
        )
        #expect(request.value(forHTTPHeaderField: "Authorization") == "tok")
        #expect(request.value(forHTTPHeaderField: "X-Bz-File-Name") == "ShareX/2026/a%20shot.png")
        // shasum -a 1 of "png"
        #expect(request.value(forHTTPHeaderField: "X-Bz-Content-Sha1") == "9040a7d6cdf7a0d6cab1823831c6ceb7d01af97f")
        #expect(request.httpBody == file.data)
    }

    @Test func fileURLUsesDownloadOrCustomHost() {
        var config = UploadersConfig()
        config.b2BucketName = "bkt"
        #expect(BackblazeB2Uploader.fileURL(downloadUrl: "https://f001.backblazeb2.com", bucket: "bkt",
                                            path: "x/y.png", config: config)
                == "https://f001.backblazeb2.com/file/bkt/x/y.png")
        config.b2UseCustomUrl = true
        config.b2CustomUrl = "cdn.example.com"
        #expect(BackblazeB2Uploader.fileURL(downloadUrl: "https://f001.backblazeb2.com", bucket: "bkt",
                                            path: "x/y.png", config: config)
                == "https://cdn.example.com/x/y.png")
    }

    @Test func destinationPathAppliesNamePatterns() {
        let date = Calendar(identifier: .gregorian).date(from: DateComponents(timeZone: TimeZone(identifier: "UTC"),
                                                                              year: 2026, month: 7, day: 9))!
        let path = BackblazeB2Uploader.destinationPath(fileName: "f.png", uploadPath: "ShareX/%y/%mo", date: date)
        #expect(path == "ShareX/2026/07/f.png")
    }
}

struct AzureStorageTests {
    let file = UploadFile(data: Data("png".utf8), fileName: "shot.png", mimeType: "image/png")
    let fixedDate = Date(timeIntervalSince1970: 1_780_000_000)

    var config: UploadersConfig {
        var c = UploadersConfig()
        c.azureStorageAccountName = "acct"
        c.azureStorageAccountAccessKey = Data("secret-key".utf8).base64EncodedString()
        c.azureStorageContainer = "shots"
        return c
    }

    @Test func buildsSignedPutRequest() throws {
        let request = try AzureStorageUploader.buildRequest(file: file, config: config, date: fixedDate)
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.absoluteString == "https://acct.blob.core.windows.net/shots/shot.png")
        #expect(request.value(forHTTPHeaderField: "x-ms-blob-type") == "BlockBlob")
        #expect(request.value(forHTTPHeaderField: "x-ms-version") == "2016-05-31")
        let auth = request.value(forHTTPHeaderField: "Authorization") ?? ""
        #expect(auth.hasPrefix("SharedKey acct:"))
        // signature is deterministic for a fixed date and key
        let again = try AzureStorageUploader.buildRequest(file: file, config: config, date: fixedDate)
        #expect(auth == again.value(forHTTPHeaderField: "Authorization"))
    }

    @Test func invalidBase64KeyThrows() {
        var bad = config
        bad.azureStorageAccountAccessKey = "!!! not base64 !!!"
        #expect(throws: UploadError.self) {
            try AzureStorageUploader.buildRequest(file: file, config: bad, date: fixedDate)
        }
    }

    @Test func resultURLPrefersCustomDomain() {
        var c = config
        #expect(AzureStorageUploader.resultURL(path: "a/b.png", config: c)
                == "https://acct.blob.core.windows.net/shots/a/b.png")
        c.azureStorageCustomDomain = "img.example.com"
        #expect(AzureStorageUploader.resultURL(path: "a/b.png", config: c) == "https://img.example.com/a/b.png")
    }
}

struct OwnCloudTests {
    var config: UploadersConfig {
        var c = UploadersConfig()
        c.ownCloudHost = "cloud.example.com"
        c.ownCloudUsername = "u"
        c.ownCloudPassword = "p"
        c.ownCloudPath = "/Screenshots"
        return c
    }

    @Test func webdavURLEncodesFileName() throws {
        let file = UploadFile(data: Data(), fileName: "a shot.png", mimeType: "image/png")
        let request = try OwnCloudUploader.webdavRequest(file: file, config: config)
        #expect(request.url?.absoluteString == "https://cloud.example.com/remote.php/webdav/Screenshots/a%20shot.png")
        #expect(request.httpMethod == "PUT")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Basic " + Data("u:p".utf8).base64EncodedString())
    }

    @Test func shareRequestAsksForPublicReadOnlyLink() throws {
        let request = try OwnCloudUploader.shareRequest(fileName: "x.png", config: config)
        let body = String(data: try #require(request.httpBody), encoding: .utf8) ?? ""
        #expect(body.contains("shareType=3"))
        #expect(body.contains("permissions=1"))
        #expect(body.contains("path=%2FScreenshots%2Fx.png"))
    }

    @Test func parsesShareResponse() throws {
        let json = #"{"ocs":{"meta":{"statuscode":100},"data":{"url":"https://cloud.example.com/s/AbC"}}}"#
        #expect(try OwnCloudUploader.parseShareResponse(Data(json.utf8)) == "https://cloud.example.com/s/AbC")
        let failure = #"{"ocs":{"meta":{"statuscode":404,"message":"not found"}}}"#
        #expect(throws: UploadError.self) {
            try OwnCloudUploader.parseShareResponse(Data(failure.utf8))
        }
    }
}

struct SeafileTests {
    var config: UploadersConfig {
        var c = UploadersConfig()
        c.seafileAPIURL = "seafile.example.com/api2"
        c.seafileAuthToken = "tok"
        c.seafileRepoID = "repo-1"
        c.seafilePath = "/shots"
        return c
    }

    @Test func buildsUploadLinkAndShareRequests() throws {
        let link = try SeafileUploader.uploadLinkRequest(config: config)
        #expect(link.url?.absoluteString == "https://seafile.example.com/api2/repos/repo-1/upload-link/?format=json")
        #expect(link.value(forHTTPHeaderField: "Authorization") == "Token tok")

        let share = try SeafileUploader.shareRequest(fileName: "x.png", config: config)
        #expect(share.httpMethod == "PUT")
        let body = String(data: try #require(share.httpBody), encoding: .utf8) ?? ""
        #expect(body.contains("p=%2Fshots%2Fx.png"))
        #expect(body.contains("share_type=download"))
    }
}

struct PushbulletTests {
    @Test func decodesUploadRequestResponse() throws {
        let json = #"{"upload_url":"https://s3.example/u","file_url":"https://dl.example/f.png","file_type":"image/png","data":{"key":"k","policy":"p"}}"#
        let slot = try JSONDecoder().decode(PushbulletUploader.UploadRequest.self, from: Data(json.utf8))
        #expect(slot.uploadUrl == "https://s3.example/u")
        #expect(slot.fileUrl == "https://dl.example/f.png")
        #expect(slot.data["policy"] == "p")
    }

    @Test func missingTokenThrows() async {
        let file = UploadFile(data: Data(), fileName: "x.png", mimeType: "image/png")
        await #expect(throws: UploadError.self) {
            try await PushbulletUploader.upload(file: file, config: UploadersConfig())
        }
    }
}
