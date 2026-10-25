import SwiftUI
import UIKit

// Friends tab. Friendship is always mutual: you send a request with the circle you chose,
// and it becomes a friendship only when they accept and choose theirs.

struct AddFriendsView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.openURL) private var openURL
    @State private var query = ""
    @State private var friends: [FriendEntry] = []
    @State private var sheet: CircleSheet?
    @State private var cancelling: FriendRequest?
    @State private var contact = ""
    @State private var shareItem: ShareItem?
    @State private var status: String?
    @State private var error: String?
    @State private var searchResults: [User] = []
    @State private var searching = false
    @State private var syncingContacts = false

    private var requests: FriendRequests { state.friendRequests }
    private var friendIds: Set<String> { Set(friends.map(\.friend.id)) }
    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    /// Contacts first, then everyone else, in the order they came.
    private func contactsFirst(_ users: [User]) -> [User] {
        let inContacts = users.filter { state.contactMatches[$0.id] != nil }
        return inContacts + users.filter { state.contactMatches[$0.id] == nil }
    }

    private var people: [User] {
        guard trimmedQuery.isEmpty else { return contactsFirst(searchResults) }
        // People you may know: your contacts on Twin, then anyone else you aren't friends with yet.
        let others = state.users.filter { $0.id != state.demoUserId && !friendIds.contains($0.id) }
        return contactsFirst(others)
    }

    /// What a typed contact is, so one field takes either.
    private var contactChannel: InviteChannel? {
        let value = contact.trimmingCharacters(in: .whitespaces)
        if value.contains("@") { return value.contains(".") ? .email : nil }
        return value.filter(\.isNumber).count >= 7 ? .sms : nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(eyebrow: "Friends", title: "Bring your people in")

                if !requests.incoming.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Eyebrow(text: requests.incoming.count == 1 ? "1 friend request" : "\(requests.incoming.count) friend requests")
                        ForEach(requests.incoming) { request in
                            incomingRow(request)
                        }
                    }
                    .card()
                }

                searchField

                if !state.contactsConnected {
                    contactsCard
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Eyebrow(text: trimmedQuery.isEmpty ? "People you may know" : "On Twin")
                        Spacer()
                        if searching { ProgressView().controlSize(.small) }
                    }
                    if people.isEmpty && !searching {
                        Text(trimmedQuery.isEmpty ? "You're friends with everyone we could find. Invite more below." : "No one on Twin matches \u{201C}\(trimmedQuery)\u{201D}. Invite them below.")
                            .font(Theme.small())
                            .foregroundStyle(Theme.ink2)
                            .padding(.vertical, 8)
                    }
                    ForEach(people) { person in
                        personRow(person)
                    }
                }
                .card()

                if !requests.outgoing.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Eyebrow(text: "Sent requests")
                        ForEach(requests.outgoing) { request in
                            HStack(spacing: 12) {
                                Avatar(user: request.user, size: 36)
                                Text(request.user.name).font(Theme.bodyStrong(15)).foregroundStyle(Theme.ink)
                                Spacer()
                                Button("Cancel") { cancelling = request }
                                    .font(Theme.semibold(13))
                                    .foregroundStyle(Theme.ink2)
                            }
                            .padding(.vertical, 6)
                        }
                    }
                    .card()
                }

                inviteCard

                Label("You choose each friend's circle, and they choose yours. Neither of you is told which.", systemImage: "eye.slash")
                    .font(Theme.small())
                    .foregroundStyle(Theme.ink2)
                    .padding(.horizontal, 4)

                if let status {
                    Label(status, systemImage: "checkmark.circle.fill")
                        .font(Theme.small())
                        .foregroundStyle(Theme.sage)
                }
                ErrorText(message: error)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .screenBackground()
        .withAccountButton()
        .pullToRefresh { await load() }
        .task(id: state.reloadToken) { await load() }
        // Searches the server as you type, after a short pause.
        .task(id: trimmedQuery) {
            guard !trimmedQuery.isEmpty else {
                searchResults = []
                return
            }
            searching = true
            defer { searching = false }
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            if let results = try? await state.api.searchUsers(trimmedQuery), !Task.isCancelled {
                searchResults = results
            }
        }
        .sheet(item: $sheet) { sheet in
            CircleChoiceSheet(sheet: sheet) { tier in
                try await run(sheet, tier: tier)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $shareItem) { item in
            ActivityView(items: [item.text])
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog(
            "Cancel your request to \(cancelling?.user.name ?? "them")?",
            isPresented: Binding(get: { cancelling != nil }, set: { if !$0 { cancelling = nil } }),
            titleVisibility: .visible
        ) {
            Button("Cancel request", role: .destructive) {
                if let request = cancelling { Task { await cancel(request) } }
            }
        }
    }

    // MARK: Rows

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.ink3)
            TextField("Search by name, email or phone", text: $query)
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
    }

    private func incomingRow(_ request: FriendRequest) -> some View {
        HStack(spacing: 12) {
            Avatar(user: request.user, size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(request.user.name).font(Theme.bodyStrong(15)).foregroundStyle(Theme.ink).lineLimit(1)
                Text("Wants to be friends").font(Theme.small(12)).foregroundStyle(Theme.ink2).lineLimit(1)
            }
            .layoutPriority(-1)
            Spacer()
            Button {
                Task { await decline(request) }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.ink2)
                    .frame(width: 34, height: 34)
                    .background(Theme.cream, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Decline")
            actionButton("Accept", systemImage: "checkmark") { sheet = .accept(request) }
        }
        .padding(.vertical, 8)
    }

    private func personRow(_ person: User) -> some View {
        HStack(spacing: 12) {
            Avatar(user: person, size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(person.name).font(Theme.bodyStrong(15)).foregroundStyle(Theme.ink)
                // Their phone or email, so you can tell it's the person you meant before tapping Add.
                Text(identifier(for: person))
                    .font(Theme.small(12))
                    .foregroundStyle(Theme.ink2)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let contactName = state.contactMatches[person.id] {
                    Label(contactName == person.name ? "In your contacts" : "In your contacts as \(contactName)", systemImage: "person.crop.circle.badge.checkmark")
                        .font(Theme.small(11))
                        .foregroundStyle(Theme.sageInk)
                        .lineLimit(1)
                }
            }
            Spacer()
            if friendIds.contains(person.id) {
                Text("Friends").font(Theme.semibold(13)).foregroundStyle(Theme.ink3)
            } else if let incoming = requests.incoming.first(where: { $0.user.id == person.id }) {
                actionButton("Accept", systemImage: "checkmark") { sheet = .accept(incoming) }
            } else if let outgoing = requests.outgoing.first(where: { $0.user.id == person.id }) {
                Button {
                    cancelling = outgoing
                } label: {
                    Pill(text: "Requested", tone: .neutral, systemImage: "clock")
                }
                .buttonStyle(.plain)
            } else {
                actionButton("Add", systemImage: "plus") { sheet = .request(person) }
            }
        }
        .padding(.vertical, 8)
    }

    /// The phone number when you searched with digits (or they're in your contacts), otherwise the email.
    private func identifier(for person: User) -> String {
        let typedDigits = trimmedQuery.filter(\.isNumber).count >= 3 && !trimmedQuery.contains("@")
        if let phone = person.phone, !phone.isEmpty, typedDigits || state.contactMatches[person.id] != nil {
            return phone
        }
        return person.email.isEmpty ? (person.phone ?? "") : person.email
    }

    private func actionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(Theme.semibold(14))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(Theme.accent, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var contactsCard: some View {
        HStack(spacing: 12) {
            IconBadge(systemImage: "person.crop.rectangle.stack")
            VStack(alignment: .leading, spacing: 2) {
                Text("Find friends from your contacts").font(Theme.bodyStrong(15)).foregroundStyle(Theme.ink)
                Text("See who's already on Twin. Your contacts aren't stored.")
                    .font(Theme.small(12))
                    .foregroundStyle(Theme.ink2)
            }
            Spacer(minLength: 0)
            Button {
                Task { await connectContacts() }
            } label: {
                if syncingContacts {
                    ProgressView().tint(Theme.onAccent).frame(width: 60, height: 34)
                } else {
                    Text("Connect")
                        .font(Theme.semibold(14))
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                }
            }
            .background(Theme.accent, in: Capsule())
            .buttonStyle(.plain)
            .disabled(syncingContacts)
        }
        .card()
    }

    private var inviteCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                IconBadge(systemImage: "paperplane")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Invite a friend").font(Theme.bodyStrong()).foregroundStyle(Theme.ink)
                    Text("Not on Twin yet? Text or email them a link. When they join, your request is waiting.")
                        .font(Theme.small())
                        .foregroundStyle(Theme.ink2)
                }
            }
            HStack(spacing: 10) {
                Image(systemName: contactChannel == .email ? "envelope" : "phone")
                    .foregroundStyle(Theme.ink3)
                    .frame(width: 18)
                TextField("Phone number or email", text: $contact)
                    .font(Theme.body(16))
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(Theme.paper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.linen, lineWidth: 1))

            Button {
                if let channel = contactChannel {
                    sheet = .invite(channel: channel, contact: contact.trimmingCharacters(in: .whitespaces))
                }
            } label: {
                Text(contactChannel == .email ? "Email invite" : contactChannel == .sms ? "Text invite" : "Send invite")
            }
            .buttonStyle(PrimaryButtonStyle(height: 46))
            .disabled(contactChannel == nil)
            .opacity(contactChannel == nil ? 0.5 : 1)

            Button {
                sheet = .invite(channel: .link, contact: nil)
            } label: {
                Label("Share an invite link", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(PrimaryButtonStyle(height: 46))
        }
        .card()
    }

    // MARK: Actions

    private func load() async {
        // Always fresh, so people who joined since the app opened show up.
        await state.reloadUsers()
        if state.contactsConnected { try? await state.syncContacts() }
        do {
            friends = try await state.api.friends()
            await state.reloadFriendRequests()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func run(_ sheet: CircleSheet, tier: Tier) async throws {
        status = nil
        error = nil
        switch sheet {
        case .request(let person):
            let result = try await state.api.sendFriendRequest(to: person.id, tier: tier)
            status = result.status == "accepted"
                ? "You and \(person.name) are now friends."
                : "Request sent to \(person.name)."
        case .accept(let request):
            _ = try await state.api.acceptFriendRequest(request.id, tier: tier)
            status = "You and \(request.user.name) are now friends."
        case .invite(let channel, let contact):
            let invite = try await state.api.createInvite(tier: tier, channel: channel, contact: contact)
            send(invite, channel: channel, to: contact)
        }
        await load()
    }

    private func send(_ invite: Invite, channel: InviteChannel, to contact: String?) {
        let body = invite.message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let address = (contact ?? "").addingPercentEncoding(withAllowedCharacters: .urlUserAllowed) ?? ""
        switch channel {
        case .sms:
            if let url = URL(string: "sms:\(address)&body=\(body)") { openURL(url) }
            self.contact = ""
        case .email:
            let subject = "Join me on Twin".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            if let url = URL(string: "mailto:\(address)?subject=\(subject)&body=\(body)") { openURL(url) }
            self.contact = ""
            status = "When \(contact ?? "they") signs in with that email, your request will be waiting."
        case .link:
            // Wait for the circle sheet to close; two sheets can't present at once.
            Task {
                try? await Task.sleep(nanoseconds: 600_000_000)
                shareItem = ShareItem(text: invite.message)
            }
        }
    }

    private func connectContacts() async {
        syncingContacts = true
        defer { syncingContacts = false }
        do {
            try await state.syncContacts()
            let count = state.contactMatches.count
            status = count == 0 ? "None of your contacts are on Twin yet. Invite them below." : "Found \(count) \(count == 1 ? "contact" : "contacts") on Twin."
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func decline(_ request: FriendRequest) async {
        do {
            try await state.api.declineFriendRequest(request.id)
            await state.reloadFriendRequests()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func cancel(_ request: FriendRequest) async {
        do {
            try await state.api.cancelFriendRequest(request.id)
            await state.reloadFriendRequests()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// What the circle sheet is choosing a circle for.
enum CircleSheet: Identifiable {
    case request(User)
    case accept(FriendRequest)
    case invite(channel: InviteChannel, contact: String?)

    var id: String {
        switch self {
        case .request(let user): return "request-\(user.id)"
        case .accept(let request): return "accept-\(request.id)"
        case .invite(let channel, let contact): return "invite-\(channel.rawValue)-\(contact ?? "")"
        }
    }
}

/// Every friendship starts with choosing a circle on purpose. No default is selected.
struct CircleChoiceSheet: View {
    @Environment(\.dismiss) private var dismiss
    let sheet: CircleSheet
    var onChoose: (Tier) async throws -> Void

    @State private var choice: Tier?
    @State private var saving = false
    @State private var error: String?

    private var person: User? {
        switch sheet {
        case .request(let user): return user
        case .accept(let request): return request.user
        case .invite: return nil
        }
    }

    private var name: String { person?.name.split(separator: " ").first.map(String.init) ?? "them" }

    private var title: String {
        switch sheet {
        case .request(let user): return "Add \(user.name)"
        case .accept(let request): return "\(request.user.name) wants to be friends"
        case .invite: return "Invite a friend"
        }
    }

    private var prompt: String {
        switch sheet {
        case .request: return "Which circle should \(name) be in? We'll send a request, and you'll be friends once they accept."
        case .accept: return "Which circle should \(name) be in? They chose one for you too, and neither of you sees the other's."
        case .invite: return "Which circle will they be in once they join?"
        }
    }

    private func buttonTitle(_ tier: Tier) -> String {
        switch sheet {
        case .request: return "Send request as \(tier.label.lowercased())"
        case .accept: return "Accept as \(tier.label.lowercased())"
        case .invite: return "Create invite as \(tier.label.lowercased())"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(spacing: 10) {
                        if let person {
                            Avatar(user: person, size: 72, glow: true)
                                .padding(14)
                        } else {
                            IconBadge(systemImage: "paperplane")
                                .padding(14)
                        }
                        Text(title)
                            .font(Theme.title(28))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Theme.ink)
                        Text(prompt)
                            .font(Theme.body(16))
                            .multilineTextAlignment(.center)
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

                    Text("Your circles decide who your twin can reach out to. You can change a friend's circle later from their profile.")
                        .font(Theme.small(12))
                        .foregroundStyle(Theme.ink3)

                    ErrorText(message: error)
                }
                .padding(.horizontal, 20)
            }

            Button {
                Task { await choose() }
            } label: {
                HStack(spacing: 8) {
                    if saving { ProgressView().tint(Theme.onAccent) }
                    Text(choice.map(buttonTitle) ?? "Choose a circle")
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

    private func choose() async {
        guard let choice else { return }
        saving = true
        defer { saving = false }
        do {
            try await onChoose(choice)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct ShareItem: Identifiable {
    let id = UUID()
    let text: String
}

/// The system share sheet, for sending an invite link through any app.
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
