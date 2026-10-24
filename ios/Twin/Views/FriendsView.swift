import SwiftUI

struct FriendsView: View {
    @EnvironmentObject private var state: AppState
    @State private var friends: [FriendEntry] = []
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(eyebrow: state.me?.name ?? "You", title: "Your people")

                CircleOfPeople(me: state.me?.name ?? "?", friends: friends)
                    .frame(maxWidth: .infinity)

                VStack(spacing: 18) {
                    ForEach(Array(friends.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 {
                            Rectangle().fill(Theme.cream).frame(height: 1)
                        }
                        FriendRow(entry: entry) { tier in
                            Task { await setTier(entry, to: tier) }
                        }
                    }
                }
                .card()

                Label("Nobody ever sees how you ranked them.", systemImage: "eye.slash")
                    .font(Theme.small())
                    .foregroundStyle(Theme.ink2)
                    .padding(.horizontal, 4)

                ErrorText(message: error)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .screenBackground()
        .withUserPicker()
        .task(id: state.reloadToken) { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do {
            friends = try await state.api.friends()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func setTier(_ entry: FriendEntry, to tier: Tier) async {
        guard let index = friends.firstIndex(where: { $0.id == entry.id }) else { return }
        let previous = friends[index].tier
        friends[index].tier = tier
        do {
            _ = try await state.api.setTier(friendId: entry.friend.id, tier: tier)
            error = nil
        } catch {
            friends[index].tier = previous
            self.error = error.localizedDescription
        }
    }
}

/// Concentric rings: you in the middle, friends placed by how close you ranked them.
private struct CircleOfPeople: View {
    let me: String
    let friends: [FriendEntry]

    /// Spots around the rings, chosen to stay clear of the tier labels in the upper right.
    private static let angles: [Double] = [200, 40, 140, 250, 100, 170]

    private func radius(for tier: Tier) -> CGFloat {
        switch tier {
        case .closest: return 52
        case .close: return 84
        case .friend: return 103
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Theme.linen, style: StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
                .frame(width: 206, height: 206)
            Circle().fill(Theme.glow).frame(width: 140, height: 140)
            Circle().fill(Theme.blush).frame(width: 78, height: 78)
            Avatar(name: me, size: 46)

            ForEach(Array(friends.enumerated()), id: \.element.id) { index, entry in
                let angle = Angle.degrees(Self.angles[index % Self.angles.count])
                let r = radius(for: entry.tier)
                Avatar(name: entry.friend.name, size: entry.tier == .closest ? 34 : 30)
                    .offset(x: r * CGFloat(cos(angle.radians)), y: r * CGFloat(sin(angle.radians)))
                    .animation(.spring(response: 0.5, dampingFraction: 0.7), value: entry.tier)
            }

            ringLabel("Closest", color: Theme.emberDeep, x: 66, y: -34)
            ringLabel("Close", color: Theme.ink2, x: 92, y: -62)
            ringLabel("Friends", color: Theme.ink3, x: 112, y: -96)
        }
        .frame(height: 220)
    }

    private func ringLabel(_ text: String, color: Color, x: CGFloat, y: CGFloat) -> some View {
        Eyebrow(text: text, color: color).offset(x: x, y: y)
    }
}

private struct FriendRow: View {
    let entry: FriendEntry
    let onChange: (Tier) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Avatar(name: entry.friend.name)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.friend.name).font(Theme.bodyStrong()).foregroundStyle(Theme.ink)
                    Text(caption).font(Theme.small()).foregroundStyle(Theme.ink2)
                }
            }
            TierPicker(selection: entry.tier, onChange: onChange)
        }
    }

    private var caption: String {
        switch entry.tier {
        case .closest: return "Hears a short summary when you need support"
        case .close: return "Hears a general heads-up"
        case .friend: return "Never nudged about you"
        }
    }
}
