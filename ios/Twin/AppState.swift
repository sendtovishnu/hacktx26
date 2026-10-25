import Foundation
import SwiftUI
import UserNotifications

// App-wide state: which demo user is active, which API is in use,
// and the 5-second polling loop that turns new nudges and surprises into notifications.

@MainActor
final class AppState: ObservableObject {
    // Settings that survive relaunches. Change the defaults in init().
    @Published var demoUserId: String {
        didSet { UserDefaults.standard.set(demoUserId, forKey: "demoUserId") }
    }
    @Published var useMockAPI: Bool {
        didSet { UserDefaults.standard.set(useMockAPI, forKey: "useMockAPI") }
    }
    @Published var serverURL: String {
        didSet { UserDefaults.standard.set(serverURL, forKey: "serverURL") }
    }
    /// Session from a real Google sign-in. Nil means the demo accounts are in use.
    @Published private(set) var sessionToken: String? {
        didSet { UserDefaults.standard.set(sessionToken, forKey: "sessionToken") }
    }
    @Published var isSignedIn: Bool {
        didSet { UserDefaults.standard.set(isSignedIn, forKey: "isSignedIn") }
    }
    @Published var hasCompletedSetup: Bool {
        didSet { UserDefaults.standard.set(hasCompletedSetup, forKey: "hasCompletedSetup") }
    }

    @Published private(set) var api: TwinAPI
    @Published var users: [User] = []
    @Published var me: User?
    @Published var nudges: [Nudge] = []
    @Published var surprises: [Gesture] = []
    @Published var activeSurprise: Gesture?
    @Published var lastError: String?
    @Published var friendRequests = FriendRequests.empty
    /// A request from someone whose invite link you just opened, shown so you can accept it.
    @Published var invitedRequest: FriendRequest?
    @Published var inviteMessage: String?
    /// Screens reload whenever this changes (user switch or new connection settings).
    @Published private(set) var reloadToken = 0

    // Remembered per demo user, so switching users on one phone still surfaces new surprises.
    private var seenNudgeIdsByUser: [String: Set<String>] = [:]
    private var seenSurpriseIdsByUser: [String: Set<String>] = [:]
    private var seenRequestIdsByUser: [String: Set<String>] = [:]
    /// An invite opened before signing in waits here until there's an account to redeem it for.
    private var pendingInviteCode: String? {
        get { UserDefaults.standard.string(forKey: "pendingInviteCode") }
        set { UserDefaults.standard.set(newValue, forKey: "pendingInviteCode") }
    }
    private var hasLoadedOnce = false
    private var pollTask: Task<Void, Never>?

    init() {
        let defaults = UserDefaults.standard
        let userId = defaults.string(forKey: "demoUserId") ?? "u_maya"
        // A server URL baked in by `make sim` / `make phone` makes a fresh install use the real server.
        let builtInURL = (Bundle.main.object(forInfoDictionaryKey: "TwinServerURL") as? String)
            .flatMap { $0.isEmpty ? nil : $0 }
        // A build with a new baked-in server replaces whatever an older build saved.
        if let builtInURL, defaults.string(forKey: "builtInServerURL") != builtInURL {
            defaults.set(builtInURL, forKey: "builtInServerURL")
            defaults.removeObject(forKey: "serverURL")
            defaults.removeObject(forKey: "useMockAPI")
            defaults.removeObject(forKey: "sessionToken")
        }
        let useMock = defaults.object(forKey: "useMockAPI") as? Bool ?? (builtInURL == nil)
        let url = defaults.string(forKey: "serverURL") ?? builtInURL ?? "http://localhost:3000"
        let token = defaults.string(forKey: "sessionToken")
        demoUserId = userId
        useMockAPI = useMock
        serverURL = url
        sessionToken = token
        isSignedIn = defaults.bool(forKey: "isSignedIn")
        hasCompletedSetup = defaults.bool(forKey: "hasCompletedSetup")
        api = AppState.makeAPI(useMock: useMock, serverURL: url, userId: userId, sessionToken: token)
    }

    private static func makeAPI(useMock: Bool, serverURL: String, userId: String, sessionToken: String?) -> TwinAPI {
        if !useMock, let url = URL(string: serverURL) {
            return APIClient(baseURL: url, userId: userId, sessionToken: sessionToken)
        }
        return MockAPI(userId: userId)
    }

    // MARK: Lifecycle

    func start() async {
        await reloadUsers()
        await reloadMe()
        startPolling()
    }

    func reloadUsers() async {
        do {
            users = try await api.users()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func reloadMe() async {
        do {
            me = try await api.me()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func switchUser(to id: String) async {
        // Picking a demo account leaves the real one.
        if sessionToken != nil, id != demoUserId { clearSession() }
        demoUserId = id
        api.currentUserId = id
        resetFeed()
        // A user switch is not a fresh launch: anything this user hasn't seen yet is news.
        hasLoadedOnce = true
        reloadToken += 1
        await reloadMe()
        await poll()
    }

    /// Rebuilds the API after the mock switch or server URL changes.
    func applyConnectionSettings() async {
        // A session belongs to one server, so a new address or mock mode needs a fresh sign-in.
        if sessionToken != nil { clearSession() }
        api = AppState.makeAPI(useMock: useMockAPI, serverURL: serverURL, userId: demoUserId, sessionToken: nil)
        resetFeed()
        reloadToken += 1
        await start()
    }

    /// Demo sign-in: an email that matches a seeded user signs in as them, anything else signs in as Maya.
    func signIn(email: String? = nil) async {
        if users.isEmpty { await reloadUsers() }
        let typed = (email ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Mock users are @example.com and the server's are @utexas.edu, so fall back to the name before the @.
        let localPart = { (s: String) in s.split(separator: "@").first.map(String.init) ?? s }
        let match = users.first { $0.email.lowercased() == typed }
            ?? users.first { localPart($0.email.lowercased()) == localPart(typed) }
        let id = match?.id ?? "u_maya"
        if id != demoUserId {
            await switchUser(to: id)
        } else {
            await reloadMe()
        }
        isSignedIn = true
        await redeemPendingInvite()
    }

    /// Real sign-in: Google proves who you are, the server finds or creates your account
    /// and connects your Calendar and Gmail in the same step.
    func signInWithGoogle() async throws {
        let credentials = try await GoogleAuth.signIn()
        let result = try await api.signInWithGoogle(idToken: credentials.idToken, serverAuthCode: credentials.serverAuthCode)
        if !useMockAPI {
            sessionToken = result.token
            api.sessionToken = result.token
        }
        demoUserId = result.user.id
        api.currentUserId = result.user.id
        me = result.user
        resetFeed()
        hasLoadedOnce = true
        reloadToken += 1
        if result.created { hasCompletedSetup = false }
        isSignedIn = true
        await reloadUsers()
        await poll()
        await redeemPendingInvite()
        if result.googleConnected {
            // Pull the week in the background so the twin has something to read.
            Task { _ = try? await api.ingestGoogle() }
        }
    }

    func signOut() {
        if sessionToken != nil {
            let api = api
            Task { await api.signOut() }
            clearSession()
        }
        isSignedIn = false
    }

    private func clearSession() {
        sessionToken = nil
        api.sessionToken = nil
        GoogleAuth.signOut()
    }

    func updateMe(_ user: User) {
        me = user
    }

    private func resetFeed() {
        nudges = []
        surprises = []
        friendRequests = .empty
        hasLoadedOnce = false
    }

    // MARK: Polling

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    func poll() async {
        do {
            let newNudges = try await api.nudges()
            let newSurprises = try await api.surprises()
            let requests = try await api.friendRequests()
            handle(requests: requests)
            handle(newNudges: newNudges, newSurprises: newSurprises)
        } catch {
            // Polling errors stay quiet; screens show their own errors.
        }
    }

    /// Refreshes requests now instead of waiting for the next poll, e.g. after accepting one.
    func reloadFriendRequests() async {
        if let requests = try? await api.friendRequests() { handle(requests: requests) }
    }

    private func handle(requests: FriendRequests) {
        let user = demoUserId
        let seen = seenRequestIdsByUser[user, default: []]
        friendRequests = requests
        // Accepted ones get a separate key, since the same id was first seen as an outgoing request.
        let ids = requests.incoming.map(\.id) + requests.accepted.map { "accepted-\($0.id)" }
        seenRequestIdsByUser[user, default: []].formUnion(ids)
        guard hasLoadedOnce else { return }
        for request in requests.incoming where !seen.contains(request.id) {
            Notifier.post(title: "\(request.user.name) sent you a friend request", body: "Accept to add each other on Twin.")
        }
        for request in requests.accepted where !seen.contains("accepted-\(request.id)") {
            Notifier.post(title: "\(request.user.name) accepted your friend request", body: "You're now friends on Twin.")
            reloadToken += 1
        }
    }

    // MARK: Invites

    /// twin://invite/<code>, from the page an invite link opens.
    func handle(url: URL) async -> Bool {
        guard url.scheme == "twin", url.host == "invite", let code = url.pathComponents.dropFirst().first, !code.isEmpty else {
            return false
        }
        pendingInviteCode = code
        if isSignedIn { await redeemPendingInvite() }
        return true
    }

    func redeemPendingInvite() async {
        guard let code = pendingInviteCode else { return }
        pendingInviteCode = nil
        do {
            let result = try await api.redeemInvite(code)
            if let request = result.request {
                invitedRequest = request
            } else {
                inviteMessage = "You and \(result.inviter.name) are already friends."
            }
            await reloadFriendRequests()
        } catch {
            inviteMessage = error.localizedDescription
        }
    }

    private func handle(newNudges: [Nudge], newSurprises: [Gesture]) {
        let user = demoUserId
        let seenNudges = seenNudgeIdsByUser[user, default: []]
        let seenSurprises = seenSurpriseIdsByUser[user, default: []]
        let freshNudges = newNudges.filter { !seenNudges.contains($0.id) }
        let freshSurprises = newSurprises.filter { !seenSurprises.contains($0.id) }

        nudges = newNudges.sorted { $0.createdAt > $1.createdAt }
        surprises = newSurprises.sorted { $0.deliveredAt > $1.deliveredAt }
        seenNudgeIdsByUser[user, default: []].formUnion(newNudges.map(\.id))
        seenSurpriseIdsByUser[user, default: []].formUnion(newSurprises.map(\.id))

        // The first load after launch or a user switch is history, not news.
        if hasLoadedOnce {
            for nudge in freshNudges {
                Notifier.post(title: "\(nudge.fromUser.name) could use you", body: nudge.message)
            }
            if let surprise = freshSurprises.first {
                Notifier.post(title: "Someone is thinking of you", body: surprise.note)
                activeSurprise = surprise
            }
        }
        hasLoadedOnce = true
    }
}

// MARK: Local notifications

final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    /// Call at launch so banners show while the app is open.
    static func install() {
        UNUserNotificationCenter.current().delegate = shared
    }

    static func requestPermission() {
        UNUserNotificationCenter.current().delegate = shared
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // Show banners even while the app is open, which is the whole demo.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}
