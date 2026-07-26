// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Contains code derived from ShareX, Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE
//
// Persists image effect presets and beautifier options to
// ImageEffects.json. Presets serialize through their C#-compatible
// config JSON, so the file's Effects entries match .sxie contents.

import EffectsKit
import Foundation
import SharedKit

@MainActor
final class ImageEffectsStore: ObservableObject {
    static let shared = ImageEffectsStore()

    @Published var presets: [ImageEffectPreset] = []
    @Published var selectedIndex = 0
    @Published var beautifier = ImageBeautifierOptions()

    private static var fileURL: URL { SettingsPaths.root.appendingPathComponent("ImageEffects.json") }

    init() {
        load()
    }

    var selectedPreset: ImageEffectPreset? {
        presets.indices.contains(selectedIndex) ? presets[selectedIndex] : nil
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            presets = [ImageEffectPreset.defaultPreset()]
            return
        }
        for entry in dict["Presets"] as? [[String: Any]] ?? [] {
            if let entryData = try? JSONSerialization.data(withJSONObject: entry),
               let preset = try? ImageEffectPreset.fromConfigJSON(entryData) {
                presets.append(preset)
            }
        }
        if presets.isEmpty { presets = [ImageEffectPreset.defaultPreset()] }
        selectedIndex = min(max(dict["SelectedPreset"] as? Int ?? 0, 0), presets.count - 1)
        if let options = dict["Beautifier"] as? [String: Any],
           let optionsData = try? JSONSerialization.data(withJSONObject: options),
           let decoded = try? JSONDecoder().decode(ImageBeautifierOptions.self, from: optionsData) {
            beautifier = decoded
        }
    }

    func save() {
        do {
            let dict: [String: Any] = [
                "SelectedPreset": selectedIndex,
                "Presets": try presets.map {
                    try JSONSerialization.jsonObject(with: $0.configJSON()) as! [String: Any]
                },
                "Beautifier": try JSONSerialization.jsonObject(with: JSONEncoder().encode(beautifier))
            ]
            try FileManager.default.createDirectory(at: SettingsPaths.root, withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
                .write(to: Self.fileURL, options: .atomic)
        } catch {
            AppLog.app.error("ImageEffectsStore save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
