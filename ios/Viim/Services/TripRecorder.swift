import Combine
import CoreLocation
import Foundation

@MainActor
final class TripRecorder: ObservableObject {
    static let maximumRecoverableActiveDraftAge: TimeInterval = 12 * 60 * 60
    private let journal: any ActiveTripJournaling
    private let tripManager: TripManager
    private var cancellables = Set<AnyCancellable>()
    private var observedLocationService: LocationService?
    private var processedTripIDs = Set<UUID>()
    private var vehicleType: VehicleType = .moto
    private var fuelProfile: VehicleFuelProfile?
    private var fuelSettings: FuelSettings?

    init(journal: any ActiveTripJournaling, tripManager: TripManager) {
        self.journal = journal
        self.tripManager = tripManager
    }

    func configure(profile: UserProfile, fuelSettings: FuelSettings? = nil) {
        vehicleType = profile.vehicleType
        fuelProfile = VehicleFuelCatalog.profile(for: profile)
        self.fuelSettings = fuelSettings
    }

    func observe(locationService: LocationService) {
        guard observedLocationService !== locationService else {
            return
        }

        cancellables.removeAll()
        observedLocationService = locationService
        locationService.$lastCompletedTrip
            .compactMap { $0 }
            .sink { [weak self] completedTrip in
                Task { @MainActor in
                    self?.persistCompletedTrip(completedTrip)
                }
            }
            .store(in: &cancellables)
    }

    func recoverActiveTrips(now: Date = Date()) {
        do {
            let drafts = try journal.activeDrafts()
            for draft in drafts {
                recover(draft, now: now)
            }
        } catch {
            ViimDiagnostics.log("trip.recorder.recover.failed")
        }
    }

    private func persistCompletedTrip(_ completedTrip: CompletedDetectedTrip) {
        guard processedTripIDs.insert(completedTrip.id).inserted else {
            return
        }

        do {
            let samples = try journal.samples(for: completedTrip.id)
            let outcome = tripManager.persistCompletedTrip(
                completedTrip,
                samples: samples,
                vehicleType: vehicleType,
                fuelProfile: fuelProfile,
                fuelSettings: fuelSettings
            )
            handle(outcome: outcome, tripId: completedTrip.id, sampleCount: samples.count, source: "live")
        } catch {
            // Le brouillon reste durable et sera retente au prochain lancement.
            // Persister avec un tableau vide transformerait une panne Core Data
            // transitoire en rejet terminal et ferait perdre le trajet.
            processedTripIDs.remove(completedTrip.id)
            ViimDiagnostics.log(
                "trip.recorder.samples.failed id=\(completedTrip.id.uuidString) source=live"
            )
        }
    }

    private func recover(_ draft: ActiveTripDraftRecord, now: Date) {
        guard processedTripIDs.insert(draft.id).inserted else {
            return
        }

        let samples: [LocationSample]
        do {
            samples = try journal.samples(for: draft.id)
        } catch {
            processedTripIDs.remove(draft.id)
            ViimDiagnostics.log(
                "trip.recorder.samples.failed id=\(draft.id.uuidString) source=recovery"
            )
            return
        }
        if draft.phase == .active,
           Self.isActiveDraftStale(lastUpdatedAt: draft.lastUpdatedAt, now: now) {
            ViimDiagnostics.log(
                "trip.capture.outcome id=\(draft.id.uuidString) status=rejected reason=staleActiveTrip source=recovery"
            )
            finalizeJournalTrip(
                id: draft.id,
                status: "rejected",
                reason: "staleActiveTrip",
                source: "recovery",
                sampleCount: samples.count
            )
            return
        }
        if draft.phase == .candidate,
           !LocationService.shouldBeginTripFromCandidateSamples(samples, vehicleType: draft.vehicleType) {
            if LocationService.isCandidateExpired(lastUpdatedAt: draft.lastUpdatedAt, now: now) {
                ViimDiagnostics.log("trip.capture.outcome id=\(draft.id.uuidString) status=rejected reason=staleCandidate")
                finalizeJournalTrip(
                    id: draft.id,
                    status: "rejected",
                    reason: "staleCandidate",
                    source: "recovery",
                    sampleCount: samples.count
                )
            } else {
                // Un callback CoreLocation peut creer le premier point pendant
                // le lancement, avant la fin du cablage de l'app. Ce candidat
                // est encore vivant : le supprimer ici provoque une perte de
                // preuve et un second resultat terminal contradictoire.
                processedTripIDs.remove(draft.id)
                ViimDiagnostics.log(
                    "trip.recorder.candidate.deferred id=\(draft.id.uuidString) samples=\(samples.count)"
                )
            }
            return
        }
        let completedTrip = CompletedDetectedTrip(
            id: draft.id,
            startedAt: draft.startedAt,
            endedAt: draft.lastMovingAt,
            distanceMeters: recoveredDistanceMeters(from: samples, draft: draft),
            sampleCount: samples.count,
            observedDuration: LocationService.observedMovementDuration(samples: samples)
        )

        let outcome = tripManager.persistCompletedTrip(
            completedTrip,
            samples: samples,
            vehicleType: draft.vehicleType,
            fuelProfile: fuelProfile,
            fuelSettings: fuelSettings
        )
        handle(outcome: outcome, tripId: draft.id, sampleCount: samples.count, source: "recovered")
        if outcome.shouldDeleteJournal {
            ViimDiagnostics.log("trip.recorder.recovered id=\(draft.id.uuidString) samples=\(samples.count)")
        }
    }

    static func isActiveDraftStale(lastUpdatedAt: Date, now: Date) -> Bool {
        now.timeIntervalSince(lastUpdatedAt) > maximumRecoverableActiveDraftAge
    }

    private func finalizeJournalTrip(
        id tripId: UUID,
        status: String,
        reason: String,
        source: String,
        sampleCount: Int
    ) {
        do {
            try journal.finalizeTrip(
                id: tripId,
                status: status,
                reason: reason,
                source: source,
                sampleCount: sampleCount
            )
        } catch {
            ViimDiagnostics.log("trip.recorder.cleanup.failed")
        }
    }

    private func handle(
        outcome: TripPersistenceOutcome,
        tripId: UUID,
        sampleCount: Int,
        source: String
    ) {
        ViimDiagnostics.log(
            "trip.capture.outcome id=\(tripId.uuidString) status=\(outcome.status) reason=\(outcome.reason) source=\(source)"
        )
        if outcome.shouldDeleteJournal {
            finalizeJournalTrip(
                id: tripId,
                status: outcome.status,
                reason: outcome.reason,
                source: source,
                sampleCount: sampleCount
            )
        } else {
            processedTripIDs.remove(tripId)
        }
    }

    private func recoveredDistanceMeters(
        from samples: [LocationSample],
        draft: ActiveTripDraftRecord
    ) -> CLLocationDistance {
        TripMetricsCalculator.distanceMetric(
            samples: samples,
            vehicleType: draft.vehicleType
        ).value ?? draft.distanceMeters
    }
}
