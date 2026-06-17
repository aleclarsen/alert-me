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
    private let travelSpeed: CGFloat = 210
    /// Distance from the top of the screen to the top of the train, in points.
    private let topMargin: CGFloat = 24

    nonisolated static let meetingMessage = "Choo choo! You have a meeting starting soon!"
    nonisolated static let welcomeMessage = "All aboard! I'll whistle when a meeting pulls in today! 🚂"

    init(config: Config) {
        self.config = config
    }

    func show(message: String = OverlayController.meetingMessage) {
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
        let trainHeight = min(160, screen.frame.height * 0.18)
        let trainWidth = trainHeight * (360.0 / 200.0)
        let topY = screen.frame.height - trainHeight - topMargin

        let animationView = makeAnimationView()
        animationView.contentMode = .scaleAspectFit
        // Spin the wheels / puff the smoke continuously while it travels.
        animationView.loopMode = .loop
        animationView.wantsLayer = true

        // The message rides behind (to the right of) the train.
        let textLayer = makeMessageLayer(message: message, trainHeight: trainHeight, scale: screen.backingScaleFactor)
        let gap: CGFloat = 24

        // A "convoy" view holds the train and the trailing text so they move
        // together as one unit.
        let convoyWidth = trainWidth + gap + textLayer.bounds.width
        let convoy = NSView(frame: NSRect(x: screen.frame.width, y: topY, width: convoyWidth, height: trainHeight))
        convoy.wantsLayer = true

        animationView.frame = NSRect(x: 0, y: 0, width: trainWidth, height: trainHeight)
        convoy.addSubview(animationView)

        textLayer.position = CGPoint(x: trainWidth + gap + textLayer.bounds.width / 2, y: trainHeight / 2)
        convoy.layer?.addSublayer(textLayer)
        container.addSubview(convoy)

        window.orderFrontRegardless()
        self.window = window

        animationView.play()

        // Slide the convoy from just off the right edge to fully off the left
        // edge at a constant speed, then dismiss when it has exited.
        let travelDistance = screen.frame.width + convoyWidth
        let duration = CFTimeInterval(travelDistance / travelSpeed)

        guard let layer = convoy.layer else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in self?.dismiss() }
            return
        }

        // Layer position is its center; the frame above puts that at the far right.
        let fromX = layer.position.x
        let toX = fromX - travelDistance

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
        layer.position.x = toX
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

    /// Builds the trailing message as a CATextLayer: bold white text with a soft
    /// shadow so it stays readable over any wallpaper. A text layer (rather than
    /// an NSTextField) renders reliably inside this transparent, non-key,
    /// click-through overlay window and rides along with the convoy's layer.
    private func makeMessageLayer(message: String, trainHeight: CGFloat, scale: CGFloat) -> CATextLayer {
        let fontSize = max(20, trainHeight * 0.26)
        let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
        let size = (message as NSString).size(withAttributes: [.font: font])

        let textLayer = CATextLayer()
        textLayer.string = message
        textLayer.font = font
        textLayer.fontSize = fontSize
        textLayer.foregroundColor = NSColor.white.cgColor
        textLayer.alignmentMode = .left
        textLayer.isWrapped = false
        textLayer.truncationMode = .none
        textLayer.contentsScale = scale
        // Pad a little so the glyphs and shadow aren't clipped.
        textLayer.bounds = CGRect(x: 0, y: 0, width: ceil(size.width) + 12, height: ceil(size.height) + 8)

        textLayer.shadowColor = NSColor.black.cgColor
        textLayer.shadowOpacity = 0.7
        textLayer.shadowRadius = 4
        textLayer.shadowOffset = CGSize(width: 0, height: -2)
        return textLayer
    }

    /// Loads the user's replacement animation if configured, otherwise the bundled default.
    private func makeAnimationView() -> LottieAnimationView {
        if let path = config.animationPath,
           !path.isEmpty,
           let animation = LottieAnimation.filepath(path) {
            return LottieAnimationView(animation: animation)
        }
        if let bundled = AnimationBundle.defaultAnimationPath,
           let animation = LottieAnimation.filepath(bundled) {
            return LottieAnimationView(animation: animation)
        }
        return LottieAnimationView()
    }
}

/// Resolves the bundled default animation. In a packaged `.app` the JSON lives in
/// `Contents/Resources` (found via `Bundle.main`); in a `swift run` dev build it
/// lives in the SwiftPM resource bundle (found via `Bundle.module`).
enum AnimationBundle {
    static let resourceName = "train-animation"

    static var defaultAnimationPath: String? {
        Bundle.main.path(forResource: resourceName, ofType: "json")
            ?? Bundle.module.path(forResource: resourceName, ofType: "json")
    }
}
