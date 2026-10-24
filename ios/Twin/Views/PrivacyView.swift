import SwiftUI

struct PrivacyView: View {
    @EnvironmentObject private var state: AppState
    @State private var info: PrivacyInfo?
    @State private var error: String?
    @State private var serverURLDraft = ""

    var body: some View {
        Form {
            Section("Your controls") {
                Toggle("Let my closest friends surprise me", isOn: settingBinding(\.surpriseOptIn) { value in
                    try await state.api.updateSettings(surpriseOptIn: value, paused: nil)
                })
                Toggle("Pause all nudges", isOn: settingBinding(\.paused) { value in
                    try await state.api.updateSettings(surpriseOptIn: nil, paused: value)
                })
            }

            Section("Connected sources") {
                sourceRow("Google Calendar and Gmail", connected: info?.sources.google ?? false)
                sourceRow("Calendar file (.ics)", connected: info?.sources.ics ?? false)
            }

            Section {
                ForEach(info?.friends ?? []) { entry in
                    HStack {
                        Avatar(name: entry.friend.name, size: 30)
                        Text(entry.friend.name)
                        Spacer()
                        Text(shareText(entry.tier))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Who can hear about you")
            } footer: {
                Text("Change tiers on the Friends tab.")
            }

            Section("Nudge log") {
                let log = info?.nudgeLog ?? []
                if log.isEmpty {
                    Text("Your twin hasn't nudged anyone yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(log) { nudge in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("To \(name(for: nudge.toFriendId))").font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(DateText.ago(nudge.createdAt)).font(.caption).foregroundStyle(.secondary)
                            }
                            Text(nudge.message).font(.caption).foregroundStyle(.secondary)
                            Text("Why: you could use support and they're your \(nudge.contextLevel) friend")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            Section("What your twin never shares") {
                Label("Your calendar entries", systemImage: "calendar")
                Label("Your emails or who they're from", systemImage: "envelope")
                Label("How you ranked anyone", systemImage: "list.number")
            }

            Section {
                Toggle("Use mock data", isOn: $state.useMockAPI)
                TextField("Server URL", text: $serverURLDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Button("Apply connection settings") {
                    state.serverURL = serverURLDraft
                    Task {
                        await state.applyConnectionSettings()
                        await load()
                    }
                }
                ErrorText(message: state.lastError)
            } header: {
                Text("Developer")
            } footer: {
                Text("Mock data runs the whole flow on this phone. Turn it off and point at Person A's server (localhost from the simulator, a tunnel URL from a phone).")
            }

            ErrorText(message: error)
        }
        .navigationTitle("Privacy")
        .withUserPicker()
        .task(id: state.reloadToken) {
            serverURLDraft = state.serverURL
            await load()
        }
        .refreshable { await load() }
    }

    private func load() async {
        do {
            info = try await state.api.privacy()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func settingBinding(_ keyPath: KeyPath<User, Bool>,
                                update: @escaping (Bool) async throws -> User) -> Binding<Bool> {
        Binding(
            get: { state.me?[keyPath: keyPath] ?? false },
            set: { value in
                Task {
                    do {
                        let user = try await update(value)
                        state.updateMe(user)
                        error = nil
                    } catch {
                        self.error = error.localizedDescription
                    }
                }
            }
        )
    }

    private func sourceRow(_ title: String, connected: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(connected ? "Connected" : "Not connected")
                .foregroundStyle(connected ? Color.green : Color.secondary)
        }
    }

    private func shareText(_ tier: Tier) -> String {
        switch tier {
        case .closest: return "Short summary"
        case .close: return "General heads-up"
        case .friend: return "Nothing"
        }
    }

    private func name(for userId: String) -> String {
        state.users.first { $0.id == userId }?.name ?? userId
    }
}
