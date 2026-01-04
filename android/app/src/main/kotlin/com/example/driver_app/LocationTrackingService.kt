package com.example.driver_app

import android.app.*
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import com.google.android.gms.location.*
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.MethodCall
import android.app.PendingIntent
import android.os.PowerManager
import java.util.concurrent.TimeUnit

class LocationTrackingService : Service(), MethodCallHandler {
    companion object {
        const val CHANNEL_ID = "location_tracking_service"
        const val NOTIFICATION_ID = 1
        const val NOTIFICATION_CHANNEL_ID = "LocationTrackingChannel"
        const val REQUEST_CODE = 1001
        private const val TAG = "LocationTrackingService"
        private const val PREFS_NAME = "LocationTrackingPrefs"
        private const val LAST_LOCATION_LAT = "last_location_lat"
        private const val LAST_LOCATION_LNG = "last_location_lng"
        private const val LAST_USERNAME = "last_username"
        private const val LOCATION_UPDATED = "location_updated"
    }

    private lateinit var fusedLocationClient: FusedLocationProviderClient
    private lateinit var locationCallback: LocationCallback
    private lateinit var locationRequest: LocationRequest
    private var isTracking = false
    private var username: String = ""
    private var wakeLock: PowerManager.WakeLock? = null
    private lateinit var sharedPreferences: SharedPreferences

    override fun onCreate() {
        super.onCreate()
        fusedLocationClient = LocationServices.getFusedLocationProviderClient(this)
        sharedPreferences = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        
        // Create notification channel for Android O and above
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                "Location Tracking Service",
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }

        // Create location request with optimized settings for battery efficiency
        locationRequest = LocationRequest.Builder(
            Priority.PRIORITY_BALANCED_POWER_ACCURACY, // Changed from HIGH_ACCURACY to save battery
            60000L // Increased to 60 seconds to save battery
        )
        .setMinUpdateDistanceMeters(25f) // Increased to 25 meters to save battery
        .setMinUpdateIntervalMillis(30000L) // 30 seconds
        .build()

        locationCallback = object : LocationCallback() {
            override fun onLocationResult(locationResult: LocationResult) {
                locationResult.lastLocation?.let { location ->
                    Log.d(TAG, "Location updated: ${location.latitude}, ${location.longitude}")
                    // Store location in shared preferences and notify Flutter
                    storeLocationInPrefs(location.latitude, location.longitude)
                }
            }
        }

        // Acquire wake lock for reliable tracking
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "DriverApp::LocationTrackingWakeLock"
        )
    }

    private fun storeLocationInPrefs(lat: Double, lng: Double) {
        with(sharedPreferences.edit()) {
            putString(LAST_USERNAME, username)
            putString(LAST_LOCATION_LAT, lat.toString())
            putString(LAST_LOCATION_LNG, lng.toString())
            putBoolean(LOCATION_UPDATED, true)
            apply()
        }
        Log.d(TAG, "Location stored in prefs: $lat, $lng for user $username")
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(NOTIFICATION_ID, createNotification())
        return START_STICKY // Restart service if killed
    }

    private fun createNotification(): Notification {
        val notificationIntent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0, notificationIntent, 
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        return NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setContentTitle("Driver Tracking Active")
            .setContentText("Updating location...")
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }

    fun startTracking(username: String) {
        this.username = username
        if (!isTracking) {
            isTracking = true
            wakeLock?.acquire(TimeUnit.MINUTES.toMillis(30)) // Acquire for 30 minutes, will be renewed
            
            // Request location updates
            fusedLocationClient.requestLocationUpdates(
                locationRequest,
                locationCallback,
                Looper.getMainLooper()
            )
            
            Log.d(TAG, "Location tracking started for $username")
        }
    }

    fun stopTracking() {
        if (isTracking) {
            isTracking = false
            fusedLocationClient.removeLocationUpdates(locationCallback)
            wakeLock?.release()
            Log.d(TAG, "Location tracking stopped")
        }
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "startTracking" -> {
                val username = call.argument<String>("username") ?: ""
                if (username.isNotEmpty()) {
                    startTracking(username)
                    result.success("Tracking started for $username")
                } else {
                    result.error("INVALID_USERNAME", "Username is required", null)
                }
            }
            "stopTracking" -> {
                stopTracking()
                result.success("Tracking stopped")
            }
            "isTracking" -> {
                result.success(isTracking)
            }
            "updateUsername" -> {
                this.username = call.argument<String>("username") ?: ""
                result.success("Username updated to ${this.username}")
            }
            "getLastLocation" -> {
                val lat = sharedPreferences.getString(LAST_LOCATION_LAT, null)
                val lng = sharedPreferences.getString(LAST_LOCATION_LNG, null)
                val lastUsername = sharedPreferences.getString(LAST_USERNAME, null)
                
                if (lat != null && lng != null && lastUsername != null) {
                    val locationMap = mapOf(
                        "lat" to lat.toDouble(),
                        "lng" to lng.toDouble(),
                        "username" to lastUsername,
                        "updated" to sharedPreferences.getBoolean(LOCATION_UPDATED, false)
                    )
                    result.success(locationMap)
                    // Reset the updated flag
                    sharedPreferences.edit().putBoolean(LOCATION_UPDATED, false).apply()
                } else {
                    result.success(null)
                }
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        stopTracking()
        Log.d(TAG, "Location tracking service destroyed")
    }
}