import CoreLocation
import Foundation

protocol LocationManaging: AnyObject {
    var delegate: CLLocationManagerDelegate? { get set }
    var authorizationStatus: CLAuthorizationStatus { get }
    var allowsBackgroundLocationUpdates: Bool { get set }
    var pausesLocationUpdatesAutomatically: Bool { get set }
    var showsBackgroundLocationIndicator: Bool { get set }
    var activityType: CLActivityType { get set }
    var desiredAccuracy: CLLocationAccuracy { get set }
    var distanceFilter: CLLocationDistance { get set }

    func requestWhenInUseAuthorization()
    func requestAlwaysAuthorization()
    func requestLocation()
    func startUpdatingLocation()
    func stopUpdatingLocation()
    func startMonitoringSignificantLocationChanges()
    func stopMonitoringSignificantLocationChanges()
    func startMonitoring(for region: CLRegion)
    func stopMonitoring(for region: CLRegion)
}

extension CLLocationManager: LocationManaging {}

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
    let receivedAt: Date
    let latitude: Double
    let longitude: Double
    let speedKmh: Double
    let horizontalAccuracy: CLLocationAccuracy
    let speedAccuracy: CLLocationSpeedAccuracy

    init(
        timestamp: Date,
        latitude: Double,
        longitude: Double,
        speedKmh: Double,
        horizontalAccuracy: CLLocationAccuracy,
        speedAccuracy: CLLocationSpeedAccuracy = 1,
        receivedAt: Date? = nil
    ) {
        self.timestamp = timestamp
        self.receivedAt = receivedAt ?? timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.speedKmh = speedKmh
        self.horizontalAccuracy = horizontalAccuracy
        self.speedAccuracy = speedAccuracy
    }

    init(location: CLLocation, speedKmh: Double, receivedAt: Date = Date()) {
        self.timestamp = location.timestamp
        self.receivedAt = receivedAt
        self.latitude = location.coordinate.latitude
        self.longitude = location.coordinate.longitude
        self.speedKmh = speedKmh
        self.horizontalAccuracy = location.horizontalAccuracy
        self.speedAccuracy = location.speedAccuracy
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct ActiveDetectedTrip {
    let id: UUID
    let startedAt: Date
    var lastUpdatedAt: Date
    var lastMovingAt: Date
    var distanceMeters: CLLocationDistance
    var sampleCount: Int
}

struct CompletedDetectedTrip {
    let id: UUID
    let startedAt: Date
    let endedAt: Date
    let distanceMeters: CLLocationDistance
    let sampleCount: Int
    let observedDuration: TimeInterval

    init(
        id: UUID,
        startedAt: Date,
        endedAt: Date,
        distanceMeters: CLLocationDistance,
        sampleCount: Int,
        observedDuration: TimeInterval? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.distanceMeters = distanceMeters
        self.sampleCount = sampleCount
        self.observedDuration = max(0, observedDuration ?? endedAt.timeIntervalSince(startedAt))
    }

    var duration: TimeInterval {
        max(endedAt.timeIntervalSince(startedAt), observedDuration)
    }
}

final class LocationService: NSObject, ObservableObject {
    private enum Constants {
        static let normalAccuracyMeters: CLLocationAccuracy = 5
        static let economyAccuracyMeters: CLLocationAccuracy = 20
        static let normalDistanceFilterMeters: CLLocationDistance = 10
        static let economyDistanceFilterMeters: CLLocationDistance = 25
        static let maximumHorizontalAccuracyMeters: CLLocationAccuracy = 100
        // Core Location peut relivrer une rafale mise en file apres une
        // suspension. Deux minutes supprimait silencieusement ces points alors
        // que la fenetre de capture durable est de quinze minutes.
        static let maximumLocationAge: TimeInterval = 15 * 60
        static let startSpeedThresholdKmh = 10.0
        static let minimumFastStartDuration: TimeInterval = 5
        static let minimumFastStartReliableSpeedSamples = 2
        static let minimumDerivedSpeedInterval: TimeInterval = 2
        static let startSustainedDuration: TimeInterval = 30
        static let stopSpeedThresholdKmh = 3.0
        static let stopSustainedDuration: TimeInterval = 5 * 60
        static let candidateWindow: TimeInterval = 15 * 60
        static let minimumStartCandidateDistanceMeters: CLLocationDistance = 60
        static let minimumSparseStartCandidateDistanceMeters: CLLocationDistance = 250
        static let minimumSparseStartCandidateDuration: TimeInterval = 60
        static let minimumStartCandidateSamples = 3
        static let minimumPersistedTripDistanceMeters = TripReliabilityRules.minimumPersistedTripDistanceMeters
        static let minimumPersistedTripDuration = TripReliabilityRules.minimumPersistedTripDuration
        static let passiveWakeupDistanceThresholdMeters: CLLocationDistance = 250
        static let passiveWakeupMaximumAge: TimeInterval = 300
        static let idleMonitoringTimeout: TimeInterval = 180
        static let hardInactivityGap: TimeInterval = 30 * 60
        // La sortie de zone reveille une app terminee des ~150-200 m, la ou le
        // changement significatif peut attendre plusieurs kilometres : c'est ce
        // retard qui a ampute le debut du trajet du 18 juillet au soir.
        static let departureRegionRadiusMeters: CLLocationDistance = 150
        static let departureRegionIdentifier = "viim.departure"
    }

    private let manager: LocationManaging
    private let backgroundActivitySessionFactory: () -> Any?
    private let alwaysServiceSessionFactory: () -> Any?
    private var shouldMonitorAfterAuthorization = false
    private var shouldRequestCurrentLocationAfterAuthorization = false
    private var batterySavingMode = false
    private var vehicleType: VehicleType = .moto
    private var aboveStartSpeedSince: Date?
    private var belowStopSpeedSince: Date?
    private var candidateSamples: [LocationSample] = []
    private var candidateTripID: UUID?
    private var lastAcceptedLocation: CLLocation?
    private var lastRouteLocation: CLLocation?
    private var lastReceivedLocation: CLLocation?
    private var lastMovementEvidenceAt: Date?
    private var monitoringStartedAt: Date?
    private var idleStopWorkItem: DispatchWorkItem?
    // CLBackgroundActivitySession (iOS 17+), stocke en Any pour la cible iOS 16.
    // La session doit etre ouverte au premier plan puis conservee pendant les
    // reveils passifs. Apple autorise seulement la reprise d'une session deja
    // existante depuis l'arriere-plan. La recreer apres le reveil significatif
    // laisse les points a la cadence passive (~5 min) et fait expirer l'armement.
    // Consequence (trajets tronques du 18 juillet) : en Always, la session doit
    // rester active meme pendant l'idle — elle doit exister au moment ou iOS
    // termine le processus pour que sa recreation immediate au relancement
    // retablisse la cadence GPS continue. Ne l'invalider que si le suivi
    // automatique est desactive ou l'autorisation perdue.
    private var backgroundActivitySession: Any?
    private var departureRegion: CLCircularRegion?
    // Depuis iOS 18, Apple demande de conserver cette session explicite pour
    // exploiter l'autorisation Always et de la recreer immediatement lors
    // d'une relance en arriere-plan. Contrairement a
    // CLBackgroundActivitySession, elle n'affiche pas la pastille bleue.
    private var alwaysServiceSession: Any?
    private let activeTripJournal: ActiveTripJournal?

    @Published private(set) var authorizationState: LocationAuthorizationState = .notDetermined
    @Published private(set) var isMonitoring = false
    @Published private(set) var isPassiveWakeupMonitoring = false
    @Published private(set) var tripPhase: TripDetectionPhase = .idle
    @Published private(set) var currentSpeedKmh = 0.0
    @Published private(set) var latestLocation: CLLocation?
    @Published private(set) var activeTrip: ActiveDetectedTrip?
    @Published private(set) var lastCompletedTrip: CompletedDetectedTrip?
    @Published private(set) var routeSamples: [LocationSample] = []

    var hasBackgroundActivitySession: Bool {
        backgroundActivitySession != nil
    }

    var hasAlwaysServiceSession: Bool {
        alwaysServiceSession != nil
    }

    init(
        activeTripJournal: ActiveTripJournal? = nil,
        manager: LocationManaging = CLLocationManager(),
        backgroundActivitySessionFactory: @escaping () -> Any? = {
            if #available(iOS 17.0, *) {
                return CLBackgroundActivitySession()
            }
            return nil
        },
        alwaysServiceSessionFactory: @escaping () -> Any? = {
            if #available(iOS 18.0, *) {
                return CLServiceSession(authorization: .always)
            }
            return nil
        }
    ) {
        self.activeTripJournal = activeTripJournal
        self.manager = manager
        self.backgroundActivitySessionFactory = backgroundActivitySessionFactory
        self.alwaysServiceSessionFactory = alwaysServiceSessionFactory
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

    func requestBackgroundAuthorization() {
        switch authorizationState {
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .denied, .restricted:
            break
        }
    }

    func requestCurrentLocation() {
        guard authorizationState.canTrackLocation else {
            shouldRequestCurrentLocationAfterAuthorization = true
            requestAuthorization()
            return
        }

        shouldRequestCurrentLocationAfterAuthorization = false
        configureManager()
        ViimDiagnostics.log("location.requestCurrent state=\(authorizationState)")
        manager.requestLocation()
    }

    func prepareForForegroundUse() {
        finishInactiveActiveTripIfNeeded()
        shouldMonitorAfterAuthorization = false
        configureManager()
        requestAuthorization()
        beginAlwaysServiceSessionIfNeeded()
        beginBackgroundActivitySessionIfNeeded(requiringAlways: true)
        startPassiveWakeupMonitoringIfAllowed()
    }

    /// Restaure les attentes de collecte sans dependre de la creation d'une
    /// vue. Cette methode est appelee au lancement, y compris lorsque Core
    /// Location relance Viim en arriere-plan apres une terminaison systeme.
    /// Les deux sessions doivent etre recreees ICI, avant le premier callback
    /// de localisation, sinon iOS garde la cadence passive (~5 min) jusqu'au
    /// prochain passage au premier plan.
    func restoreAutomaticTrackingSession() {
        configureManager()
        beginAlwaysServiceSessionIfNeeded()
        beginBackgroundActivitySessionIfNeeded(requiringAlways: true)
        startPassiveWakeupMonitoringIfAllowed()
        ViimDiagnostics.log("location.automaticSession.restored state=\(authorizationState)")
    }

    func startMonitoring() {
        shouldMonitorAfterAuthorization = true

        guard authorizationState.canTrackLocation else {
            isMonitoring = false
            ViimDiagnostics.log("location.start.requestAuthorization state=\(authorizationState)")
            requestAuthorization()
            return
        }

        guard !isMonitoring else {
            return
        }

        configureManager()
        beginBackgroundActivitySessionIfNeeded()
        stopDepartureRegionMonitoring()
        // Conserver le service de changements significatifs pendant la
        // collecte standard. Les logs terrain du 14 juillet prouvent que les
        // demarrages declenches par CoreMotion peuvent etre suspendus avant le
        // premier callback GPS. Ce service est alors le seul mecanisme iOS qui
        // relance l'app et evite qu'un trajet disparaisse sans aucun sample.
        manager.startUpdatingLocation()
        isMonitoring = true
        monitoringStartedAt = Date()
        scheduleIdleMonitoringFailsafe()
        ViimDiagnostics.log("location.start active authorization=\(authorizationState)")
    }

    func stopMonitoring(keepPassiveWakeups: Bool = true) {
        shouldMonitorAfterAuthorization = false
        idleStopWorkItem?.cancel()
        idleStopWorkItem = nil
        manager.stopUpdatingLocation()
        isMonitoring = false
        monitoringStartedAt = nil
        ViimDiagnostics.log("location.stop phase=\(tripPhase)")
        if activeTrip != nil {
            endTripAtLastMovingSample()
        } else {
            resetDetectionState()
        }

        if keepPassiveWakeups {
            startPassiveWakeupMonitoringIfAllowed()
            startDepartureRegionMonitoringIfAllowed()
            // En Always, conserver la session d'activite pendant l'idle : elle
            // doit etre vivante a la terminaison du processus pour que le
            // prochain reveil en arriere-plan retrouve la cadence GPS continue.
            if authorizationState != .authorizedAlways {
                endBackgroundActivitySession()
            }
        } else {
            stopPassiveWakeupMonitoring()
            stopDepartureRegionMonitoring()
            endAlwaysServiceSession()
            endBackgroundActivitySession()
        }
    }

    func finishActiveTripAfterStationaryMotion() {
        guard let activeTrip else {
            return
        }

        let endedAt = Self.endDateForStationaryFinalization(activeTrip: activeTrip)
        let duration = endedAt.timeIntervalSince(activeTrip.startedAt)
        guard Self.shouldPersistTripAfterStationaryMotion(distanceMeters: activeTrip.distanceMeters, duration: duration) else {
            ViimDiagnostics.log("trip.finish.motionStop shortClosed distanceMeters=\(Int(activeTrip.distanceMeters)) durationSec=\(Int(duration))")
            endTrip(endedAt: endedAt)
            return
        }

        ViimDiagnostics.log("trip.finish.motionStop distanceMeters=\(Int(activeTrip.distanceMeters)) durationSec=\(Int(duration))")
        endTrip(endedAt: endedAt)
    }

    static func shouldPersistTripAfterStationaryMotion(
        distanceMeters: CLLocationDistance,
        duration: TimeInterval
    ) -> Bool {
        distanceMeters >= Constants.minimumPersistedTripDistanceMeters &&
            duration >= Constants.minimumPersistedTripDuration
    }

    static func endDateForStationaryFinalization(activeTrip: ActiveDetectedTrip) -> Date {
        activeTrip.lastMovingAt
    }

    static func shouldFinalizeInactiveTrip(activeTrip: ActiveDetectedTrip, now: Date) -> Bool {
        now.timeIntervalSince(activeTrip.lastUpdatedAt) >= Constants.stopSustainedDuration
    }

    /// Core Motion peut rester en mode "automotive" lorsque le telephone ne
    /// bouge plus. Apres cinq minutes sans aucune preuve GPS de mouvement, le
    /// GPS devient la source d'autorite pour terminer le trajet.
    static func shouldFinalizeDespiteMotionMovement(
        hasActiveTrip: Bool,
        currentSpeedKmh: Double,
        lastMovementEvidenceAt: Date?,
        now: Date
    ) -> Bool {
        guard hasActiveTrip,
              currentSpeedKmh <= Constants.stopSpeedThresholdKmh,
              let lastMovementEvidenceAt else {
            return false
        }
        return now.timeIntervalSince(lastMovementEvidenceAt) >= Constants.stopSustainedDuration
    }

    var shouldFinalizeDespiteMotionMovement: Bool {
        Self.shouldFinalizeDespiteMotionMovement(
            hasActiveTrip: activeTrip != nil,
            currentSpeedKmh: currentSpeedKmh,
            lastMovementEvidenceAt: lastMovementEvidenceAt,
            now: Date()
        )
    }

    static func shouldBeginTripFromCandidateSamples(
        _ samples: [LocationSample],
        vehicleType: VehicleType
    ) -> Bool {
        let validSamples = TripMetricsCalculator.validRouteSamples(from: samples)
        guard let firstTimestamp = validSamples.first?.timestamp,
              let lastTimestamp = validSamples.last?.timestamp,
              validSamples.count >= TripReliabilityRules.minimumValidRoutePoints else {
            return false
        }

        // Meme regle que distanceMetric : un segment aberrant est saute, il
        // n'annule plus le demarrage du trajet entier.
        let analysis = TripMetricsCalculator.distanceAnalysis(
            samples: validSamples,
            vehicleType: vehicleType
        )
        let elapsed = lastTimestamp.timeIntervalSince(firstTimestamp)

        // Les traces reelles du 15 juillet montrent des rafales coherentes de
        // 3 points sur 9-10 s avant suspension iOS. Une telle rafale est une
        // preuve de conduite suffisante si la distance ET au moins deux
        // vitesses GPS fiables concordent. La passer immediatement en trajet
        // actif garantit que le journal durable survivra au prochain reveil.
        let reliableDrivingSpeedCount = validSamples.filter { sample in
            TripReliabilityRules.hasReliableMovementSpeed(sample) &&
                sample.speedKmh >= Constants.startSpeedThresholdKmh
        }.count
        if validSamples.count >= Constants.minimumStartCandidateSamples,
           elapsed >= Constants.minimumFastStartDuration,
           analysis.distanceMeters >= Constants.minimumStartCandidateDistanceMeters,
           reliableDrivingSpeedCount >= Constants.minimumFastStartReliableSpeedSamples {
            return true
        }

        if validSamples.count >= Constants.minimumStartCandidateSamples,
           elapsed >= Constants.startSustainedDuration,
           analysis.distanceMeters >= Constants.minimumStartCandidateDistanceMeters {
            return true
        }

        // En arriere-plan, iOS peut ne reveiller l'app que par changements
        // significatifs, environ toutes les quelques minutes. Deux points
        // precis, separes dans le temps et dans l'espace, prouvent mieux un
        // vrai trajet qu'une exigence de 3 points denses impossible a obtenir.
        return elapsed >= Constants.minimumSparseStartCandidateDuration &&
            analysis.distanceMeters >= Constants.minimumSparseStartCandidateDistanceMeters
    }

    static func shouldFinalizeInactiveTripBeforeIngest(
        activeTrip: ActiveDetectedTrip,
        incomingSample: LocationSample
    ) -> Bool {
        let gap = incomingSample.timestamp.timeIntervalSince(activeTrip.lastUpdatedAt)

        // Plafond dur : au-dela de ce silence, le point entrant appartient a
        // un autre trajet, meme s'il est rapide (voiture garee 2 h puis
        // nouveau depart). Sans cela, deux trajets fusionneraient.
        if gap >= Constants.hardInactivityGap {
            return true
        }

        return gap >= Constants.stopSustainedDuration &&
            incomingSample.speedKmh <= Constants.stopSpeedThresholdKmh
    }

    private func configureManager() {
        // L'arriere-plan sans indicateur visible exige l'autorisation Always.
        // En When In Use, Viim suit uniquement tant que l'app est utilisee.
        manager.allowsBackgroundLocationUpdates = authorizationState == .authorizedAlways
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = false
        manager.activityType = vehicleType == .velo ? .fitness : .automotiveNavigation
        manager.desiredAccuracy = batterySavingMode ? Constants.economyAccuracyMeters : Constants.normalAccuracyMeters
        manager.distanceFilter = batterySavingMode ? Constants.economyDistanceFilterMeters : Constants.normalDistanceFilterMeters
    }

    /// `requiringAlways` reserve la creation aux autorisations Always : au
    /// lancement et pendant l'idle, un utilisateur When In Use ne doit pas
    /// porter l'indicateur de localisation en permanence.
    private func beginBackgroundActivitySessionIfNeeded(requiringAlways: Bool = false) {
        guard #available(iOS 17.0, *) else {
            return
        }
        if requiringAlways, authorizationState != .authorizedAlways {
            return
        }
        guard backgroundActivitySession == nil,
              authorizationState.canTrackLocation else {
            return
        }

        backgroundActivitySession = backgroundActivitySessionFactory()
        if backgroundActivitySession != nil {
            ViimDiagnostics.log("location.backgroundSession.start authorization=\(authorizationState)")
        }
    }

    private func beginAlwaysServiceSessionIfNeeded() {
        guard #available(iOS 18.0, *),
              alwaysServiceSession == nil,
              authorizationState == .authorizedAlways else {
            return
        }

        alwaysServiceSession = alwaysServiceSessionFactory()
        if alwaysServiceSession != nil {
            ViimDiagnostics.log("location.alwaysServiceSession.start")
        }
    }

    private func endAlwaysServiceSession() {
        guard #available(iOS 18.0, *) else {
            alwaysServiceSession = nil
            return
        }

        if let session = alwaysServiceSession as? CLServiceSession {
            session.invalidate()
        }
        alwaysServiceSession = nil
        ViimDiagnostics.log("location.alwaysServiceSession.end")
    }

    private func endBackgroundActivitySession() {
        guard #available(iOS 17.0, *),
              let session = backgroundActivitySession as? CLBackgroundActivitySession else {
            backgroundActivitySession = nil
            return
        }

        session.invalidate()
        backgroundActivitySession = nil
        ViimDiagnostics.log("location.backgroundSession.end")
    }

    /// Vrai si un point recu (meme trop imprecis pour la route) prouve un
    /// deplacement reel : vitesse GPS au-dessus du seuil de demarrage, ou
    /// deplacement superieur a la marge d'imprecision des deux points.
    static func isMovementEvidence(
        previous: CLLocation?,
        current: CLLocation,
        now: Date
    ) -> Bool {
        guard current.horizontalAccuracy >= 0,
              abs(now.timeIntervalSince(current.timestamp)) <= Constants.passiveWakeupMaximumAge else {
            return false
        }

        if Self.hasReliableReportedSpeed(current),
           current.speed * 3.6 >= Constants.startSpeedThresholdKmh {
            return true
        }

        guard let previous else {
            return false
        }

        let displacement = current.distance(from: previous)
        let accuracyMargin = max(current.horizontalAccuracy, max(previous.horizontalAccuracy, 0))
        return displacement >= max(Constants.passiveWakeupDistanceThresholdMeters, accuracyMargin)
    }

    static func shouldDeferIdleStop(lastMovementEvidenceAt: Date?, now: Date) -> Bool {
        guard let lastMovementEvidenceAt else {
            return false
        }
        return now.timeIntervalSince(lastMovementEvidenceAt) < Constants.idleMonitoringTimeout
    }

    static func isCandidateExpired(lastUpdatedAt: Date, now: Date) -> Bool {
        now.timeIntervalSince(lastUpdatedAt) >= Constants.candidateWindow
    }

    static func shouldDeferCandidateTimeout(lastUpdatedAt: Date?, now: Date) -> Bool {
        guard let lastUpdatedAt else {
            return false
        }
        return !isCandidateExpired(lastUpdatedAt: lastUpdatedAt, now: now)
    }

    static func shouldDeferStationaryStop(
        monitoringStartedAt: Date?,
        lastMovementEvidenceAt: Date?,
        now: Date
    ) -> Bool {
        if let monitoringStartedAt,
           now.timeIntervalSince(monitoringStartedAt) < Constants.idleMonitoringTimeout {
            return true
        }
        return shouldDeferIdleStop(lastMovementEvidenceAt: lastMovementEvidenceAt, now: now)
    }

    var shouldDeferStationaryStop: Bool {
        Self.shouldDeferStationaryStop(
            monitoringStartedAt: monitoringStartedAt,
            lastMovementEvidenceAt: lastMovementEvidenceAt,
            now: Date()
        )
    }

    private func registerMovementEvidence(_ location: CLLocation) {
        if Self.isMovementEvidence(previous: lastReceivedLocation, current: location, now: Date()) {
            lastMovementEvidenceAt = Date()
        }
        lastReceivedLocation = location
    }

    private func scheduleIdleMonitoringFailsafe() {
        idleStopWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isMonitoring else {
                return
            }

            if self.activeTrip != nil || self.tripPhase == .stopping {
                self.scheduleIdleMonitoringFailsafe()
                return
            }

            if self.tripPhase == .starting {
                let now = Date()
                let lastCandidateUpdate = self.candidateSamples.last?.timestamp
                if Self.shouldDeferCandidateTimeout(lastUpdatedAt: lastCandidateUpdate, now: now) {
                    ViimDiagnostics.log("location.idleFailsafe.deferred candidate=durable")
                    self.scheduleIdleMonitoringFailsafe()
                    return
                }
                self.resetStartCandidate(outcomeReason: "armingTimeout")
                ViimDiagnostics.log("location.idleFailsafe.stop phase=starting")
                self.stopMonitoring()
                return
            }

            // Un deplacement recent prouve par n'importe quel point recu (meme
            // imprecis) signifie que l'utilisateur roule probablement : ne pas
            // couper le GPS en plein trajet quand iOS livre les points au
            // compte-gouttes.
            if Self.shouldDeferIdleStop(lastMovementEvidenceAt: self.lastMovementEvidenceAt, now: Date()) {
                ViimDiagnostics.log("location.idleFailsafe.deferred movementEvidence=recent")
                self.scheduleIdleMonitoringFailsafe()
                return
            }

            ViimDiagnostics.log("location.idleFailsafe.stop phase=\(self.tripPhase)")
            self.stopMonitoring()
        }

        idleStopWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Constants.idleMonitoringTimeout,
            execute: workItem
        )
    }

    private func startPassiveWakeupMonitoringIfAllowed() {
        guard authorizationState == .authorizedAlways else {
            isPassiveWakeupMonitoring = false
            return
        }

        guard !isPassiveWakeupMonitoring else {
            return
        }

        manager.startMonitoringSignificantLocationChanges()
        isPassiveWakeupMonitoring = true
        ViimDiagnostics.log("location.passiveWakeups.start")
    }

    private func stopPassiveWakeupMonitoring() {
        guard isPassiveWakeupMonitoring else {
            return
        }

        manager.stopMonitoringSignificantLocationChanges()
        isPassiveWakeupMonitoring = false
        ViimDiagnostics.log("location.passiveWakeups.stop")
    }

    /// Arme une geofence de sortie autour du dernier point connu quand le GPS
    /// se coupe a l'idle. La sortie de zone relance l'app (meme terminee) des
    /// les premieres centaines de metres du prochain trajet, bien avant le
    /// changement significatif de cellule.
    private func startDepartureRegionMonitoringIfAllowed() {
        guard authorizationState == .authorizedAlways,
              let center = (lastReceivedLocation ?? lastAcceptedLocation)?.coordinate else {
            return
        }

        stopDepartureRegionMonitoring()
        let region = CLCircularRegion(
            center: center,
            radius: Constants.departureRegionRadiusMeters,
            identifier: Constants.departureRegionIdentifier
        )
        region.notifyOnExit = true
        region.notifyOnEntry = false
        manager.startMonitoring(for: region)
        departureRegion = region
        ViimDiagnostics.log("location.departureRegion.start radius=\(Int(Constants.departureRegionRadiusMeters))")
    }

    private func stopDepartureRegionMonitoring() {
        guard let departureRegion else {
            return
        }

        manager.stopMonitoring(for: departureRegion)
        self.departureRegion = nil
        ViimDiagnostics.log("location.departureRegion.stop")
    }

    private func shouldPromotePassiveWakeupToContinuousMonitoring(_ locations: [CLLocation]) -> Bool {
        Self.shouldPromotePassiveWakeup(
            locations: locations,
            lastKnownLocation: lastAcceptedLocation,
            now: Date()
        )
    }

    static func shouldPromotePassiveWakeup(
        locations: [CLLocation],
        lastKnownLocation: CLLocation?,
        now: Date
    ) -> Bool {
        for location in locations {
            guard location.horizontalAccuracy >= 0,
                  abs(now.timeIntervalSince(location.timestamp)) <= Constants.passiveWakeupMaximumAge else {
                continue
            }

            if Self.hasReliableReportedSpeed(location),
               location.speed * 3.6 >= Constants.startSpeedThresholdKmh {
                return true
            }

            guard let lastKnownLocation else {
                // Relance a froid : aucune position de reference en memoire. Le reveil
                // par changement significatif implique deja un deplacement (~500 m),
                // donc on promeut et on laisse le failsafe d'inactivite couper le GPS
                // si aucun trajet ne demarre.
                return true
            }

            let displacement = location.distance(from: lastKnownLocation)
            let accuracyMargin = max(location.horizontalAccuracy, Constants.maximumHorizontalAccuracyMeters)
            if displacement >= max(Constants.passiveWakeupDistanceThresholdMeters, accuracyMargin) {
                return true
            }
        }

        return false
    }

    private func ingest(_ location: CLLocation) {
        guard isUsable(location) else {
            return
        }

        let speedKmh = resolvedSpeedKmh(for: location)
        let sample = LocationSample(location: location, speedKmh: speedKmh)

        if let activeTrip,
           Self.shouldFinalizeInactiveTripBeforeIngest(activeTrip: activeTrip, incomingSample: sample) {
            ViimDiagnostics.log("trip.finish.inactive distanceMeters=\(Int(activeTrip.distanceMeters)) samples=\(activeTrip.sampleCount)")
            endTrip(endedAt: Self.endDateForStationaryFinalization(activeTrip: activeTrip))
        }

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

    static func hasReliableReportedSpeed(_ location: CLLocation) -> Bool {
        location.speed >= 0 &&
            TripReliabilityRules.isValidSpeedAccuracy(location.horizontalAccuracy) &&
            TripReliabilityRules.isValidReportedSpeedAccuracy(location.speedAccuracy)
    }

    static func resolvedSpeedKmh(
        for location: CLLocation,
        previousLocation: CLLocation?,
        vehicleType: VehicleType
    ) -> Double {
        if hasReliableReportedSpeed(location) {
            let reportedSpeedKmh = location.speed * 3.6
            guard reportedSpeedKmh.isFinite,
                  reportedSpeedKmh <= TripReliabilityRules.maximumReasonableSpeedKmh(for: vehicleType) else {
                return 0
            }
            return reportedSpeedKmh
        }

        guard let previousLocation else {
            return 0
        }

        let elapsed = location.timestamp.timeIntervalSince(previousLocation.timestamp)
        guard elapsed >= Constants.minimumDerivedSpeedInterval,
              elapsed <= Constants.maximumLocationAge else {
            return 0
        }

        let displacement = previousLocation.distance(from: location)
        let uncertainty = max(0, previousLocation.horizontalAccuracy) + max(0, location.horizontalAccuracy)
        guard displacement > uncertainty else {
            return 0
        }

        let derivedSpeedKmh = displacement / elapsed * 3.6
        guard derivedSpeedKmh.isFinite,
              derivedSpeedKmh <= TripReliabilityRules.maximumReasonableSpeedKmh(for: vehicleType) else {
            return 0
        }
        return max(0, derivedSpeedKmh)
    }

    private func resolvedSpeedKmh(for location: CLLocation) -> Double {
        Self.resolvedSpeedKmh(
            for: location,
            previousLocation: lastAcceptedLocation,
            vehicleType: vehicleType
        )
    }

    private func updateTripDetection(with sample: LocationSample, location: CLLocation) {
        if activeTrip != nil {
            appendActiveSample(sample, location: location)
            updateActiveTripStopDetection(with: sample)
            return
        }

        guard sample.speedKmh >= Constants.startSpeedThresholdKmh else {
            guard candidateTripID != nil else {
                tripPhase = .idle
                return
            }

            // Un point lent isole (feu rouge, vitesse GPS momentanement nulle)
            // ne doit pas effacer une tentative deja prouvee par un point en
            // mouvement. Le failsafe d'armement fermera la tentative si le
            // calme se confirme.
            candidateSamples.append(sample)
            trimCandidateSamples(now: sample.timestamp)
            journalCandidateSamples()
            evaluateStartCandidate(currentSample: sample, location: location)
            if activeTrip == nil {
                tripPhase = .starting
            }
            return
        }

        if aboveStartSpeedSince == nil {
            aboveStartSpeedSince = sample.timestamp
            candidateSamples = [sample]
            candidateTripID = UUID()
            journalCandidateSamples()
            if let candidateTripID {
                ViimDiagnostics.log("trip.capture.start id=\(candidateTripID.uuidString) source=location")
            }
            tripPhase = .starting
            return
        }

        candidateSamples.append(sample)
        trimCandidateSamples(now: sample.timestamp)
        journalCandidateSamples()
        evaluateStartCandidate(currentSample: sample, location: location)
        if activeTrip == nil {
            tripPhase = .starting
        }
    }

    private func evaluateStartCandidate(currentSample sample: LocationSample, location: CLLocation) {
        guard let startDate = aboveStartSpeedSince else {
            return
        }

        guard Self.shouldBeginTripFromCandidateSamples(candidateSamples, vehicleType: vehicleType) else {
            // Une tentative sparse reste ouverte pendant sa fenetre : iOS peut
            // livrer le second point plusieurs minutes apres le premier.
            if sample.timestamp.timeIntervalSince(startDate) < Constants.candidateWindow {
                return
            }
            ViimDiagnostics.log("trip.begin.candidateRejected samples=\(candidateSamples.count)")
            resetStartCandidate(outcomeReason: "candidateRejected")
            tripPhase = .idle
            return
        }
        beginTrip(startedAt: startDate, currentLocation: location)
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
            endTripAtLastMovingSample()
        } else {
            tripPhase = .stopping
        }
    }

    private func beginTrip(startedAt: Date, currentLocation: CLLocation) {
        let distanceMeters = distanceMeters(in: candidateSamples)
        let trip = ActiveDetectedTrip(
            id: candidateTripID ?? UUID(),
            startedAt: startedAt,
            lastUpdatedAt: currentLocation.timestamp,
            lastMovingAt: currentLocation.timestamp,
            distanceMeters: distanceMeters,
            sampleCount: candidateSamples.count
        )

        routeSamples = candidateSamples
        activeTrip = trip
        lastRouteLocation = currentLocation
        journalStartTrip(trip, samples: routeSamples)
        resetStartCandidate(deleteJournal: false)
        belowStopSpeedSince = nil
        tripPhase = .active
        ViimDiagnostics.log("trip.begin samples=\(trip.sampleCount) distanceMeters=\(Int(trip.distanceMeters))")
    }

    private func appendActiveSample(_ sample: LocationSample, location: CLLocation) {
        routeSamples.append(sample)

        lastRouteLocation = location

        guard var activeTrip else {
            return
        }

        // Recalculer avec la meme regle a double chronologie que la
        // persistance. L'etat live ne peut ainsi ni compter un saut impossible,
        // ni perdre un segment rendu plausible par douze minutes de reception.
        activeTrip.distanceMeters = distanceMeters(in: routeSamples)
        activeTrip.lastUpdatedAt = sample.timestamp
        if sample.speedKmh > Constants.stopSpeedThresholdKmh {
            activeTrip.lastMovingAt = sample.timestamp
        }
        activeTrip.sampleCount = routeSamples.count
        self.activeTrip = activeTrip
        journalAppendSample(sample, to: activeTrip)
    }

    private func endTripAtLastMovingSample() {
        guard let activeTrip else {
            return
        }

        endTrip(endedAt: activeTrip.lastMovingAt)
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
            sampleCount: activeTrip.sampleCount,
            observedDuration: Self.observedMovementDuration(samples: routeSamples)
        )
        ViimDiagnostics.log("trip.end distanceMeters=\(Int(activeTrip.distanceMeters)) samples=\(activeTrip.sampleCount)")

        self.activeTrip = nil
        lastRouteLocation = nil
        belowStopSpeedSince = nil
        tripPhase = .idle
    }

    private func finishInactiveActiveTripIfNeeded(now: Date = Date()) {
        guard let activeTrip,
              Self.shouldFinalizeInactiveTrip(activeTrip: activeTrip, now: now) else {
            return
        }

        ViimDiagnostics.log("trip.finish.inactive distanceMeters=\(Int(activeTrip.distanceMeters)) samples=\(activeTrip.sampleCount)")
        endTrip(endedAt: Self.endDateForStationaryFinalization(activeTrip: activeTrip))
    }

    private func trimCandidateSamples(now: Date) {
        candidateSamples.removeAll { sample in
            now.timeIntervalSince(sample.timestamp) > Constants.candidateWindow
        }
    }

    private func resetStartCandidate(
        deleteJournal: Bool = true,
        outcomeReason: String? = nil
    ) {
        let abandonedCandidateID = candidateTripID
        let abandonedSampleCount = candidateSamples.count
        aboveStartSpeedSince = nil
        candidateSamples.removeAll(keepingCapacity: true)
        candidateTripID = nil

        guard deleteJournal, let abandonedCandidateID else {
            return
        }
        if let outcomeReason {
            ViimDiagnostics.log(
                "trip.capture.outcome id=\(abandonedCandidateID.uuidString) status=rejected reason=\(outcomeReason) samples=\(abandonedSampleCount)"
            )
        }
        do {
            if let outcomeReason {
                try activeTripJournal?.finalizeTrip(
                    id: abandonedCandidateID,
                    status: "rejected",
                    reason: outcomeReason,
                    source: "location",
                    sampleCount: abandonedSampleCount
                )
            } else {
                try activeTripJournal?.deleteTrip(id: abandonedCandidateID)
            }
        } catch {
            ViimDiagnostics.log("trip.journal.candidate.cleanup.failed id=\(abandonedCandidateID.uuidString)")
        }
    }

    private func resetDetectionState() {
        activeTrip = nil
        lastRouteLocation = nil
        resetStartCandidate(outcomeReason: "monitoringStopped")
        belowStopSpeedSince = nil
        tripPhase = .idle
    }

    private func journalStartTrip(_ activeTrip: ActiveDetectedTrip, samples: [LocationSample]) {
        do {
            try activeTripJournal?.startTrip(activeTrip, vehicleType: vehicleType, samples: samples)
        } catch {
            ViimDiagnostics.log("trip.journal.start.failed")
        }
    }

    private func journalCandidateSamples() {
        guard let candidateTripID else {
            return
        }
        do {
            try activeTripJournal?.saveCandidate(
                id: candidateTripID,
                vehicleType: vehicleType,
                samples: candidateSamples,
                distanceMeters: distanceMeters(in: candidateSamples)
            )
        } catch {
            ViimDiagnostics.log("trip.journal.candidate.failed id=\(candidateTripID.uuidString)")
        }
    }

    private func journalAppendSample(_ sample: LocationSample, to activeTrip: ActiveDetectedTrip) {
        do {
            try activeTripJournal?.appendSample(sample, to: activeTrip, vehicleType: vehicleType)
        } catch {
            ViimDiagnostics.log("trip.journal.append.failed")
        }
    }

    private func distanceMeters(in samples: [LocationSample]) -> CLLocationDistance {
        let validSamples = TripMetricsCalculator.validRouteSamples(from: samples)
        return TripMetricsCalculator.distanceAnalysis(
            samples: validSamples,
            vehicleType: vehicleType
        ).distanceMeters
    }

    static func observedMovementDuration(samples: [LocationSample]) -> TimeInterval {
        guard let first = samples.first else {
            return 0
        }

        let lastMoving = samples.last { sample in
            sample.speedKmh > Constants.stopSpeedThresholdKmh
        } ?? samples.last
        guard let lastMoving else {
            return 0
        }

        let gpsDuration = lastMoving.timestamp.timeIntervalSince(first.timestamp)
        let receiptDuration = lastMoving.receivedAt.timeIntervalSince(first.receivedAt)
        return max(0, max(gpsDuration, receiptDuration))
    }
}

extension LocationService: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationState = LocationAuthorizationState(status: manager.authorizationStatus)
        configureManager()
        ViimDiagnostics.log("location.authorization state=\(authorizationState)")
        if authorizationState == .authorizedAlways {
            beginAlwaysServiceSessionIfNeeded()
            beginBackgroundActivitySessionIfNeeded(requiringAlways: true)
        } else {
            endAlwaysServiceSession()
            stopDepartureRegionMonitoring()
        }
        if !authorizationState.canTrackLocation {
            endBackgroundActivitySession()
        }
        startPassiveWakeupMonitoringIfAllowed()

        if shouldRequestCurrentLocationAfterAuthorization, authorizationState.canTrackLocation {
            requestCurrentLocation()
        }

        if shouldMonitorAfterAuthorization, authorizationState.canTrackLocation {
            startMonitoring()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Enregistre la preuve de mouvement sur TOUS les points recus, y
        // compris ceux trop imprecis pour la route : c'est ce qui empeche le
        // failsafe et l'arret stationnaire de couper le GPS en plein trajet
        // quand iOS ne livre que des points epars.
        locations.forEach(registerMovementEvidence)

        if !isMonitoring, authorizationState == .authorizedAlways {
            if shouldPromotePassiveWakeupToContinuousMonitoring(locations) {
                ViimDiagnostics.log("location.passiveWakeup.promote count=\(locations.count)")
                startMonitoring()
            } else {
                ViimDiagnostics.log("location.passiveWakeup.ignored count=\(locations.count)")
            }
        }

        locations.forEach(ingest)
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard region.identifier == Constants.departureRegionIdentifier else {
            return
        }

        ViimDiagnostics.log("location.departureRegion.exit")
        guard authorizationState == .authorizedAlways, !isMonitoring else {
            return
        }
        startMonitoring()
    }

    func locationManager(
        _ manager: CLLocationManager,
        monitoringDidFailFor region: CLRegion?,
        withError error: Error
    ) {
        ViimDiagnostics.log("location.departureRegion.failed region=\(region?.identifier ?? "nil")")
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if (error as? CLError)?.code == .denied {
            authorizationState = .denied
            shouldRequestCurrentLocationAfterAuthorization = false
            isMonitoring = false
            isPassiveWakeupMonitoring = false
            stopDepartureRegionMonitoring()
            endBackgroundActivitySession()
            endAlwaysServiceSession()
        }
    }
}
