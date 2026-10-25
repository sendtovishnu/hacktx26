import CoreLocation

// One location fix, when the person allows it: for searching near them, and for the Map,
// where only the circles they choose can see it.

@MainActor
final class LocationReporter: NSObject, CLLocationManagerDelegate {
    static let shared = LocationReporter()

    private let manager = CLLocationManager()
    private var authContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?
    private var fixContinuation: CheckedContinuation<CLLocation?, Never>?

    override private init() {
        super.init()
        manager.delegate = self
        // A city block is plenty for "near me", and it's quicker and kinder on battery.
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var isAuthorized: Bool {
        [.authorizedWhenInUse, .authorizedAlways].contains(manager.authorizationStatus)
    }

    var isUndecided: Bool { manager.authorizationStatus == .notDetermined }

    /// Asks only if the person hasn't decided yet; returns nil if they said no.
    func currentLocation(askIfNeeded: Bool) async -> (lat: Double, lng: Double, label: String?)? {
        if manager.authorizationStatus == .notDetermined {
            guard askIfNeeded else { return nil }
            _ = await withCheckedContinuation { continuation in
                authContinuation = continuation
                manager.requestWhenInUseAuthorization()
            }
        }
        guard isAuthorized else { return nil }
        let location = await withCheckedContinuation { continuation in
            fixContinuation = continuation
            manager.requestLocation()
        }
        guard let location else { return nil }
        return (location.coordinate.latitude, location.coordinate.longitude, await cityLabel(for: location))
    }

    /// "Austin, TX", so the twin's prompts and searches name the right city.
    private func cityLabel(for location: CLLocation) async -> String? {
        guard let place = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return nil }
        return [place.locality, place.administrativeArea].compactMap { $0 }.joined(separator: ", ")
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard status != .notDetermined else { return }
            authContinuation?.resume(returning: status)
            authContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let last = locations.last
        Task { @MainActor in
            fixContinuation?.resume(returning: last)
            fixContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            fixContinuation?.resume(returning: nil)
            fixContinuation = nil
        }
    }
}
