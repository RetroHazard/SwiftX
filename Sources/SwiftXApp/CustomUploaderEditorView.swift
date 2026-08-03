// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE
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
        Section(L10n.t("settings.customuploader.uploaders")) {
            if files.isEmpty {
                Text(L10n.t("settings.customuploader.empty_hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Picker(L10n.t("settings.customuploader.uploader"), selection: Binding(get: { selected }, set: select)) {
                    ForEach(files, id: \.self) { name in
                        Text(name + (name == activeUploader ? L10n.t("settings.customuploader.active_suffix") : "")).tag(name)
                    }
                }
            }
            HStack {
                Button(L10n.t("settings.customuploader.new")) { create(from: CustomUploaderItem()) }
                Button(L10n.t("settings.customuploader.duplicate")) { create(from: draft) }
                    .disabled(selected.isEmpty)
                Button(L10n.t("settings.customuploader.delete"), role: .destructive) { confirmDelete = true }
                    .disabled(selected.isEmpty)
                Button(L10n.t("settings.customuploader.import")) { importFile() }
                Button(L10n.t("settings.customuploader.export")) { exportFile() }
                    .disabled(selected.isEmpty)
                Spacer()
                if !selected.isEmpty && selected != activeUploader {
                    Button(L10n.t("settings.customuploader.set_active")) {
                        activeUploader = selected
                        var config = UploadersConfig.load()
                        config.activeCustomUploader = selected
                        try? config.save()
                    }
                }
            }
            .confirmationDialog(L10n.t("settings.customuploader.confirm_delete", selected), isPresented: $confirmDelete) {
                Button(L10n.t("common.delete"), role: .destructive) { deleteSelected() }
            }
        }
        .onAppear {
            if selected.isEmpty {
                select(files.contains(activeUploader) ? activeUploader : (files.first ?? ""))
            }
        }

        if !selected.isEmpty {
            Section(L10n.t("settings.customuploader.request")) {
                TextField(L10n.t("common.name"), text: field(\.name))
                    .focused($nameFieldFocused)
                    .onSubmit { syncFileName() }
                    .onChange(of: nameFieldFocused) {
                        if !nameFieldFocused { syncFileName() }
                    }
                Picker(L10n.t("settings.customuploader.method"), selection: field(\.requestMethod)) {
                    ForEach(Self.methods, id: \.self) { Text($0).tag($0) }
                }
                TextField(L10n.t("settings.customuploader.request_url"), text: field(\.requestURL))
                Picker(L10n.t("settings.customuploader.body"), selection: Binding(
                    get: { draft.body },
                    set: { draft.body = $0; persist() }
                )) {
                    ForEach(CustomUploaderItem.BodyType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                if draft.body == .multipartFormData || draft.body == .binary {
                    TextField(L10n.t("settings.customuploader.file_form_name"), text: field(\.fileFormName))
                }
                if draft.body == .json || draft.body == .xml {
                    TextField(L10n.t("settings.customuploader.body_data"), text: field(\.data), axis: .vertical)
                        .lineLimit(3...8)
                        .font(.body.monospaced())
                }
            }

            kvSection(L10n.t("settings.customuploader.url_parameters"), rows: $parameterRows) { draft.parameters = $0 }
            kvSection(L10n.t("settings.customuploader.headers"), rows: $headerRows) { draft.headers = $0 }
            if draft.body == .multipartFormData || draft.body == .formURLEncoded {
                kvSection(L10n.t("settings.customuploader.body_arguments"), rows: $argumentRows) { draft.arguments = $0 }
            }

            Section(L10n.t("settings.customuploader.response")) {
                TextField(L10n.t("settings.customuploader.response_url"), text: field(\.url))
                TextField(L10n.t("settings.customuploader.thumbnail_url"), text: field(\.thumbnailURL))
                TextField(L10n.t("settings.customuploader.deletion_url"), text: field(\.deletionURL))
                TextField(L10n.t("settings.customuploader.error_message"), text: field(\.errorMessage))
                Text(L10n.t("settings.customuploader.syntax_help"))
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
                    TextField(L10n.t("common.name"), text: $row.key)
                        .frame(maxWidth: 180)
                    TextField(L10n.t("settings.customuploader.value"), text: $row.value)
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
                Label(L10n.t("common.add"), systemImage: "plus.circle.fill")
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

    private func exportFile() {
        guard !selected.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "sxcu") ?? .json]
        panel.nameFieldStringValue = selected
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try CustomUploaderStore.exportFile(named: selected, to: url)
        } catch {
            Notifier.notify(title: L10n.t("settings.customuploader.export_failed"), body: error.localizedDescription)
        }
    }
}
