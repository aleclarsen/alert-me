import AppKit
import Lottie

// SPM executables don't automatically expose the .app bundle's Info.plist via
// Bundle.main. macOS window-tabbing (and other subsystems) read CFBundleIdentifier
// very early, before NSApplication is set up, and log a warning when it's missing.
// Force-populating it here silences "Cannot index window tabs due to missing main
// bundle identifier" and ensures any code that reads Bundle.main.bundleIdentifier
// gets the correct value.
if Bundle.main.bundleIdentifier == nil {
    // Bundle.infoDictionary is read-only, but the underlying CFBundle dictionary
    // is a mutable CFDictionary that we can write into directly via the CF API.
    let infoDict = CFBundleGetInfoDictionary(CFBundleGetMainBundle())
    let mutableInfoDict = infoDict as! NSMutableDictionary
    mutableInfoDict[kCFBundleIdentifierKey] = "com.alertme.app"
}

// Headless self-test: verifies the bundled animation resolves and parses,
// without launching the menu-bar UI. Used by CI / `swift run AlertMe --check`.
if CommandLine.arguments.contains("--check") {
    guard let path = Bundle.module.path(forResource: "train-animation", ofType: "json") else {
        print("FAIL: bundled animation not found via Bundle.module")
        exit(1)
    }
    guard LottieAnimation.filepath(path) != nil else {
        print("FAIL: Lottie could not parse \(path)")
        exit(1)
    }
    print("OK: bundled animation resolved and parsed")
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    // Menu-bar agent: no Dock icon, no main window.
    app.setActivationPolicy(.accessory)
    app.run()
}
