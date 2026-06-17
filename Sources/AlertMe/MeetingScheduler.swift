import Foundation

/// Periodically syncs the calendar and arms a timer for each upcoming meeting so
/// the overlay fires at (start − leadTime). De-duplicates so a meeting only
/// triggers once even though it shows up in several poll windows.
@MainActor
final class MeetingScheduler {
    private let calendar: CalendarService
    private let overlay: OverlayController
    private let config: Config

    private var pollTimer: Timer?
    private var armedTimers: [String: Timer] = [:]
    private var firedKeys: Set<String> = []

    /// Reports human-readable status changes for the menu bar.
    var onStatus: ((String) -> Void)?

    init(calendar: CalendarService, overlay: OverlayController, config: Config) {
        self.calendar = calendar
        self.overlay = overlay
        self.config = config
    }

    func start() {
        sync()
        pollTimer = Timer.scheduledTimer(withTimeInterval: config.pollIntervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sync() }
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        armedTimers.values.forEach { $0.invalidate() }
        armedTimers.removeAll()
    }

    func sync() {
        Task {
            do {
                // Look slightly past the next poll so nothing slips through the gap.
                let window = config.pollIntervalSeconds + config.leadTimeSeconds + 60
                let events = try await calendar.upcomingEvents(within: window)
                arm(events)
                onStatus?("Synced \(events.count) upcoming • \(timeString(Date()))")
            } catch {
                onStatus?("Sync error: \(error.localizedDescription)")
            }
        }
    }

    private func arm(_ events: [CalendarEvent]) {
        let now = Date()
        for event in events {
            let key = "\(event.id)@\(Int(event.start.timeIntervalSince1970))"
            guard !firedKeys.contains(key), armedTimers[key] == nil else { continue }

            let fireDate = event.start.addingTimeInterval(-config.leadTimeSeconds)
            let delay = fireDate.timeIntervalSince(now)

            if delay <= 0 {
                // Meeting is starting right now (within this poll); fire immediately.
                fire(key: key, title: event.title)
            } else {
                let title = event.title
                let timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                    Task { @MainActor in self?.fire(key: key, title: title) }
                }
                armedTimers[key] = timer
            }
        }
    }

    private func fire(key: String, title: String) {
        firedKeys.insert(key)
        armedTimers[key]?.invalidate()
        armedTimers[key] = nil
        overlay.show(message: OverlayController.meetingMessage(title: title))
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: date)
    }
}
