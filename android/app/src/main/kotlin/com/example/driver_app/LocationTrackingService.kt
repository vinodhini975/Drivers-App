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
import android.content.pm.ServiceInfo

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
    private var lastLocationLat: Double = 0.0
    private var lastLocationLng: Double = 0.0
    private var stationaryUpdateCount: Int = 0

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

        // Create location request optimized for live tracking
        // IMPORTANT: Updates happen every 15 seconds even when driver is stationary
        locationRequest = LocationRequest.Builder(
            Priority.PRIORITY_HIGH_ACCURACY, // High accuracy for precise live tracking
            15000L // Update every 15 seconds - guaranteed updates even when stationary
        )
        .setMinUpdateDistanceMeters(0f) // Update even without movement (0 meters = always update on time interval)
        .setMinUpdateIntervalMillis(15000L) // Guaranteed update every 15 seconds minimum
        .setMaxUpdateDelayMillis(20000L) // Maximum 20 seconds delay
        .build()
        
        Log.d(TAG, "Location request configured: interval=15s (updates even when stationary), minDistance=0m")

        locationCallback = object : LocationCallback() {
            override fun onLocationResult(locationResult: LocationResult) {
                locationResult.lastLocation?.let { location ->
                    // Check if driver is stationary (same location as last update)
                    val isStationary = (lastLocationLat != 0.0 && lastLocationLng != 0.0) &&
                                     Math.abs(location.latitude - lastLocationLat) < 0.00001 &&
                                     Math.abs(location.longitude - lastLocationLng) < 0.00001
                    
                    if (isStationary) {
                        stationaryUpdateCount++
                        Log.d(TAG, "🚦 Driver STATIONARY: ${location.latitude}, ${location.longitude} (stationary update #$stationaryUpdateCount)")
                    } else {
                        stationaryUpdateCount = 0
                        Log.d(TAG, "📍 NEW Location (MOVING): ${location.latitude}, ${location.longitude} (accuracy: ${location.accuracy}m)")
                    }
                    
                    // Store location in shared preferences and notify Flutter
                    storeLocationInPrefs(location.latitude, location.longitude)
                    
                    // Update last known location
                    lastLocationLat = location.latitude
                    lastLocationLng = location.longitude
                }
            }
            
            override fun onLocationAvailability(availability: com.google.android.gms.location.LocationAvailability) {
                super.onLocationAvailability(availability)
                Log.d(TAG, "Location availability changed: isLocationAvailable=${availability.isLocationAvailable}")
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
            commit() // Use commit instead of apply for immediate persistence
        }
        Log.d(TAG, "✅ Location stored in prefs: $lat, $lng for user $username (updated=true)")
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "onStartCommand called")
        
        // Extract username from Intent
        intent?.getStringExtra("username")?.let {
            if (it.isNotEmpty()) {
                Log.d(TAG, "Starting tracking for username: $it")
                username = it
                startTracking(it)
            }
        }

        // Handle foreground service start properly for different Android versions
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID, 
                    createNotification(), 
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
                )
            } else {
                startForeground(NOTIFICATION_ID, createNotification())
            }
            Log.d(TAG, "Foreground service started successfully")
        } catch (e: Exception) {
            Log.e(TAG, "Error starting foreground service: ${e.message}")
        }

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
            .setContentTitle("👨‍✈️ Driver Live Tracking")
            .setContentText("Tracking $username - Updates every 15s (even when stopped)")
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentIntent(pendingIntent)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .build()
    }

    fun startTracking(username: String) {
        this.username = username
        if (!isTracking) {
            isTracking = true
            
            // Reset stationary tracking
            lastLocationLat = 0.0
            lastLocationLng = 0.0
            stationaryUpdateCount = 0
            
            // Acquire wake lock to keep the service alive
            try {
                if (wakeLock?.isHeld == false) {
                    wakeLock?.acquire(TimeUnit.HOURS.toMillis(10)) // Acquire for 10 hours
                    Log.d(TAG, "Wake lock acquired")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error acquiring wake lock: ${e.message}")
            }
            
            try {
                Log.d(TAG, "Attempting to start location tracking for $username")
                
                // Check if we have location permission
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                    if (checkSelfPermission(android.Manifest.permission.ACCESS_FINE_LOCATION) != 
                        android.content.pm.PackageManager.PERMISSION_GRANTED) {
                        Log.e(TAG, "Missing ACCESS_FINE_LOCATION permission")
                        return
                    }
                    if (checkSelfPermission(android.Manifest.permission.ACCESS_COARSE_LOCATION) != 
                        android.content.pm.PackageManager.PERMISSION_GRANTED) {
                        Log.e(TAG, "Missing ACCESS_COARSE_LOCATION permission")
                        return
                    }
                }
                
                // Request location updates
                fusedLocationClient.requestLocationUpdates(
                    locationRequest,
                    locationCallback,
                    Looper.getMainLooper()
                )
                Log.d(TAG, "✅ Location tracking started successfully for $username")
                
                // Get last known location immediately
                fusedLocationClient.lastLocation.addOnSuccessListener { location ->
                    location?.let {
                        Log.d(TAG, "📍 Got last known location: ${it.latitude}, ${it.longitude}")
                        storeLocationInPrefs(it.latitude, it.longitude)
                    } ?: run {
                        Log.w(TAG, "⚠️ No last known location available")
                    }
                }.addOnFailureListener { e ->
                    Log.e(TAG, "❌ Failed to get last known location: ${e.message}")
                }
            } catch (e: SecurityException) {
                Log.e(TAG, "❌ Location permission missing: ${e.message}")
                isTracking = false
                wakeLock?.release()
            } catch (e: Exception) {
                Log.e(TAG, "❌ Error starting location tracking: ${e.message}")
                e.printStackTrace()
                isTracking = false
                wakeLock?.release()
            }
        } else {
            Log.d(TAG, "Location tracking already running for $username")
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
        // This won't be called directly since we're starting it as a Service, 
        // but keeping it if we switch architecture later
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