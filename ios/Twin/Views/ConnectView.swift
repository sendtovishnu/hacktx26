import SwiftUI
import UIKit
import UniformTypeIdentifiers
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

struct ConnectView: View {
    @EnvironmentObject private var state: AppState
    @State private var status: String?
    @State private var error: String?
    @State private var working = false
    @State private var showImporter = false

    private let scopes = [
        "https://www.googleapis.com/auth/calendar.readonly",
        "https://www.googleapis.com/auth/gmail.readonly"
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(eyebrow: "Connect", title: "Help your twin keep up")

                Text("Your twin reads your week so your closest friends can show up for you, without you having to ask.")
                    .font(Theme.body())
                    .foregroundStyle(Theme.ink2)

                VStack(alignment: .leading, spacing: 12) {
                    Eyebrow(text: "Sources")
                    sourceButton(
                        title: "Google Calendar and Gmail",
                        subtitle: "Read-only. Emails are summarized, then deleted.",
                        systemImage: "calendar.badge.plus"
                    ) {
                        Task { await connectGoogle() }
                    }
                    Rectangle().fill(Theme.cream).frame(height: 1)
                    sourceButton(
                        title: "Upload a calendar file",
                        subtitle: "An .ics export from any calendar app",
                        systemImage: "doc.badge.plus"
                    ) {
                        showImporter = true
                    }
                    if working {
                        HStack(spacing: 10) {
                            ProgressView().tint(Theme.ember)
                            Text("Connecting...").font(Theme.small()).foregroundStyle(Theme.ink2)
                        }
                    }
                    if let status {
                        Pill(text: status, tone: .sage, systemImage: "checkmark")
                    }
                    ErrorText(message: error)
                }
                .card()

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 14) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Surprise support").font(Theme.bodyStrong(15)).foregroundStyle(Theme.ink)
                            Text("Let my closest friends surprise me when I'm having a rough week")
                                .font(Theme.small())
                                .foregroundStyle(Theme.ink2)
                        }
                        Spacer()
                        Toggle("", isOn: optInBinding)
                            .labelsHidden()
                            .tint(Theme.sage)
                    }
                    Text("You won't be asked each time. Only close and closest friends can ever receive a nudge.")
                        .font(Theme.small(12))
                        .foregroundStyle(Theme.ink3)
                }
                .card()

                Label("Friends never see your calendar or email. Only a one-line summary leaves your account.", systemImage: "lock.fill")
                    .font(Theme.small())
                    .foregroundStyle(Theme.ink2)
                    .labelStyle(SageIconLabelStyle())
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .screenBackground()
        .withUserPicker()
        .task(id: state.reloadToken) {
            status = nil
            error = nil
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: icsTypes) { result in
            Task { await importICS(result) }
        }
    }

    private func sourceButton(title: String, subtitle: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                IconBadge(systemImage: systemImage)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.bodyStrong(15)).foregroundStyle(Theme.ink)
                    Text(subtitle).font(Theme.small()).foregroundStyle(Theme.ink2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(working)
    }

    private var icsTypes: [UTType] {
        [UTType(filenameExtension: "ics"), UTType.calendarEvent].compactMap { $0 }
    }

    private var optInBinding: Binding<Bool> {
        Binding(
            get: { state.me?.surpriseOptIn ?? false },
            set: { value in Task { await setOptIn(value) } }
        )
    }

    private func setOptIn(_ value: Bool) async {
        do {
            let user = try await state.api.updateSettings(surpriseOptIn: value, paused: nil)
            state.updateMe(user)
            error = nil
        } catch {
            self.error = error.localizedDescription
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
            status = "Connected · \(result.events) events, \(result.emails ?? 0) emails"
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func googleServerAuthCode() async throws -> String {
        #if canImport(GoogleSignIn)
        let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String ?? ""
        let serverClientID = Bundle.main.object(forInfoDictionaryKey: "GIDServerClientID") as? String ?? ""
        guard !clientID.isEmpty, !serverClientID.isEmpty else {
            throw APIError.notConfigured("Add GIDClientID (iOS client) and GIDServerClientID (Web client) to Twin-Info.plist, and the reversed iOS client ID as a URL scheme.")
        }
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
        } catch {
            self.error = error.localizedDescription
        }
    }
}
