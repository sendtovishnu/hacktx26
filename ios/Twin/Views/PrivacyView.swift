import SwiftUI

struct PrivacyView: View {
    @EnvironmentObject private var state: AppState
    @State private var info: PrivacyInfo?
    @State private var error: String?
    @State private var serverURLDraft = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(eyebrow: "Privacy", title: "Only what you choose")

                VStack(spacing: 16) {
                    control("Surprise support", "Closest friends can be nudged when your week gets heavy",
                            isOn: settingBinding(\.surpriseOptIn) { value in
                                try await state.api.updateSettings(surpriseOptIn: value, paused: nil)
                            })
                    Rectangle().fill(Theme.cream).frame(height: 1)
                    control("Pause all nudges", "For when you'd rather have space",
                            isOn: settingBinding(\.paused) { value in
                                try await state.api.updateSettings(surpriseOptIn: nil, paused: value)
                            })
                }
                .card()

                VStack(alignment: .leading, spacing: 12) {
                    Eyebrow(text: "Your twin never shares")
                    neverRow("calendar", "Your calendar entries")
                    neverRow("envelope", "Your emails or who sent them")
                    neverRow("list.number", "How you ranked anyone")
                }
                .card()

                VStack(alignment: .leading, spacing: 12) {
                    Eyebrow(text: "Connected sources")
                    sourceRow("Google Calendar and Gmail", connected: info?.sources.google ?? false)
                    sourceRow("Calendar file", connected: info?.sources.ics ?? false)
                    Text("Manage these from your account: tap your photo in the top right.")
                        .font(Theme.small(12))
                        .foregroundStyle(Theme.ink3)
                }
                .card()

                VStack(alignment: .leading, spacing: 12) {
                    Eyebrow(text: "Who can hear about you")
                    Text("Change someone's circle from their profile on Home.")
                        .font(Theme.small(12))
                        .foregroundStyle(Theme.ink3)
                    ForEach(info?.friends ?? []) { entry in
                        HStack(spacing: 12) {
                            Avatar(user: entry.friend, size: 32)
                            Text(entry.friend.name).font(Theme.bodyStrong(15)).foregroundStyle(Theme.ink)
                            Spacer()
                            Text(shareText(entry.tier)).font(Theme.small()).foregroundStyle(Theme.ink2)
                        }
                    }
                }
                .card()

                VStack(alignment: .leading, spacing: 12) {
                    Eyebrow(text: "Times friends showed up")
                    // Only nudges a friend has acted on. Pending ones stay hidden so the surprise isn't spoiled.
                    let revealed = (info?.nudgeLog ?? []).filter { $0.status == "acted" }
                    if revealed.isEmpty {
                        Text("Nothing here yet. When a friend shows up for you, you'll see how it happened.")
                            .font(Theme.body())
                            .foregroundStyle(Theme.ink2)
                    } else {
                        ForEach(revealed) { nudge in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .top, spacing: 12) {
                                    Avatar(name: name(for: nudge.toFriendId), id: nudge.toFriendId, size: 34)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(name(for: nudge.toFriendId)) showed up for you")
                                            .font(Theme.bodyStrong(14))
                                            .foregroundStyle(Theme.ink)
                                        // Muse's own explanation when it gave one.
                                        Text(nudge.reason ?? "Because you could use support and they're your \((Tier(rawValue: nudge.contextLevel) ?? .friend).label.lowercased())")
                                            .font(Theme.small(12))
                                            .foregroundStyle(Theme.ink2)
                                    }
                                    Spacer(minLength: 0)
                                    Text(DateText.ago(nudge.createdAt)).font(Theme.small(12)).foregroundStyle(Theme.ink3)
                                }
                                TwinHandshake(nudge: nudge, friendName: firstName(name(for: nudge.toFriendId)), sources: info?.sources)
                            }
                        }
                    }
                    Text("Your twin never tells you who it nudged until they act, so a surprise stays a surprise.")
                        .font(Theme.small(12))
                        .foregroundStyle(Theme.ink3)
                }
                .card()

                VStack(alignment: .leading, spacing: 12) {
                    Eyebrow(text: "Developer")
                    Toggle(isOn: $state.useMockAPI) {
                        Text("Use mock data").font(Theme.bodyStrong(15)).foregroundStyle(Theme.ink)
                    }
                    .tint(Theme.sage)
                    TextField("Server URL", text: $serverURLDraft)
                        .font(Theme.body())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .padding(12)
                        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Button("Apply connection settings") {
                        state.serverURL = serverURLDraft
                        Task {
                            await state.applyConnectionSettings()
                            await load()
                        }
                    }
                    .buttonStyle(SoftButtonStyle(height: 44))
                    Text("Mock data runs the whole flow on this phone. Turn it off and point at Person A's server: localhost from the simulator, a tunnel URL from a phone.")
                        .font(Theme.small(12))
                        .foregroundStyle(Theme.ink3)
                    ErrorText(message: state.lastError)
                }
                .card()

                ErrorText(message: error)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .screenBackground()
        .withAccountButton()
        .task(id: state.reloadToken) {
            serverURLDraft = state.serverURL
            await load()
        }
        .refreshable { await load() }
    }

    private func control(_ title: String, _ subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.bodyStrong(15)).foregroundStyle(Theme.ink)
                Text(subtitle).font(Theme.small()).foregroundStyle(Theme.ink2)
            }
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().tint(Theme.sage)
        }
    }

    private func neverRow(_ systemImage: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            IconBadge(systemImage: systemImage, size: 30, radius: 10, background: Theme.sageLight, foreground: Theme.sageInk)
            Text(text).font(Theme.body()).foregroundStyle(Theme.ink)
        }
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
            Text(title).font(Theme.body()).foregroundStyle(Theme.ink)
            Spacer()
            if connected {
                Pill(text: "Connected", tone: .sage, systemImage: "checkmark")
            } else {
                Text("Not connected").font(Theme.small()).foregroundStyle(Theme.ink3)
            }
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

    private func firstName(_ name: String) -> String {
        name.split(separator: " ").first.map(String.init) ?? name
    }
}

/// Twin to twin, made visible: what each twin knew, what crossed between them,
/// and what never left your account. Shown only after the friend acted.
private struct TwinHandshake: View {
    let nudge: Nudge
    let friendName: String
    let sources: PrivacyInfo.Sources?
    @State private var open = false

    private var yourSources: String {
        switch (sources?.google ?? false, sources?.ics ?? false) {
        case (true, _): return "your Google Calendar and Gmail"
        case (false, true): return "your calendar file"
        default: return "your calendar and email"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.snappy) { open.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.left.arrow.right.circle")
                    Text("How your twins worked it out")
                    Spacer()
                    Image(systemName: open ? "chevron.up" : "chevron.down").font(.system(size: 12, weight: .semibold))
                }
                .font(Theme.semibold(13))
                .foregroundStyle(Theme.accentDeep)
            }
            .buttonStyle(.plain)

            if open {
                VStack(alignment: .leading, spacing: 12) {
                    step(1, "Your twin", "Read \(yourSources). Saw you could use support.")
                    step(2, "To \(friendName)", "\u{201C}\(nudge.message)\u{201D}")
                    step(3, "To \(friendName)'s twin", "Only when you're busy and where you usually are. Never what you're doing.")
                    step(4, "\(friendName)'s twin", nudge.moment.map { "Read \(friendName)'s own calendar and found: \u{201C}\($0)\u{201D}" }
                         ?? "Read \(friendName)'s own calendar to find a good time.")
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lock.fill").foregroundStyle(Theme.sageInk)
                        Text("Never left your account: your event names, your emails, anything about other people.")
                            .font(Theme.small(12))
                            .foregroundStyle(Theme.sageInk)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.sageLight, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(Theme.cream, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func step(_ n: Int, _ who: String, _ what: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)")
                .font(Theme.semibold(12))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 22, height: 22)
                .background(Theme.accent, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(who).font(Theme.bodyStrong(13)).foregroundStyle(Theme.ink)
                Text(what).font(Theme.small(12)).foregroundStyle(Theme.ink2)
            }
        }
    }
}
