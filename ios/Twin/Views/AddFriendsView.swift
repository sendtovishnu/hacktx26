import SwiftUI

struct AddFriendsView: View {
    @EnvironmentObject private var state: AppState
    @State private var query = ""
    @State private var friends: [FriendEntry] = []
    @State private var justAdded: [String: Tier] = [:]
    @State private var adding: User?
    @State private var error: String?

    private var friendIds: Set<String> { Set(friends.map(\.friend.id)) }

    private var people: [User] {
        let others = state.users.filter { $0.id != state.demoUserId }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return others.filter { !friendIds.contains($0.id) || justAdded[$0.id] != nil } }
        return others.filter { $0.name.lowercased().contains(q) || $0.email.lowercased().contains(q) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(eyebrow: "Add friends", title: "Bring your people in")

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.ink3)
                    TextField("Search by name or email", text: $query)
                        .font(Theme.body(16))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.ink3)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .frame(height: 50)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: Theme.shadow.opacity(0.05), radius: 8, y: 4)

                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow(text: query.isEmpty ? "People you may know" : "On Twin")
                    if people.isEmpty {
                        Text(query.isEmpty ? "You've added everyone we could find. Invite more friends below." : "No one by that name yet. Invite them below.")
                            .font(Theme.small())
                            .foregroundStyle(Theme.ink2)
                            .padding(.vertical, 8)
                    }
                    ForEach(people) { person in
                        personRow(person)
                    }
                }
                .card()

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        IconBadge(systemImage: "paperplane")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Invite a friend").font(Theme.bodyStrong()).foregroundStyle(Theme.ink)
                            Text("Twin works best when your closest people are on it too.")
                                .font(Theme.small())
                                .foregroundStyle(Theme.ink2)
                        }
                    }
                    ShareLink(item: "I'm using Twin so my friends and I can show up for each other. Join me?") {
                        Text("Share an invite")
                            .font(Theme.button())
                            .foregroundStyle(Theme.accentDeep)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(Theme.tint, in: Capsule())
                    }
                }
                .card()

                Label("When you add someone, you choose their circle. They're never told which one.", systemImage: "eye.slash")
                    .font(Theme.small())
                    .foregroundStyle(Theme.ink2)
                    .padding(.horizontal, 4)

                ErrorText(message: error)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .screenBackground()
        .withAccountButton()
        .task(id: state.reloadToken) {
            justAdded = [:]
            await load()
        }
        .sheet(item: $adding) { person in
            AddFriendSheet(person: person) { entry in
                justAdded[entry.friend.id] = entry.tier
                Task { await load() }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private func personRow(_ person: User) -> some View {
        HStack(spacing: 12) {
            Avatar(name: person.name, size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(person.name).font(Theme.bodyStrong(15)).foregroundStyle(Theme.ink)
                Text(person.homeLocation.components(separatedBy: ",").first ?? "")
                    .font(Theme.small(12))
                    .foregroundStyle(Theme.ink2)
            }
            Spacer()
            if let tier = justAdded[person.id] {
                Pill(text: "Added · \(tier.circleName)", tone: .sage, systemImage: "checkmark")
            } else if friendIds.contains(person.id) {
                Text("Friends").font(Theme.semibold(13)).foregroundStyle(Theme.ink3)
            } else {
                Button {
                    adding = person
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(Theme.semibold(14))
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(Theme.accent, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
    }

    private func load() async {
        if state.users.isEmpty { await state.reloadUsers() }
        do {
            friends = try await state.api.friends()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Adding someone means choosing their circle on purpose. No default is selected.
struct AddFriendSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    let person: User
    var onAdded: (FriendEntry) -> Void

    @State private var choice: Tier?
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(spacing: 10) {
                        Avatar(name: person.name, size: 72, glow: true)
                            .padding(14)
                        Text("Add \(person.name)")
                            .font(Theme.title(30))
                            .foregroundStyle(Theme.ink)
                        Text("Which circle should \(person.name) be in?")
                            .font(Theme.body(16))
                            .foregroundStyle(Theme.ink2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)

                    VStack(spacing: 10) {
                        ForEach(Tier.innerToOuter) { tier in
                            CircleOption(tier: tier, selected: choice == tier) {
                                withAnimation(.snappy) { choice = tier }
                            }
                        }
                    }

                    Text("Choose carefully. Your circles decide who your twin can reach out to, so you can change them later only from \(person.name)'s profile.")
                        .font(Theme.small(12))
                        .foregroundStyle(Theme.ink3)

                    ErrorText(message: error)
                }
                .padding(.horizontal, 20)
            }

            Button {
                Task { await add() }
            } label: {
                HStack(spacing: 8) {
                    if saving { ProgressView().tint(Theme.onAccent) }
                    Text(choice.map { "Add to \($0.circleName)" } ?? "Choose a circle")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(choice == nil || saving)
            .opacity(choice == nil ? 0.5 : 1)
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .screenBackground()
    }

    private func add() async {
        guard let choice else { return }
        saving = true
        defer { saving = false }
        do {
            let entry = try await state.api.addFriend(friendId: person.id, tier: choice)
            onAdded(entry)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
