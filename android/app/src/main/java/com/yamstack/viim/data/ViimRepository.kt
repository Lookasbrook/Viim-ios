package com.yamstack.viim.data

import android.content.Context
import com.yamstack.viim.core.*
import java.util.UUID

/**
 * Persistance de fondation locale. Les anciennes tables Room sont documentées dans
 * memory/; aucune donnée de l’ancienne APK n’est importée ni lue depuis le téléphone.
 */
class ViimRepository(context: Context) {
    private val preferences = context.getSharedPreferences("viim_recovery", Context.MODE_PRIVATE)

    var selectedVehicle: VehicleType
        get() = runCatching { VehicleType.valueOf(preferences.getString("vehicle", VehicleType.MOTO.name)!!) }.getOrDefault(VehicleType.MOTO)
        set(value) = preferences.edit().putString("vehicle", value.name).apply()

    fun recordDemoTrip(samples: List<LocationSample>, durationSeconds: Int): TripRecord? {
        val quality = TripQualityEngine.report(samples, durationSeconds, selectedVehicle)
        if (!quality.shouldPersist) return null
        val scores = ScoreEngine.scores(samples, selectedVehicle)
        return TripRecord(
            id = UUID.randomUUID().toString(), startDateMs = samples.first().timestampMs,
            endDateMs = samples.last().timestampMs, distanceKm = (quality.distanceMeters ?: 0.0) / 1_000,
            durationSeconds = durationSeconds, maxSpeedKmh = samples.maxOf { it.speedKmh },
            vehicleType = selectedVehicle, scores = scores, quality = quality
        )
    }
}
