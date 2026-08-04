// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE
//
// Settings pane for "Actions" - external programs run on captured files
// when the PerformActions after-capture task is enabled.

import SwiftUI
import SharedKit

struct ActionsSettingsView: View {
    @State private var programs = TaskSettings.load().externalPrograms

    var body: some View {
        // no section header: the navigation title above already says "External
        // Programs", and repeating it just spends a row
        Section {
            Text(L10n.t("settings.actions.help"))
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(programs.indices, id: \.self) { index in
                DisclosureGroup {
                    TextField(L10n.t("common.name"), text: binding(index, \.name))
                    HStack {
                        TextField(L10n.t("settings.actions.program_path"), text: binding(index, \.path))
                        Button(L10n.t("common.choose")) { choosePath(index) }
                    }
                    TextField(L10n.t("settings.actions.arguments"), text: binding(index, \.args))
                        .font(.body.monospaced())
                    TextField(L10n.t("settings.actions.output_extension"), text: binding(index, \.outputExtension))
                    TextField(L10n.t("settings.actions.only_for_extensions"), text: binding(index, \.extensions))
                    Toggle(L10n.t("settings.actions.move_input_to_trash"), isOn: binding(index, \.deleteInputFile))
                    Button(L10n.t("common.remove"), role: .destructive) { remove(index) }
                } label: {
                    Toggle(isOn: binding(index, \.isActive)) {
                        Text(programs[index].name.isEmpty ? L10n.t("settings.actions.unnamed_action") : programs[index].name)
                    }
                }
            }

            Button {
                var program = ExternalProgramSettings()
                program.isActive = true
                program.name = "New Action"
                programs.append(program)
                persist()
            } label: {
                Label(L10n.t("settings.actions.add_action"), systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderless)
        }
    }

    private func binding<T>(_ index: Int, _ keyPath: WritableKeyPath<ExternalProgramSettings, T>) -> Binding<T> {
        Binding(
            get: { programs[index][keyPath: keyPath] },
            set: { value in
                programs[index][keyPath: keyPath] = value
                persist()
            }
        )
    }

    private func remove(_ index: Int) {
        programs.remove(at: index)
        persist()
    }

    private func persist() {
        var task = TaskSettings.load()
        task.externalPrograms = programs
        try? task.save()
    }

    private func choosePath(_ index: Int) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.showsHiddenFiles = true
        panel.directoryURL = URL(fileURLWithPath: "/usr/local/bin")
        if panel.runModal() == .OK, let url = panel.url {
            programs[index].path = url.path
            persist()
        }
    }
}
