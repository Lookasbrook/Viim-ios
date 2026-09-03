import CoreLocation
import Foundation

/// Localite grossiere obtenue au moment ou l'utilisateur demande un prix public.
/// Elle ne contient aucune coordonnee et permet de verifier que la localite du
/// prix correspond bien a la localite demandee.
struct FuelPriceLocationEvidence: Codable, Equatable, Hashable {
    static let schemaVersion = 1

    let countryCode: String
    let regionCode: String
    let locality: String
    let resolvedAt: Date
    let schemaVersion: Int

    init(
        countryCode: String,
        regionCode: String,
        locality: String,
        resolvedAt: Date,
        schemaVersion: Int = Self.schemaVersion
    ) {
        self.countryCode = countryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.regionCode = regionCode.trimmingCharacters(in: .whitespacesAndNewlines)
        self.locality = locality.trimmingCharacters(in: .whitespacesAndNewlines)
        self.resolvedAt = resolvedAt
        self.schemaVersion = schemaVersion
    }

    var isStructurallyValid: Bool {
        schemaVersion == Self.schemaVersion &&
            Self.isValidComponent(countryCode, maximumLength: 2) &&
            countryCode.count == 2 &&
            countryCode.unicodeScalars.allSatisfy(CharacterSet.letters.contains) &&
            Self.isValidComponent(regionCode, maximumLength: 80) &&
            Self.isValidComponent(locality, maximumLength: 80) &&
            resolvedAt.timeIntervalSince1970.isFinite
    }

    private static func isValidComponent(_ value: String, maximumLength: Int) -> Bool {
        !value.isEmpty &&
            value.count <= maximumLength &&
            value.rangeOfCharacter(from: .controlCharacters) == nil
    }
}

/// Resultat grossier d'un geocodage d'extremite de trajet. Aucune coordonnee
/// supplementaire n'est conservee : la trace GPS du trajet existe deja dans son
/// propre champ protege.
struct TripEndpointLocality: Equatable, Hashable {
    let countryCode: String
    let regionCode: String
    let locality: String

    init(countryCode: String, regionCode: String, locality: String) {
        self.countryCode = countryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.regionCode = regionCode.trimmingCharacters(in: .whitespacesAndNewlines)
        self.locality = locality.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isStructurallyValid: Bool {
        let evidence = FuelPriceLocationEvidence(
            countryCode: countryCode,
            regionCode: regionCode,
            locality: locality,
            resolvedAt: Date(timeIntervalSince1970: 0)
        )
        return evidence.isStructurallyValid
    }
}

struct VerifiedFuelPriceGeographyMatch: Equatable {
    static let version = "fuel-price-geography-v1-start-end"

    let tripID: UUID
    let start: TripEndpointLocality
    let end: TripEndpointLocality
    let matchedAt: Date
    let priceCountryCode: String
    let priceRegionCode: String
    let priceRequestedLocality: String
    let priceLocationResolvedAt: Date
    let priceEvidenceLocality: String
    let priceSourceIdentifier: String
    let version: String

    fileprivate init(
        tripID: UUID,
        start: TripEndpointLocality,
        end: TripEndpointLocality,
        matchedAt: Date,
        acquisition: FuelPriceLocationEvidence,
        priceEvidenceLocality: String,
        priceSourceIdentifier: String
    ) {
        self.tripID = tripID
        self.start = start
        self.end = end
        self.matchedAt = matchedAt
        priceCountryCode = acquisition.countryCode
        priceRegionCode = acquisition.regionCode
        priceRequestedLocality = acquisition.locality
        priceLocationResolvedAt = acquisition.resolvedAt
        self.priceEvidenceLocality = priceEvidenceLocality
        self.priceSourceIdentifier = priceSourceIdentifier
        version = Self.version
    }

    func matches(tripID: UUID, settings: FuelSettings) -> Bool {
        guard let acquisition = settings.locationEvidence else { return false }
        return self.tripID == tripID &&
            version == Self.version &&
            matchedAt.timeIntervalSince1970.isFinite &&
            priceLocationResolvedAt == acquisition.resolvedAt &&
            matchedAt.timeIntervalSince(acquisition.resolvedAt) >= -FuelSettings.maximumFutureClockSkew &&
            priceCountryCode == acquisition.countryCode &&
            priceRegionCode == acquisition.regionCode &&
            priceRequestedLocality == acquisition.locality &&
            priceEvidenceLocality == settings.locality &&
            priceSourceIdentifier == settings.sourceIdentifier
    }
}

enum FuelPriceGeographyMatcher {
    static func acquisitionMatchesPrice(_ settings: FuelSettings) -> Bool {
        guard settings.source == .officialPublicData,
              let sourceIdentifier = settings.sourceIdentifier,
              let evidenceLocality = settings.locality,
              let acquisition = settings.locationEvidence,
              acquisition.isStructurallyValid,
              let expected = canonicalEvidenceLocality(
                sourceIdentifier: sourceIdentifier,
                countryCode: acquisition.countryCode,
                regionCode: acquisition.regionCode,
                locality: acquisition.locality
              ) else {
            return false
        }
        return normalize(expected) == normalize(evidenceLocality)
    }

    static func verifiedMatch(
        tripID: UUID,
        settings: FuelSettings,
        start: TripEndpointLocality,
        end: TripEndpointLocality,
        matchedAt: Date
    ) -> VerifiedFuelPriceGeographyMatch? {
        guard settings.source == .officialPublicData,
              settings.canSnapshotCost,
              let acquisition = settings.locationEvidence,
              let priceEvidenceLocality = settings.locality,
              let priceSourceIdentifier = settings.sourceIdentifier,
              start.isStructurallyValid,
              end.isStructurallyValid,
              matchedAt.timeIntervalSince1970.isFinite,
              acquisitionMatchesPrice(settings),
              endpoint(start, isCoveredBy: settings),
              endpoint(end, isCoveredBy: settings) else {
            return nil
        }
        return VerifiedFuelPriceGeographyMatch(
            tripID: tripID,
            start: start,
            end: end,
            matchedAt: matchedAt,
            acquisition: acquisition,
            priceEvidenceLocality: priceEvidenceLocality,
            priceSourceIdentifier: priceSourceIdentifier
        )
    }

    private static func endpoint(
        _ endpoint: TripEndpointLocality,
        isCoveredBy settings: FuelSettings
    ) -> Bool {
        guard let sourceIdentifier = settings.sourceIdentifier,
              let evidenceLocality = settings.locality else {
            return false
        }

        switch sourceIdentifier {
        case OfficialFuelPriceEvidenceContract.ontarioIdentifier:
            guard endpoint.countryCode == "CA", isOntario(endpoint.regionCode) else {
                return false
            }
            if normalize(evidenceLocality) == "ontario" {
                return true
            }
        case OfficialFuelPriceEvidenceContract.statisticsCanadaIdentifier:
            guard endpoint.countryCode == "CA" else { return false }
            if normalize(evidenceLocality) == "canada" {
                return true
            }
        default:
            return false
        }

        guard let endpointMarket = canonicalEvidenceLocality(
            sourceIdentifier: sourceIdentifier,
            countryCode: endpoint.countryCode,
            regionCode: endpoint.regionCode,
            locality: endpoint.locality
        ) else {
            return false
        }
        return normalize(endpointMarket) == normalize(evidenceLocality)
    }

    private static func canonicalEvidenceLocality(
        sourceIdentifier: String,
        countryCode: String,
        regionCode: String,
        locality: String
    ) -> String? {
        guard countryCode.uppercased() == "CA" else { return nil }
        switch sourceIdentifier {
        case OfficialFuelPriceEvidenceContract.ontarioIdentifier:
            guard isOntario(regionCode) else { return nil }
            return OntarioPublicFuelPriceClient.evidenceLocality(locality: locality)
        case OfficialFuelPriceEvidenceContract.statisticsCanadaIdentifier:
            guard !isOntario(regionCode) else { return nil }
            return StatisticsCanadaPublicFuelPriceClient.evidenceLocality(
                region: regionCode,
                locality: locality
            )
        default:
            return nil
        }
    }

    private static func isOntario(_ regionCode: String) -> Bool {
        ["on", "ontario"].contains(normalize(regionCode))
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "fr_CA")
            )
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }
}

@MainActor
protocol TripEndpointLocalityResolving: AnyObject {
    func resolve(coordinate: CLLocationCoordinate2D) async throws -> TripEndpointLocality
}

@MainActor
final class AppleTripEndpointLocalityResolver: TripEndpointLocalityResolving {
    func resolve(coordinate: CLLocationCoordinate2D) async throws -> TripEndpointLocality {
        guard CLLocationCoordinate2DIsValid(coordinate) else {
            throw CLError(.locationUnknown)
        }
        let placemarks = try await CLGeocoder().reverseGeocodeLocation(
            CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
            preferredLocale: Locale(identifier: "fr_CA")
        )
        guard let placemark = placemarks.first,
              let countryCode = placemark.isoCountryCode,
              let regionCode = placemark.administrativeArea,
              let locality = FuelPriceLookupRequest.coarseLocality(
                locality: placemark.locality,
                regionCode: regionCode
              ) else {
            throw CLError(.geocodeFoundNoResult)
        }
        let result = TripEndpointLocality(
            countryCode: countryCode,
            regionCode: regionCode,
            locality: locality
        )
        guard result.isStructurallyValid else {
            throw CLError(.geocodeFoundNoResult)
        }
        return result
    }
}

@MainActor
protocol TripFuelCostPersisting: AnyObject {
    @discardableResult
    func persistVerifiedOfficialFuelCost(
        tripID: UUID,
        settings: FuelSettings,
        match: VerifiedFuelPriceGeographyMatch
    ) throws -> Bool
}

enum TripFuelCostEnrichmentOutcome: String, Equatable {
    case enriched
    case notApplied
    case noQualifiedEndpoints
    case locationResolutionFailed
    case geographyMismatch
    case persistenceFailed
}

struct TripFuelCostEnrichmentRequest {
    let tripID: UUID
    let routePoints: [TripRoutePoint]
    let settings: FuelSettings
    let tripEndedAt: Date
}

/// Enrichissement asynchrone et non critique : la persistance du trajet est deja
/// terminee. Une erreur de geocodage ou de stockage ne peut donc jamais supprimer
/// le trajet ; elle laisse seulement son cout officiel indisponible et retentable.
@MainActor
final class TripFuelCostEnricher {
    static let maximumEndpointHorizontalAccuracy: CLLocationAccuracy = 100

    private weak var persister: (any TripFuelCostPersisting)?
    private let resolver: any TripEndpointLocalityResolving
    private var inFlightTripIDs = Set<UUID>()
    private var pendingTask: Task<Void, Never>?

    init(
        persister: any TripFuelCostPersisting,
        resolver: any TripEndpointLocalityResolving
    ) {
        self.persister = persister
        self.resolver = resolver
    }

    convenience init(persister: any TripFuelCostPersisting) {
        self.init(
            persister: persister,
            resolver: AppleTripEndpointLocalityResolver()
        )
    }

    func schedule(_ request: TripFuelCostEnrichmentRequest) {
        guard inFlightTripIDs.insert(request.tripID).inserted else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let outcome = await enrich(request)
            Self.log(outcome: outcome, tripID: request.tripID)
            inFlightTripIDs.remove(request.tripID)
        }
    }

    /// Les reprises sont sequentielles pour ne pas saturer le geocodeur Apple.
    func schedulePending(_ requests: [TripFuelCostEnrichmentRequest]) {
        guard pendingTask == nil else { return }
        pendingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { pendingTask = nil }
            for request in requests where !Task.isCancelled {
                guard inFlightTripIDs.insert(request.tripID).inserted else { continue }
                let outcome = await enrich(request)
                Self.log(outcome: outcome, tripID: request.tripID)
                inFlightTripIDs.remove(request.tripID)
            }
        }
    }

    func enrich(
        _ request: TripFuelCostEnrichmentRequest,
        matchedAt: Date = Date()
    ) async -> TripFuelCostEnrichmentOutcome {
        guard request.settings.source == .officialPublicData,
              request.settings.canSnapshotCost(at: request.tripEndedAt),
              let endpoints = Self.qualifiedEndpoints(from: request.routePoints) else {
            return .noQualifiedEndpoints
        }

        let start: TripEndpointLocality
        let end: TripEndpointLocality
        do {
            start = try await resolver.resolve(coordinate: endpoints.start.coordinate)
            if endpoints.start.coordinate.latitude == endpoints.end.coordinate.latitude,
               endpoints.start.coordinate.longitude == endpoints.end.coordinate.longitude {
                end = start
            } else {
                end = try await resolver.resolve(coordinate: endpoints.end.coordinate)
            }
        } catch {
            return .locationResolutionFailed
        }

        guard let match = FuelPriceGeographyMatcher.verifiedMatch(
            tripID: request.tripID,
            settings: request.settings,
            start: start,
            end: end,
            matchedAt: matchedAt
        ) else {
            return .geographyMismatch
        }

        do {
            guard let persister else { return .persistenceFailed }
            return try persister.persistVerifiedOfficialFuelCost(
                tripID: request.tripID,
                settings: request.settings,
                match: match
            ) ? .enriched : .notApplied
        } catch {
            return .persistenceFailed
        }
    }

    private static func log(outcome: TripFuelCostEnrichmentOutcome, tripID: UUID) {
        ViimDiagnostics.log(
            "trip.fuelCost.enrichment id=\(tripID.uuidString) outcome=\(outcome.rawValue)"
        )
    }

    private static func qualifiedEndpoints(
        from points: [TripRoutePoint]
    ) -> (start: TripRoutePoint, end: TripRoutePoint)? {
        let qualified = points.filter {
            $0.latitude.isFinite &&
                $0.longitude.isFinite &&
                (-90...90).contains($0.latitude) &&
                (-180...180).contains($0.longitude) &&
                $0.horizontalAccuracy > 0 &&
                $0.horizontalAccuracy <= maximumEndpointHorizontalAccuracy
        }
        guard let start = qualified.first, let end = qualified.last else { return nil }
        return (start, end)
    }
}
