import CoreLocation
import Foundation

enum LocationAuthorizationState: Equatable {
    case notDetermined
    case restricted
    case denied
    case authorizedWhenInUse
    case authorizedAlways

    init(status: CLAuthorizationStatus) {
        switch status {
        case .notDetermined:
            self = .notDetermined
        case .restricted:
            self = .restricted
        case .denied:
            self = .denied
        case .authorizedWhenInUse:
            self = .authorizedWhenInUse
        case .authorizedAlways:
            self = .authorizedAlways
        @unknown default:
            self = .restricted
        }
    }

    var canTrackLocation: Bool {
        self == .authorizedWhenInUse || self == .authorizedAlways
    }
}

enum TripDetectionPhase: Equatable {
    case idle
    case starting
    case active
    case stopping
}

struct LocationSample {
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let speedKmh: Double
    let horizontalAccuracy: CLLocationAccuracy

    init(location: CLLocation, speedKmh: Double) {
        self.timestamp = location.timestamp
        self.latitude = location.coordinate.latitude
        self.longitude = location.coordinate.longitude
        self.speedKmh = speedKmh
        self.horizontalAccuracy = location.horizontalAccuracy
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct ActiveDetectedTrip {
    let id: UUID
    let startedAt: Date
    var lastUpdatedAt: Date
    var distanceMeters: CLLocationDistance
    var sampleCount: Int
}

struct CompletedDetectedTrip {
    let id: UUID
    let startedAt: Date
    let endedAt: Date
    let distanceMeters: CLLocationDistance
    let sampleCount: Int

    var duration: TimeInterval {
        endedAt.timeIntervalSince(startedAt)
    }
}

final class LocationService: NSObject, ObservableObject {
    private enum Constants {
        static let normalAccuracyMeters: CLLocationAccuracy = 5
        static let economyAccuracyMeters: CLLocationAccuracy = 20
        static let normalDistanceFilterMeters: CLLocationDistance = 10
        static let economyDistanceFilterMeters: CLLocationDistance = 25
        static let maximumHorizontalAccuracyMeters: CLLocationAccuracy = 100
        static let maximumLocationAge: TimeInterval = 120
        static let startSpeedThresholdKmh = 10.0
        static let startSustainedDuration: TimeInterval = 30
        static let stopSpeedThresholdKmh = 3.0
        static let stopSustainedDuration: TimeInterval = 5 * 60
        static let candidateWindow: TimeInterval = 120
    }

    private let manager = CLLocationManager()
    private var shouldMonitorAfterAuthorization = false
    private var batterySavingMode = false
    private var vehicleType: VehicleType = .moto
    private var aboveStartSpeedSince: Date?
    private var belowStopSpeedSince: Date?
    private var candidateSamples: [LocationSample] = []
    private var lastAcceptedLocation: CLLocation?
    private var lastRouteLocation: CLLocation?

    @Published private(set) var authorizationState: LocationAuthorizationState = .notDetermined
    @Published private(set) var isMonitoring = false
    @Published private(set) var tripPhase: TripDetectionPhase = .idle
    @Published private(set) var currentSpeedKmh = 0.0
    @Published private(set) var latestLocation: CLLocation?
    @Published private(set) var activeTrip: ActiveDetectedTrip?
    @Published private(set) var lastCompletedTrip: CompletedDetectedTrip?
    @Published private(set) var routeSamples: [LocationSample] = []

    override init() {
        super.init()
        manager.delegate = self
        authorizationState = LocationAuthorizationState(status: manager.authorizationStatus)
        configureManager()
    }

    func configure(vehicleType: VehicleType) {
        self.vehicleType = vehicleType
        configureManager()
    }

    func setBatterySavingMode(_ isEnabled: Bool) {
        batterySavingMode = isEnabled
        configureManager()
    }

    func requestAuthorization() {
        switch authorizationState {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways, .denied, .restricted:
            break
        }
    }

    func prepareForForegroundUse() {
        shouldMonitorAfterAuthorization = false
        configureManager()
        requestAuthorization()
    }

    func startMonitoring() {
        shouldMonitorAfterAuthorization = true

        guard authorizationState.canTrackLocation else {
            isMonitoring = false
            requestAuthorization()
            return
        }

        configureManager()
        manager.startUpdatingLocation()
        if authorizationState == .authorizedAlways {
            manager.startMonitoringSignificantLocationChanges()
        }
        isMonitoring = true
    }

    func stopMonitoring() {
        shouldMonitorAfterAuthorization = false
        manager.stopUpdatingLocation()
        manager.stopMonitoringSignificantLocationChanges()
        isMonitoring = false
        resetDetectionState()
    }

    private func configureManager() {
        manager.allowsBackgroundLocationUpdates = authorizationState == .authorizedAlways
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = false
        manager.activityType = vehicleType == .velo ? .fitness : .automotiveNavigation
        manager.desiredAccuracy = batterySavingMode ? Constants.economyAccuracyMeters : Constants.normalAccuracyMeters
        manager.distanceFilter = batterySavingMode ? Constants.economyDistanceFilterMeters : Constants.normalDistanceFilterMeters
    }

    private func ingest(_ location: CLLocation) {
        guard isUsable(location) else {
            return
        }

        let speedKmh = resolvedSpeedKmh(for: location)
        let sample = LocationSample(location: location, speedKmh: speedKmh)
        latestLocation = location
        currentSpeedKmh = speedKmh
        updateTripDetection(with: sample, location: location)
        lastAcceptedLocation = location
    }

    private func isUsable(_ location: CLLocation) -> Bool {
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= Constants.maximumHorizontalAccuracyMeters else {
            return false
        }

        return abs(Date().timeIntervalSince(location.timestamp)) <= Constants.maximumLocationAge
    }

    private func resolvedSpeedKmh(for location: CLLocation) -> Double {
        if location.speed >= 0 {
            return location.speed * 3.6
        }

        guard let previousLocation = lastAcceptedLocation else {
            return 0
        }

        let elapsed = location.timestamp.timeIntervalSince(previousLocation.timestamp)
        guard elapsed > 0, elapsed <= Constants.maximumLocationAge else {
            return 0
        }

        return max(0, previousLocation.distance(from: location) / elapsed * 3.6)
    }

    private func updateTripDetection(with sample: LocationSample, location: CLLocation) {
        if activeTrip != nil {
            appendActiveSample(sample, location: location)
            updateActiveTripStopDetection(with: sample)
            return
        }

        guard sample.speedKmh >= Constants.startSpeedThresholdKmh else {
            resetStartCandidate()
            tripPhase = .idle
            return
        }

        if aboveStartSpeedSince == nil {
            aboveStartSpeedSince = sample.timestamp
            candidateSamples = [sample]
            tripPhase = .starting
            return
        }

        candidateSamples.append(sample)
        trimCandidateSamples(now: sample.timestamp)

        guard let startDate = aboveStartSpeedSince else {
            return
        }

        if sample.timestamp.timeIntervalSince(startDate) >= Constants.startSustainedDuration {
            beginTrip(startedAt: startDate, currentLocation: location)
        } else {
            tripPhase = .starting
        }
    }

    private func updateActiveTripStopDetection(with sample: LocationSample) {
        guard sample.speedKmh <= Constants.stopSpeedThresholdKmh else {
            belowStopSpeedSince = nil
            tripPhase = .active
            return
        }

        if belowStopSpeedSince == nil {
            belowStopSpeedSince = sample.timestamp
            tripPhase = .stopping
            return
        }

        guard let stopStartDate = belowStopSpeedSince else {
            return
        }

        if sample.timestamp.timeIntervalSince(stopStartDate) >= Constants.stopSustainedDuration {
            endTrip(endedAt: sample.timestamp)
        } else {
            tripPhase = .stopping
        }
    }

    private func beginTrip(startedAt: Date, currentLocation: CLLocation) {
        let distanceMeters = Self.distanceMeters(in: candidateSamples)
        let trip = ActiveDetectedTrip(
            id: UUID(),
            startedAt: startedAt,
            lastUpdatedAt: currentLocation.timestamp,
            distanceMeters: distanceMeters,
            sampleCount: candidateSamples.count
        )

        routeSamples = candidateSamples
        activeTrip = trip
        lastRouteLocation = currentLocation
        resetStartCandidate()
        belowStopSpeedSince = nil
        tripPhase = .active
    }

    private func appendActiveSample(_ sample: LocationSample, location: CLLocation) {
        routeSamples.append(sample)

        var distanceDelta: CLLocationDistance = 0
        if let lastRouteLocation {
            distanceDelta = lastRouteLocation.distance(from: location)
        }
        lastRouteLocation = location

        guard var activeTrip else {
            return
        }

        activeTrip.distanceMeters += max(0, distanceDelta)
        activeTrip.lastUpdatedAt = sample.timestamp
        activeTrip.sampleCount = routeSamples.count
        self.activeTrip = activeTrip
    }

    private func endTrip(endedAt: Date) {
        guard let activeTrip else {
            return
        }

        lastCompletedTrip = CompletedDetectedTrip(
            id: activeTrip.id,
            startedAt: activeTrip.startedAt,
            endedAt: endedAt,
            distanceMeters: activeTrip.distanceMeters,
            sampleCount: activeTrip.sampleCount
        )

        self.activeTrip = nil
        lastRouteLocation = nil
        belowStopSpeedSince = nil
        tripPhase = .idle
    }

    private func trimCandidateSamples(now: Date) {
        candidateSamples.removeAll { sample in
            now.timeIntervalSince(sample.timestamp) > Constants.candidateWindow
        }
    }

    private func resetStartCandidate() {
        aboveStartSpeedSince = nil
        candidateSamples.removeAll(keepingCapacity: true)
    }

    private func resetDetectionState() {
        activeTrip = nil
        lastRouteLocation = nil
        resetStartCandidate()
        belowStopSpeedSince = nil
        tripPhase = .idle
    }

    private static func distanceMeters(in samples: [LocationSample]) -> CLLocationDistance {
        guard samples.count > 1 else {
            return 0
        }

        return zip(samples, samples.dropFirst()).reduce(0) { partialResult, pair in
            let previous = CLLocation(latitude: pair.0.latitude, longitude: pair.0.longitude)
            let current = CLLocation(latitude: pair.1.latitude, longitude: pair.1.longitude)
            return partialResult + previous.distance(from: current)
        }
    }
}

extension LocationService: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationState = LocationAuthorizationState(status: manager.authorizationStatus)
        configureManager()

        if shouldMonitorAfterAuthorization, authorizationState.canTrackLocation {
            startMonitoring()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        locations.forEach(ingest)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if (error as? CLError)?.code == .denied {
            authorizationState = .denied
            isMonitoring = false
        }
    }
}
