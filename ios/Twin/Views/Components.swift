import SwiftUI

// Shared pieces used across tabs. Visual tokens live in Theme.swift.

struct Avatar: View {
    let name: String
    var size: CGFloat = 44
    var glow = false

    var body: some View {
        Circle()
            .fill(LinearGradient(colors: Theme.avatarColors(for: name), startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay(
                Text(String(name.prefix(1)))
                    .font(.custom(Theme.Typeface.serif, size: size * 0.42))
                    .foregroundStyle(.white)
            )
            .background {
                if glow {
                    Circle().fill(Theme.glow).frame(width: size + 24, height: size + 24)
                    Circle().fill(Theme.blush).frame(width: size + 12, height: size + 12)
                }
            }
    }
}

struct UserPicker: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Menu {
            Section("Demo as") {
                ForEach(state.users) { user in
                    Button {
                        Task { await state.switchUser(to: user.id) }
                    } label: {
                        if user.id == state.demoUserId {
                            Label(user.name, systemImage: "checkmark")
                        } else {
                            Text(user.name)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 7) {
                Avatar(name: state.me?.name ?? "?", size: 28)
                Text(state.me?.name ?? "Pick user")
                    .font(Theme.semibold(15))
                    .foregroundStyle(Theme.ink)
            }
            .padding(.leading, 4)
            .padding(.trailing, 10)
            .padding(.vertical, 4)
            .background(Color.white, in: Capsule())
            .shadow(color: Theme.ink.opacity(0.08), radius: 6, y: 2)
        }
    }
}

extension View {
    /// Adds the demo user switcher and hides the system title so screens can use ScreenHeader.
    func withUserPicker() -> some View {
        self
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { UserPicker() }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
    }
}

struct ErrorText: View {
    let message: String?

    var body: some View {
        if let message {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(Theme.small())
                .foregroundStyle(Theme.emberDeep)
        }
    }
}

struct PlaceDetails: View {
    let place: Place

    private var details: String {
        var parts: [String] = []
        if let rating = place.rating { parts.append(String(format: "%.1f stars", rating)) }
        if let street = place.address.split(separator: ",").first { parts.append(String(street)) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.ember)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(place.name)
                        .font(Theme.bodyStrong(14))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    if place.openNow == true {
                        Text("Open")
                            .font(Theme.semibold(11))
                            .foregroundStyle(Theme.sageInk)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Theme.sageLight, in: Capsule())
                    }
                }
                Text(details)
                    .font(Theme.small(12))
                    .foregroundStyle(Theme.ink2)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let link = place.mapsLink {
                Link(destination: link) {
                    Image(systemName: "map.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.ember)
                        .frame(width: 34, height: 34)
                        .background(Theme.blush, in: Circle())
                }
                .accessibilityLabel("Open in Maps")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
