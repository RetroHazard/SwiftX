// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt
//
// Global hotkeys via Carbon RegisterEventHotKey - still the supported API for
// system-wide shortcuts, and the only one that needs no TCC permission.

import AppKit
import Carbon.HIToolbox
import SharedKit

@MainActor
final class HotkeyCenter {
    static let shared = HotkeyCenter()

    /// DisableHotkeys toggles this; hotkeys marked alwaysEnabled bypass it.
    var isEnabled = true

    private struct Registration {
        let action: () -> Void
        let alwaysEnabled: Bool
        let ref: EventHotKeyRef
    }

    private var registrations: [UInt32: Registration] = [:]
    private var nextID: UInt32 = 1
    private var handlerInstalled = false

    @discardableResult
    func register(_ combo: KeyCombo, alwaysEnabled: Bool = false, action: @escaping () -> Void) -> Bool {
        installHandlerIfNeeded()
        guard let keyCode = combo.carbonKeyCode else { return false }

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x5348_5258) /* 'SHRX' */, id: nextID)
        let status = RegisterEventHotKey(keyCode, combo.carbonModifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }

        registrations[nextID] = Registration(action: action, alwaysEnabled: alwaysEnabled, ref: ref)
        nextID += 1
        return true
    }

    func unregisterAll() {
        registrations.values.forEach { UnregisterEventHotKey($0.ref) }
        registrations.removeAll()
    }

    fileprivate func fire(id: UInt32) {
        guard let registration = registrations[id] else { return }
        guard isEnabled || registration.alwaysEnabled else { return }
        registration.action()
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        // C callback: no captures allowed; Carbon delivers on the main thread
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            guard let event else { return noErr }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            MainActor.assumeIsolated {
                HotkeyCenter.shared.fire(id: hotKeyID.id)
            }
            return noErr
        }, 1, &eventType, nil, nil)
    }
}

/// (Re)registers every configured hotkey; the settings recorder calls this
/// after edits so changes apply without a relaunch.
@MainActor
enum HotkeyRegistrar {
    static func applyAll() {
        HotkeyCenter.shared.unregisterAll()
        for config in HotkeySettings.load().hotkeys {
            guard let combo = config.combo, let type = config.type, type != .none else { continue }
            let registered = HotkeyCenter.shared.register(combo, alwaysEnabled: type == .disableHotkeys) {
                HotkeyDispatcher.execute(type)
            }
            if !registered {
                NSLog("Could not register hotkey %@ for %@ (conflict or unknown key)",
                      combo.displayString, config.taskType)
            }
        }
    }
}

/// Maps hotkey actions to implementations. Unimplemented types log and no-op
/// until their phase lands.
@MainActor
enum HotkeyDispatcher {
    static func execute(_ type: HotkeyType) {
        switch type {
        case .rectangleRegion:
            CaptureCoordinator.shared.captureRegion()
        case .lastRegion:
            CaptureCoordinator.shared.captureLastRegion()
        case .printScreen, .activeMonitor:
            // both capture the display under the cursor; C# PrintScreen
            // stitches all displays, which waits on cross-display capture
            CaptureCoordinator.shared.captureFullScreen()
        case .activeWindow:
            CaptureCoordinator.shared.captureActiveWindow()
        case .screenRecorder, .screenRecorderCustomRegion:
            RecordingCoordinator.shared.toggleRegion(gif: false)
        case .startScreenRecorder:
            RecordingCoordinator.shared.toggleDisplay(gif: false)
        case .screenRecorderActiveWindow:
            RecordingCoordinator.shared.toggleActiveWindow(gif: false)
        case .screenRecorderGIF, .screenRecorderGIFCustomRegion:
            RecordingCoordinator.shared.toggleRegion(gif: true)
        case .startScreenRecorderGIF:
            RecordingCoordinator.shared.toggleDisplay(gif: true)
        case .screenRecorderGIFActiveWindow:
            RecordingCoordinator.shared.toggleActiveWindow(gif: true)
        case .stopScreenRecording:
            RecordingCoordinator.shared.stop()
        case .pauseScreenRecording:
            RecordingCoordinator.shared.togglePause()
        case .abortScreenRecording:
            RecordingCoordinator.shared.abort()
        case .openMainWindow, .openHistory, .openImageHistory:
            (NSApp.delegate as? AppDelegate)?.showMainWindow()
        case .openScreenshotsFolder:
            NSWorkspace.shared.open(ApplicationConfig.load().screenshotsFolder)
        case .colorPicker:
            ToolWindows.showColorPicker()
        case .ocr:
            ToolWindows.runOCRFromRegion()
        case .qrCode:
            ToolWindows.showQRCode()
        case .qrCodeDecodeFromScreen:
            ToolWindows.scanQRFromScreen()
        case .qrCodeScanRegion:
            ToolWindows.scanQRFromRegion()
        case .hashCheck:
            ToolWindows.showHashChecker()
        case .videoConverter:
            ToolWindows.showVideoConverter()
        case .videoThumbnailer:
            ToolWindows.showVideoThumbnailer()
        case .imageViewer:
            ToolWindows.showImageViewer()
        case .imageCombiner:
            ToolWindows.showImageCombiner()
        case .imageSplitter:
            ToolWindows.showImageSplitter()
        case .imageThumbnailer:
            ToolWindows.showImageThumbnailer()
        case .metadata:
            ToolWindows.showMetadataViewer()
        case .stripMetadata:
            ToolWindows.stripMetadataFromFile()
        case .indexFolder:
            ToolWindows.showFolderIndexer()
        case .clipboardViewer:
            ToolWindows.showClipboardViewer()
        case .inspectWindow:
            ToolWindows.showWindowInspector()
        case .monitorTest:
            ToolWindows.showMonitorTest()
        case .screenColorPicker:
            ToolWindows.pickScreenColor()
        case .ruler:
            ToolWindows.runRuler()
        case .pinToScreen, .pinToScreenFromClipboard:
            PinnedWindows.pinFromClipboard()
        case .pinToScreenFromScreen:
            PinnedWindows.pinFromScreen()
        case .pinToScreenFromFile:
            PinnedWindows.pinFromFile()
        case .pinToScreenCloseAll:
            PinnedWindows.closeAll()
        case .disableHotkeys:
            HotkeyCenter.shared.isEnabled.toggle()
        case .exitShareX:
            NSApp.terminate(nil)
        default:
            NSLog("HotkeyType %@ is not implemented yet", type.rawValue)
        }
    }
}
