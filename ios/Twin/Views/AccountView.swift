import SwiftUI
import UIKit
import UniformTypeIdentifiers

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
    @State private var phone = ""
    @State private var phoneSaved = false
    @State private var editingInterests = false

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

                    Button {
                        editingInterests = true
                    } label: {
                        HStack(spacing: 12) {
                            IconBadge(systemImage: "heart.text.square")
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Your interests").font(Theme.bodyStrong(15)).foregroundStyle(Theme.ink)
                                Text(interestSummary)
                                    .font(Theme.small())
                                    .foregroundStyle(Theme.ink2)
                                    .lineLimit(1)
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

                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow(text: "Phone number")
                        HStack(spacing: 10) {
                            TextField("Add your number", text: $phone)
                                .font(Theme.body(16))
                                .keyboardType(.phonePad)
                                .textContentType(.telephoneNumber)
                                .onChange(of: phone) { _, _ in phoneSaved = false }
                            if phone != (state.me?.phone ?? "") {
                                Button("Save") { Task { await savePhone() } }
                                    .font(Theme.semibold(14))
                            } else if phoneSaved {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.sage)
                            }
                        }
                        Text("Friends who have you in their contacts find you by this number.")
                            .font(Theme.small(12))
                            .foregroundStyle(Theme.ink3)
                    }
                    .card()
                    .onAppear { phone = state.me?.phone ?? "" }

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
                        ForEach(state.users.filter { ["u_maya", "u_jay", "u_priya"].contains($0.id) }) { user in
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
            .sheet(isPresented: $editingInterests) {
                InterestsSheet()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .pullToRefresh {
                await state.reloadMe()
                await loadSources()
            }
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
                guard let code = try await GoogleAuth.signIn().serverAuthCode else {
                    throw APIError.notConfigured("Google did not return a server auth code. Check GIDServerClientID.")
                }
                try await state.api.exchangeGoogleCode(code)
            }
            let result = try await state.api.ingestGoogle()
            status = "Synced \(result.events) events, \(result.emails ?? 0) emails"
            await loadSources()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private var interestSummary: String {
        let picks = state.me?.interests ?? []
        return picks.isEmpty ? "Pick a few so suggestions fit you" : picks.joined(separator: ", ")
    }

    private func savePhone() async {
        do {
            let trimmed = phone.trimmingCharacters(in: .whitespaces)
            // An empty string clears the number on the server.
            let user = try await state.api.updateSettings(SettingsPatch(phone: trimmed))
            state.updateMe(user)
            phone = user.phone ?? ""
            phoneSaved = true
        } catch {
            self.error = error.localizedDescription
        }
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
