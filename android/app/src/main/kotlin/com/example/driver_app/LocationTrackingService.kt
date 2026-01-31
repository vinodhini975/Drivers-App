package com.example.driver_app

import android.app.*
import android.content.*
import android.os.*
import android.util.Log
import androidx.core.app.NotificationCompat
import com.google.android.gms.location.*
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FieldValue
import android.content.pm.ServiceInfo

class LocationTrackingService : Service() {
    companion object {
        const val NOTIFICATION_ID = 888
        const val CHANNEL_ID = "DriverTrackingChannel"
        private const val TAG = "LocationService"
    }

    private lateinit var fusedLocationClient: FusedLocationProviderClient
    private lateinit var locationCallback: LocationCallback
    private var driverId: String = ""
    private val db = FirebaseFirestore.getInstance()

    override fun onCreate() {
        super.onCreate()
        fusedLocationClient = LocationServices.getFusedLocationProviderClient(this)
        createNotificationChannel()
        
        // 30-second High Accuracy Hardware Request
        locationCallback = object : LocationCallback() {
            override fun onLocationResult(locationResult: LocationResult) {
                locationResult.lastLocation?.let { location ->
                    Log.d(TAG, "Hardware GPS Tick (30s): ${location.latitude}, ${location.longitude}")
                    syncToFirebase(location.latitude, location.longitude, location.accuracy)
                }
            }
        }
    }

    private fun syncToFirebase(lat: Double, lng: Double, acc: Float) {
        if (driverId.isEmpty()) return

        val data = hashMapOf<String, Any>(
            "latitude" to lat,
            "longitude" to lng,
            "accuracy" to acc,
            "lastUpdate" to FieldValue.serverTimestamp(),
            "isTrackingEnabled" to true
        )

        // Direct Native push for ultra-low latency & termination resilience
        db.collection("drivers").document(driverId).update(data)
            .addOnFailureListener {
                Log.e(TAG, "Sync deferred (Offline mode). Firebase will auto-sync later.")
            }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val inputId = intent?.getStringExtra("username")
        if (inputId != null) driverId = inputId
        
        val notification = createNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        requestHardwareUpdates()
        return START_STICKY
    }

    private fun requestHardwareUpdates() {
        // PRODUCTION SAFE: 30-second intervals
        val locationRequest = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 30000L) 
            .setMinUpdateIntervalMillis(30000L) // Ensure no more than 1 update per 30s
            .setWaitForAccurateLocation(true)
            .build()

        try {
            fusedLocationClient.requestLocationUpdates(locationRequest, locationCallback, Looper.getMainLooper())
            Log.i(TAG, "GPS Hardware Activated (30s interval) for $driverId")
        } catch (e: SecurityException) {
            Log.e(TAG, "GPS Activation Failed: Missing Permissions")
        }
    }

    private fun createNotification(): Notification {
        val intent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_IMMUTABLE)

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Vehicle Tracking Active")
            .setContentText("Continuous 30s updates for $driverId")
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(pendingIntent)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL_ID, "Tracking Service", NotificationManager.IMPORTANCE_LOW)
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        fusedLocationClient.removeLocationUpdates(locationCallback)
        Log.i(TAG, "GPS Hardware Deactivated")
        super.onDestroy()
    }
}
