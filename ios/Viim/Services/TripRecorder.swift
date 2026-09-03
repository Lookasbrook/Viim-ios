import Combine
import CoreLocation
import Foundation

@MainActor
final class TripRecorder: ObservableObject {
    static let maximumRecoverableActiveDraftAge: TimeInterval = 12 * 60 * 60
    private let journal: any ActiveTripJournaling
    private let tripManager: TripManager
    private let fuelCostEnricher: TripFuelCostEnricher
    private let collectionHealthJournal: (any CollectionHealthJournaling)?
    private var cancellables = Set<AnyCancellable>()
    private var observedLocationService: LocationService?
    private var processedTripIDs = Set<UUID>()
    private var vehicleType: VehicleType = .moto
    private var fuelProfile: VehicleFuelProfile?
    private var userProfile: UserProfile?
    private var fuelSettings: FuelSettings?

    init(
        journal: any ActiveTripJournaling,
        tripManager: TripManager,
        collectionHealthJournal: (any CollectionHealthJournaling)? = nil,
        fuelCostEnricher: TripFuelCostEnricher? = nil
    ) {
        self.journal = journal
        self.tripManager = tripManager
        self.collectionHealthJournal = collectionHealthJournal
        self.fuelCostEnricher = fuelCostEnricher ?? TripFuelCostEnricher(persister: tripManager)
    }

    func configure(profile: UserProfile, fuelSettings: FuelSettings? = nil) {
        vehicleType = profile.vehicleType
        userProfile = profile
        fuelProfile = VehicleFuelCatalog.profile(for: profile)
        self.fuelSettings = fuelSettings
        schedulePendingOfficialFuelCostEnrichment()
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
            recordCollectionHealthFailure(.activeTripJournalRead)
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
                fuelProfile: resolvedFuelProfile(for: vehicleType),
                fuelSettings: fuelSettings
            )
            scheduleOfficialFuelCostEnrichmentIfNeeded(
                tripID: completedTrip.id,
                outcome: outcome
            )
            handle(
                outcome: outcome,
                tripId: completedTrip.id,
                sampleCount: samples.count,
                source: "live",
                evidenceAt: completedTrip.endedAt
            )
        } catch {
            // Le brouillon reste durable et sera retente au prochain lancement.
            // Persister avec un tableau vide transformerait une panne Core Data
            // transitoire en rejet terminal et ferait perdre le trajet.
            processedTripIDs.remove(completedTrip.id)
            recordCollectionHealthFailure(.activeTripJournalRead)
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
            recordCollectionHealthFailure(.activeTripJournalRead)
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
            recordCollectionHealthOutcome(.rejected, at: draft.lastUpdatedAt)
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
                recordCollectionHealthOutcome(.rejected, at: draft.lastUpdatedAt)
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
            fuelProfile: resolvedFuelProfile(for: draft.vehicleType),
            fuelSettings: fuelSettings
        )
        scheduleOfficialFuelCostEnrichmentIfNeeded(
            tripID: draft.id,
            outcome: outcome
        )
        handle(
            outcome: outcome,
            tripId: draft.id,
            sampleCount: samples.count,
            source: "recovered",
            evidenceAt: draft.lastMovingAt
        )
        if outcome.shouldDeleteJournal {
            ViimDiagnostics.log("trip.recorder.recovered id=\(draft.id.uuidString) samples=\(samples.count)")
        }
    }

    static func isActiveDraftStale(lastUpdatedAt: Date, now: Date) -> Bool {
        now.timeIntervalSince(lastUpdatedAt) > maximumRecoverableActiveDraftAge
    }

    private func resolvedFuelProfile(for tripVehicleType: VehicleType) -> VehicleFuelProfile? {
        guard let userProfile else {
            return fuelProfile?.vehicleType == tripVehicleType ? fuelProfile : nil
        }
        let resolved = tripManager.calibratedFuelProfile(for: userProfile)
        return resolved?.vehicleType == tripVehicleType ? resolved : nil
    }

    private func schedulePendingOfficialFuelCostEnrichment() {
        guard let settings = fuelSettings,
              settings.source == .officialPublicData,
              let activeProfile = resolvedFuelProfile(for: vehicleType) else {
            return
        }
        let requests = tripManager.recentTrips.compactMap { trip -> TripFuelCostEnrichmentRequest? in
            guard trip.vehicleType == vehicleType,
                  trip.fuelCostMinorUnits == nil,
                  trip.fuelLiters != nil,
                  trip.fuelProfileName == activeProfile.canonicalName,
                  trip.fuelProfileFuelType == settings.fuelType,
                  trip.fuelProfileSource == activeProfile.sourceIdentifier,
                  settings.canSnapshotCost(at: trip.endDate) else {
                return nil
            }
            return TripFuelCostEnrichmentRequest(
                tripID: trip.id,
                routePoints: trip.routePoints,
                settings: settings,
                tripEndedAt: trip.endDate
            )
        }
        fuelCostEnricher.schedulePending(requests)
    }

    private func scheduleOfficialFuelCostEnrichmentIfNeeded(
        tripID: UUID,
        outcome: TripPersistenceOutcome
    ) {
        guard outcome == .persisted || outcome == .duplicate,
              let settings = fuelSettings,
              settings.source == .officialPublicData,
              let trip = tripManager.recentTrips.first(where: { $0.id == tripID }),
              trip.fuelCostMinorUnits == nil,
              trip.fuelLiters != nil,
              trip.fuelProfileFuelType == settings.fuelType else {
            return
        }
        fuelCostEnricher.schedule(
            TripFuelCostEnrichmentRequest(
                tripID: trip.id,
                routePoints: trip.routePoints,
                settings: settings,
                tripEndedAt: trip.endDate
            )
        )
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
            recordCollectionHealthFailure(.activeTripJournalWrite)
            ViimDiagnostics.log("trip.recorder.cleanup.failed")
        }
    }

    private func handle(
        outcome: TripPersistenceOutcome,
        tripId: UUID,
        sampleCount: Int,
        source: String,
        evidenceAt: Date
    ) {
        ViimDiagnostics.log(
            "trip.capture.outcome id=\(tripId.uuidString) status=\(outcome.status) reason=\(outcome.reason) source=\(source)"
        )
        let healthOutcome: CollectionHealthTripOutcome
        switch outcome {
        case .persisted, .duplicate:
            healthOutcome = source == "recovered" ? .recovered : .persisted
        case .rejected:
            healthOutcome = .rejected
        case .failedRetryable:
            healthOutcome = .failedRetryable
        }
        recordCollectionHealthOutcome(healthOutcome, at: evidenceAt)

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

    private func recordCollectionHealthOutcome(
        _ outcome: CollectionHealthTripOutcome,
        at date: Date
    ) {
        let recordedAt = Date()
        do {
            try collectionHealthJournal?.append(
                .outcome(outcome, at: recordedAt, evidenceAt: date),
                now: recordedAt
            )
        } catch {
            ViimDiagnostics.log("collection.health.append.failed kind=tripOutcome")
        }
    }

    private func recordCollectionHealthFailure(
        _ failure: CollectionHealthPersistenceFailure,
        at date: Date = Date()
    ) {
        do {
            try collectionHealthJournal?.append(
                .persistenceFailure(failure, at: date),
                now: date
            )
        } catch {
            ViimDiagnostics.log("collection.health.append.failed kind=persistenceFailure")
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
