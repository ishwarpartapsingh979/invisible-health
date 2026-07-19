import Foundation
import CoreLocation

/// App-wide coarse location — ONE manager, kept fresh (low power) while the app is
/// active, so callers read `current` synchronously. No per-call fetch, no
/// continuation races, no blocking reverse-geocode in the send path — which is what
/// was silently dropping the location before it ever reached the coach.
final class LocationStore: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationStore()

    private let manager = CLLocationManager()
    /// Latest coarse fix — read this synchronously; it's kept up to date.
    @Published private(set) var current: CLLocation?
    /// Reverse-geocoded area name (e.g. "Whitefield"); filled in the background.
    private(set) var area: String?
    private var lastGeocodeAt = Date.distantPast

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters   // coarse / low power
    }

    /// Call when the app becomes active (prompts once if needed, then keeps a fix).
    func start() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            if let cached = manager.location { update(cached) }   // instant if available
            manager.startUpdatingLocation()
        default:
            break
        }
    }

    func stop() { manager.stopUpdatingLocation() }

    private func update(_ loc: CLLocation) {
        current = loc
        // Throttled background reverse-geocode — never blocks a send.
        guard Date().timeIntervalSince(lastGeocodeAt) > 120 else { return }
        lastGeocodeAt = Date()
        CLGeocoder().reverseGeocodeLocation(loc) { [weak self] places, _ in
            if let p = places?.first { self?.area = p.subLocality ?? p.locality }
        }
    }

    // MARK: - CLLocationManagerDelegate
    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        switch m.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            if let cached = m.location { update(cached) }
            m.startUpdatingLocation()
        default:
            break
        }
    }
    func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        if let loc = locs.last { update(loc) }
    }
    func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {}
}
