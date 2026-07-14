// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt
//
// Installs the browser extension host manifests (C# writes registry keys;
// macOS browsers read JSON manifests from NativeMessagingHosts directories).
// The manifests point at the SwiftXHost binary inside the app bundle.

import Foundation
import SwiftUI

enum NativeMessagingSetup {
    private struct Browser {
        let displayName: String
        let directory: String
        let fileName: String
        /// Chrome-family manifests use allowed_origins, Firefox allowed_extensions.
        let isFirefox: Bool
    }

    private static let browsers = [
        Browser(displayName: "Chrome",
                directory: "Google/Chrome/NativeMessagingHosts",
                fileName: "com.getsharex.sharex.json", isFirefox: false),
        Browser(displayName: "Edge",
                directory: "Microsoft Edge/NativeMessagingHosts",
                fileName: "com.getsharex.sharex.json", isFirefox: false),
        Browser(displayName: "Firefox",
                directory: "Mozilla/NativeMessagingHosts",
                fileName: "ShareX.json", isFirefox: true)
    ]

    private static var applicationSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    static var hostBinaryURL: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/SwiftXHost")
    }

    static var isInstalled: Bool {
        browsers.contains {
            FileManager.default.fileExists(
                atPath: applicationSupport.appendingPathComponent($0.directory)
                    .appendingPathComponent($0.fileName).path)
        }
    }

    static func install() throws {
        for browser in browsers {
            // manifest names/IDs match the Windows ShareX browser extensions
            var manifest: [String: Any] = [
                "name": browser.isFirefox ? "ShareX" : "com.getsharex.sharex",
                "description": "SwiftX",
                "path": hostBinaryURL.path,
                "type": "stdio"
            ]
            if browser.isFirefox {
                manifest["allowed_extensions"] = ["firefox@getsharex.com"]
            } else {
                manifest["allowed_origins"] = ["chrome-extension://nlkoigbdolhchiicbonbihbphgamnaoc/"]
            }
            let directory = applicationSupport.appendingPathComponent(browser.directory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: manifest,
                                                  options: [.prettyPrinted, .sortedKeys])
            try data.write(to: directory.appendingPathComponent(browser.fileName), options: .atomic)
        }
    }

    static func uninstall() {
        for browser in browsers {
            try? FileManager.default.removeItem(
                at: applicationSupport.appendingPathComponent(browser.directory)
                    .appendingPathComponent(browser.fileName))
        }
    }
}

/// "Browser extension" section for the General settings pane.
struct NativeMessagingSection: View {
    @State private var installed = NativeMessagingSetup.isInstalled
    @State private var hostMissing = false

    var body: some View {
        Toggle("Accept uploads from the ShareX browser extension", isOn: Binding(
            get: { installed },
            set: { enable in
                if enable {
                    hostMissing = !FileManager.default.fileExists(atPath: NativeMessagingSetup.hostBinaryURL.path)
                    if !hostMissing { try? NativeMessagingSetup.install() }
                } else {
                    NativeMessagingSetup.uninstall()
                    hostMissing = false
                }
                installed = NativeMessagingSetup.isInstalled
            }
        ))
        Text(hostMissing
             ? "Host binary not found — run the bundled SwiftX.app (Scripts/make-app.sh)."
             : "Registers native messaging manifests for Chrome, Edge and Firefox. Restart the browser afterwards.")
            .font(.caption)
            .foregroundStyle(hostMissing ? .red : .secondary)
    }
}
