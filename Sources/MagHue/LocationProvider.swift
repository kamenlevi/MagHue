import Combine
import CoreLocation

/// Fetches a one-time coarse location so the helper can resolve sunrise/sunset
/// anchors. Coordinates are cached in the config, so this only needs to run
/// when a solar schedule exists and we don't have a location yet.
final class LocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var authorization: CLAuthorizationStatus
    @Published private(set) var lastError: String?

    /// Called on the main thread when a fix arrives.
    var onLocation: ((CLLocationCoordinate2D) -> Void)?

    private let manager = CLLocationManager()

    override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    /// Ask for permission if needed, then request a single fix.
    func request() {
        lastError = nil
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorized, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            lastError = "Location access is off. Turn it on in System Settings → Privacy & Security → Location Services."
        @unknown default:
            manager.requestWhenInUseAuthorization()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        switch manager.authorizationStatus {
        case .authorized, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            lastError = "Location access was denied. Sunrise/sunset schedules can't be scheduled without it."
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        lastError = nil
        onLocation?(coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        lastError = "Couldn't get your location: \(error.localizedDescription)"
    }
}
