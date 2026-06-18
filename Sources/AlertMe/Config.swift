import Foundation

/// User-editable configuration. Nothing about a Google account is hardcoded:
/// every user supplies their own OAuth client via this file so the app is
/// secure (no shared secret) and reusable by anyone.
struct Config: Codable {
    /// OAuth 2.0 Client ID from a Google Cloud "Desktop app" credential.
    var clientId: String
    /// OAuth client secret. Desktop clients are issued one; it is not truly
    /// confidential for installed apps, but Google's token endpoint expects it.
    var clientSecret: String?
    /// Scopes requested. Read-only calendar access is enough.
    var scopes: [String]
    /// How often to re-sync the calendar, in seconds.
    var pollIntervalSeconds: Double
    /// Fire the overlay this many seconds before the meeting starts (0 = at start).
    var leadTimeSeconds: Double
    /// Optional absolute path to a replacement Lottie JSON. When nil the bundled
    /// default animation is used. This is how the animation is "easily replaceable".
    var animationPath: String?

    static let `default` = Config(
        clientId: "",
        clientSecret: nil,
        scopes: ["https://www.googleapis.com/auth/calendar.readonly"],
        pollIntervalSeconds: 300,
        leadTimeSeconds: 180,
        animationPath: nil
    )
}

enum ConfigStore {
    /// ~/Library/Application Support/AlertMe
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("AlertMe", isDirectory: true)
    }

    static var configURL: URL {
        directory.appendingPathComponent("config.json")
    }

    /// Loads config, creating a template on first run so the user knows what to fill in.
    static func load() throws -> Config {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: configURL.path) {
            try save(.default)
            return .default
        }
        let data = try Data(contentsOf: configURL)
        return try JSONDecoder().decode(Config.self, from: data)
    }

    static func save(_ config: Config) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: configURL, options: .atomic)
    }
}
