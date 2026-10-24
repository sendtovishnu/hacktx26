import Foundation

// Runs the full demo flow in memory from the JSON files in Mocks/.
// Maya refreshes her twin -> Jay (closest) gets a nudge, Priya (friend) gets nothing
// -> Jay picks a gesture -> Maya receives a surprise.

@MainActor
final class MockAPI: TwinAPI {
    struct Link: Codable {
        var userId: String
        var friendId: String
        var tier: Tier
    }

    private struct StoredGesture {
        var gesture: Gesture
        var helpedUserId: String
    }

    var currentUserId: String

    private var allUsers: [User]
    private var links: [Link]
    private let mayaSignals: Signals?
    private let places: [Place]
    private var signalsByUser: [String: Signals] = [:]
    private var nudgeList: [Nudge] = []
    private var suggestionsByNudge: [String: [Suggestion]] = [:]
    private var gestureList: [StoredGesture] = []
    private var googleConnected = false
    private var icsConnected = false

    init(userId: String) {
        currentUserId = userId
        allUsers = MockAPI.load("users") ?? []
        links = MockAPI.load("friends") ?? []
        mayaSignals = MockAPI.load("signals_maya")
        places = MockAPI.load("places_coffee") ?? []
    }

    static func load<T: Decodable>(_ name: String) -> T? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            print("MockAPI: missing \(name).json")
            return nil
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            print("MockAPI: could not decode \(name).json: \(error)")
            return nil
        }
    }

    private func delay() async {
        try? await Task.sleep(nanoseconds: 350_000_000)
    }

    private func user(_ id: String) -> User? {
        allUsers.first { $0.id == id }
    }

    private func currentUser() throws -> User {
        guard let me = user(currentUserId) else {
            throw APIError.notConfigured("Unknown demo user \(currentUserId).")
        }
        return me
    }

    private func friendEntries(of userId: String) -> [FriendEntry] {
        links.filter { $0.userId == userId }.compactMap { link in
            guard let friend = user(link.friendId) else { return nil }
            return FriendEntry(friend: friend, tier: link.tier)
        }
    }

    // MARK: TwinAPI

    func users() async throws -> [User] {
        await delay()
        return allUsers
    }

    func me() async throws -> User {
        await delay()
        return try currentUser()
    }

    func friends() async throws -> [FriendEntry] {
        await delay()
        return friendEntries(of: currentUserId)
    }

    func setTier(friendId: String, tier: Tier) async throws -> FriendEntry {
        await delay()
        guard let index = links.firstIndex(where: { $0.userId == currentUserId && $0.friendId == friendId }),
              let friend = user(friendId) else {
            throw APIError.notConfigured("No such friend.")
        }
        links[index].tier = tier
        return FriendEntry(friend: friend, tier: tier)
    }

    func exchangeGoogleCode(_ code: String) async throws {
        await delay()
        googleConnected = true
    }

    func ingestGoogle() async throws -> IngestResult {
        await delay()
        googleConnected = true
        return IngestResult(events: 14, emails: 23)
    }

    func ingestICS(data: Data, filename: String) async throws -> IngestResult {
        await delay()
        icsConnected = true
        let text = String(data: data, encoding: .utf8) ?? ""
        let count = text.components(separatedBy: "BEGIN:VEVENT").count - 1
        return IngestResult(events: max(count, 0), emails: nil)
    }

    func refreshTwin(checkin: String?) async throws -> TwinRefreshResult {
        try? await Task.sleep(nanoseconds: 1_200_000_000) // feels like the twin is thinking
        let me = try currentUser()
        let signals = signalsFor(me, checkin: checkin)
        signalsByUser[me.id] = signals

        var sent = 0
        if signals.supportLevel != .doingFine && me.surpriseOptIn && !me.paused {
            for entry in friendEntries(of: me.id) where entry.tier != .friend {
                // One open nudge per pair: replace any earlier unanswered one.
                nudgeList.removeAll { $0.fromUser.id == me.id && $0.toFriendId == entry.friend.id && $0.status != "acted" }
                let nudge = Nudge(
                    id: UUID().uuidString,
                    fromUser: me,
                    toFriendId: entry.friend.id,
                    message: message(for: me, tier: entry.tier, signals: signals),
                    contextLevel: entry.tier.rawValue,
                    status: "sent",
                    createdAt: DateText.now()
                )
                nudgeList.insert(nudge, at: 0)
                suggestionsByNudge[nudge.id] = suggestionsFor(me, signals: signals)
                sent += 1
            }
        }
        return TwinRefreshResult(signals: signals, nudgesSent: sent)
    }

    func twin() async throws -> Signals? {
        await delay()
        return signalsByUser[currentUserId]
    }

    func nudges() async throws -> [Nudge] {
        nudgeList.filter { $0.toFriendId == currentUserId }
    }

    func suggestions(nudgeId: String) async throws -> [Suggestion] {
        await delay()
        return suggestionsByNudge[nudgeId] ?? []
    }

    func sendGesture(nudgeId: String, suggestionIndex: Int) async throws -> Gesture {
        await delay()
        let me = try currentUser()
        guard let nudgeIndex = nudgeList.firstIndex(where: { $0.id == nudgeId }) else {
            throw APIError.notConfigured("That nudge no longer exists.")
        }
        let options = suggestionsByNudge[nudgeId] ?? []
        guard options.indices.contains(suggestionIndex) else {
            throw APIError.notConfigured("That suggestion no longer exists.")
        }
        let choice = options[suggestionIndex]
        let helped = nudgeList[nudgeIndex].fromUser
        nudgeList[nudgeIndex].status = "acted"

        let gesture = Gesture(
            id: UUID().uuidString,
            nudgeId: nudgeId,
            fromFriend: me,
            type: choice.gestureType,
            place: choice.place,
            note: note(for: choice, helped: helped),
            deliveredAt: DateText.now()
        )
        gestureList.append(StoredGesture(gesture: gesture, helpedUserId: helped.id))
        return gesture
    }

    func surprises() async throws -> [Gesture] {
        gestureList.filter { $0.helpedUserId == currentUserId }.map(\.gesture)
    }

    func privacy() async throws -> PrivacyInfo {
        await delay()
        return PrivacyInfo(
            sources: .init(google: googleConnected, ics: icsConnected),
            friends: friendEntries(of: currentUserId),
            nudgeLog: nudgeList.filter { $0.fromUser.id == currentUserId }
        )
    }

    func updateSettings(surpriseOptIn: Bool?, paused: Bool?) async throws -> User {
        await delay()
        guard let index = allUsers.firstIndex(where: { $0.id == currentUserId }) else {
            throw APIError.notConfigured("Unknown demo user.")
        }
        if let surpriseOptIn { allUsers[index].surpriseOptIn = surpriseOptIn }
        if let paused { allUsers[index].paused = paused }
        return allUsers[index]
    }

    // MARK: Fake twin logic

    private func signalsFor(_ me: User, checkin: String?) -> Signals {
        if me.id == "u_maya", let mayaSignals {
            return mayaSignals
        }
        let text = (checkin ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            return Signals(
                supportLevel: .doingFine,
                stressors: [],
                busyHoursNext3Days: 9,
                likelyLocation: me.homeLocation,
                summaryForClosest: "A normal week",
                summaryForClose: "Doing well"
            )
        }
        return Signals(
            supportLevel: .couldUseSupport,
            stressors: [Stressor(what: text, when: "this week")],
            busyHoursNext3Days: 22,
            likelyLocation: me.homeLocation,
            summaryForClosest: text,
            summaryForClose: "A tough week"
        )
    }

    private func message(for me: User, tier: Tier, signals: Signals) -> String {
        if tier == .closest {
            return "\(me.name) could use you right now: \(signals.summaryForClosest.lowercasedFirst)."
        }
        return "\(me.name) could use a lift this week."
    }

    private func suggestionsFor(_ me: User, signals: Signals) -> [Suggestion] {
        let drink = me.preferences.coffeeOrder ?? "coffee"
        let spot = signals.likelyLocation ?? me.homeLocation
        var result: [Suggestion] = places.prefix(2).map { place in
            Suggestion(
                gestureType: .dropOff,
                title: "Bring \(me.name) \(drink.withArticle) from \(place.name)",
                detail: "\(me.name) is studying at \(spot) with no free time to hang out. A quick drop-off won't cost any study time.",
                place: place
            )
        }
        result.append(Suggestion(
            gestureType: .message,
            title: "Send \(me.name) a note",
            detail: "A short message saying you're rooting for \(me.name) this week.",
            place: nil
        ))
        return result
    }

    private func note(for choice: Suggestion, helped: User) -> String {
        switch choice.gestureType {
        case .dropOff:
            let drink = helped.preferences.coffeeOrder ?? "coffee"
            let from = choice.place.map { " from \($0.name)" } ?? ""
            return "\(drink.withArticle.capitalizedFirst)\(from) is on its way to you. You've got this!"
        case .hangout:
            return "Your study break is booked. Come grab a breather!"
        case .message:
            return "Rooting for you this week. You're going to do great."
        }
    }
}

private extension String {
    var lowercasedFirst: String {
        guard let first else { return self }
        return first.lowercased() + dropFirst()
    }

    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }

    /// "oat latte" -> "an oat latte", "cold brew" -> "a cold brew"
    var withArticle: String {
        guard let first = first?.lowercased() else { return self }
        return ("aeiou".contains(first) ? "an " : "a ") + self
    }
}
