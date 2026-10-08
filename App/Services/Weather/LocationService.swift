import CoreLocation
import Foundation

enum LocationError: LocalizedError {
    case denied, unavailable, cityNotFound

    var errorDescription: String? {
        switch self {
        case .denied: "Location access is off. Allow it in Settings or set a city in Profile."
        case .unavailable: "Your location is not available right now."
        case .cityNotFound: "That city could not be found."
        }
    }
}

/// When-in-use location with async/await on top of CLLocationManager.
@MainActor
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?
    private var authorizationContinuation: CheckedContinuation<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }

    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    /// Shows the system prompt if needed and waits for the answer.
    func requestPermission() async {
        guard manager.authorizationStatus == .notDetermined else { return }
        await withCheckedContinuation { continuation in
            authorizationContinuation = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    func currentLocation() async throws -> CLLocation {
        await requestPermission()
        guard isAuthorized else { throw LocationError.denied }
        if let recent = manager.location, recent.timestamp.timeIntervalSinceNow > -900 { return recent }
        locationContinuation?.resume(throwing: LocationError.unavailable)
        return try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            manager.requestLocation()
        }
    }

    func location(forCity city: String) async throws -> CLLocation {
        let placemarks = try? await CLGeocoder().geocodeAddressString(city)
        guard let location = placemarks?.first?.location else { throw LocationError.cityNotFound }
        return location
    }

    func placeName(for location: CLLocation) async -> String {
        let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first
        return placemark?.locality ?? placemark?.administrativeArea ?? "Current location"
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard self.manager.authorizationStatus != .notDetermined else { return }
            self.authorizationContinuation?.resume()
            self.authorizationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last
        Task { @MainActor in
            if let location {
                self.locationContinuation?.resume(returning: location)
            } else {
                self.locationContinuation?.resume(throwing: LocationError.unavailable)
            }
            self.locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.locationContinuation?.resume(throwing: LocationError.unavailable)
            self.locationContinuation = nil
        }
    }
}
