// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE
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
        present(title: L10n.t("log.window_title"), resizable: true, content: LogViewerView())
    }
}

private struct LogViewerView: View {
    @State private var text = L10n.t("log.loading")

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
                Text(L10n.t("log.footer", AppLog.subsystem))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(L10n.t("common.copy")) {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(text, forType: .string)
                }
                Button(L10n.t("log.refresh")) { load() }
            }
        }
        .padding(12)
        .onAppear { load() }
    }

    private func load() {
        let emptyMessage = L10n.t("log.empty")
        let readFailedFormat = L10n.t("log.read_failed")
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
                content = lines.isEmpty ? emptyMessage : lines.joined(separator: "\n")
            } catch {
                content = String(format: readFailedFormat, error.localizedDescription)
            }
            await MainActor.run { text = content }
        }
    }
}
