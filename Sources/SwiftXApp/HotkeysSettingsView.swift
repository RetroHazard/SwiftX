// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE
//
// Hotkey editor: pick an action, click the combo button, press the keys.
// While recording, global registrations are suspended so the pressed combo
// reaches us instead of firing its current action.

import AppKit
import SwiftUI
import SharedKit

struct HotkeysSettingsView: View {
    @State private var settings = HotkeySettings.load()
    @State private var recordingIndex: Int?
    @State private var monitor: Any?

    var body: some View {
        Section("Hotkeys") {
            ForEach(settings.hotkeys.indices, id: \.self) { index in
                HStack {
                    Picker("", selection: taskTypeBinding(index)) {
                        ForEach(HotkeyType.allCases, id: \.rawValue) { type in
                            Text(Self.displayName(for: type)).tag(type.rawValue)
                        }
                    }
                    .labelsHidden()
                    Spacer()
                    Button(buttonTitle(index)) { startRecording(index) }
                        .font(.body.monospaced())
                    Button {
                        remove(index)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                    }
                    .buttonStyle(.borderless)
                }
            }
            Button {
                settings.hotkeys.append(HotkeyConfig(taskType: HotkeyType.none.rawValue))
                persist()
            } label: {
                Label("Add Hotkey", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderless)

            if recordingIndex != nil {
                Text("Press the new shortcut (with at least one modifier), or Esc to cancel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onDisappear { stopRecording() }
    }

    private func buttonTitle(_ index: Int) -> String {
        if recordingIndex == index { return "Press keys…" }
        return settings.hotkeys[index].combo?.displayString ?? "Record"
    }

    /// "ScreenRecorderGIF" -> "Screen Recorder GIF"
    static func displayName(for type: HotkeyType) -> String {
        var result = ""
        var previous: Character = " "
        for char in type.rawValue {
            if char.isUppercase, !previous.isUppercase, previous != " " {
                result.append(" ")
            }
            result.append(char)
            previous = char
        }
        return result
    }

    private func taskTypeBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { settings.hotkeys[index].taskType },
            set: { value in
                settings.hotkeys[index].taskType = value
                persist()
            }
        )
    }

    private func remove(_ index: Int) {
        stopRecording()
        settings.hotkeys.remove(at: index)
        persist()
    }

    private func startRecording(_ index: Int) {
        stopRecording()
        recordingIndex = index
        // suspend live hotkeys so re-recording the same combo works
        HotkeyCenter.shared.unregisterAll()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            capture(event)
            return nil // swallow the keystroke
        }
    }

    private func capture(_ event: NSEvent) {
        defer { stopRecording() }
        guard let index = recordingIndex else { return }

        var modifiers: [String] = []
        if event.modifierFlags.contains(.control) { modifiers.append("control") }
        if event.modifierFlags.contains(.option) { modifiers.append("option") }
        if event.modifierFlags.contains(.shift) { modifiers.append("shift") }
        if event.modifierFlags.contains(.command) { modifiers.append("command") }

        guard let key = KeyCombo.keyName(forCarbonKeyCode: UInt32(event.keyCode)),
              key != "escape" else { return }
        // an unmodified letter would hijack normal typing system-wide;
        // function keys are the accepted exception
        guard !modifiers.isEmpty || key.hasPrefix("f") && key.count > 1 else { return }

        settings.hotkeys[index].key = key
        settings.hotkeys[index].modifiers = modifiers
        persist()
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        recordingIndex = nil
        HotkeyRegistrar.applyAll()
    }

    private func persist() {
        try? settings.save()
        HotkeyRegistrar.applyAll()
    }
}
