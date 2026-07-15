// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE.txt
//
// In-app editor for .sxcu custom uploaders, mirroring the Windows custom
// uploader settings window. Every edit saves straight back to the .sxcu file,
// so files stay interchangeable with Windows ShareX and the community repo.

import SwiftUI
import SharedKit
import UploadKit

struct KVRow: Identifiable, Equatable {
    let id = UUID()
    var key = ""
    var value = ""
}

struct CustomUploaderEditorView: View {
    @State private var files: [String] = CustomUploaderStore.list()
    @State private var selected = ""
    @State private var draft = CustomUploaderItem()
    @State private var headerRows: [KVRow] = []
    @State private var parameterRows: [KVRow] = []
    @State private var argumentRows: [KVRow] = []
    @State private var activeUploader = UploadersConfig.load().activeCustomUploader
    @State private var confirmDelete = false
    /// Name as loaded from disk; renames only happen after a real edit, so
    /// merely focusing an imported uploader never moves its file.
    @State private var loadedName = ""
    @FocusState private var nameFieldFocused: Bool

    private static let methods = ["GET", "POST", "PUT", "PATCH", "DELETE"]

    var body: some View {
        Section("Uploaders") {
            if files.isEmpty {
                Text("No custom uploaders yet. Create one, or import a community .sxcu file.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Uploader", selection: Binding(get: { selected }, set: select)) {
                    ForEach(files, id: \.self) { name in
                        Text(name + (name == activeUploader ? "  (active)" : "")).tag(name)
                    }
                }
            }
            HStack {
                Button("New") { create(from: CustomUploaderItem()) }
                Button("Duplicate") { create(from: draft) }
                    .disabled(selected.isEmpty)
                Button("Delete…", role: .destructive) { confirmDelete = true }
                    .disabled(selected.isEmpty)
                Button("Import…") { importFile() }
                Spacer()
                if !selected.isEmpty && selected != activeUploader {
                    Button("Set Active") {
                        activeUploader = selected
                        var config = UploadersConfig.load()
                        config.activeCustomUploader = selected
                        try? config.save()
                    }
                }
            }
            .confirmationDialog("Delete \(selected)?", isPresented: $confirmDelete) {
                Button("Delete", role: .destructive) { deleteSelected() }
            }
        }
        .onAppear {
            if selected.isEmpty {
                select(files.contains(activeUploader) ? activeUploader : (files.first ?? ""))
            }
        }

        if !selected.isEmpty {
            Section("Request") {
                TextField("Name", text: field(\.name))
                    .focused($nameFieldFocused)
                    .onSubmit { syncFileName() }
                    .onChange(of: nameFieldFocused) {
                        if !nameFieldFocused { syncFileName() }
                    }
                Picker("Method", selection: field(\.requestMethod)) {
                    ForEach(Self.methods, id: \.self) { Text($0).tag($0) }
                }
                TextField("Request URL", text: field(\.requestURL))
                Picker("Body", selection: Binding(
                    get: { draft.body },
                    set: { draft.body = $0; persist() }
                )) {
                    ForEach(CustomUploaderItem.BodyType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                if draft.body == .multipartFormData || draft.body == .binary {
                    TextField("File form name", text: field(\.fileFormName))
                }
                if draft.body == .json || draft.body == .xml {
                    TextField("Body data (supports {input}, {filename}…)", text: field(\.data), axis: .vertical)
                        .lineLimit(3...8)
                        .font(.body.monospaced())
                }
            }

            kvSection("URL parameters", rows: $parameterRows) { draft.parameters = $0 }
            kvSection("Headers", rows: $headerRows) { draft.headers = $0 }
            if draft.body == .multipartFormData || draft.body == .formURLEncoded {
                kvSection("Body arguments", rows: $argumentRows) { draft.arguments = $0 }
            }

            Section("Response") {
                TextField("URL (e.g. {json:url})", text: field(\.url))
                TextField("Thumbnail URL", text: field(\.thumbnailURL))
                TextField("Deletion URL", text: field(\.deletionURL))
                TextField("Error message", text: field(\.errorMessage))
                Text("Syntax: {json:path}, {regex:pattern|group}, {response}, {filename}, {random:a|b}, {base64:text} — same as Windows ShareX.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Key-value tables

    @ViewBuilder
    private func kvSection(_ title: String, rows: Binding<[KVRow]>, apply: @escaping ([String: String]) -> Void) -> some View {
        Section(title) {
            ForEach(rows) { $row in
                HStack {
                    TextField("Name", text: $row.key)
                        .frame(maxWidth: 180)
                    TextField("Value", text: $row.value)
                    Button {
                        rows.wrappedValue.removeAll { $0.id == row.id }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                    }
                    .buttonStyle(.borderless)
                }
            }
            Button {
                rows.wrappedValue.append(KVRow())
            } label: {
                Label("Add", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderless)
        }
        .onChange(of: rows.wrappedValue) {
            apply(dictionary(from: rows.wrappedValue))
            persist()
        }
    }

    private func dictionary(from rows: [KVRow]) -> [String: String] {
        var result: [String: String] = [:]
        for row in rows where !row.key.isEmpty {
            result[row.key] = row.value
        }
        return result
    }

    private static func rows(from dict: [String: String]) -> [KVRow] {
        dict.sorted { $0.key < $1.key }.map { KVRow(key: $0.key, value: $0.value) }
    }

    // MARK: - Persistence

    private func field(_ keyPath: WritableKeyPath<CustomUploaderItem, String>) -> Binding<String> {
        Binding(
            get: { draft[keyPath: keyPath] },
            set: { draft[keyPath: keyPath] = $0; persist() }
        )
    }

    private func persist() {
        guard !selected.isEmpty else { return }
        try? CustomUploaderStore.save(draft, as: selected)
    }

    /// Renames the .sxcu file to match the Name field (on Enter or focus loss).
    private func syncFileName() {
        guard draft.name != loadedName else { return }
        loadedName = draft.name
        guard !selected.isEmpty,
              let newName = try? CustomUploaderStore.rename(selected, toBaseName: draft.name),
              newName != selected else { return }
        if activeUploader == selected {
            activeUploader = newName
            var config = UploadersConfig.load()
            config.activeCustomUploader = newName
            try? config.save()
        }
        selected = newName
        files = CustomUploaderStore.list()
    }

    private func select(_ name: String) {
        selected = name
        let item = CustomUploaderStore.load(named: name) ?? CustomUploaderItem()
        draft = item
        loadedName = item.name
        headerRows = Self.rows(from: item.headers)
        parameterRows = Self.rows(from: item.parameters)
        argumentRows = Self.rows(from: item.arguments)
    }

    private func create(from template: CustomUploaderItem) {
        guard let fileName = try? CustomUploaderStore.create(named: "New Uploader", from: template) else { return }
        files = CustomUploaderStore.list()
        select(fileName)
    }

    private func deleteSelected() {
        try? CustomUploaderStore.delete(named: selected)
        if activeUploader == selected {
            activeUploader = ""
            var config = UploadersConfig.load()
            config.activeCustomUploader = ""
            try? config.save()
        }
        files = CustomUploaderStore.list()
        select(files.first ?? "")
        if files.isEmpty { selected = "" }
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json, .init(filenameExtension: "sxcu") ?? .json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let name = try? CustomUploaderStore.importFile(from: url) else { return }
        files = CustomUploaderStore.list()
        select(name)
    }
}
