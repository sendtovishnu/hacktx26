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

    @Published private(set) var api: TwinAPI
    @Published var users: [User] = []
    @Published var me: User?
    @Published var nudges: [Nudge] = []
    @Published var surprises: [Gesture] = []
    @Published var activeSurprise: Gesture?
    @Published var lastError: String?
    /// Screens reload whenever this changes (user switch or new connection settings).
    @Published private(set) var reloadToken = 0

    private var seenNudgeIds: Set<String> = []
    private var seenSurpriseIds: Set<String> = []
    private var hasLoadedOnce = false
    private var pollTask: Task<Void, Never>?

    init() {
        let defaults = UserDefaults.standard
        let userId = defaults.string(forKey: "demoUserId") ?? "u_maya"
        let useMock = defaults.object(forKey: "useMockAPI") as? Bool ?? true
        let url = defaults.string(forKey: "serverURL") ?? "http://localhost:3000"
        demoUserId = userId
        useMockAPI = useMock
        serverURL = url
        api = AppState.makeAPI(useMock: useMock, serverURL: url, userId: userId)
    }

    private static func makeAPI(useMock: Bool, serverURL: String, userId: String) -> TwinAPI {
        if !useMock, let url = URL(string: serverURL) {
            return APIClient(baseURL: url, userId: userId)
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
        demoUserId = id
        api.currentUserId = id
        resetFeed()
        reloadToken += 1
        await reloadMe()
        await poll()
    }

    /// Rebuilds the API after the mock switch or server URL changes.
    func applyConnectionSettings() async {
        api = AppState.makeAPI(useMock: useMockAPI, serverURL: serverURL, userId: demoUserId)
        resetFeed()
        reloadToken += 1
        await start()
    }

    func updateMe(_ user: User) {
        me = user
    }

    private func resetFeed() {
        nudges = []
        surprises = []
        seenNudgeIds = []
        seenSurpriseIds = []
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
            handle(newNudges: newNudges, newSurprises: newSurprises)
        } catch {
            // Polling errors stay quiet; screens show their own errors.
        }
    }

    private func handle(newNudges: [Nudge], newSurprises: [Gesture]) {
        let freshNudges = newNudges.filter { !seenNudgeIds.contains($0.id) }
        let freshSurprises = newSurprises.filter { !seenSurpriseIds.contains($0.id) }

        nudges = newNudges.sorted { $0.createdAt > $1.createdAt }
        surprises = newSurprises.sorted { $0.deliveredAt > $1.deliveredAt }
        seenNudgeIds.formUnion(newNudges.map(\.id))
        seenSurpriseIds.formUnion(newSurprises.map(\.id))

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
