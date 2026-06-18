import Foundation

struct CalendarEvent: Identifiable {
    let id: String
    let title: String
    let start: Date
}

/// Thin wrapper over the Google Calendar v3 REST API. Read-only: it only lists
/// upcoming events on the user's primary calendar.
struct CalendarService {
    let auth: GoogleAuth

    /// Returns timed events on the primary calendar starting within the next `window` seconds.
    func upcomingEvents(within window: TimeInterval) async throws -> [CalendarEvent] {
        let token = try await auth.validAccessToken()

        let now = Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        var comps = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")!
        comps.queryItems = [
            URLQueryItem(name: "timeMin", value: formatter.string(from: now)),
            URLQueryItem(name: "timeMax", value: formatter.string(from: now.addingTimeInterval(window))),
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
            // Google's timeMin filters on event END time, so meetings already in
            // progress come back too. We only want events that haven't started yet,
            // so the overlay fires as a pre-meeting heads-up rather than late.
            guard start >= now else { return nil }
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
