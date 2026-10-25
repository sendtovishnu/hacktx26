import SwiftUI
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

@main
struct TwinApp: App {
    @StateObject private var state = AppState()

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

    private var tabs: some View {
        TabView {
            NavigationStack { HomeView() }
                .tabItem { Label("Home", systemImage: "circle.circle") }
            NavigationStack { AddFriendsView() }
                .tabItem { Label("Friends", systemImage: "person.badge.plus") }
                .badge(state.friendRequests.incoming.count)
            NavigationStack { TwinView() }
                .tabItem { Label("Twin", systemImage: "sparkles") }
            NavigationStack { NudgesView() }
                .tabItem { Label("Nudges", systemImage: "bell.fill") }
                .badge(openNudgeCount)
            NavigationStack { PrivacyView() }
                .tabItem { Label("Privacy", systemImage: "lock.fill") }
        }
    }
}
