import MapKit
import SwiftUI

// Map tab: friends who chose to share with you, like Snap Map or Life360.
// You pick which circles see you; a friend shows up only if their setting covers the circle
// they put you in.

struct FriendsMapView: View {
    @EnvironmentObject private var state: AppState
    @State private var friends: [FriendLocation] = []
    @State private var position: MapCameraPosition = .automatic
    @State private var selected: FriendLocation?
    @State private var saving = false
    @State private var error: String?

    private var sharing: LocationSharing {
        LocationSharing(rawValue: state.me?.locationSharing ?? "nobody") ?? .nobody
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(position: $position, selection: $selected) {
                UserAnnotation()
                ForEach(friends) { friend in
                    Annotation(friend.user.name.split(separator: " ").first.map(String.init) ?? friend.user.name,
                               coordinate: CLLocationCoordinate2D(latitude: friend.lat, longitude: friend.lng),
                               anchor: .bottom) {
                        FriendPin(friend: friend, selected: selected == friend)
                    }
                    .tag(friend)
                }
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
            }
            .ignoresSafeArea(edges: .top)

            sharingCard
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
        }
        .withAccountButton()
        .task {
            // While the Map is open: friends every 20 seconds, your own spot every 2 minutes.
            var tick = 0
            while !Task.isCancelled {
                if tick % 6 == 0, sharing != .nobody { await state.shareLocation(askIfNeeded: false) }
                await loadFriends()
                tick += 1
                try? await Task.sleep(nanoseconds: 20_000_000_000)
            }
        }
    }

    private var sharingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let selected {
                HStack(spacing: 10) {
                    Avatar(user: selected.user, size: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(selected.user.name).font(Theme.bodyStrong(15)).foregroundStyle(Theme.ink)
                        Text([selected.label, "updated \(DateText.ago(selected.updatedAt))"].compactMap { $0 }.joined(separator: " · "))
                            .font(Theme.small(12))
                            .foregroundStyle(Theme.ink2)
                    }
                    Spacer()
                    Button {
                        openInMaps(selected)
                    } label: {
                        Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(Theme.accent)
                    }
                    .accessibilityLabel("Directions")
                }
                Rectangle().fill(Theme.cream).frame(height: 1)
            }

            HStack {
                Eyebrow(text: "Who can see you")
                Spacer()
                if saving { ProgressView().controlSize(.small) }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(LocationSharing.allCases) { option in
                        Button {
                            Task { await setSharing(option) }
                        } label: {
                            Text(option.label)
                                .font(Theme.semibold(13))
                                .foregroundStyle(option == sharing ? Theme.onAccent : Theme.ink)
                                .padding(.horizontal, 12)
                                .frame(height: 32)
                                .background(option == sharing ? Theme.accent : Theme.paper, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(saving)
                    }
                }
            }
            Text(friends.isEmpty
                 ? "\(sharing.detail) No friends are sharing with you yet."
                 : "\(sharing.detail) \(friends.count) \(friends.count == 1 ? "friend is" : "friends are") sharing with you.")
                .font(Theme.small(12))
                .foregroundStyle(Theme.ink2)
            ErrorText(message: error)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Theme.shadow.opacity(0.12), radius: 14, y: 6)
    }

    private func loadFriends() async {
        if let list = try? await state.api.friendLocations() {
            friends = list
            if let current = selected { selected = list.first { $0.id == current.id } }
        }
    }

    private func setSharing(_ option: LocationSharing) async {
        saving = true
        defer { saving = false }
        do {
            // Turning it on needs a location to share; ask for permission if we haven't.
            if option != .nobody, await state.shareLocation(askIfNeeded: true) == nil {
                error = "Twin can't see your location. Allow it in Settings > Twin > Location."
                return
            }
            state.updateMe(try await state.api.updateSettings(SettingsPatch(locationSharing: option.rawValue)))
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func openInMaps(_ friend: FriendLocation) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: friend.lat, longitude: friend.lng)))
        item.name = friend.user.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
    }
}

/// A friend's photo as a map pin.
private struct FriendPin: View {
    let friend: FriendLocation
    let selected: Bool

    var body: some View {
        VStack(spacing: 2) {
            Avatar(user: friend.user, size: selected ? 48 : 40)
                .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
            Image(systemName: "triangle.fill")
                .font(.system(size: 9))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(180))
                .offset(y: -4)
        }
        .animation(.snappy, value: selected)
    }
}
