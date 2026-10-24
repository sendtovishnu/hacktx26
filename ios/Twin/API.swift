import Foundation

// One protocol, two implementations: APIClient talks to Person A's server,
// MockAPI runs the whole flow on bundled JSON so the UI never waits on the server.

@MainActor
protocol TwinAPI: AnyObject {
    var currentUserId: String { get set }

    func users() async throws -> [User]
    func me() async throws -> User
    func friends() async throws -> [FriendEntry]
    func setTier(friendId: String, tier: Tier) async throws -> FriendEntry
    func addFriend(friendId: String, tier: Tier) async throws -> FriendEntry
    func exchangeGoogleCode(_ code: String) async throws
    func ingestGoogle() async throws -> IngestResult
    func ingestICS(data: Data, filename: String) async throws -> IngestResult
    func refreshTwin(checkin: String?) async throws -> TwinRefreshResult
    func twin() async throws -> Signals?
    func updateSummaries(closest: String, close: String, friend: String) async throws -> Signals
    func resetSummaries() async throws -> Signals
    func nudges() async throws -> [Nudge]
    func suggestions(nudgeId: String) async throws -> [Suggestion]
    func sendGesture(nudgeId: String, suggestionIndex: Int) async throws -> Gesture
    func surprises() async throws -> [Gesture]
    func privacy() async throws -> PrivacyInfo
    func updateSettings(surpriseOptIn: Bool?, paused: Bool?) async throws -> User
    func uploadPhoto(_ jpeg: Data) async throws -> User
    func removePhoto() async throws -> User
}

enum APIError: LocalizedError {
    case badURL
    case http(Int, String)
    case notConfigured(String)

    var errorDescription: String? {
        switch self {
        case .badURL:
            return "The server address is not a valid URL."
        case .http(let code, let body):
            return "Server returned \(code). \(body.prefix(200))"
        case .notConfigured(let detail):
            return detail
        }
    }
}

private struct Ignored: Decodable {}

@MainActor
final class APIClient: TwinAPI {
    var currentUserId: String
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL, userId: String) {
        self.baseURL = baseURL
        self.currentUserId = userId
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    // MARK: Core request

    private func makeRequest(_ method: String, _ path: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue(currentUserId, forHTTPHeaderField: "X-Demo-User")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw APIError.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        try await send(makeRequest("GET", path))
    }

    private func call<T: Decodable, B: Encodable>(_ method: String, _ path: String, body: B) async throws -> T {
        var request = makeRequest(method, path)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await send(request)
    }

    private struct Empty: Encodable {}

    // MARK: Endpoints

    func users() async throws -> [User] { try await get("api/users") }

    func me() async throws -> User { try await get("api/me") }

    func friends() async throws -> [FriendEntry] { try await get("api/friends") }

    func setTier(friendId: String, tier: Tier) async throws -> FriendEntry {
        struct Body: Encodable { let tier: Tier }
        return try await call("PATCH", "api/friends/\(friendId)", body: Body(tier: tier))
    }

    func addFriend(friendId: String, tier: Tier) async throws -> FriendEntry {
        struct Body: Encodable { let friendId: String; let tier: Tier }
        return try await call("POST", "api/friends", body: Body(friendId: friendId, tier: tier))
    }

    func exchangeGoogleCode(_ code: String) async throws {
        struct Body: Encodable { let serverAuthCode: String }
        let _: Ignored = try await call("POST", "api/auth/google/exchange", body: Body(serverAuthCode: code))
    }

    func ingestGoogle() async throws -> IngestResult {
        try await call("POST", "api/ingest/google", body: Empty())
    }

    func ingestICS(data: Data, filename: String) async throws -> IngestResult {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = makeRequest("POST", "api/ingest/ics")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".utf8))
        body.append(Data("Content-Type: text/calendar\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        request.httpBody = body
        return try await send(request)
    }

    func refreshTwin(checkin: String?) async throws -> TwinRefreshResult {
        struct Body: Encodable { let checkin: String? }
        return try await call("POST", "api/twin/refresh", body: Body(checkin: checkin))
    }

    func twin() async throws -> Signals? {
        let state: TwinState = try await get("api/twin")
        return state.signals
    }

    func updateSummaries(closest: String, close: String, friend: String) async throws -> Signals {
        struct Body: Encodable { let summaryForClosest: String; let summaryForClose: String; let summaryForFriend: String }
        let state: TwinState = try await call("PATCH", "api/twin/summaries",
                                              body: Body(summaryForClosest: closest, summaryForClose: close, summaryForFriend: friend))
        guard let signals = state.signals else { throw APIError.notConfigured("Refresh your twin first.") }
        return signals
    }

    /// Drops your edits and goes back to the twin's own wording.
    func resetSummaries() async throws -> Signals {
        let state: TwinState = try await send(makeRequest("DELETE", "api/twin/summaries"))
        guard let signals = state.signals else { throw APIError.notConfigured("Refresh your twin first.") }
        return signals
    }

    func nudges() async throws -> [Nudge] { try await get("api/nudges") }

    func suggestions(nudgeId: String) async throws -> [Suggestion] {
        try await get("api/nudges/\(nudgeId)/suggestions")
    }

    func sendGesture(nudgeId: String, suggestionIndex: Int) async throws -> Gesture {
        struct Body: Encodable { let nudgeId: String; let suggestionIndex: Int }
        return try await call("POST", "api/gestures", body: Body(nudgeId: nudgeId, suggestionIndex: suggestionIndex))
    }

    func surprises() async throws -> [Gesture] { try await get("api/surprises") }

    func privacy() async throws -> PrivacyInfo { try await get("api/privacy") }

    func updateSettings(surpriseOptIn: Bool?, paused: Bool?) async throws -> User {
        struct Body: Encodable { let surpriseOptIn: Bool?; let paused: Bool? }
        return try await call("PATCH", "api/settings", body: Body(surpriseOptIn: surpriseOptIn, paused: paused))
    }

    func uploadPhoto(_ jpeg: Data) async throws -> User {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = makeRequest("POST", "api/me/photo")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"photo\"; filename=\"photo.jpg\"\r\n".utf8))
        body.append(Data("Content-Type: image/jpeg\r\n\r\n".utf8))
        body.append(jpeg)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        request.httpBody = body
        return try await send(request)
    }

    func removePhoto() async throws -> User {
        try await send(makeRequest("DELETE", "api/me/photo"))
    }
}
