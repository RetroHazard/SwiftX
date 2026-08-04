// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE
//
// Write-through bindings shared by every settings pane. A macOS settings window
// saves on change - there is no OK button to save behind - so each control
// updates the view's copy (so SwiftUI refreshes) and persists the file.

import SwiftUI
import SharedKit

extension Binding where Value: SettingsFile {
    /// One field of a settings file the view holds in `@State`.
    func field<T>(_ keyPath: WritableKeyPath<Value, T>) -> Binding<T> {
        Binding<T>(
            get: { self.wrappedValue[keyPath: keyPath] },
            set: { newValue in
                var updated = self.wrappedValue
                updated[keyPath: keyPath] = newValue
                self.wrappedValue = updated
                // Persist against a fresh load, not the view's copy: the copy
                // can be stale (the cached settings window outlives it, and
                // sibling panes and the after-capture window write the same
                // file), and saving it whole would revert every field this
                // control doesn't own.
                var onDisk = Value.load()
                onDisk[keyPath: keyPath] = newValue
                try? onDisk.save()
            }
        )
    }

    /// Same, clamped on commit: text entry can produce anything.
    func field(_ keyPath: WritableKeyPath<Value, Int>, in range: ClosedRange<Int>) -> Binding<Int> {
        let base: Binding<Int> = field(keyPath)
        return Binding<Int>(get: { base.wrappedValue },
                             set: { base.wrappedValue = Swift.min(Swift.max($0, range.lowerBound), range.upperBound) })
    }

    func field(_ keyPath: WritableKeyPath<Value, Double>, in range: ClosedRange<Double>) -> Binding<Double> {
        let base: Binding<Double> = field(keyPath)
        return Binding<Double>(get: { base.wrappedValue },
                                set: { base.wrappedValue = Swift.min(Swift.max($0, range.lowerBound), range.upperBound) })
    }
}

enum SettingsBinding {
    /// For config no view keeps in `@State` - UploadersConfig is read from disk
    /// and the Keychain on every access, so a cached copy would go stale as soon
    /// as an OAuth connect or an .sxcu import writes to it.
    static func onDisk<Value: SettingsFile, T>(_ keyPath: WritableKeyPath<Value, T>) -> Binding<T> {
        Binding(
            get: { Value.load()[keyPath: keyPath] },
            set: { newValue in
                var updated = Value.load()
                updated[keyPath: keyPath] = newValue
                try? updated.save()
            }
        )
    }
}
