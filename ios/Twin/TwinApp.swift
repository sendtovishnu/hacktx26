import SwiftUI
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

@main
struct TwinApp: App {
    @StateObject private var state = AppState()

    init() {
        Notifier.requestPermission()
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

struct RootView: View {
    @EnvironmentObject private var state: AppState
    @AppStorage("hasOnboarded") private var hasOnboarded = false

    private var openNudgeCount: Int {
        state.nudges.filter { $0.status != "acted" }.count
    }

    var body: some View {
        Group {
            if hasOnboarded {
                tabs
            } else {
                WelcomeView {
                    withAnimation(.easeInOut) { hasOnboarded = true }
                }
            }
        }
        .tint(Theme.ember)
        .fullScreenCover(item: $state.activeSurprise) { gesture in
            SurpriseView(gesture: gesture)
        }
    }

    private var tabs: some View {
        TabView {
            NavigationStack { FriendsView() }
                .tabItem { Label("People", systemImage: "person.2.fill") }
            NavigationStack { ConnectView() }
                .tabItem { Label("Connect", systemImage: "link") }
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

struct WelcomeView: View {
    let onStart: () -> Void
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 28) {
                ZStack {
                    Circle()
                        .fill(RadialGradient(
                            colors: [Color(hex: 0xFBE3D6), Theme.glow, Theme.paper.opacity(0)],
                            center: .center, startRadius: 0, endRadius: 115
                        ))
                        .frame(width: 230, height: 230)
                        .scaleEffect(appeared ? 1 : 0.85)
                    TwinMark(width: 150)
                        .scaleEffect(appeared ? 1 : 0.7)
                }
                Text("Your friends shouldn't have to ask.")
                    .font(Theme.title(38))
                    .tracking(-0.6)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.ink)
                Text("Twin keeps up with your week and quietly lets your closest people know when you could use them.")
                    .font(Theme.body(17))
                    .lineSpacing(3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.ink2)
            }
            .padding(.horizontal, 28)
            .opacity(appeared ? 1 : 0)
            Spacer()
            VStack(spacing: 14) {
                Button("Get started", action: onStart)
                    .buttonStyle(PrimaryButtonStyle())
                Label("Your calendar and email never leave your twin.", systemImage: "lock.fill")
                    .font(Theme.small())
                    .foregroundStyle(Theme.ink2)
                    .labelStyle(SageIconLabelStyle())
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .screenBackground()
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) { appeared = true }
        }
    }
}

struct SageIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 7) {
            configuration.icon.foregroundStyle(Theme.sage)
            configuration.title
        }
    }
}
