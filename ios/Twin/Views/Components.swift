import SwiftUI

// Shared pieces used across tabs. Visual tokens live in Theme.swift.

struct Avatar: View {
    let name: String
    var id: String?
    var photoURL: String?
    var size: CGFloat = 44
    var glow = false
    @ObservedObject private var photos = AvatarStore.shared

    init(name: String, id: String? = nil, photoURL: String? = nil, size: CGFloat = 44, glow: Bool = false) {
        self.name = name
        self.id = id
        self.photoURL = photoURL
        self.size = size
        self.glow = glow
    }

    /// Preferred: shows the person's photo when they have one.
    init(user: User?, size: CGFloat = 44, glow: Bool = false) {
        self.init(name: user?.name ?? "?", id: user?.id, photoURL: user?.photoUrl, size: size, glow: glow)
    }

    var body: some View {
        ZStack {
            initials
            if let image = photos.image(for: id) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let photoURL, let url = URL(string: photoURL) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .background {
            if glow {
                Circle().fill(Theme.glow).frame(width: size + 24, height: size + 24)
                Circle().fill(Theme.tint).frame(width: size + 12, height: size + 12)
            }
        }
        .accessibilityLabel(name)
    }

    private var initials: some View {
        Circle()
            .fill(LinearGradient(colors: Theme.avatarColors(for: name), startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(
                Text(String(name.prefix(1)))
                    .font(.custom(Theme.Typeface.serif, size: size * 0.42))
                    .foregroundStyle(.white)
            )
    }
}

/// Your avatar with a camera badge; tapping it picks a new profile photo.
struct EditableAvatar: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject private var photos = AvatarStore.shared
    var size: CGFloat = 72

    private var hasPhoto: Bool { photos.image(for: state.me?.id) != nil }

    var body: some View {
        VStack(spacing: 10) {
            ProfilePhotoPicker {
                Avatar(user: state.me, size: size, glow: true)
                    .padding(12)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: size * 0.17, weight: .semibold))
                            .foregroundStyle(Theme.onAccent)
                            .frame(width: size * 0.4, height: size * 0.4)
                            .background(Theme.accent, in: Circle())
                            .overlay(Circle().strokeBorder(Theme.card, lineWidth: 3))
                            .offset(x: -6, y: -6)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Change profile photo")

            HStack(spacing: 14) {
                ProfilePhotoPicker {
                    Text(hasPhoto ? "Change photo" : "Add a photo")
                        .font(Theme.semibold(14))
                        .foregroundStyle(Theme.accentDeep)
                }
                if hasPhoto, let id = state.me?.id {
                    Button("Remove") {
                        AvatarStore.shared.remove(for: id)
                        Task {
                            if let user = try? await state.api.removePhoto() { state.updateMe(user) }
                        }
                    }
                    .font(Theme.semibold(14))
                    .foregroundStyle(Theme.ink3)
                }
            }
        }
    }
}

/// Your avatar in the top right. Opens Account: connected calendars and email, demo switching, sign out.
struct AccountButton: View {
    @EnvironmentObject private var state: AppState
    @State private var showAccount = false

    var body: some View {
        Button {
            showAccount = true
        } label: {
            Avatar(user: state.me, size: 34)
                .overlay(Circle().strokeBorder(Theme.card, lineWidth: 2))
                .shadow(color: Theme.shadow.opacity(0.12), radius: 6, y: 2)
        }
        .accessibilityLabel("Account")
        .sheet(isPresented: $showAccount) {
            AccountView()
                .presentationDragIndicator(.visible)
        }
    }
}

extension View {
    /// Adds the account avatar and hides the system title so screens can use ScreenHeader.
    func withAccountButton() -> some View {
        self
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { AccountButton() }
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
                .foregroundStyle(Theme.accentDeep)
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
                .foregroundStyle(Theme.accent)
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
                        .foregroundStyle(Theme.accent)
                        .frame(width: 34, height: 34)
                        .background(Theme.tint, in: Circle())
                }
                .accessibilityLabel("Open in Maps")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
