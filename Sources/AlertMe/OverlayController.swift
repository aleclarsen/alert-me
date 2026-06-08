import AppKit
import Lottie

/// Shows the meeting alert: a borderless, transparent, click-through window that
/// floats above everything (including full-screen apps) and plays a Lottie
/// animation centered on the main screen, then dismisses itself.
@MainActor
final class OverlayController {
    private var window: NSWindow?
    private let config: Config

    init(config: Config) {
        self.config = config
    }

    func show() {
        // Don't stack overlays if one is already on screen.
        guard window == nil else { return }
        guard let screen = NSScreen.main else { return }

        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let container = NSView(frame: screen.frame)
        container.wantsLayer = true
        window.contentView = container

        let animationView = makeAnimationView()
        let side: CGFloat = 360
        animationView.frame = NSRect(
            x: (screen.frame.width - side) / 2,
            y: (screen.frame.height - side) / 2,
            width: side,
            height: side
        )
        animationView.contentMode = .scaleAspectFit
        container.addSubview(animationView)

        window.orderFrontRegardless()
        self.window = window

        animationView.play { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        }

        // Safety net in case the animation never reports completion.
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.dismiss()
        }
    }

    private func dismiss() {
        window?.orderOut(nil)
        window = nil
    }

    /// Loads the user's replacement animation if configured, otherwise the bundled default.
    private func makeAnimationView() -> LottieAnimationView {
        if let path = config.animationPath,
           !path.isEmpty,
           let animation = LottieAnimation.filepath(path) {
            return LottieAnimationView(animation: animation)
        }
        if let bundled = Bundle.module.path(forResource: "default-animation", ofType: "json"),
           let animation = LottieAnimation.filepath(bundled) {
            return LottieAnimationView(animation: animation)
        }
        return LottieAnimationView()
    }
}
