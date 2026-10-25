import SwiftUI

extension Tier {
    /// Inner to outer.
    static let innerToOuter: [Tier] = [.closest, .close, .friend]

    var circleName: String {
        switch self {
        case .closest: return "Closest friends"
        case .close: return "Close friends"
        case .friend: return "Friends"
        }
    }

    var hears: String {
        switch self {
        case .closest: return "Hears a short summary when you could use support"
        case .close: return "Hears a gentle heads-up, never details"
        case .friend: return "Hears nothing about your week"
        }
    }

    var accent: Color {
        switch self {
        case .closest: return Theme.accentDeep
        case .close: return Theme.ink2
        case .friend: return Theme.ink3
        }
    }
}

// MARK: Home

struct HomeView: View {
    @EnvironmentObject private var state: AppState
    @State private var friends: [FriendEntry] = []
    @State private var selected: FriendEntry?
    @State private var sheetDetent: PresentationDetent = .medium
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(eyebrow: state.me?.name ?? "You", title: "Your circles")

                OrbitView(me: state.me, friends: friends) { entry in
                    selected = entry
                }
                .frame(maxWidth: .infinity)

                ForEach(Tier.innerToOuter) { tier in
                    circleCard(tier)
                }

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
        .withAccountButton()
        .task(id: state.reloadToken) { await load() }
        .onAppear { Task { await load() } }
        .refreshable { await load() }
        .onChange(of: selected) { _, _ in sheetDetent = .medium }
        .sheet(item: $selected) { entry in
            FriendProfileSheet(entry: entry, onEdit: { sheetDetent = .large }) { updated in
                if let index = friends.firstIndex(where: { $0.id == updated.id }) {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                        friends[index] = updated
                    }
                }
            }
            .presentationDetents([.medium, .large], selection: $sheetDetent)
            .presentationDragIndicator(.visible)
        }
    }

    private func circleCard(_ tier: Tier) -> some View {
        let members = friends.filter { $0.tier == tier }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(tier.circleName)
                    .font(Theme.heading(20))
                    .foregroundStyle(Theme.ink)
                Text("\(members.count)")
                    .font(Theme.semibold(13))
                    .foregroundStyle(tier.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(tier == .closest ? Theme.tint : Theme.cream, in: Capsule())
                Spacer()
            }
            Text(tier.hears)
                .font(Theme.small())
                .foregroundStyle(Theme.ink2)

            if members.isEmpty {
                Text(tier == .closest ? "No one yet. Add your person from Friends." : "No one here yet.")
                    .font(Theme.small())
                    .foregroundStyle(Theme.ink3)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(members) { entry in
                        Button {
                            selected = entry
                        } label: {
                            HStack(spacing: 12) {
                                Avatar(user: entry.friend, size: 38)
                                Text(entry.friend.name)
                                    .font(Theme.bodyStrong(15))
                                    .foregroundStyle(Theme.ink)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.ink3)
                            }
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .card()
    }

    private func load() async {
        do {
            friends = try await state.api.friends()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: Orbits

/// You at the center, friends orbiting slowly on the ring for their circle.
struct OrbitView: View {
    let me: User?
    let friends: [FriendEntry]
    var onSelect: (FriendEntry) -> Void = { _ in }

    private let size: CGFloat = 320

    private func radius(_ tier: Tier) -> CGFloat {
        switch tier {
        case .closest: return 62
        case .close: return 106
        case .friend: return 148
        }
    }

    /// Seconds per revolution; inner rings move a little faster, like planets.
    private func period(_ tier: Tier) -> Double {
        switch tier {
        case .closest: return 90
        case .close: return 140
        case .friend: return 200
        }
    }

    private func startAngle(_ tier: Tier) -> Double {
        switch tier {
        case .closest: return 200
        case .close: return 40
        case .friend: return 130
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            orbits
            legend
        }
    }

    private var orbits: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                Circle()
                    .strokeBorder(Theme.accentSoft.opacity(0.7), style: StrokeStyle(lineWidth: 1.2, dash: [4, 6]))
                    .frame(width: radius(.friend) * 2, height: radius(.friend) * 2)
                Circle()
                    .fill(Theme.glow)
                    .frame(width: radius(.close) * 2, height: radius(.close) * 2)
                Circle()
                    .strokeBorder(Theme.accentSoft, lineWidth: 1.2)
                    .frame(width: radius(.close) * 2, height: radius(.close) * 2)
                Circle()
                    .fill(Theme.tint)
                    .frame(width: radius(.closest) * 2, height: radius(.closest) * 2)
                Circle()
                    .strokeBorder(Theme.accent.opacity(0.35), lineWidth: 1.2)
                    .frame(width: radius(.closest) * 2, height: radius(.closest) * 2)

                Avatar(user: me, size: 52, glow: false)
                    .overlay(Circle().strokeBorder(Theme.card, lineWidth: 3))
                    .shadow(color: Theme.accent.opacity(0.3), radius: 10, y: 4)

                ForEach(Tier.innerToOuter) { tier in
                    let members = friends.filter { $0.tier == tier }
                    ForEach(Array(members.enumerated()), id: \.element.id) { index, entry in
                        let spread = 360.0 / Double(max(members.count, 1))
                        let progress = t.truncatingRemainder(dividingBy: period(tier)) / period(tier)
                        let degrees = startAngle(tier) + Double(index) * spread + progress * 360
                        let radians = degrees * .pi / 180
                        planet(entry)
                            .offset(x: radius(tier) * CGFloat(cos(radians)),
                                    y: radius(tier) * CGFloat(sin(radians)))
                    }
                }
            }
            .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
    }

    private var legend: some View {
        HStack(spacing: 14) {
            ForEach(Tier.innerToOuter) { tier in
                HStack(spacing: 6) {
                    Circle()
                        .fill(tier == .closest ? Theme.tint : tier == .close ? Theme.glow : Color.clear)
                        .overlay(Circle().strokeBorder(tier == .friend ? Theme.linen : Theme.accentSoft.opacity(0.7), lineWidth: 1))
                        .frame(width: 10, height: 10)
                    Text(tier.circleName.uppercased())
                        .font(Theme.label(10))
                        .tracking(1.2)
                        .foregroundStyle(tier.accent)
                }
            }
        }
    }

    private func planet(_ entry: FriendEntry) -> some View {
        Button {
            onSelect(entry)
        } label: {
            VStack(spacing: 3) {
                Avatar(user: entry.friend, size: entry.tier == .closest ? 38 : 32)
                    .overlay(Circle().strokeBorder(Theme.card, lineWidth: 2))
                    .shadow(color: Theme.shadow.opacity(0.12), radius: 4, y: 2)
                Text(entry.friend.name)
                    .font(Theme.semibold(11))
                    .foregroundStyle(Theme.ink2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Theme.paper.opacity(0.9), in: Capsule())
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: Friend profile

/// Changing a circle is deliberate: pick a new circle, read what changes, then confirm.
struct FriendProfileSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    let entry: FriendEntry
    var onEdit: () -> Void = {}
    var onUpdate: (FriendEntry) -> Void

    @State private var editing = false
    @State private var choice: Tier?
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 10) {
                    Avatar(user: entry.friend, size: 76, glow: entry.tier == .closest)
                        .padding(14)
                    Text(entry.friend.name)
                        .font(Theme.title(30))
                        .foregroundStyle(Theme.ink)
                    Pill(text: "Your \(entry.tier.label.lowercased())",
                         tone: entry.tier == .closest ? .ember : .neutral)
                }
                .padding(.top, 24)

                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow(text: "What \(entry.friend.name) hears about you")
                    Text(entry.tier.hears + ".")
                        .font(Theme.body())
                        .foregroundStyle(Theme.ink)
                }
                .card()

                if editing {
                    VStack(alignment: .leading, spacing: 12) {
                        Eyebrow(text: "Move to")
                        ForEach(Tier.innerToOuter) { tier in
                            CircleOption(tier: tier, selected: choice == tier, current: tier == entry.tier) {
                                if tier != entry.tier { choice = tier }
                            }
                        }
                        if let choice {
                            Button {
                                Task { await save(choice) }
                            } label: {
                                HStack(spacing: 8) {
                                    if saving { ProgressView().tint(Theme.onAccent) }
                                    Text("Move \(entry.friend.name) to \(choice.circleName)")
                                }
                            }
                            .buttonStyle(PrimaryButtonStyle(height: 50))
                            .disabled(saving)
                        }
                        Button("Cancel") {
                            withAnimation { editing = false; choice = nil }
                        }
                        .font(Theme.semibold(15))
                        .foregroundStyle(Theme.ink2)
                        .frame(maxWidth: .infinity)
                    }
                    .card()
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else {
                    Button("Change circle") {
                        onEdit()
                        withAnimation { editing = true }
                    }
                    .buttonStyle(SoftButtonStyle(height: 50))
                }

                ErrorText(message: error)

                Text("\(entry.friend.name) is never told which circle they're in.")
                    .font(Theme.small(12))
                    .foregroundStyle(Theme.ink3)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .screenBackground()
    }

    private func save(_ tier: Tier) async {
        saving = true
        defer { saving = false }
        do {
            let updated = try await state.api.setTier(friendId: entry.friend.id, tier: tier)
            onUpdate(updated)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// A selectable circle with what that circle hears. Used when adding or moving a friend.
struct CircleOption: View {
    let tier: Tier
    let selected: Bool
    var current = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().strokeBorder(selected ? Theme.accent : Theme.linen, lineWidth: 2).frame(width: 22, height: 22)
                    if selected { Circle().fill(Theme.accent).frame(width: 12, height: 12) }
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(tier.label).font(Theme.bodyStrong(15)).foregroundStyle(Theme.ink)
                        if current {
                            Text("Now").font(Theme.semibold(11)).foregroundStyle(Theme.ink3)
                        }
                    }
                    Text(tier.hears).font(Theme.small()).foregroundStyle(Theme.ink2)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(selected ? Theme.glow : Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Theme.shadow.opacity(selected ? 0 : 0.05), radius: 6, y: 3)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(selected ? Theme.accent.opacity(0.5) : .clear, lineWidth: 1.5)
            )
            .opacity(current ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        .disabled(current)
    }
}
