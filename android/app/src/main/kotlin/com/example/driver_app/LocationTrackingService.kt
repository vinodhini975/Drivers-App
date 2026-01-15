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
    private lateinit var locationRequest: LocationRequest
    private var driverId: String = ""
    private val db = FirebaseFirestore.getInstance()

    override fun onCreate() {
        super.onCreate()
        fusedLocationClient = LocationServices.getFusedLocationProviderClient(this)
        createNotificationChannel()
        
        locationRequest = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 10000L)
            .setMinUpdateIntervalMillis(5000L)
            .setWaitForAccurateLocation(true)
            .build()

        locationCallback = object : LocationCallback() {
            override fun onLocationResult(locationResult: LocationResult) {
                locationResult.lastLocation?.let { location ->
                    syncToFirebase(location.latitude, location.longitude, location.accuracy)
                }
            }
        }
    }

    private fun syncToFirebase(lat: Double, lng: Double, acc: Float) {
        if (driverId.isEmpty()) return

        val timestamp = System.currentTimeMillis()
        val data = hashMapOf<String, Any>(
            "latitude" to lat,
            "longitude" to lng,
            "accuracy" to acc,
            "lastUpdate" to FieldValue.serverTimestamp(),
            "status" to "active",
            "isOnDuty" to true
        )

        // 1. Update Live Snapshot (For Govt Map)
        db.collection("drivers").document(driverId).update(data)
            .addOnFailureListener {
                // If update fails (doc might not exist in auto-onboarding), try set with merge
                db.collection("drivers").document(driverId).set(data, com.google.firebase.firestore.SetOptions.merge())
            }

        // 2. Add to Scalable History (For Audit Trail)
        db.collection("drivers").document(driverId)
            .collection("locations").document(timestamp.toString())
            .set(data)
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

        requestUpdates()
        return START_STICKY
    }

    private fun requestUpdates() {
        try {
            fusedLocationClient.requestLocationUpdates(locationRequest, locationCallback, Looper.getMainLooper())
        } catch (e: SecurityException) {
            Log.e(TAG, "Permission lost: $e")
        }
    }

    private fun createNotification(): Notification {
        val intent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_IMMUTABLE)

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Vehicle Tracking Active")
            .setContentText("Continuous 10s updates for $driverId")
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
        super.onDestroy()
    }
}
