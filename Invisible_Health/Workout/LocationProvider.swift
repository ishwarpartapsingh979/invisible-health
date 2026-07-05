import Foundation
import CoreLocation

/// Live outdoor distance + pace from the iPhone's GPS during a workout (Tier 3
/// #9). Whoop has no GPS — it uses the phone's — so we read it directly. Indoors
/// / on a treadmill there's no GPS movement, so it simply reports nothing and the
/// coach falls back to time + heart rate.
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    /// Called ~every GPS update with (cumulative meters, pace string like "6:10 /km" or nil).
    var onUpdate: ((_ distanceMeters: Double, _ pace: String?) -> Void)?

    private let manager = CLLocationManager()
    private var lastLocation: CLLocation?
    private(set) var distanceMeters: Double = 0
    private var running = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .fitness
        manager.distanceFilter = 5   // meters
    }

    func start() {
        guard !running else { return }
        running = true
        distanceMeters = 0
        lastLocation = nil
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func stop() {
        running = false
        manager.stopUpdatingLocation()
        lastLocation = nil
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard running else { return }
        for loc in locations {
            // Reject noisy / stale fixes.
            guard loc.horizontalAccuracy >= 0, loc.horizontalAccuracy < 25,
                  loc.timestamp.timeIntervalSinceNow > -5 else { continue }
            if let last = lastLocation {
                let step = loc.distance(from: last)
                // Ignore GPS jitter while stationary (indoor/treadmill).
                if step > 1 { distanceMeters += step }
            }
            lastLocation = loc

            var pace: String? = nil
            if loc.speed > 0.4 {   // m/s; ~ slower than a shuffle => ignore
                let secPerKm = 1000.0 / loc.speed
                pace = String(format: "%d:%02d /km", Int(secPerKm) / 60, Int(secPerKm) % 60)
            }
            onUpdate?(distanceMeters, pace)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Silent — outdoor GPS can drop; the coach just uses time + HR meanwhile.
    }
}
