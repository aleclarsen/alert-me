import Foundation

struct CalendarEvent: Identifiable {
    let id: String
    let title: String
    let start: Date
}

/// Thin wrapper over the Google Calendar v3 REST API. Read-only: it only lists
/// events on the user's primary calendar.
struct CalendarService {
    let auth: GoogleAuth

    /// Returns timed events on the primary calendar starting within the next `window` seconds.
    func upcomingEvents(within window: TimeInterval) async throws -> [CalendarEvent] {
        let now = Date()
        let events = try await fetchEvents(timeMin: now, timeMax: now.addingTimeInterval(window))
        // Google's timeMin filters on event END time, so meetings already in
        // progress come back too. We only want events that haven't started yet,
        // so the overlay fires as a pre-meeting heads-up rather than late.
        return events.filter { $0.start >= now }
    }

    /// Counts timed meetings that have already started earlier today — the
    /// "trains" that have already arrived. View-only; never arms the overlay.
    func pastMeetingsToday() async throws -> Int {
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let events = try await fetchEvents(timeMin: startOfDay, timeMax: now)
        return events.filter { $0.start >= startOfDay && $0.start <= now }.count
    }

    /// Lists timed events whose Google-side window overlaps [timeMin, timeMax].
    /// All-day events are dropped here; callers filter further by start time.
    private func fetchEvents(timeMin: Date, timeMax: Date) async throws -> [CalendarEvent] {
        let token = try await auth.validAccessToken()

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        var comps = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")!
        comps.queryItems = [
            URLQueryItem(name: "timeMin", value: formatter.string(from: timeMin)),
            URLQueryItem(name: "timeMax", value: formatter.string(from: timeMax)),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "maxResults", value: "50")
        ]

        var request = URLRequest(url: comps.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AuthError.message("Calendar API error \(http.statusCode): \(body)")
        }

        let decoded = try JSONDecoder().decode(EventsResponse.self, from: data)
        return decoded.items.compactMap { item in
            // Only timed events have start.dateTime; all-day events (start.date) are skipped.
            guard let startString = item.start.dateTime,
                  let start = formatter.date(from: startString) else { return nil }
            return CalendarEvent(id: item.id, title: item.summary ?? "(no title)", start: start)
        }
    }
}

private struct EventsResponse: Decodable {
    let items: [Item]
    struct Item: Decodable {
        let id: String
        let summary: String?
        let start: Start
    }
    struct Start: Decodable {
        let dateTime: String?
        let date: String?
    }
}
