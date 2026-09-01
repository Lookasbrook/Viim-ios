package com.yamstack.viim.location

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.PackageManager
import android.location.LocationListener
import android.location.LocationManager
import android.os.IBinder
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import com.yamstack.viim.R

/** Service GPS explicite. Il ne démarre qu’après consentement d’emplacement dans l’UI. */
class LocationTrackingService : Service(), LocationListener {
    private val locationManager by lazy { getSystemService(LocationManager::class.java) }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        createChannel()
        startForeground(1, NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentTitle(getString(R.string.tracking_notification_title))
            .setContentText(getString(R.string.tracking_notification_body))
            .setOngoing(true).build())
        if (ActivityCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED) {
            locationManager.requestLocationUpdates(LocationManager.GPS_PROVIDER, 10_000, 10f, this)
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() { locationManager.removeUpdates(this); super.onDestroy() }
    override fun onBind(intent: Intent?): IBinder? = null
    override fun onLocationChanged(location: android.location.Location) = Unit
    private fun createChannel() {
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel(CHANNEL_ID, getString(R.string.tracking_channel), NotificationManager.IMPORTANCE_LOW)
        )
    }
    private companion object { const val CHANNEL_ID = "viim_location_tracking" }
}
