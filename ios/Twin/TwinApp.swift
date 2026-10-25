import BackgroundTasks
import SwiftUI
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

@main
struct TwinApp: App {
    @StateObject private var state = AppState()
    @Environment(\.scenePhase) private var scenePhase
    static let refreshTaskId = "com.sendtovishnu.hacktx26.twin.refresh"

    init() {
        Notifier.install()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .task { await state.start() }
                .onOpenURL { url in
                    Task {
                        if await state.handle(url: url) { return }
                        #if canImport(GoogleSignIn)
                        GIDSignIn.sharedInstance.handle(url)
                        #endif
                    }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { TwinApp.scheduleRefresh() }
        }
        // iOS wakes the app now and then to check for nudges and surprises and notify about them.
        // (Real push needs a paid Apple Developer account; this works with a free one.)
        .backgroundTask(.appRefresh(TwinApp.refreshTaskId)) {
            TwinApp.scheduleRefresh()
            await state.backgroundCheck()
        }
    }

    static func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}

/// Welcome (first launch) -> Sign in -> Setup (first sign-in) -> the app.
struct RootView: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject private var theme = ThemeStore.shared
    @AppStorage("hasOnboarded") private var hasSeenWelcome = false

    private var openNudgeCount: Int {
        state.nudges.filter { $0.status != "acted" }.count
    }

    var body: some View {
        ZStack {
            if !hasSeenWelcome {
                WelcomeView {
                    withAnimation(.easeInOut(duration: 0.35)) { hasSeenWelcome = true }
                }
                .transition(.opacity)
            } else if !state.isSignedIn {
                SignInView()
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else if !state.hasCompletedSetup {
                SetupView()
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                tabs
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: state.isSignedIn)
        .animation(.easeInOut(duration: 0.35), value: state.hasCompletedSetup)
        .tint(Theme.accent)
        .lineSpacing(2.5)
        // Accent colors are read when views draw, so redraw everything when the accent changes.
        .id(theme.accent)
        .onAppear { theme.applyAppearance() }
        .sheet(item: $state.invitedRequest) { request in
            CircleChoiceSheet(sheet: .accept(request)) { tier in
                _ = try await state.api.acceptFriendRequest(request.id, tier: tier)
                await state.reloadFriendRequests()
            }
            .environmentObject(state)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .alert(state.inviteMessage ?? "", isPresented: Binding(
            get: { state.inviteMessage != nil },
            set: { if !$0 { state.inviteMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        }
        .fullScreenCover(item: $state.activeSurprise) { gesture in
            SurpriseView(gesture: gesture)
        }
        .sheet(isPresented: $theme.showAppearance) {
            AppearanceView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    // Home sits in the middle and is where the app opens. Five tabs is all an iPhone tab bar
    // fits, so Privacy lives in Account (your photo, top right).
    private var tabs: some View {
        TabView(selection: $state.selectedTab) {
            NavigationStack { FriendsMapView() }
                .tabItem { Label("Map", systemImage: "map.fill") }
                .tag(AppTab.map)
            NavigationStack { AddFriendsView() }
                .tabItem { Label("Friends", systemImage: "person.2.fill") }
                .badge(state.friendRequests.incoming.count)
                .tag(AppTab.friends)
            NavigationStack { HomeView() }
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(AppTab.home)
            NavigationStack { TwinView() }
                .tabItem { Label("Twin", systemImage: "sparkles") }
                .tag(AppTab.twin)
            NavigationStack(path: $state.nudgePath) { NudgesView() }
                .tabItem { Label("Nudges", systemImage: "bell.fill") }
                .badge(openNudgeCount)
                .tag(AppTab.nudges)
        }
    }
}
