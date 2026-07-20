// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE.txt
//
// "Show Log" window (upstream DebugForm equivalent): reads this process's
// entries for the SwiftX subsystem back out of the unified log. Storage and
// rotation belong to the system, so there are no log files to clean up.

import AppKit
import OSLog
import SharedKit
import SwiftUI

extension ToolWindows {
    static func showLog() {
        present(title: "SwiftX Log", resizable: true, content: LogViewerView())
    }
}

private struct LogViewerView: View {
    @State private var text = "Loading…"

    var body: some View {
        VStack(spacing: 8) {
            ScrollView {
                Text(text)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(minWidth: 640, minHeight: 400)
            .background(Color(nsColor: .textBackgroundColor))

            HStack {
                Text("This session's log (subsystem \(AppLog.subsystem)); "
                     + "the unified log owns storage, so there is nothing to clean up.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Copy") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(text, forType: .string)
                }
                Button("Refresh") { load() }
            }
        }
        .padding(12)
        .onAppear { load() }
    }

    private func load() {
        Task.detached(priority: .userInitiated) {
            let content: String
            do {
                // OSLogStore is blocking; keep it off the main thread
                let store = try OSLogStore(scope: .currentProcessIdentifier)
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm:ss.SSS"
                let lines = try store.getEntries()
                    .compactMap { $0 as? OSLogEntryLog }
                    .filter { $0.subsystem == AppLog.subsystem }
                    .map { "\(formatter.string(from: $0.date)) [\($0.category)] \($0.composedMessage)" }
                content = lines.isEmpty ? "No log entries this session." : lines.joined(separator: "\n")
            } catch {
                content = "Could not read the log: \(error.localizedDescription)"
            }
            await MainActor.run { text = content }
        }
    }
}
