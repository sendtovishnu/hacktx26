import SwiftUI

struct FriendsView: View {
    @EnvironmentObject private var state: AppState
    @State private var friends: [FriendEntry] = []
    @State private var error: String?

    var body: some View {
        List {
            Section {
                ForEach(friends) { entry in
                    FriendRow(entry: entry) { tier in
                        Task { await setTier(entry, to: tier) }
                    }
                }
            } footer: {
                Text("Only close and closest friends can ever be nudged about you. Nobody sees how you ranked them.")
            }
            if error != nil {
                Section { ErrorText(message: error) }
            }
        }
        .navigationTitle("Friends")
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

private struct FriendRow: View {
    let entry: FriendEntry
    let onChange: (Tier) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Avatar(name: entry.friend.name)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.friend.name).font(.headline)
                    Text(caption).font(.caption).foregroundStyle(.secondary)
                }
            }
            Picker("Tier", selection: Binding(get: { entry.tier }, set: onChange)) {
                ForEach(Tier.allCases) { tier in
                    Text(tier.label).tag(tier)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.vertical, 6)
    }

    private var caption: String {
        switch entry.tier {
        case .closest: return "Hears a short summary when you need support"
        case .close: return "Hears a general heads-up"
        case .friend: return "Never nudged about you"
        }
    }
}
