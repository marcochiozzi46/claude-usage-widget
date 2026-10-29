import Foundation

struct UsageWindow: Codable {
    var percent: Double
    var resetsAt: Date?

    /// Dopo l'orario di reset la finestra riparte da zero, anche se non abbiamo ancora un dato nuovo.
    func percent(at now: Date) -> Double {
        if let resetsAt, resetsAt <= now { return 0 }
        return percent
    }
}

struct UsageSnapshot: Codable {
    var session: UsageWindow
    var weekly: UsageWindow
    var fetchedAt: Date
    var error: String?

    static let placeholder = UsageSnapshot(
        session: UsageWindow(percent: 42, resetsAt: Date().addingTimeInterval(2 * 3600 + 14 * 60)),
        weekly: UsageWindow(percent: 17, resetsAt: Date().addingTimeInterval(3 * 86400)),
        fetchedAt: Date()
    )
}

enum SharedStore {
    static var groupID: String {
        Bundle.main.object(forInfoDictionaryKey: "AppGroup") as? String ?? ""
    }

    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appendingPathComponent("usage.json")
    }

    static func save(_ snapshot: UsageSnapshot) throws {
        guard let url = fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(snapshot).write(to: url, options: .atomic)
    }

    static func load() -> UsageSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(UsageSnapshot.self, from: data)
    }
}

enum Format {
    /// "2h 14m", "3d 5h", "12m"
    static func remaining(until date: Date?, from now: Date) -> String {
        guard let date else { return "—" }
        let s = max(0, Int(date.timeIntervalSince(now)))
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }
}
