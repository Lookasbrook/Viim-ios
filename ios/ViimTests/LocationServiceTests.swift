import CoreLocation
import XCTest
@testable import Viim

final class LocationServiceTests: XCTestCase {
    func testStationaryFinalizationKeepsShortNoiseOut() {
        let shouldPersist = LocationService.shouldPersistTripAfterStationaryMotion(
            distanceMeters: 40,
            duration: 30
        )

        XCTAssertFalse(shouldPersist)
    }

    func testStationaryFinalizationRejectsDistanceWithoutMinimumDuration() {
        let shouldPersist = LocationService.shouldPersistTripAfterStationaryMotion(
            distanceMeters: 90,
            duration: 30
        )

        XCTAssertFalse(shouldPersist)
    }

    func testStationaryFinalizationRejectsDurationWithoutMinimumDistance() {
        let shouldPersist = LocationService.shouldPersistTripAfterStationaryMotion(
            distanceMeters: 40,
            duration: 70
        )

        XCTAssertFalse(shouldPersist)
    }

    func testStationaryFinalizationPersistsOnlyWhenDistanceAndDurationAreMeaningful() {
        let shouldPersist = LocationService.shouldPersistTripAfterStationaryMotion(
            distanceMeters: 90,
            duration: 70
        )

        XCTAssertTrue(shouldPersist)
    }

    func testCompletedTripUsesReceiptDurationWhenGpsTimestampsWereCompressed() {
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        let trip = CompletedDetectedTrip(
            id: UUID(),
            startedAt: start,
            endedAt: start.addingTimeInterval(10),
            distanceMeters: 2_514,
            sampleCount: 11,
            observedDuration: 12 * 60
        )

        XCTAssertEqual(trip.duration, 12 * 60)
        XCTAssertNotNil(TripMetricsCalculator.durationMetric(completedTrip: trip).value)
    }

    func testStationaryFinalizationEndsAtLastMovingSample() {
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        let activeTrip = ActiveDetectedTrip(
            id: UUID(),
            startedAt: start,
            lastUpdatedAt: start.addingTimeInterval(240),
            lastMovingAt: start.addingTimeInterval(120),
            distanceMeters: 900,
            sampleCount: 8
        )

        XCTAssertEqual(
            LocationService.endDateForStationaryFinalization(activeTrip: activeTrip),
            start.addingTimeInterval(120)
        )
    }

    func testInactiveTripCanBeFinalizedAfterSustainedLocationGap() {
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        let activeTrip = ActiveDetectedTrip(
            id: UUID(),
            startedAt: start,
            lastUpdatedAt: start.addingTimeInterval(120),
            lastMovingAt: start.addingTimeInterval(100),
            distanceMeters: 900,
            sampleCount: 8
        )

        XCTAssertFalse(
            LocationService.shouldFinalizeInactiveTrip(
                activeTrip: activeTrip,
                now: start.addingTimeInterval(240)
            )
        )
        XCTAssertTrue(
            LocationService.shouldFinalizeInactiveTrip(
                activeTrip: activeTrip,
                now: start.addingTimeInterval(421)
            )
        )
    }

    func testStaleActiveTripIsNotFinalizedWhenIncomingPointIsStillMoving() {
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        let activeTrip = ActiveDetectedTrip(
            id: UUID(),
            startedAt: start,
            lastUpdatedAt: start.addingTimeInterval(120),
            lastMovingAt: start.addingTimeInterval(120),
            distanceMeters: 900,
            sampleCount: 4
        )
        let incomingSample = sample(
            latitude: 12.3794,
            longitude: -1.5117,
            speedKmh: 18,
            timestamp: start.addingTimeInterval(500)
        )

        XCTAssertFalse(
            LocationService.shouldFinalizeInactiveTripBeforeIngest(
                activeTrip: activeTrip,
                incomingSample: incomingSample
            )
        )
    }

    func testStaleActiveTripFinalizesWhenIncomingPointIsStationary() {
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        let activeTrip = ActiveDetectedTrip(
            id: UUID(),
            startedAt: start,
            lastUpdatedAt: start.addingTimeInterval(120),
            lastMovingAt: start.addingTimeInterval(120),
            distanceMeters: 900,
            sampleCount: 4
        )
        let incomingSample = sample(
            latitude: 12.3794,
            longitude: -1.5117,
            speedKmh: 0,
            timestamp: start.addingTimeInterval(500)
        )

        XCTAssertTrue(
            LocationService.shouldFinalizeInactiveTripBeforeIngest(
                activeTrip: activeTrip,
                incomingSample: incomingSample
            )
        )
    }

    func testStaleActiveTripFinalizesAfterHardGapEvenIfIncomingPointIsFast() {
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        let activeTrip = ActiveDetectedTrip(
            id: UUID(),
            startedAt: start,
            lastUpdatedAt: start.addingTimeInterval(120),
            lastMovingAt: start.addingTimeInterval(120),
            distanceMeters: 900,
            sampleCount: 4
        )
        // Voiture garee 2 h, puis premier point rapide du trajet suivant :
        // l'ancien trajet doit etre cloture, pas fusionne avec le nouveau.
        let incomingSample = sample(
            latitude: 12.3794,
            longitude: -1.5117,
            speedKmh: 45,
            timestamp: start.addingTimeInterval(2 * 3_600)
        )

        XCTAssertTrue(
            LocationService.shouldFinalizeInactiveTripBeforeIngest(
                activeTrip: activeTrip,
                incomingSample: incomingSample
            )
        )
    }

    func testStartCandidateRequiresEnoughGpsSamples() {
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        let shouldBegin = LocationService.shouldBeginTripFromCandidateSamples(
            [
                sample(latitude: 12.3714, longitude: -1.5197, speedKmh: 18, timestamp: start),
                sample(latitude: 12.3734, longitude: -1.5177, speedKmh: 18, timestamp: start.addingTimeInterval(35))
            ],
            vehicleType: .moto
        )

        XCTAssertFalse(shouldBegin)
    }

    func testSparseBackgroundCandidateStartsFromTwoPreciseDisplacedPoints() {
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        let shouldBegin = LocationService.shouldBeginTripFromCandidateSamples(
            [
                sample(latitude: 12.3714, longitude: -1.5197, speedKmh: 18, timestamp: start),
                sample(latitude: 12.3754, longitude: -1.5157, speedKmh: 18, timestamp: start.addingTimeInterval(300))
            ],
            vehicleType: .moto
        )

        XCTAssertTrue(shouldBegin)
    }

    func testSparseBackgroundCandidateRejectsNearbyPoints() {
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        let shouldBegin = LocationService.shouldBeginTripFromCandidateSamples(
            [
                sample(latitude: 12.3714, longitude: -1.5197, speedKmh: 18, timestamp: start),
                sample(latitude: 12.3716, longitude: -1.5195, speedKmh: 18, timestamp: start.addingTimeInterval(300))
            ],
            vehicleType: .moto
        )

        XCTAssertFalse(shouldBegin)
    }

    func testStartCandidateRejectsSpeedSpikeWithoutDistance() {
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        let shouldBegin = LocationService.shouldBeginTripFromCandidateSamples(
            [
                sample(latitude: 12.3714, longitude: -1.5197, speedKmh: 18, timestamp: start),
                sample(latitude: 12.3714, longitude: -1.5197, speedKmh: 18, timestamp: start.addingTimeInterval(20)),
                sample(latitude: 12.3714, longitude: -1.5197, speedKmh: 18, timestamp: start.addingTimeInterval(40))
            ],
            vehicleType: .moto
        )

        XCTAssertFalse(shouldBegin)
    }

    func testStartCandidateRejectsImpossibleGpsJump() {
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        let shouldBegin = LocationService.shouldBeginTripFromCandidateSamples(
            [
                sample(latitude: 12.3714, longitude: -1.5197, speedKmh: 18, timestamp: start),
                sample(latitude: 12.4714, longitude: -1.5197, speedKmh: 18, timestamp: start.addingTimeInterval(10)),
                sample(latitude: 12.4724, longitude: -1.5187, speedKmh: 18, timestamp: start.addingTimeInterval(40))
            ],
            vehicleType: .moto
        )

        XCTAssertFalse(shouldBegin)
    }

    func testDelayedBackgroundSegmentUsesReceiptTimeline() {
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        let receivedStart = start.addingTimeInterval(1_000)
        let delayedSamples = [
            sample(
                latitude: 46.8915,
                longitude: -71.2137,
                speedKmh: 18,
                timestamp: start,
                receivedAt: receivedStart
            ),
            sample(
                latitude: 46.9027,
                longitude: -71.2137,
                speedKmh: 20,
                timestamp: start.addingTimeInterval(5),
                receivedAt: receivedStart.addingTimeInterval(360)
            ),
            sample(
                latitude: 46.9140,
                longitude: -71.2137,
                speedKmh: 22,
                timestamp: start.addingTimeInterval(10),
                receivedAt: receivedStart.addingTimeInterval(720)
            )
        ]

        XCTAssertTrue(
            LocationService.shouldBeginTripFromCandidateSamples(
                delayedSamples,
                vehicleType: .voiture
            )
        )
        XCTAssertGreaterThan(
            TripMetricsCalculator.distanceMetric(
                samples: delayedSamples,
                vehicleType: .voiture
            ).value ?? 0,
            2_000
        )
        XCTAssertEqual(
            LocationService.observedMovementDuration(samples: delayedSamples),
            720
        )
    }

    func testStartCandidateAcceptsCoherentSustainedMovement() {
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        let shouldBegin = LocationService.shouldBeginTripFromCandidateSamples(
            [
                sample(latitude: 12.3714, longitude: -1.5197, speedKmh: 18, timestamp: start),
                sample(latitude: 12.3720, longitude: -1.5191, speedKmh: 18, timestamp: start.addingTimeInterval(20)),
                sample(latitude: 12.3726, longitude: -1.5185, speedKmh: 18, timestamp: start.addingTimeInterval(40))
            ],
            vehicleType: .moto
        )

        XCTAssertTrue(shouldBegin)
    }

    func testShortReliableDrivingBurstBecomesDurableTripBeforeIOSSuspension() {
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        let shouldBegin = LocationService.shouldBeginTripFromCandidateSamples(
            [
                sample(latitude: 46.89150, longitude: -71.21370, speedKmh: 34, timestamp: start),
                sample(latitude: 46.89175, longitude: -71.21370, speedKmh: 34, timestamp: start.addingTimeInterval(3)),
                sample(latitude: 46.89200, longitude: -71.21370, speedKmh: 34, timestamp: start.addingTimeInterval(6)),
                sample(latitude: 46.89225, longitude: -71.21370, speedKmh: 34, timestamp: start.addingTimeInterval(9))
            ],
            vehicleType: .voiture
        )

        XCTAssertTrue(shouldBegin)
    }

    func testShortBurstRejectsUnreliableReportedSpeeds() {
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        let samples = [0.0, 3.0, 6.0, 9.0].enumerated().map { index, offset in
            LocationSample(
                timestamp: start.addingTimeInterval(offset),
                latitude: 46.89150 + Double(index) * 0.00025,
                longitude: -71.21370,
                speedKmh: 4_388,
                horizontalAccuracy: 5,
                speedAccuracy: -1
            )
        }

        XCTAssertFalse(
            LocationService.shouldBeginTripFromCandidateSamples(samples, vehicleType: .voiture)
        )
    }

    func testStartCandidateSurvivesIsolatedGpsGlitch() {
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        // Points coherents avec un seul point aberrant au milieu : le glitch
        // est saute, le demarrage du trajet n'est plus annule.
        let shouldBegin = LocationService.shouldBeginTripFromCandidateSamples(
            [
                sample(latitude: 12.3714, longitude: -1.5197, speedKmh: 18, timestamp: start),
                sample(latitude: 12.3720, longitude: -1.5191, speedKmh: 18, timestamp: start.addingTimeInterval(15)),
                sample(latitude: 12.4900, longitude: -1.5191, speedKmh: 18, timestamp: start.addingTimeInterval(16)),
                sample(latitude: 12.3726, longitude: -1.5185, speedKmh: 18, timestamp: start.addingTimeInterval(30)),
                sample(latitude: 12.3732, longitude: -1.5179, speedKmh: 18, timestamp: start.addingTimeInterval(45))
            ],
            vehicleType: .moto
        )

        XCTAssertTrue(shouldBegin)
    }

    func testPassiveWakeupPromotesOnColdRelaunchWithoutReferenceLocation() {
        let now = Date(timeIntervalSince1970: 1_783_000_000)
        // Relance a froid : fix cellulaire imprecis, vitesse inconnue, aucune
        // position de reference. Le reveil significatif implique un deplacement,
        // la promotion doit avoir lieu.
        let coarseWakeupFix = location(
            latitude: 12.3714,
            longitude: -1.5197,
            accuracy: 1_500,
            speedMps: -1,
            timestamp: now.addingTimeInterval(-30)
        )

        XCTAssertTrue(
            LocationService.shouldPromotePassiveWakeup(
                locations: [coarseWakeupFix],
                lastKnownLocation: nil,
                now: now
            )
        )
    }

    func testPassiveWakeupIgnoresStaleLocationsOnColdRelaunch() {
        let now = Date(timeIntervalSince1970: 1_783_000_000)
        let staleFix = location(
            latitude: 12.3714,
            longitude: -1.5197,
            accuracy: 1_500,
            speedMps: -1,
            timestamp: now.addingTimeInterval(-3_600)
        )

        XCTAssertFalse(
            LocationService.shouldPromotePassiveWakeup(
                locations: [staleFix],
                lastKnownLocation: nil,
                now: now
            )
        )
    }

    func testPassiveWakeupPromotesOnReportedDrivingSpeed() {
        let now = Date(timeIntervalSince1970: 1_783_000_000)
        let movingFix = location(
            latitude: 12.3714,
            longitude: -1.5197,
            accuracy: 50,
            speedMps: 12,
            timestamp: now.addingTimeInterval(-5)
        )

        XCTAssertTrue(
            LocationService.shouldPromotePassiveWakeup(
                locations: [movingFix],
                lastKnownLocation: nil,
                now: now
            )
        )
    }

    func testPassiveWakeupStaysQuietNearLastKnownLocation() {
        let now = Date(timeIntervalSince1970: 1_783_000_000)
        let reference = location(
            latitude: 12.3714,
            longitude: -1.5197,
            accuracy: 10,
            speedMps: 0,
            timestamp: now.addingTimeInterval(-60)
        )
        // Fix precis a ~40 m de la reference, sans vitesse : pas de promotion.
        let nearbyFix = location(
            latitude: 12.37176,
            longitude: -1.5197,
            accuracy: 30,
            speedMps: -1,
            timestamp: now.addingTimeInterval(-10)
        )

        XCTAssertFalse(
            LocationService.shouldPromotePassiveWakeup(
                locations: [nearbyFix],
                lastKnownLocation: reference,
                now: now
            )
        )
    }

    func testPassiveWakeupPromotesOnRealDisplacementFromLastKnownLocation() {
        let now = Date(timeIntervalSince1970: 1_783_000_000)
        let reference = location(
            latitude: 12.3714,
            longitude: -1.5197,
            accuracy: 10,
            speedMps: 0,
            timestamp: now.addingTimeInterval(-600)
        )
        // ~1.1 km de deplacement avec un fix a 150 m de precision : promotion.
        let displacedFix = location(
            latitude: 12.3814,
            longitude: -1.5197,
            accuracy: 150,
            speedMps: -1,
            timestamp: now.addingTimeInterval(-10)
        )

        XCTAssertTrue(
            LocationService.shouldPromotePassiveWakeup(
                locations: [displacedFix],
                lastKnownLocation: reference,
                now: now
            )
        )
    }

    func testMovementEvidenceFromReportedDrivingSpeed() {
        let now = Date(timeIntervalSince1970: 1_783_000_000)
        let movingFix = location(
            latitude: 46.8915,
            longitude: -71.2137,
            accuracy: 40,
            speedMps: 12,
            timestamp: now.addingTimeInterval(-5)
        )

        XCTAssertTrue(
            LocationService.isMovementEvidence(previous: nil, current: movingFix, now: now)
        )
    }

    func testMovementEvidenceFromCoarseDisplacedFix() {
        let now = Date(timeIntervalSince1970: 1_783_000_000)
        let previous = location(
            latitude: 46.8915,
            longitude: -71.2137,
            accuracy: 30,
            speedMps: -1,
            timestamp: now.addingTimeInterval(-320)
        )
        // ~2,2 km plus loin, fix imprecis (800 m) sans vitesse : cadence typique
        // des reveils significatifs quand l'app est suspendue. C'est une preuve
        // de deplacement, meme si le point est inutilisable pour la route.
        let displaced = location(
            latitude: 46.9115,
            longitude: -71.2137,
            accuracy: 800,
            speedMps: -1,
            timestamp: now.addingTimeInterval(-10)
        )

        XCTAssertTrue(
            LocationService.isMovementEvidence(previous: previous, current: displaced, now: now)
        )
    }

    func testNoMovementEvidenceFromCoarseJitterWithinAccuracyMargin() {
        let now = Date(timeIntervalSince1970: 1_783_000_000)
        let previous = location(
            latitude: 46.8915,
            longitude: -71.2137,
            accuracy: 30,
            speedMps: -1,
            timestamp: now.addingTimeInterval(-120)
        )
        // ~400 m de deplacement apparent mais precision 1500 m : indiscernable
        // du bruit, pas une preuve de mouvement.
        let jitter = location(
            latitude: 46.8951,
            longitude: -71.2137,
            accuracy: 1_500,
            speedMps: -1,
            timestamp: now.addingTimeInterval(-10)
        )

        XCTAssertFalse(
            LocationService.isMovementEvidence(previous: previous, current: jitter, now: now)
        )
    }

    func testIdleStopDeferredWhileMovementEvidenceIsRecent() {
        let now = Date(timeIntervalSince1970: 1_783_000_000)

        XCTAssertTrue(
            LocationService.shouldDeferIdleStop(
                lastMovementEvidenceAt: now.addingTimeInterval(-60),
                now: now
            )
        )
        XCTAssertFalse(
            LocationService.shouldDeferIdleStop(
                lastMovementEvidenceAt: now.addingTimeInterval(-600),
                now: now
            )
        )
        XCTAssertFalse(
            LocationService.shouldDeferIdleStop(lastMovementEvidenceAt: nil, now: now)
        )
    }

    func testStationaryStopIsDeferredDuringInitialArmingGraceWithoutGpsEvidence() {
        let startedAt = Date(timeIntervalSince1970: 1_783_000_000)

        XCTAssertTrue(
            LocationService.shouldDeferStationaryStop(
                monitoringStartedAt: startedAt,
                lastMovementEvidenceAt: nil,
                now: startedAt.addingTimeInterval(5)
            )
        )
    }

    func testStationaryStopIsAllowedAfterArmingGraceWithoutMovementEvidence() {
        let startedAt = Date(timeIntervalSince1970: 1_783_000_000)

        XCTAssertFalse(
            LocationService.shouldDeferStationaryStop(
                monitoringStartedAt: startedAt,
                lastMovementEvidenceAt: nil,
                now: startedAt.addingTimeInterval(181)
            )
        )
    }

    func testCandidateTimeoutWaitsForFullDurableRecoveryWindow() {
        let now = Date(timeIntervalSince1970: 1_783_000_000)

        XCTAssertTrue(
            LocationService.shouldDeferCandidateTimeout(
                lastUpdatedAt: now.addingTimeInterval(-5 * 60),
                now: now
            )
        )
        XCTAssertFalse(
            LocationService.shouldDeferCandidateTimeout(
                lastUpdatedAt: now.addingTimeInterval(-15 * 60),
                now: now
            )
        )
    }

    func testInvalidReportedSpeedCannotCreateImpossibleDerivedSpeed() {
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        let previous = location(
            latitude: 46.8915,
            longitude: -71.2137,
            accuracy: 5,
            speedMps: 0,
            timestamp: start,
            speedAccuracy: 1
        )
        let invalidSpeedFix = location(
            latitude: 46.8915,
            longitude: -71.2137,
            accuracy: 5,
            speedMps: 1_219,
            timestamp: start.addingTimeInterval(9),
            speedAccuracy: -1
        )

        XCTAssertEqual(
            LocationService.resolvedSpeedKmh(
                for: invalidSpeedFix,
                previousLocation: previous,
                vehicleType: .voiture
            ),
            0
        )
    }

    func testAlwaysAuthorizationKeepsBackgroundSessionAcrossIdleStops() {
        let manager = LocationManagerSpy(authorizationStatus: .authorizedAlways)
        var visualSessionCreationCount = 0
        var alwaysSessionCreationCount = 0
        let service = LocationService(
            manager: manager,
            backgroundActivitySessionFactory: {
                visualSessionCreationCount += 1
                return NSObject()
            },
            alwaysServiceSessionFactory: {
                alwaysSessionCreationCount += 1
                return NSObject()
            }
        )

        service.prepareForForegroundUse()

        // La session d'activite doit exister des le premier plan et survivre a
        // l'idle : c'est la condition Apple pour retrouver la cadence GPS
        // continue apres une relance en arriere-plan.
        XCTAssertEqual(visualSessionCreationCount, 1)
        XCTAssertEqual(alwaysSessionCreationCount, 1)
        XCTAssertTrue(service.hasAlwaysServiceSession)
        XCTAssertTrue(service.hasBackgroundActivitySession)
        XCTAssertTrue(manager.allowsBackgroundLocationUpdates)
        XCTAssertFalse(manager.showsBackgroundLocationIndicator)
        XCTAssertEqual(manager.actions, [.startSignificant])

        manager.actions.removeAll()
        service.startMonitoring()

        XCTAssertEqual(manager.actions, [.startStandard])
        XCTAssertTrue(service.isPassiveWakeupMonitoring)
        XCTAssertEqual(visualSessionCreationCount, 1)
        XCTAssertTrue(service.hasBackgroundActivitySession)

        manager.actions.removeAll()
        service.stopMonitoring()

        XCTAssertEqual(manager.actions, [.stopStandard])
        XCTAssertTrue(service.isPassiveWakeupMonitoring)
        XCTAssertTrue(service.hasAlwaysServiceSession)
        XCTAssertTrue(service.hasBackgroundActivitySession)

        service.stopMonitoring(keepPassiveWakeups: false)

        XCTAssertEqual(manager.actions, [.stopStandard, .stopStandard, .stopSignificant])
        XCTAssertFalse(service.hasAlwaysServiceSession)
        XCTAssertFalse(service.hasBackgroundActivitySession)
    }

    func testColdLaunchRestoreRecreatesBackgroundSessionImmediately() {
        let manager = LocationManagerSpy(authorizationStatus: .authorizedAlways)
        var visualSessionCreationCount = 0
        let service = LocationService(
            manager: manager,
            backgroundActivitySessionFactory: {
                visualSessionCreationCount += 1
                return NSObject()
            },
            alwaysServiceSessionFactory: { NSObject() }
        )

        service.restoreAutomaticTrackingSession()

        XCTAssertEqual(visualSessionCreationCount, 1)
        XCTAssertTrue(service.hasBackgroundActivitySession)
        XCTAssertTrue(service.hasAlwaysServiceSession)
    }

    func testWhenInUseRestoreDoesNotCreateBackgroundSession() {
        let manager = LocationManagerSpy(authorizationStatus: .authorizedWhenInUse)
        var visualSessionCreationCount = 0
        let service = LocationService(
            manager: manager,
            backgroundActivitySessionFactory: {
                visualSessionCreationCount += 1
                return NSObject()
            }
        )

        service.restoreAutomaticTrackingSession()
        service.prepareForForegroundUse()

        XCTAssertEqual(visualSessionCreationCount, 0)
        XCTAssertFalse(service.hasBackgroundActivitySession)
    }

    func testDepartureRegionArmsOnIdleStopAndPromotesOnExit() {
        let manager = LocationManagerSpy(authorizationStatus: .authorizedAlways)
        let service = LocationService(
            manager: manager,
            backgroundActivitySessionFactory: { NSObject() },
            alwaysServiceSessionFactory: { NSObject() }
        )
        let delegateManager = CLLocationManager()

        service.prepareForForegroundUse()
        service.startMonitoring()

        // Sans position connue, aucun armement possible.
        service.stopMonitoring()
        XCTAssertFalse(manager.actions.contains(.startRegion("viim.departure")))

        service.startMonitoring()
        let parked = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 12.3714, longitude: -1.5197),
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            course: 0,
            speed: 0,
            timestamp: Date()
        )
        service.locationManager(delegateManager, didUpdateLocations: [parked])

        manager.actions.removeAll()
        service.stopMonitoring()

        XCTAssertEqual(manager.actions, [.stopStandard, .startRegion("viim.departure")])

        manager.actions.removeAll()
        let region = CLCircularRegion(
            center: parked.coordinate,
            radius: 150,
            identifier: "viim.departure"
        )
        service.locationManager(delegateManager, didExitRegion: region)

        // La sortie de zone relance la collecte GPS et desarme la geofence.
        XCTAssertEqual(manager.actions, [.stopRegion("viim.departure"), .startStandard])
        XCTAssertTrue(service.isMonitoring)
    }

    func testSustainedGpsStationarityOverridesNoisyMotionMovement() {
        let now = Date(timeIntervalSince1970: 1_783_000_000)

        XCTAssertTrue(
            LocationService.shouldFinalizeDespiteMotionMovement(
                hasActiveTrip: true,
                currentSpeedKmh: 0,
                lastMovementEvidenceAt: now.addingTimeInterval(-6 * 60),
                now: now
            )
        )
        XCTAssertFalse(
            LocationService.shouldFinalizeDespiteMotionMovement(
                hasActiveTrip: true,
                currentSpeedKmh: 25,
                lastMovementEvidenceAt: now.addingTimeInterval(-6 * 60),
                now: now
            )
        )
        XCTAssertFalse(
            LocationService.shouldFinalizeDespiteMotionMovement(
                hasActiveTrip: true,
                currentSpeedKmh: 0,
                lastMovementEvidenceAt: now.addingTimeInterval(-60),
                now: now
            )
        )
    }

    func testWhenInUseVisualSessionExistsOnlyDuringActiveTracking() {
        let manager = LocationManagerSpy(authorizationStatus: .authorizedWhenInUse)
        var sessionCreationCount = 0
        let service = LocationService(
            manager: manager,
            backgroundActivitySessionFactory: {
                sessionCreationCount += 1
                return NSObject()
            }
        )

        service.prepareForForegroundUse()

        XCTAssertEqual(sessionCreationCount, 0)
        XCTAssertFalse(manager.allowsBackgroundLocationUpdates)
        XCTAssertFalse(manager.showsBackgroundLocationIndicator)
        XCTAssertFalse(service.hasBackgroundActivitySession)

        service.startMonitoring()

        XCTAssertEqual(sessionCreationCount, 1)
        XCTAssertTrue(service.hasBackgroundActivitySession)
        XCTAssertEqual(manager.actions, [.startStandard])

        service.stopMonitoring()

        XCTAssertFalse(service.hasBackgroundActivitySession)
        XCTAssertEqual(manager.actions, [.startStandard, .stopStandard])
    }

    func testCandidateExpiresOnlyAfterFullRecoveryWindow() {
        let now = Date(timeIntervalSince1970: 1_783_000_000)

        XCTAssertFalse(
            LocationService.isCandidateExpired(
                lastUpdatedAt: now.addingTimeInterval(-60),
                now: now
            )
        )
        XCTAssertTrue(
            LocationService.isCandidateExpired(
                lastUpdatedAt: now.addingTimeInterval(-15 * 60),
                now: now
            )
        )
    }

    private func location(
        latitude: Double,
        longitude: Double,
        accuracy: Double,
        speedMps: Double,
        timestamp: Date,
        speedAccuracy: Double = 1
    ) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: 300,
            horizontalAccuracy: accuracy,
            verticalAccuracy: 10,
            course: 0,
            courseAccuracy: 1,
            speed: speedMps,
            speedAccuracy: speedAccuracy,
            timestamp: timestamp
        )
    }

    private func sample(
        latitude: Double,
        longitude: Double,
        speedKmh: Double,
        timestamp: Date,
        receivedAt: Date? = nil
    ) -> LocationSample {
        LocationSample(
            timestamp: timestamp,
            latitude: latitude,
            longitude: longitude,
            speedKmh: speedKmh,
            horizontalAccuracy: 5,
            speedAccuracy: 1,
            receivedAt: receivedAt
        )
    }
}

private final class LocationManagerSpy: LocationManaging {
    enum Action: Equatable {
        case startStandard
        case stopStandard
        case startSignificant
        case stopSignificant
        case startRegion(String)
        case stopRegion(String)
    }

    weak var delegate: CLLocationManagerDelegate?
    let authorizationStatus: CLAuthorizationStatus
    var allowsBackgroundLocationUpdates = false
    var pausesLocationUpdatesAutomatically = true
    var showsBackgroundLocationIndicator = false
    var activityType: CLActivityType = .other
    var desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyBest
    var distanceFilter: CLLocationDistance = kCLDistanceFilterNone
    var actions: [Action] = []

    init(authorizationStatus: CLAuthorizationStatus) {
        self.authorizationStatus = authorizationStatus
    }

    func requestWhenInUseAuthorization() {}
    func requestAlwaysAuthorization() {}
    func requestLocation() {}
    func startUpdatingLocation() { actions.append(.startStandard) }
    func stopUpdatingLocation() { actions.append(.stopStandard) }
    func startMonitoringSignificantLocationChanges() { actions.append(.startSignificant) }
    func stopMonitoringSignificantLocationChanges() { actions.append(.stopSignificant) }
    func startMonitoring(for region: CLRegion) { actions.append(.startRegion(region.identifier)) }
    func stopMonitoring(for region: CLRegion) { actions.append(.stopRegion(region.identifier)) }
}

@MainActor
final class PreventionRegionTests: XCTestCase {
    func testOuagadougouCoordinateIsClassifiedAsBurkina() {
        let ouagadougou = CLLocation(latitude: 12.3714, longitude: -1.5197)
        XCTAssertEqual(PreventionRegion.classify(location: ouagadougou), .burkina)
    }

    func testQuebecCoordinateIsClassifiedAsCanada() {
        let quebec = CLLocation(latitude: 46.8139, longitude: -71.2080)
        XCTAssertEqual(PreventionRegion.classify(location: quebec), .canada)
    }

    func testMontrealAndTorontoAreClassifiedAsCanada() {
        let montreal = CLLocation(latitude: 45.5019, longitude: -73.5674)
        let toronto = CLLocation(latitude: 43.6532, longitude: -79.3832)
        XCTAssertEqual(PreventionRegion.classify(location: montreal), .canada)
        XCTAssertEqual(PreventionRegion.classify(location: toronto), .canada)
    }

    func testParisCoordinateIsClassifiedOutsideKnownRegions() {
        let paris = CLLocation(latitude: 48.8566, longitude: 2.3522)
        XCTAssertEqual(PreventionRegion.classify(location: paris), .outsideKnownRegions)
    }

    func testBoboDioulassoCoordinateIsClassifiedAsBurkina() {
        let bobo = CLLocation(latitude: 11.1771, longitude: -4.2979)
        XCTAssertEqual(PreventionRegion.classify(location: bobo), .burkina)
    }

    func testMissingLocationIsClassifiedAsUnknown() {
        XCTAssertEqual(PreventionRegion.classify(location: nil), .unknown)
    }

    func testInvalidAccuracyIsClassifiedAsUnknown() {
        let invalid = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 12.3714, longitude: -1.5197),
            altitude: 0,
            horizontalAccuracy: -1,
            verticalAccuracy: -1,
            timestamp: Date()
        )
        XCTAssertEqual(PreventionRegion.classify(location: invalid), .unknown)
    }
}
