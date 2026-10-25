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
    /// Which tab is showing, so tapping a notification can switch to the right one.
    @Published var selectedTab: AppTab = .home
    /// The Nudges tab's navigation, so a notification can open one nudge directly.
    @Published var nudgePath: [Nudge] = []
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

    /// The real server's address, for turning photo paths into URLs. Nil in mock mode.
    static private(set) var serverBase: URL?

    /// Profile photos come back as paths like /api/photos/u_1?v=2.
    static func resolve(_ path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        if path.hasPrefix("http") { return URL(string: path) }
        guard let base = serverBase else { return nil }
        let root = base.absoluteString.hasSuffix("/") ? String(base.absoluteString.dropLast()) : base.absoluteString
        return URL(string: root + (path.hasPrefix("/") ? path : "/" + path))
    }

    private static func makeAPI(useMock: Bool, serverURL: String, userId: String, sessionToken: String?) -> TwinAPI {
        serverBase = useMock ? nil : URL(string: serverURL)
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
        if contactsConnected { try? await syncContacts() }
        await shareLocation(askIfNeeded: false)
        // Notifications are how nudges and surprises reach you; iOS only shows this prompt the first time.
        if isSignedIn && hasCompletedSetup { Notifier.requestPermission() }
        // Notification taps from now on go straight to their screen, and so does one that opened the app.
        Notifier.onOpen = { [weak self] route in Task { await self?.open(route) } }
        if let route = Notifier.pendingRoute {
            Notifier.pendingRoute = nil
            await open(route)
        }
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
        friendRequests = requests
        // Accepted ones get a separate key, since the same id was first seen as an outgoing request.
        let ids = requests.incoming.map(\.id) + requests.accepted.map { "accepted-\($0.id)" }
        let fresh = SeenStore.fresh(ids, kind: "requests", user: demoUserId)
        for request in requests.incoming where fresh.contains(request.id) {
            Notifier.post(title: "\(request.user.name) sent you a friend request",
                          body: "Tap to accept and choose their circle.",
                          route: .friends, id: "request-\(request.id)")
        }
        for request in requests.accepted where fresh.contains("accepted-\(request.id)") {
            Notifier.post(title: "\(request.user.name) accepted your friend request",
                          body: "You're now friends on Twin.",
                          route: .friends, id: "accepted-\(request.id)")
            reloadToken += 1
        }
    }

    // MARK: Opening from a notification

    /// Takes you to what a notification was about: a nudge, a surprise to rate, or Friends.
    func open(_ route: NotificationRoute) async {
        guard isSignedIn else { return }
        switch route {
        case .friends:
            selectedTab = .friends
        case .nudge(let id):
            selectedTab = .nudges
            if !nudges.contains(where: { $0.id == id }) { await poll() }
            if let nudge = nudges.first(where: { $0.id == id }) { nudgePath = [nudge] }
        case .surprise(let id):
            selectedTab = .nudges
            if !surprises.contains(where: { $0.id == id }) { await poll() }
            // The surprise screen is where you rate it: ❤️ or "I needed space".
            activeSurprise = surprises.first { $0.id == id }
        }
    }

    /// Wakes up now and then in the background (Background App Refresh) to notify about anything new.
    func backgroundCheck() async {
        guard isSignedIn else { return }
        await poll()
    }

    /// A revealed surprise is a surprise; otherwise the person is told what's coming.
    static func headline(for gesture: Gesture) -> String {
        let name = gesture.fromFriend.name.split(separator: " ").first.map(String.init) ?? gesture.fromFriend.name
        if gesture.surprise == true { return "\(name) surprised you" }
        switch gesture.type {
        case .dropOff:
            let what = gesture.note.lowercased().contains("matcha") ? "a matcha" : "something"
            return "\(name) is bringing you \(what)"
        case .hangout: return "\(name) planned a hangout with you"
        case .message: return "\(name) sent you a note"
        }
    }

    // MARK: Location

    /// Sends where you are so suggestions are searched nearby. Quietly does nothing without permission.
    @discardableResult
    func shareLocation(askIfNeeded: Bool) async -> String? {
        guard let fix = await LocationReporter.shared.currentLocation(askIfNeeded: askIfNeeded) else { return nil }
        _ = try? await api.updateSettings(SettingsPatch(location: LocationPatch(lat: fix.lat, lng: fix.lng, label: fix.label)))
        UserDefaults.standard.set(fix.label, forKey: "locationLabel")
        return fix.label ?? "Shared"
    }

    var locationLabel: String? { UserDefaults.standard.string(forKey: "locationLabel") }

    // MARK: Contacts

    /// People on Twin from your phone's contacts, by user id, with the name you saved them under.
    @Published private(set) var contactMatches: [String: String] = [:]

    var contactsConnected: Bool { UserDefaults.standard.bool(forKey: "contactsConnected") }

    /// Reads your contacts (after you allow it) and asks the server which of them are on Twin.
    func syncContacts() async throws {
        let contacts = try await ContactsReader.read()
        let users = try await api.matchContacts(phones: contacts.flatMap(\.phones), emails: contacts.flatMap(\.emails))
        var matches: [String: String] = [:]
        for user in users {
            let key = user.phone.flatMap(ContactsReader.phoneKey)
            let contact = contacts.first { c in
                (key != nil && c.phones.contains { ContactsReader.phoneKey($0) == key }) || c.emails.contains { $0.lowercased() == user.email.lowercased() }
            }
            matches[user.id] = contact?.name ?? user.name
        }
        contactMatches = matches
        UserDefaults.standard.set(true, forKey: "contactsConnected")
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
        nudges = newNudges.sorted { $0.createdAt > $1.createdAt }
        surprises = newSurprises.sorted { $0.deliveredAt > $1.deliveredAt }

        // Remembered across launches, so anything that came in while the app was closed is still news.
        let freshNudges = SeenStore.fresh(newNudges.map(\.id), kind: "nudges", user: demoUserId)
        let freshSurprises = SeenStore.fresh(newSurprises.map(\.id), kind: "surprises", user: demoUserId)
        for nudge in newNudges where freshNudges.contains(nudge.id) {
            Notifier.post(title: "\(nudge.fromUser.name) could use you", body: nudge.message,
                          route: .nudge(nudge.id), id: "nudge-\(nudge.id)")
        }
        for surprise in newSurprises where freshSurprises.contains(surprise.id) {
            // A surprise shows up once the friend marked it done: time to say how it landed.
            let body = surprise.surprise == true ? "\(surprise.note)\nTap to tell your twin how it landed." : surprise.note
            Notifier.post(title: AppState.headline(for: surprise), body: body,
                          route: .surprise(surprise.id), id: "surprise-\(surprise.id)")
        }
        if let first = newSurprises.first(where: { freshSurprises.contains($0.id) }) {
            activeSurprise = first
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

    /// `route` is where tapping it leads; `id` keeps the same item from notifying twice.
    static func post(title: String, body: String, route: NotificationRoute, id: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["route": route.rawValue]
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// A tap that came in before the app was ready (it was closed), picked up once it is.
    @MainActor static var pendingRoute: NotificationRoute?
    @MainActor static var onOpen: ((NotificationRoute) -> Void)?

    // Tapping a notification: go to the thing it's about.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let raw = response.notification.request.content.userInfo["route"] as? String
        Task { @MainActor in
            if let route = raw.flatMap(NotificationRoute.init(rawValue:)) {
                if let onOpen = Notifier.onOpen { onOpen(route) } else { Notifier.pendingRoute = route }
            }
            completionHandler()
        }
    }

    // Show banners even while the app is open, which is the whole demo.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}

enum AppTab: Hashable { case map, friends, home, twin, nudges }

/// Where a notification leads, stored in it as text ("nudge:n_123").
enum NotificationRoute: Equatable {
    case nudge(String)
    case surprise(String)
    case friends

    var rawValue: String {
        switch self {
        case .nudge(let id): return "nudge:\(id)"
        case .surprise(let id): return "surprise:\(id)"
        case .friends: return "friends"
        }
    }

    init?(rawValue: String) {
        let parts = rawValue.split(separator: ":", maxSplits: 1).map(String.init)
        switch (parts.first, parts.count) {
        case ("nudge", 2): self = .nudge(parts[1])
        case ("surprise", 2): self = .surprise(parts[1])
        case ("friends", _): self = .friends
        default: return nil
        }
    }
}

/// Ids already notified about, per account and kind, kept across launches. The first look at an
/// account just records what's there, so old items aren't announced as new.
enum SeenStore {
    static func fresh(_ ids: [String], kind: String, user: String) -> Set<String> {
        let key = "seen.\(user).\(kind)"
        let defaults = UserDefaults.standard
        let firstLook = defaults.object(forKey: key) == nil
        var seen = Set(defaults.stringArray(forKey: key) ?? [])
        let fresh = firstLook ? [] : Set(ids).subtracting(seen)
        seen.formUnion(ids)
        defaults.set(Array(seen), forKey: key)
        return fresh
    }
}
