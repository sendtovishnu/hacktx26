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
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your twin keeps up with your week so your closest friends can show up for you, without you having to ask.")
                    Text("Friends never see your calendar or email. Only a one-line summary ever leaves your account.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Sources") {
                Button {
                    Task { await connectGoogle() }
                } label: {
                    Label("Connect Google Calendar and Gmail", systemImage: "calendar.badge.plus")
                }
                .disabled(working)

                Button {
                    showImporter = true
                } label: {
                    Label("Upload a calendar file (.ics)", systemImage: "doc.badge.plus")
                }
                .disabled(working)

                if working {
                    HStack {
                        ProgressView()
                        Text("Connecting...").foregroundStyle(.secondary)
                    }
                }
                if let status {
                    Label(status, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                ErrorText(message: error)
            }

            Section {
                Toggle("Let my closest friends surprise me when I'm having a rough week", isOn: optInBinding)
            } header: {
                Text("Surprise support")
            } footer: {
                Text("You won't be asked each time. Your twin decides when a nudge would help, and only close and closest friends can receive one.")
            }
        }
        .navigationTitle("Connect")
        .withUserPicker()
        .task(id: state.reloadToken) {
            status = nil
            error = nil
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: icsTypes) { result in
            Task { await importICS(result) }
        }
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
            status = "Connected: \(result.events) events and \(result.emails ?? 0) emails"
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
            status = "Imported \(response.events) events from \(url.lastPathComponent)"
        } catch {
            self.error = error.localizedDescription
        }
    }
}
