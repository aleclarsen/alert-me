import AppKit
import Lottie

/// Shows the meeting alert: a borderless, transparent, click-through window that
/// floats above everything (including full-screen apps) and drives a Lottie
/// animation (a little steam train by default) across the top of the main
/// screen, then dismisses itself once it has chugged off the far edge.
@MainActor
final class OverlayController {
    private var window: NSWindow?
    private let config: Config

    /// Horizontal speed of the train, in points per second.
    private let travelSpeed: CGFloat = 420
    /// Distance from the top of the screen to the top of the train, in points.
    private let topMargin: CGFloat = 24

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

        // Size the train to a fraction of the screen height, preserving the
        // 360x200 aspect ratio of the bundled animation.
        let height = min(160, screen.frame.height * 0.18)
        let width = height * (360.0 / 200.0)
        let startY = screen.frame.height - height - topMargin

        let animationView = makeAnimationView()
        animationView.contentMode = .scaleAspectFit
        // Spin the wheels / puff the smoke continuously while it travels.
        animationView.loopMode = .loop
        // Park it just off the left edge to begin.
        animationView.frame = NSRect(x: -width, y: startY, width: width, height: height)
        animationView.wantsLayer = true
        container.addSubview(animationView)

        window.orderFrontRegardless()
        self.window = window

        animationView.play()

        // Slide the whole train from off the left edge to off the right edge at
        // a constant speed, then dismiss when it has fully exited.
        let travelDistance = screen.frame.width + width * 2
        let duration = CFTimeInterval(travelDistance / travelSpeed)

        guard let layer = animationView.layer else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in self?.dismiss() }
            return
        }

        let fromX = layer.position.x
        let toX = fromX + travelDistance

        let travel = CABasicAnimation(keyPath: "position.x")
        travel.fromValue = fromX
        travel.toValue = toX
        travel.duration = duration
        travel.timingFunction = CAMediaTimingFunction(name: .linear)
        travel.isRemovedOnCompletion = false
        travel.fillMode = .forwards

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            Task { @MainActor in self?.dismiss() }
        }
        layer.add(travel, forKey: "travel")
        CATransaction.commit()

        // Safety net in case the animation never reports completion.
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 2) { [weak self] in
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
        if let bundled = Bundle.module.path(forResource: "train-animation", ofType: "json"),
           let animation = LottieAnimation.filepath(bundled) {
            return LottieAnimationView(animation: animation)
        }
        return LottieAnimationView()
    }
}
