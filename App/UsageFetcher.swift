import Foundation

enum FetchError: LocalizedError {
    case noCredentials
    case refreshFailed(String)
    case http(Int)
    case parse

    var errorDescription: String? {
        switch self {
        case .noCredentials: return "Accedi a Claude Code"
        case .refreshFailed(let msg): return "Rinnovo accesso fallito: \(msg)"
        case .http(let code): return "Errore server \(code)"
        case .parse: return "Risposta non valida"
        }
    }
}

/// Legge e aggiorna le credenziali che Claude Code salva nel Portachiavi,
/// usando lo stesso formato e lo stesso comando `security` che usa Claude Code.
enum ClaudeKeychain {
    static let service = "Claude Code-credentials"

    static func read() throws -> [String: Any] {
        let out = try run(["find-generic-password", "-a", NSUserName(), "-s", service, "-w"], stdin: nil)
        guard let data = out.data(using: .utf8),
              let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw FetchError.noCredentials }
        return dict
    }

    static func write(_ dict: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: dict)
        let hex = data.map { String(format: "%02x", $0) }.joined()
        // In modalità interattiva il segreto passa da stdin e non compare nella lista dei processi.
        _ = try run(["-i"], stdin: "add-generic-password -U -a \"\(NSUserName())\" -s \"\(service)\" -X \"\(hex)\"\n")
    }

    private static func run(_ args: [String], stdin: String?) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = args
        let outPipe = Pipe(), inPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = Pipe()
        if stdin != nil { p.standardInput = inPipe }
        try p.run()
        if let stdin {
            inPipe.fileHandleForWriting.write(stdin.data(using: .utf8)!)
            try inPipe.fileHandleForWriting.close()
        }
        let out = outPipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw FetchError.noCredentials }
        return String(decoding: out, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum UsageFetcher {
    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let tokenURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    private static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

    static func fetch() async throws -> UsageSnapshot {
        let token = try await validAccessToken()
        var req = URLRequest(url: usageURL)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw FetchError.http(status) }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FetchError.parse
        }
        return UsageSnapshot(
            session: window(json["five_hour"]),
            weekly: window(json["seven_day"]),
            fetchedAt: Date()
        )
    }

    private static func window(_ any: Any?) -> UsageWindow {
        let dict = any as? [String: Any]
        let percent = (dict?["utilization"] as? NSNumber)?.doubleValue ?? 0
        let resets = (dict?["resets_at"] as? String).flatMap(parseDate)
        return UsageWindow(percent: percent, resetsAt: resets)
    }

    /// Le date arrivano con i microsecondi ("…00.359510+00:00"), che ISO8601DateFormatter non sempre accetta.
    private static func parseDate(_ s: String) -> Date? {
        let trimmed = s.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return ISO8601DateFormatter().date(from: trimmed)
    }

    /// Restituisce un token valido, rinnovandolo (e salvandolo per Claude Code) se sta per scadere.
    private static func validAccessToken() async throws -> String {
        var creds = try ClaudeKeychain.read()
        guard var oauth = creds["claudeAiOauth"] as? [String: Any],
              let access = oauth["accessToken"] as? String
        else { throw FetchError.noCredentials }

        let expiresAt = (oauth["expiresAt"] as? NSNumber)?.doubleValue ?? 0
        if expiresAt / 1000 > Date().timeIntervalSince1970 + 120 { return access }

        guard let refresh = oauth["refreshToken"] as? String else { throw FetchError.noCredentials }
        let scopes = (oauth["scopes"] as? [String]) ?? []
        var req = URLRequest(url: tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "refresh_token": refresh,
            "client_id": clientID,
            "scope": scopes.joined(separator: " "),
        ])
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let newAccess = json["access_token"] as? String
        else { throw FetchError.refreshFailed("HTTP \(status)") }

        oauth["accessToken"] = newAccess
        if let newRefresh = json["refresh_token"] as? String { oauth["refreshToken"] = newRefresh }
        if let expiresIn = (json["expires_in"] as? NSNumber)?.doubleValue {
            oauth["expiresAt"] = Int64((Date().timeIntervalSince1970 + expiresIn) * 1000)
        }
        creds["claudeAiOauth"] = oauth
        try ClaudeKeychain.write(creds)
        return newAccess
    }
}
