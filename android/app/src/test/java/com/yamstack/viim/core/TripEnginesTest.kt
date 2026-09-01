package com.yamstack.viim.core

import org.junit.Assert.*
import org.junit.Test

class TripEnginesTest {
    private fun sample(at: Long, latitude: Double, longitude: Double, speed: Double = 25.0) =
        LocationSample(at, latitude, longitude, speed, 8f, 1f)

    @Test fun `un trajet de qualite est persistant`() {
        val report = TripQualityEngine.report(listOf(sample(0, 12.37, -1.52), sample(65_000, 12.3712, -1.52)), 65, VehicleType.MOTO)
        assertTrue(report.shouldPersist)
        assertEquals(MetricConfidence.RELIABLE, report.confidence)
    }

    @Test fun `un trajet trop court est refuse`() {
        val report = TripQualityEngine.report(listOf(sample(0, 12.37, -1.52), sample(30_000, 12.3712, -1.52)), 30, VehicleType.MOTO)
        assertFalse(report.shouldPersist)
        assertEquals(MetricReasonCode.TRIP_TOO_SHORT, report.reason)
    }

    @Test fun `les alias historiques du role restent compatibles`() {
        assertEquals(TripRole.PASSAGER_TRANSPORT, TripRole.fromStorage("bus"))
        assertEquals(TripRole.CONDUCTEUR, TripRole.fromStorage("conducteur"))
    }

    @Test fun `la vitesse excessive diminue le score`() {
        val scores = ScoreEngine.scores(listOf(sample(0, 12.37, -1.52, 115.0)), VehicleType.MOTO)
        assertNotNull(scores.speed)
        assertTrue(scores.speed!! < 100)
    }
}
