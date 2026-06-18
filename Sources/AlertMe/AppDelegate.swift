import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let statusMenuItem = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
    private let arrivedMenuItem = NSMenuItem(title: "Trains arrived today: —", action: nil, keyEquivalent: "")

    private var config = Config.default
    private var auth: GoogleAuth!
    private var scheduler: MeetingScheduler!
    private var overlay: OverlayController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        loadConfig()

        auth = GoogleAuth(config: config)
        overlay = OverlayController(config: config)
        let calendar = CalendarService(auth: auth)
        scheduler = MeetingScheduler(calendar: calendar, overlay: overlay, config: config)
        scheduler.onStatus = { [weak self] text in
            Task { @MainActor in self?.statusMenuItem.title = text }
        }
        scheduler.onArrived = { [weak self] count in
            Task { @MainActor in self?.arrivedMenuItem.title = "Trains arrived today: \(count)" }
        }

        setupStatusItem()
        refreshMenu()

        // initial user greeting
        overlay.show(message: OverlayController.welcomeMessage)

        Task {
            if await auth.isSignedIn {
                scheduler.start()
            } else {
                statusMenuItem.title = "Not signed in"
            }
        }
    }

    private func loadConfig() {
        do {
            config = try ConfigStore.load()
        } catch {
            presentError("Failed to load config: \(error.localizedDescription)")
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            // Side-profile train matches the app icon. It needs macOS 14, so fall
            // back to tram.fill (available on the macOS 13 target) when unavailable.
            button.image = NSImage(systemSymbolName: "train.side.front.car", accessibilityDescription: "alert-me")
                ?? NSImage(systemSymbolName: "tram.fill", accessibilityDescription: "alert-me")
        }
    }

    private func refreshMenu() {
        let menu = NSMenu()
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        arrivedMenuItem.isEnabled = false
        menu.addItem(arrivedMenuItem)
        menu.addItem(.separator())

        Task {
            let signedIn = await auth.isSignedIn
            await MainActor.run {
                if signedIn {
                    menu.addItem(withTitle: "Sync now", action: #selector(self.syncNow), keyEquivalent: "r").target = self
                    menu.addItem(withTitle: "Sign out", action: #selector(self.signOut), keyEquivalent: "").target = self
                } else {
                    menu.addItem(withTitle: "Sign in to Google…", action: #selector(self.signIn), keyEquivalent: "").target = self
                }
                menu.addItem(.separator())
                menu.addItem(withTitle: "Test animation", action: #selector(self.testAnimation), keyEquivalent: "t").target = self
                menu.addItem(withTitle: "Open config file…", action: #selector(self.openConfig), keyEquivalent: "").target = self
                menu.addItem(.separator())
                menu.addItem(withTitle: "Quit alert-me", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
                self.statusItem.menu = menu
            }
        }
    }

    // MARK: - Actions

    @objc private func signIn() {
        Task {
            do {
                try await auth.signIn()
                scheduler.start()
                refreshMenu()
            } catch {
                presentError(error.localizedDescription)
            }
        }
    }

    @objc private func signOut() {
        Task {
            await auth.signOut()
            scheduler.stop()
            statusMenuItem.title = "Not signed in"
            refreshMenu()
        }
    }

    @objc private func syncNow() {
        scheduler.sync()
    }

    @objc private func testAnimation() {
        overlay.show(message: OverlayController.meetingMessage(title: "Test Meeting"))
    }

    @objc private func openConfig() {
        NSWorkspace.shared.open(ConfigStore.configURL)
    }

    private func presentError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "alert-me"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}
