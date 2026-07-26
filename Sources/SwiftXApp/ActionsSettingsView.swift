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
        Section("Actions") {
            Text("Programs run on the saved file, in order, when “Perform actions” is enabled in Capture. Placeholders: $input, $output (%input/%output add quotes).")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(programs.indices, id: \.self) { index in
                DisclosureGroup {
                    TextField("Name", text: binding(index, \.name))
                    HStack {
                        TextField("Program path (/usr/local/bin/…)", text: binding(index, \.path))
                        Button("Choose…") { choosePath(index) }
                    }
                    TextField("Arguments (empty = the file path)", text: binding(index, \.args))
                        .font(.body.monospaced())
                    TextField("Output extension (task continues with the output file)", text: binding(index, \.outputExtension))
                    TextField("Only for extensions (e.g. png, jpg — empty = all)", text: binding(index, \.extensions))
                    Toggle("Move input file to Trash after a successful conversion", isOn: binding(index, \.deleteInputFile))
                    Button("Remove", role: .destructive) { remove(index) }
                } label: {
                    Toggle(isOn: binding(index, \.isActive)) {
                        Text(programs[index].name.isEmpty ? "(unnamed action)" : programs[index].name)
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
                Label("Add Action", systemImage: "plus.circle.fill")
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
