package com.yamstack.viim.core

/** Contrats miroir de `shared-data/carburant-contract-v1.json` et d’iOS. */
enum class FuelCostState { PENDING, UNAVAILABLE, ESTIMATED, CONFIRMED }
enum class FuelPriceEvidenceKind { ADMINISTERED_EXACT, OFFICIAL_AVERAGE, CACHED_STALE }

enum class TripRole(val storageValue: String) {
    CONDUCTEUR("conducteur"),
    PASSAGER_TRANSPORT("passager_transport"),
    INCONNU("inconnu");

    companion object {
        fun fromStorage(value: String?) = when (value) {
            "conducteur" -> CONDUCTEUR
            "passager_transport", "passager", "bus" -> PASSAGER_TRANSPORT
            else -> INCONNU
        }
    }
}

enum class VehicleType(val storageValue: String, val speedLimitKmh: Double) {
    MOTO("moto", 80.0), VOITURE("voiture", 100.0), VELO("velo", 35.0);

    val maximumReasonableSpeedKmh: Double
        get() = when (this) { MOTO -> 160.0; VOITURE -> 220.0; VELO -> 70.0 }
}

enum class MetricConfidence { RELIABLE, PARTIAL, NEEDS_INPUT, UNAVAILABLE, NEEDS_REVIEW }
enum class MetricReasonCode { COMPLETE, GPS_INSUFFICIENT, GPS_ACCURACY_TOO_LOW, IMPOSSIBLE_SPEED, TRIP_TOO_SHORT, FUEL_ESTIMATED, FUEL_INPUT_MISSING, SCORE_UNAVAILABLE }

data class LocationSample(
    val timestampMs: Long,
    val latitude: Double,
    val longitude: Double,
    val speedKmh: Double,
    val horizontalAccuracyMeters: Float,
    val speedAccuracyMetersPerSecond: Float?
)

data class TripScores(
    val global: Int?, val speed: Int?, val fluidity: Int?, val vigilance: Int?, val eco: Int?
) { companion object { val unavailable = TripScores(null, null, null, null, null) } }

data class TripQualityReport(
    val confidence: MetricConfidence,
    val reason: MetricReasonCode,
    val shouldPersist: Boolean,
    val distanceMeters: Double?
)

data class TripRecord(
    val id: String,
    val startDateMs: Long,
    val endDateMs: Long,
    val distanceKm: Double,
    val durationSeconds: Int,
    val maxSpeedKmh: Double,
    val vehicleType: VehicleType,
    val role: TripRole = TripRole.INCONNU,
    val scores: TripScores = TripScores.unavailable,
    val quality: TripQualityReport,
    val fuelLiters: Double? = null,
    val fuelCostState: FuelCostState = FuelCostState.UNAVAILABLE
)

data class CarburantFeatureFlags(
    val gpsSessionSplit: Boolean = false,
    val physicalFuelModel: Boolean = false,
    val transitClassifier: Boolean = false
) {
    companion object {
        /** Ces variantes ne sont jamais activées dans une build release. */
        fun defaults(isDebug: Boolean) = if (isDebug) CarburantFeatureFlags() else CarburantFeatureFlags()
    }
}
