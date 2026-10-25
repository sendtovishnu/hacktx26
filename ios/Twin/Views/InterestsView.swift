import SwiftUI

// What you're into, picked at sign-up and editable from Account.
// The twin builds ways to show up for you around these, together with your friend's.

enum InterestCatalog {
    struct Group: Identifiable {
        let title: String
        let items: [(emoji: String, name: String)]
        var id: String { title }
    }

    static let groups: [Group] = [
        Group(title: "Food and drink", items: [
            ("☕️", "Coffee"), ("🍵", "Matcha"), ("🧋", "Boba"), ("🥐", "Bakeries"), ("🍳", "Brunch"),
            ("🍦", "Ice cream"), ("🍩", "Desserts"), ("🌮", "Tacos"), ("🍣", "Sushi"), ("🍕", "Pizza"),
            ("🍜", "Ramen"), ("🥗", "Healthy eats"), ("🚚", "Food trucks"), ("🧑‍🍳", "Cooking"), ("🧁", "Baking"),
        ]),
        Group(title: "Getting out", items: [
            ("🥾", "Hiking"), ("🌳", "Parks"), ("🏞️", "Lakes and swimming"), ("🏃", "Running"), ("🚴", "Cycling"),
            ("🧗", "Climbing"), ("🧘", "Yoga"), ("🏋️", "Gym"), ("🏀", "Basketball"), ("⚽️", "Soccer"),
            ("🎾", "Tennis"), ("🏐", "Volleyball"), ("💃", "Dance"), ("🛼", "Skating"),
        ]),
        Group(title: "Arts and culture", items: [
            ("📚", "Reading"), ("📖", "Bookstores"), ("🎨", "Art"), ("🏛️", "Museums"), ("📷", "Photography"),
            ("🎬", "Movies"), ("🎭", "Theater"), ("😂", "Comedy"), ("🎵", "Live music"), ("🎤", "Karaoke"),
            ("🎧", "Music"), ("🎹", "Playing music"), ("✍️", "Writing"), ("🧶", "Crafts"),
        ]),
        Group(title: "Hanging out", items: [
            ("🎲", "Board games"), ("🎮", "Video games"), ("🧩", "Puzzles"), ("🍿", "Movie nights"), ("📺", "Anime"),
            ("🛍️", "Thrifting"), ("👗", "Fashion"), ("🪴", "Plants"), ("🐶", "Dogs"), ("🐱", "Cats"),
            ("📝", "Studying together"), ("🤝", "Volunteering"), ("💻", "Tech"), ("🧠", "Trivia"),
        ]),
        Group(title: "Slowing down", items: [
            ("🧖", "Spa days"), ("🕯️", "Self-care"), ("📓", "Journaling"), ("🧘‍♀️", "Meditation"), ("🌅", "Sunsets"),
            ("🛏️", "Naps"), ("🌸", "Flowers"),
        ]),
    ]

    static var allNames: Set<String> { Set(groups.flatMap { $0.items.map(\.name) }) }
}

/// The checklist, plus anything you type yourself.
struct InterestsPicker: View {
    @Binding var selection: [String]
    @State private var custom = ""

    private var customPicks: [String] {
        selection.filter { !InterestCatalog.allNames.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(InterestCatalog.groups) { group in
                VStack(alignment: .leading, spacing: 10) {
                    Eyebrow(text: group.title)
                    FlowRow(spacing: 8) {
                        ForEach(group.items, id: \.name) { item in
                            chip(item.name, emoji: item.emoji, on: selection.contains(item.name)) {
                                toggle(item.name)
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: "Something else")
                HStack(spacing: 10) {
                    TextField("Type an interest", text: $custom)
                        .font(Theme.body(16))
                        .submitLabel(.done)
                        .onSubmit(addCustom)
                    Button("Add", action: addCustom)
                        .font(Theme.semibold(14))
                        .disabled(custom.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.linen, lineWidth: 1))
                if !customPicks.isEmpty {
                    FlowRow(spacing: 8) {
                        ForEach(customPicks, id: \.self) { name in
                            chip("\(name)  ✕", on: true) { toggle(name) }
                        }
                    }
                }
            }
        }
    }

    /// Paper Mono has no emoji, so the emoji is drawn in the system font beside the name.
    private func chip(_ text: String, emoji: String? = nil, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let emoji {
                    Text(emoji).font(.system(size: 15))
                }
                Text(text)
                    .font(Theme.semibold(14))
            }
            .foregroundStyle(on ? Theme.onAccent : Theme.ink)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(on ? Theme.accent : Theme.card, in: Capsule())
            .overlay(Capsule().strokeBorder(on ? .clear : Theme.linen, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.15), value: on)
    }

    private func toggle(_ name: String) {
        if let index = selection.firstIndex(of: name) {
            selection.remove(at: index)
        } else {
            selection.append(name)
        }
    }

    private func addCustom() {
        let name = custom.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        if !selection.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            selection.append(String(name.prefix(40)))
        }
        custom = ""
    }
}

/// Editing interests later, from Account.
struct InterestsSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var selection: [String] = []
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("What are you into?")
                            .font(Theme.title(28))
                            .foregroundStyle(Theme.ink)
                        Text("Your FirstMate uses these to suggest ways friends can show up for you, and ways you can show up for them.")
                            .font(Theme.small())
                            .foregroundStyle(Theme.ink2)
                    }
                    .padding(.top, 24)
                    InterestsPicker(selection: $selection)
                    ErrorText(message: error)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)

            Button {
                Task { await save() }
            } label: {
                HStack(spacing: 8) {
                    if saving { ProgressView().tint(Theme.onAccent) }
                    Text("Save")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(saving)
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .screenBackground()
        .onAppear { selection = state.me?.interests ?? [] }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            state.updateMe(try await state.api.updateSettings(SettingsPatch(interests: selection)))
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
