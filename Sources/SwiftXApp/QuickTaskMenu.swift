// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Contains code derived from ShareX, Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE
//
// Quick task menu: pops at the cursor after a capture when the
// ShowQuickTaskMenu flag is set. "Continue" keeps the configured chain,
// a preset replaces it for this run, anything else aborts the task.

import AppKit
import SharedKit
import SwiftUI

@MainActor
enum QuickTaskMenu {
    enum Choice {
        case continueChain
        case preset(QuickTaskPreset)
        case cancel
    }

    /// Blocks in the menu tracking loop until the user picks or dismisses.
    static func choose() -> Choice {
        var choice = Choice.cancel
        var actions: [MenuAction] = []

        let menu = NSMenu()
        func add(_ title: String, handler: @escaping () -> Void) {
            let action = MenuAction(handler)
            actions.append(action)
            let item = NSMenuItem(title: title, action: #selector(MenuAction.fire), keyEquivalent: "")
            item.target = action
            menu.addItem(item)
        }

        add(L10n.t("common.continue")) { choice = .continueChain }
        menu.addItem(.separator())
        for preset in ApplicationConfig.load().quickTaskPresets {
            if preset.isValid {
                add(preset.localizedDisplayName) { choice = .preset(preset) }
            } else {
                menu.addItem(.separator())
            }
        }
        menu.addItem(.separator())
        add(L10n.t("quicktaskmenu.edit_this_menu")) {
            ToolWindows.present(title: L10n.t("quicktaskmenu.window_title"), content: QuickTaskEditorView())
        }
        menu.addItem(.separator())
        add(L10n.t("common.cancel")) {}

        NSApp.activate(ignoringOtherApps: true)
        menu.popUp(positioning: menu.items.first, at: NSEvent.mouseLocation, in: nil)
        withExtendedLifetime(actions) {}
        return choice
    }
}

private final class MenuAction: NSObject {
    private let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
    @objc func fire() { handler() }
}

/// Checkbox list for a NamedOptionSet, shared by the quick task editor and
/// the after-capture window.
struct TaskFlagToggles<S: NamedOptionSet>: View {
    @Binding var value: S
    var excluded: S = []

    var body: some View {
        // closure, not key path: static requirement key paths crash SILGen
        ForEach(Array(S.flagNames.enumerated()), id: \.offset) { _, entry in
            if !excluded.contains(entry.0) {
                Toggle(taskFlagTitle(entry.1), isOn: Binding(
                    get: { value.contains(entry.0) },
                    set: { on in
                        if on { value.insert(entry.0) } else { value.remove(entry.0) }
                    }
                ))
            }
        }
    }
}

/// C# QuickTaskMenuEditorForm: manage presets; separators are empty entries.
struct QuickTaskEditorView: View {
    @State private var presets = ApplicationConfig.load().quickTaskPresets
    @State private var selection: Int?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                List(selection: $selection) {
                    ForEach(Array(presets.enumerated()), id: \.offset) { index, preset in
                        (preset.isValid ? Text(preset.localizedDisplayName)
                            : Text(L10n.t("quicktaskmenu.separator")).foregroundStyle(.secondary))
                            .tag(index)
                    }
                }
                .frame(minWidth: 240, minHeight: 260)
                HStack(spacing: 6) {
                    Button("+") { mutate { $0.append(QuickTaskPreset(afterCaptureTasks: [.saveImageToFile])) }
                        selection = presets.count - 1 }
                    Button(L10n.t("quicktaskmenu.separator_button")) { mutate { $0.append(QuickTaskPreset()) } }
                    Button("−") {
                        guard let index = selection, presets.indices.contains(index) else { return }
                        mutate { $0.remove(at: index) }
                        selection = nil
                    }
                    Button("↑") { move(-1) }
                    Button("↓") { move(1) }
                    Spacer()
                    Button(L10n.t("common.reset")) {
                        mutate { $0 = QuickTaskPreset.defaultPresets }
                        selection = nil
                    }
                }
            }

            Divider()

            if let index = selection, presets.indices.contains(index) {
                Form {
                    TextField(L10n.t("quicktaskmenu.name_label"), text: binding(index).name)
                    Section(L10n.t("pipeline.section.after_capture")) {
                        TaskFlagToggles(value: binding(index).afterCaptureTasks,
                                        excluded: [.showQuickTaskMenu])
                    }
                    Section(L10n.t("pipeline.section.after_upload")) {
                        TaskFlagToggles(value: binding(index).afterUploadTasks)
                    }
                }
                .formStyle(.grouped)
                .frame(minWidth: 320)
            } else {
                Text(L10n.t("quicktaskmenu.select_preset_hint"))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 320, maxHeight: .infinity)
            }
        }
        .padding()
    }

    private func binding(_ index: Int) -> Binding<QuickTaskPreset> {
        Binding(
            get: { presets.indices.contains(index) ? presets[index] : QuickTaskPreset() },
            set: { newValue in mutate { if $0.indices.contains(index) { $0[index] = newValue } } }
        )
    }

    private func mutate(_ body: (inout [QuickTaskPreset]) -> Void) {
        body(&presets)
        var config = ApplicationConfig.load()
        config.quickTaskPresets = presets
        try? config.save()
    }

    private func move(_ offset: Int) {
        guard let index = selection, presets.indices.contains(index),
              presets.indices.contains(index + offset) else { return }
        mutate { $0.swapAt(index, index + offset) }
        selection = index + offset
    }
}
