// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Contains code derived from ShareX, Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt
//
// Live upload rows for the main window: filename, destination, progress bar.
// Finished rows linger briefly so quick uploads are still visible, then clear.

import Foundation
import SwiftUI

@MainActor
final class UploadTaskCenter: ObservableObject {
    static let shared = UploadTaskCenter()

    enum State: Equatable {
        case uploading
        case completed(url: String)
        case failed(message: String)
        case retrying
    }

    struct Entry: Identifiable {
        let id = UUID()
        let fileName: String
        let host: String
        var fraction: Double = 0
        var state: State = .uploading
    }

    @Published private(set) var entries: [Entry] = []

    /// Uploads still in flight (auto capture's "wait for uploads" gate).
    var isBusy: Bool {
        entries.contains { $0.state == .uploading || $0.state == .retrying }
    }

    private var inFlight: [UUID: Task<Void, Never>] = [:]

    func begin(fileName: String, host: String) -> UUID {
        let entry = Entry(fileName: fileName, host: host)
        entries.append(entry)
        return entry.id
    }

    func register(_ id: UUID, task: Task<Void, Never>) {
        inFlight[id] = task
    }

    /// StopUploads hotkey (C# TaskManager.StopAllTasks).
    func stopAll() {
        inFlight.values.forEach { $0.cancel() }
    }

    func progress(_ id: UUID, sent: Int64, expected: Int64) {
        guard expected > 0, let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let fraction = Double(sent) / Double(expected)
        // didSendBodyData fires constantly; only publish visible changes
        guard abs(fraction - entries[index].fraction) > 0.01 || fraction >= 1 else { return }
        entries[index].fraction = fraction
    }

    func finish(_ id: UUID, state: State) {
        inFlight[id] = nil
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].state = state
        if case .completed = state { entries[index].fraction = 1 }
        let linger: Duration = if case .failed = state { .seconds(10) } else { .seconds(5) }
        Task {
            try? await Task.sleep(for: linger)
            entries.removeAll { $0.id == id }
        }
    }
}

struct UploadTaskRows: View {
    @ObservedObject var center = UploadTaskCenter.shared

    var body: some View {
        if !center.entries.isEmpty {
            VStack(spacing: 6) {
                ForEach(center.entries) { entry in
                    HStack(spacing: 8) {
                        stateIcon(entry.state)
                        Text(entry.fileName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if entry.state == .uploading {
                            ProgressView(value: min(entry.fraction, 1))
                                .frame(maxWidth: .infinity)
                        } else {
                            Text(stateText(entry.state))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Text(entry.host)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
        }
    }

    @ViewBuilder
    private func stateIcon(_ state: UploadTaskCenter.State) -> some View {
        switch state {
        case .uploading:
            Image(systemName: "arrow.up.circle").foregroundStyle(.blue)
        case .completed:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .retrying:
            Image(systemName: "arrow.clockwise.circle").foregroundStyle(.orange)
        }
    }

    private func stateText(_ state: UploadTaskCenter.State) -> String {
        switch state {
        case .uploading: ""
        case .completed(let url): url
        case .failed(let message): message
        case .retrying: "Retrying…"
        }
    }
}
