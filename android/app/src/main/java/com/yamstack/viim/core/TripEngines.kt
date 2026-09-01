package com.yamstack.viim.core

import kotlin.math.*

/** Règles volontairement identiques aux seuils définis dans TripReliability.swift. */
object TripQualityEngine {
    const val minimumDistanceMeters = 80.0
    const val minimumDurationSeconds = 60
    const val maximumRouteAccuracyMeters = 100f
    const val maximumSpeedAccuracyMeters = 50f
    const val maximumReportedSpeedAccuracy = 3f

    fun report(samples: List<LocationSample>, durationSeconds: Int, vehicle: VehicleType): TripQualityReport {
        if (durationSeconds < minimumDurationSeconds) return TripQualityReport(MetricConfidence.UNAVAILABLE, MetricReasonCode.TRIP_TOO_SHORT, false, null)
        val valid = samples.filter { it.horizontalAccuracyMeters in 0f..maximumRouteAccuracyMeters }
        if (valid.size < 2) return TripQualityReport(MetricConfidence.UNAVAILABLE, MetricReasonCode.GPS_INSUFFICIENT, false, null)
        var distance = 0.0
        var rejected = false
        valid.zipWithNext().forEach { (previous, current) ->
            val elapsed = (current.timestampMs - previous.timestampMs) / 1_000.0
            if (elapsed <= 0) return@forEach
            val segment = haversineMeters(previous.latitude, previous.longitude, current.latitude, current.longitude)
            val derivedSpeed = segment / elapsed * 3.6
            if (derivedSpeed <= vehicle.maximumReasonableSpeedKmh) distance += segment else rejected = true
        }
        if (distance < minimumDistanceMeters) {
            return TripQualityReport(if (rejected) MetricConfidence.NEEDS_REVIEW else MetricConfidence.UNAVAILABLE, if (rejected) MetricReasonCode.IMPOSSIBLE_SPEED else MetricReasonCode.TRIP_TOO_SHORT, false, null)
        }
        return TripQualityReport(MetricConfidence.RELIABLE, MetricReasonCode.COMPLETE, true, distance)
    }

    private fun haversineMeters(latA: Double, lonA: Double, latB: Double, lonB: Double): Double {
        val dLat = Math.toRadians(latB - latA)
        val dLon = Math.toRadians(lonB - lonA)
        val a = sin(dLat / 2).pow(2) + cos(Math.toRadians(latA)) * cos(Math.toRadians(latB)) * sin(dLon / 2).pow(2)
        return 6_371_000.0 * 2.0 * atan2(sqrt(a), sqrt(1.0 - a))
    }
}

object ScoreEngine {
    const val version = "score-speed-fluidity-eco-v3"

    fun scores(samples: List<LocationSample>, vehicle: VehicleType): TripScores {
        val speeds = samples.filter {
            it.speedKmh.isFinite() && it.speedKmh >= 0 && it.speedKmh <= vehicle.maximumReasonableSpeedKmh &&
                it.horizontalAccuracyMeters <= TripQualityEngine.maximumSpeedAccuracyMeters &&
                (it.speedAccuracyMetersPerSecond ?: Float.MAX_VALUE) <= TripQualityEngine.maximumReportedSpeedAccuracy
        }.map { it.speedKmh }
        if (speeds.isEmpty()) return TripScores.unavailable
        val excess = max(0.0, (speeds.max() - vehicle.speedLimitKmh - 5.0))
        val speed = (100 - (excess * 2.5).roundToInt()).coerceIn(0, 100)
        return TripScores(global = speed, speed = speed, fluidity = null, vigilance = null, eco = null)
    }
}
