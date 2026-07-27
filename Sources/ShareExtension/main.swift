// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE
//
// Entry point for SwiftXShare.appex. App extensions start in Foundation's
// NSExtensionMain, which loads NSExtensionPrincipalClass and speaks the host's
// XPC protocol; Xcode's extension targets get there by overriding the linker
// entry point (-e _NSExtensionMain), which SwiftPM cannot set without unsafe
// flags. Calling the same function from an ordinary main is equivalent and has
// the Swift runtime already up by the time it runs.

import Foundation

@_silgen_name("NSExtensionMain")
func NSExtensionMain() -> Int32

exit(NSExtensionMain())
