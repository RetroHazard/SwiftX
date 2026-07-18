// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE.txt
//
// os.Logger subsystem (upstream keeps a rotating log file + viewer; on macOS
// the unified log owns storage/rotation, and the in-app Show Log window reads
// it back through OSLogStore). Messages are marked public: this is a debug
// log the user is meant to read, not telemetry.

import Foundation
import os

public enum AppLog {
    public static let subsystem = "com.retrohazard.swiftx"

    public static let app = Logger(subsystem: subsystem, category: "app")
    public static let capture = Logger(subsystem: subsystem, category: "capture")
    public static let upload = Logger(subsystem: subsystem, category: "upload")
    public static let hotkeys = Logger(subsystem: subsystem, category: "hotkeys")
    public static let history = Logger(subsystem: subsystem, category: "history")
    public static let notifications = Logger(subsystem: subsystem, category: "notifications")
}
