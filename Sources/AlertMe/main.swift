import AppKit
import Lottie

// Headless self-test: verifies the bundled animation resolves and parses,
// without launching the menu-bar UI. Used by CI / `swift run AlertMe --check`.
if CommandLine.arguments.contains("--check") {
    guard let path = Bundle.module.path(forResource: "default-animation", ofType: "json") else {
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
