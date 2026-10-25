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

    private struct MockRequest {
        var id: String
        var from: String
        var to: String
        var fromTier: Tier
        var status = "pending"
        var createdAt = ISO8601DateFormatter().string(from: Date())
        var respondedAt: Date?
    }

    private struct StoredGesture {
        var gesture: Gesture
        var helpedUserId: String
        /// A surprise stays hidden from the helped person until the friend marks it delivered.
        var revealed = true
    }

    var currentUserId: String
    var sessionToken: String?

    private var allUsers: [User]
    private var links: [Link]
    private let mayaSignals: Signals?
    private let places: [Place]
    private var signalsByUser: [String: Signals] = [:]
    /// Wording the person chose for what friends see. Applied to every later refresh.
    private var summaryOverrides: [String: (closest: String, close: String, friend: String)] = [:]
    private var nudgeList: [Nudge] = []
    private var suggestionsByNudge: [String: [Suggestion]] = [:]
    private var gestureList: [StoredGesture] = []
    private var googleConnected = false
    private var icsConnected = false
    /// Sofia has already asked Maya, so the demo shows a request waiting.
    private var requests = [MockRequest(id: "fr_demo_sofia", from: "u_sofia", to: "u_maya", fromTier: .close)]
    private var invites: [String: (from: String, tier: Tier, redeemedBy: String?)] = [:]
    private var entriesByUser: [String: [TwinEntry]] = [:]
    /// "from>to" -> inputs that friend was already nudged about.
    private var coverage: [String: Set<String>] = [:]

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

    func friendRequests() async throws -> FriendRequests {
        await delay()
        let me = currentUserId
        let dayAgo = Date().addingTimeInterval(-86_400)
        func entries(_ list: [MockRequest], otherSide: (MockRequest) -> String) -> [FriendRequest] {
            list.compactMap { r in user(otherSide(r)).map { FriendRequest(id: r.id, user: $0, createdAt: r.createdAt) } }
        }
        return FriendRequests(
            incoming: entries(requests.filter { $0.to == me && $0.status == "pending" }) { $0.from },
            outgoing: entries(requests.filter { $0.from == me && $0.status == "pending" }) { $0.to },
            accepted: entries(requests.filter { $0.from == me && $0.status == "accepted" && ($0.respondedAt ?? .distantPast) > dayAgo }) { $0.to }
        )
    }

    func sendFriendRequest(to userId: String, tier: Tier) async throws -> SendRequestResult {
        await delay()
        let me = currentUserId
        guard let other = user(userId), userId != me else { throw APIError.notConfigured("That person isn't on Twin.") }
        guard !links.contains(where: { $0.userId == me && $0.friendId == userId }) else {
            throw APIError.notConfigured("You're already friends.")
        }
        // They already asked you, so both sides have now chosen a circle.
        if let reverse = requests.first(where: { $0.from == userId && $0.to == me && $0.status == "pending" }) {
            let entry = try await acceptFriendRequest(reverse.id, tier: tier)
            return SendRequestResult(status: "accepted", request: nil, friend: entry)
        }
        if let index = requests.firstIndex(where: { $0.from == me && $0.to == userId && $0.status == "pending" }) {
            requests[index].fromTier = tier
            return SendRequestResult(status: "pending", request: FriendRequest(id: requests[index].id, user: other, createdAt: requests[index].createdAt), friend: nil)
        }
        let request = MockRequest(id: "fr_\(UUID().uuidString.prefix(8))", from: me, to: userId, fromTier: tier)
        requests.append(request)
        return SendRequestResult(status: "pending", request: FriendRequest(id: request.id, user: other, createdAt: request.createdAt), friend: nil)
    }

    func acceptFriendRequest(_ id: String, tier: Tier) async throws -> FriendEntry {
        await delay()
        guard let index = requests.firstIndex(where: { $0.id == id && $0.to == currentUserId && $0.status == "pending" }),
              let friend = user(requests[index].from) else {
            throw APIError.notConfigured("That request is no longer pending.")
        }
        requests[index].status = "accepted"
        requests[index].respondedAt = Date()
        let request = requests[index]
        links.removeAll { ($0.userId == request.from && $0.friendId == request.to) || ($0.userId == request.to && $0.friendId == request.from) }
        links.append(Link(userId: request.from, friendId: request.to, tier: request.fromTier))
        links.append(Link(userId: request.to, friendId: request.from, tier: tier))
        return FriendEntry(friend: friend, tier: tier)
    }

    func declineFriendRequest(_ id: String) async throws {
        await delay()
        guard let index = requests.firstIndex(where: { $0.id == id && $0.to == currentUserId && $0.status == "pending" }) else { return }
        requests[index].status = "declined"
    }

    func cancelFriendRequest(_ id: String) async throws {
        await delay()
        guard let index = requests.firstIndex(where: { $0.id == id && $0.from == currentUserId && $0.status == "pending" }) else { return }
        requests[index].status = "cancelled"
    }

    func createInvite(tier: Tier, channel: InviteChannel, contact: String?) async throws -> Invite {
        await delay()
        let code = String(UUID().uuidString.prefix(8)).lowercased()
        invites[code] = (from: currentUserId, tier: tier, redeemedBy: nil)
        let url = "https://twin.example/i/\(code)"
        let firstName = user(currentUserId)?.name.split(separator: " ").first.map(String.init) ?? "A friend"
        return Invite(code: code, url: url, message: "\(firstName) wants to be friends on Twin, so you can show up for each other. Join here: \(url)")
    }

    func redeemInvite(_ code: String) async throws -> RedeemResult {
        await delay()
        guard let invite = invites[code], let inviter = user(invite.from) else {
            throw APIError.notConfigured("That invite link isn't valid.")
        }
        guard invite.from != currentUserId else { throw APIError.notConfigured("This is your own invite. Send it to a friend.") }
        if let by = invite.redeemedBy, by != currentUserId {
            throw APIError.notConfigured("Someone else already used this invite. Ask for a new one.")
        }
        invites[code]?.redeemedBy = currentUserId
        let me = currentUserId
        currentUserId = invite.from
        defer { currentUserId = me }
        let result = try await sendFriendRequest(to: me, tier: invite.tier)
        guard let request = result.request else { return RedeemResult(status: "friends", inviter: inviter, request: nil) }
        return RedeemResult(status: "pending", inviter: inviter, request: FriendRequest(id: request.id, user: inviter, createdAt: request.createdAt))
    }

    /// Mock mode has no real accounts, so Google signs in as Maya with her calendar connected.
    func signInWithGoogle(idToken: String, serverAuthCode: String?) async throws -> SignInResult {
        await delay()
        googleConnected = true
        guard let maya = allUsers.first(where: { $0.id == "u_maya" }) else { throw APIError.http(404, "No mock Maya") }
        return SignInResult(token: "mock-session", user: maya, created: false, googleConnected: true)
    }

    func signOut() async {}

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

    func twinEntries() async throws -> [TwinEntry] {
        entriesByUser[currentUserId] ?? []
    }

    func addTwinEntry(_ text: String) async throws -> TwinEntry {
        await delay()
        let entry = TwinEntry(id: "te_\(UUID().uuidString.prefix(8))", text: text, createdAt: DateText.now())
        entriesByUser[currentUserId, default: []].insert(entry, at: 0)
        return entry
    }

    func deleteTwinEntry(_ id: String) async throws {
        entriesByUser[currentUserId]?.removeAll { $0.id == id }
    }

    func refreshTwin(checkin: String?) async throws -> TwinRefreshResult {
        try? await Task.sleep(nanoseconds: 1_200_000_000) // feels like the twin is thinking
        let me = try currentUser()
        let entries = entriesByUser[me.id] ?? []
        let told = ([checkin] + entries.map(\.text)).compactMap { $0 }.joined(separator: ". ")
        var signals = signalsFor(me, checkin: told.isEmpty ? nil : told)
        // Like the server: what you told your twin joins its read of the week.
        let today = String(DateText.now().prefix(10))
        for entry in entries where !signals.stressors.contains(where: { $0.what == entry.text }) {
            signals.stressors.append(Stressor(what: entry.text, when: today))
        }
        signalsByUser[me.id] = signals
        let now = DateText.now()
        entriesByUser[me.id] = entries.map { var e = $0; e.readAt = e.readAt ?? now; return e }

        // Same rule as the server: the week itself, plus each entry, is news to a friend only once.
        let inputKeys = Set(["week"] + entries.map(\.id))
        var sent = 0
        var anyNews = false
        if signals.supportLevel != .doingFine && me.surpriseOptIn && !me.paused {
            for entry in friendEntries(of: me.id) {
                let pair = "\(me.id)>\(entry.friend.id)"
                guard !inputKeys.isSubset(of: coverage[pair, default: []]) else { continue }
                anyNews = true
                coverage[pair, default: []].formUnion(inputKeys)
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
                suggestionsByNudge[nudge.id] = suggestionsFor(me, tier: entry.tier, signals: signals)
                sent += 1
            }
        }
        return TwinRefreshResult(signals: signals, nudgesSent: sent, nothingNew: !anyNews && sent == 0 && signals.supportLevel != .doingFine)
    }

    func twin() async throws -> Signals? {
        await delay()
        return signalsByUser[currentUserId]
    }

    func updateSummaries(closest: String, close: String, friend: String) async throws -> Signals {
        await delay()
        let me = try currentUser()
        guard var signals = signalsByUser[me.id] else {
            throw APIError.notConfigured("Refresh your twin first.")
        }
        summaryOverrides[me.id] = (closest, close, friend)
        signals.summaryForClosest = closest
        signals.summaryForClose = close
        // Empty means the Friends circle hears nothing.
        signals.summaryForFriend = friend.isEmpty ? nil : friend
        signalsByUser[me.id] = signals
        rewordPendingNudges(from: me, signals: signals)
        return signals
    }

    func resetSummaries() async throws -> Signals {
        await delay()
        let me = try currentUser()
        guard var signals = signalsByUser[me.id] else {
            throw APIError.notConfigured("Refresh your twin first.")
        }
        summaryOverrides[me.id] = nil
        let ai = baseSignals(me, checkin: nil)
        signals.summaryForClosest = ai.summaryForClosest
        signals.summaryForClose = ai.summaryForClose
        signals.summaryForFriend = ai.summaryForFriend
        signalsByUser[me.id] = signals
        rewordPendingNudges(from: me, signals: signals)
        return signals
    }

    /// Nudges a friend hasn't acted on yet pick up the new wording too.
    private func rewordPendingNudges(from me: User, signals: Signals) {
        for index in nudgeList.indices where nudgeList[index].fromUser.id == me.id && nudgeList[index].status != "acted" {
            let tier = Tier(rawValue: nudgeList[index].contextLevel) ?? .friend
            nudgeList[index].message = message(for: me, tier: tier, signals: signals)
        }
    }

    func nudges() async throws -> [Nudge] {
        nudgeList.filter { $0.toFriendId == currentUserId }.map { nudge in
            var nudge = nudge
            if let stored = gestureList.first(where: { $0.gesture.nudgeId == nudge.id }) {
                nudge.gesture = NudgeGesture(id: stored.gesture.id, surprise: stored.gesture.surprise ?? false, revealed: stored.revealed)
            }
            return nudge
        }
    }

    func suggestions(nudgeId: String) async throws -> [Suggestion] {
        await delay()
        return suggestionsByNudge[nudgeId] ?? []
    }

    func sendGesture(nudgeId: String, suggestionIndex: Int, note customNote: String?) async throws -> Gesture {
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

        let surprise = choice.gestureType != .message && (user(helped.id)?.surprisesEnabled ?? true)
        let gesture = Gesture(
            id: UUID().uuidString,
            nudgeId: nudgeId,
            fromFriend: me,
            type: choice.gestureType,
            place: choice.place,
            note: customNote ?? note(for: choice, helped: helped),
            deliveredAt: DateText.now(),
            surprise: surprise
        )
        gestureList.append(StoredGesture(gesture: gesture, helpedUserId: helped.id, revealed: !surprise))
        return gesture
    }

    func surprises() async throws -> [Gesture] {
        gestureList.filter { $0.helpedUserId == currentUserId && $0.revealed }.map(\.gesture)
    }

    func markDelivered(gestureId: String) async throws {
        await delay()
        guard let index = gestureList.firstIndex(where: { $0.gesture.id == gestureId }) else { return }
        gestureList[index].revealed = true
        gestureList[index].gesture.deliveredAt = DateText.now()
    }

    /// Mock friends stand around UT Austin so the Map has something to show.
    func friendLocations() async throws -> [FriendLocation] {
        let spots: [String: (Double, Double, String)] = [
            "u_jay": (30.2862, -97.7394, "West Campus"),
            "u_priya": (30.2827, -97.7330, "PCL Library"),
        ]
        return friendEntries(of: currentUserId).compactMap { entry in
            guard let spot = spots[entry.friend.id] else { return nil }
            return FriendLocation(user: entry.friend, lat: spot.0, lng: spot.1, label: spot.2, updatedAt: DateText.now())
        }
    }

    func searchUsers(_ query: String) async throws -> [User] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        return allUsers.filter { $0.id != currentUserId && ($0.name.lowercased().contains(q) || $0.email.lowercased().contains(q)) }
    }

    /// Mock users have no phone numbers, so only emails match.
    func matchContacts(phones: [String], emails: [String]) async throws -> [User] {
        let wanted = Set(emails.map { $0.lowercased() })
        return allUsers.filter { $0.id != currentUserId && wanted.contains($0.email.lowercased()) }
    }

    func react(toSurprise gestureId: String, reaction: String) async throws {
        if let i = gestureList.firstIndex(where: { $0.gesture.id == gestureId }) {
            gestureList[i].gesture.reaction = reaction
        }
    }

    func privacy() async throws -> PrivacyInfo {
        await delay()
        return PrivacyInfo(
            sources: .init(google: googleConnected, ics: icsConnected),
            friends: friendEntries(of: currentUserId),
            nudgeLog: nudgeList.filter { $0.fromUser.id == currentUserId && $0.status == "acted" }
        )
    }

    func updateSettings(_ patch: SettingsPatch) async throws -> User {
        await delay()
        guard let index = allUsers.firstIndex(where: { $0.id == currentUserId }) else {
            throw APIError.notConfigured("Unknown demo user.")
        }
        if let open = patch.openToSupport { allUsers[index].surpriseOptIn = open }
        if let surprisesOn = patch.surprisesOn { allUsers[index].surprisesOn = surprisesOn }
        if let phone = patch.phone { allUsers[index].phone = phone.isEmpty ? nil : phone }
        if let interests = patch.interests { allUsers[index].interests = interests }
        if let sharing = patch.locationSharing { allUsers[index].locationSharing = sharing }
        return allUsers[index]
    }

    // Photos live on this device (AvatarStore), so every demo user here sees them.
    func uploadPhoto(_ jpeg: Data) async throws -> User {
        await delay()
        return try currentUser()
    }

    func removePhoto() async throws -> User {
        await delay()
        return try currentUser()
    }

    // MARK: Fake twin logic

    private func signalsFor(_ me: User, checkin: String?) -> Signals {
        var signals = baseSignals(me, checkin: checkin)
        if let custom = summaryOverrides[me.id] {
            signals.summaryForClosest = custom.closest
            signals.summaryForClose = custom.close
            signals.summaryForFriend = custom.friend
        }
        return signals
    }

    private func baseSignals(_ me: User, checkin: String?) -> Signals {
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
                summaryForClose: "Doing well",
                summaryForFriend: "All good"
            )
        }
        return Signals(
            supportLevel: .couldUseSupport,
            stressors: [Stressor(what: text, when: "this week")],
            busyHoursNext3Days: 22,
            likelyLocation: me.homeLocation,
            summaryForClosest: text,
            summaryForClose: "A tough week",
            summaryForFriend: "Busy week"
        )
    }

    private func message(for me: User, tier: Tier, signals: Signals) -> String {
        switch tier {
        case .closest:
            return "\(me.name) could use you right now: \(signals.summaryForClosest.lowercasedFirst)."
        case .close:
            return "\(me.name) could use a lift this week: \(signals.summaryForClose.lowercasedFirst)."
        case .friend:
            return "\(me.name)'s week: \(signals.friendLine.lowercasedFirst). A kind word might be nice."
        }
    }

    private func suggestionsFor(_ me: User, tier: Tier, signals: Signals) -> [Suggestion] {
        // The outer circle only ever gets light-touch ideas.
        if tier == .friend {
            return [Suggestion(
                gestureType: .message,
                title: "Send \(me.name) a quick hello",
                detail: "Nothing big. A friendly message can brighten a busy week.",
                place: nil
            )]
        }
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
