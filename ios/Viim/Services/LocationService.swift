import CoreLocation
import Foundation

final class LocationService: NSObject, ObservableObject {
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
    }

    func requestAuthorization() {
        manager.requestAlwaysAuthorization()
    }
}

extension LocationService: CLLocationManagerDelegate {}
