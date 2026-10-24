import SwiftUI

// Small shared pieces used across tabs.

struct Avatar: View {
    let name: String
    var size: CGFloat = 40

    private var color: Color {
        let palette: [Color] = [.orange, .pink, .purple, .teal, .indigo, .mint, .blue]
        let sum = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return palette[sum % palette.count]
    }

    var body: some View {
        Circle()
            .fill(color.gradient)
            .frame(width: size, height: size)
            .overlay(
                Text(String(name.prefix(1)))
                    .font(.system(size: size * 0.45, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            )
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
            HStack(spacing: 6) {
                Avatar(name: state.me?.name ?? "?", size: 28)
                Text(state.me?.name ?? "Pick user")
                    .font(.subheadline.weight(.semibold))
            }
        }
    }
}

extension View {
    /// Adds the demo user switcher to the navigation bar.
    func withUserPicker() -> some View {
        toolbar {
            ToolbarItem(placement: .topBarTrailing) { UserPicker() }
        }
    }

    func card() -> some View {
        padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
    }
}

struct ErrorText: View {
    let message: String?

    var body: some View {
        if let message {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }
}

struct PlaceDetails: View {
    let place: Place

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "mappin.and.ellipse")
                Text(place.name).font(.subheadline.weight(.semibold))
                if let rating = place.rating {
                    Label(String(format: "%.1f", rating), systemImage: "star.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if place.openNow == true {
                    Text("Open now")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }
            Text(place.address)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let link = place.mapsLink {
                Link(destination: link) {
                    Label("Open in Maps", systemImage: "map")
                        .font(.caption.weight(.semibold))
                }
            }
        }
    }
}
