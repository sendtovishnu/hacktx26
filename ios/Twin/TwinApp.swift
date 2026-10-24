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
                    #if canImport(GoogleSignIn)
                    GIDSignIn.sharedInstance.handle(url)
                    #endif
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
        .preferredColorScheme(theme.appearance.colorScheme)
        .fullScreenCover(item: $state.activeSurprise) { gesture in
            SurpriseView(gesture: gesture)
        }
        .sheet(isPresented: $theme.showAppearance) {
            AppearanceView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(theme.appearance.colorScheme)
        }
    }

    private var tabs: some View {
        TabView {
            NavigationStack { HomeView() }
                .tabItem { Label("Home", systemImage: "circle.circle") }
            NavigationStack { AddFriendsView() }
                .tabItem { Label("Add friends", systemImage: "person.badge.plus") }
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
