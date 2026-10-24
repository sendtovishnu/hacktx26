import SwiftUI
import UIKit
import UniformTypeIdentifiers
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

/// Opened from the avatar in the top right of every tab.
struct AccountView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var theme = ThemeStore.shared
    @State private var sources = PrivacyInfo.Sources(google: false, ics: false)
    @State private var status: String?
    @State private var error: String?
    @State private var working = false
    @State private var showImporter = false
    @State private var confirmSignOut = false

    private let scopes = [
        "https://www.googleapis.com/auth/calendar.readonly",
        "https://www.googleapis.com/auth/gmail.readonly"
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(spacing: 10) {
                        EditableAvatar(size: 72)
                        Text(state.me?.name ?? "")
                            .font(Theme.title(28))
                            .foregroundStyle(Theme.ink)
                        Text(state.me?.email ?? "")
                            .font(Theme.small())
                            .foregroundStyle(Theme.ink2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)

                    VStack(alignment: .leading, spacing: 14) {
                        Eyebrow(text: "Connected accounts")
                        sourceRow(
                            title: "Google Calendar and Gmail",
                            subtitle: sources.google ? "Read-only. Emails are summarized, then deleted." : "Lets your twin notice busy weeks and deadlines",
                            systemImage: "calendar",
                            connected: sources.google
                        ) {
                            Task { await connectGoogle() }
                        }
                        Rectangle().fill(Theme.cream).frame(height: 1)
                        sourceRow(
                            title: "Calendar file",
                            subtitle: sources.ics ? "Imported" : "Upload an .ics export from any calendar app",
                            systemImage: "doc.badge.plus",
                            connected: sources.ics
                        ) {
                            showImporter = true
                        }
                        if working {
                            HStack(spacing: 10) {
                                ProgressView().tint(Theme.accent)
                                Text("Connecting...").font(Theme.small()).foregroundStyle(Theme.ink2)
                            }
                        }
                        if let status {
                            Pill(text: status, tone: .sage, systemImage: "checkmark")
                        }
                        ErrorText(message: error)
                        Text("Friends never see your calendar or email. Only a one-line summary ever leaves your account.")
                            .font(Theme.small(12))
                            .foregroundStyle(Theme.ink3)
                    }
                    .card()

                    Button {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                            ThemeStore.shared.showAppearance = true
                        }
                    } label: {
                        HStack(spacing: 12) {
                            IconBadge(systemImage: "paintpalette")
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Appearance").font(Theme.bodyStrong(15)).foregroundStyle(Theme.ink)
                                Text("\(theme.accent.name) · \(theme.appearance.label) mode")
                                    .font(Theme.small())
                                    .foregroundStyle(Theme.ink2)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.ink3)
                        }
                        .contentShape(Rectangle())
                        .card()
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 12) {
                        Eyebrow(text: "Demo: switch account")
                        ForEach(state.users.prefix(3)) { user in
                            Button {
                                Task {
                                    await state.switchUser(to: user.id)
                                    await loadSources()
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Avatar(user: user, size: 32)
                                    Text(user.name).font(Theme.bodyStrong(15)).foregroundStyle(Theme.ink)
                                    Spacer()
                                    if user.id == state.demoUserId {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.sage)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .card()

                    Button(role: .destructive) {
                        confirmSignOut = true
                    } label: {
                        Text("Sign out")
                            .font(Theme.button())
                            .foregroundStyle(Theme.accentDeep)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Theme.card, in: Capsule())
                            .overlay(Capsule().strokeBorder(Theme.linen, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .screenBackground()
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(Theme.semibold(16))
                }
            }
            .confirmationDialog("Sign out of Twin?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) {
                    dismiss()
                    state.signOut()
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: icsTypes) { result in
                Task { await importICS(result) }
            }
            .task { await loadSources() }
        }
        .id(theme.accent)
        .tint(theme.accent.accent)
    }

    private func sourceRow(title: String, subtitle: String, systemImage: String, connected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                IconBadge(systemImage: systemImage,
                          background: connected ? Theme.sageLight : Theme.tint,
                          foreground: connected ? Theme.sageInk : Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.bodyStrong(15)).foregroundStyle(Theme.ink)
                    Text(subtitle).font(Theme.small()).foregroundStyle(Theme.ink2)
                }
                Spacer()
                if connected {
                    Text("Connected").font(Theme.semibold(12)).foregroundStyle(Theme.sageInk)
                } else {
                    Text("Connect").font(Theme.semibold(13)).foregroundStyle(Theme.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(working)
    }

    private var icsTypes: [UTType] {
        [UTType(filenameExtension: "ics"), UTType.calendarEvent].compactMap { $0 }
    }

    private func loadSources() async {
        if let info = try? await state.api.privacy() {
            sources = info.sources
        }
    }

    private func connectGoogle() async {
        working = true
        error = nil
        status = nil
        defer { working = false }
        do {
            if state.useMockAPI {
                try await state.api.exchangeGoogleCode("mock-code")
            } else {
                let code = try await googleServerAuthCode()
                try await state.api.exchangeGoogleCode(code)
            }
            let result = try await state.api.ingestGoogle()
            status = "Synced \(result.events) events, \(result.emails ?? 0) emails"
            await loadSources()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func googleServerAuthCode() async throws -> String {
        #if canImport(GoogleSignIn)
        let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String ?? ""
        let serverClientID = Bundle.main.object(forInfoDictionaryKey: "GIDServerClientID") as? String ?? ""
        guard !clientID.isEmpty, !serverClientID.isEmpty else {
            throw APIError.notConfigured("Google sign-in isn't set up in this build. Add GOOGLE_IOS_CLIENT_ID, GOOGLE_WEB_CLIENT_ID, and GOOGLE_WEB_CLIENT_SECRET to server/.env (see README), run make google-check, then rebuild with make sim or make phone.")
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(
            clientID: clientID,
            serverClientID: serverClientID
        )
        guard let presenter = topViewController() else {
            throw APIError.notConfigured("Could not find a screen to show Google sign-in on.")
        }
        let result = try await GIDSignIn.sharedInstance.signIn(
            withPresenting: presenter,
            hint: nil,
            additionalScopes: scopes
        )
        guard let code = result.serverAuthCode, !code.isEmpty else {
            throw APIError.notConfigured("Google did not return a server auth code. Check GIDServerClientID.")
        }
        return code
        #else
        throw APIError.notConfigured("Add the GoogleSignIn package first: File > Add Package Dependencies > https://github.com/google/GoogleSignIn-iOS (product GoogleSignIn).")
        #endif
    }

    private func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }

    private func importICS(_ result: Result<URL, Error>) async {
        working = true
        error = nil
        status = nil
        defer { working = false }
        do {
            let url = try result.get()
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing { url.stopAccessingSecurityScopedResource() }
            }
            let data = try Data(contentsOf: url)
            let response = try await state.api.ingestICS(data: data, filename: url.lastPathComponent)
            status = "Imported \(response.events) events"
            await loadSources()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
