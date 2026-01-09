package com.example.driver_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.content.Context
import android.content.SharedPreferences
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "location_tracking_service"
    private var locationUpdateHandler: Handler? = null
    private var locationUpdateRunnable: Runnable? = null
    private lateinit var sharedPreferences: SharedPreferences
    private var eventSink: EventChannel.EventSink? = null
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        sharedPreferences = applicationContext.getSharedPreferences("LocationTrackingPrefs", Context.MODE_PRIVATE)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startTracking" -> {
                    val username = call.argument<String>("username")
                    startLocationTrackingService(username)
                    result.success("Service started")
                }
                "stopTracking" -> {
                    stopLocationTrackingService()
                    result.success("Service stopped")
                }
                "isTracking" -> {
                    // Check if the service is running by checking SharedPreferences
                    val lastUsername = sharedPreferences.getString("last_username", null)
                    val isRunning = lastUsername != null && lastUsername.isNotEmpty()
                    android.util.Log.d("MainActivity", "isTracking called: $isRunning (username=$lastUsername)")
                    result.success(isRunning)
                }
                "getLastLocation" -> {
                    // This method will be called by Flutter to get the latest location
                    val lat = sharedPreferences.getString("last_location_lat", null)
                    val lng = sharedPreferences.getString("last_location_lng", null)
                    val lastUsername = sharedPreferences.getString("last_username", null)
                    val updated = sharedPreferences.getBoolean("location_updated", false)
                    
                    android.util.Log.d("MainActivity", "getLastLocation called: lat=$lat, lng=$lng, username=$lastUsername, updated=$updated")
                    
                    if (lat != null && lng != null && lastUsername != null && updated) {
                        try {
                            val locationMap = mapOf(
                                "lat" to lat.toDouble(),
                                "lng" to lng.toDouble(),
                                "username" to lastUsername,
                                "updated" to true
                            )
                            result.success(locationMap)
                            // Reset the updated flag after successful retrieval
                            sharedPreferences.edit().putBoolean("location_updated", false).apply()
                            android.util.Log.d("MainActivity", "Location data sent to Flutter: $locationMap")
                        } catch (e: Exception) {
                            android.util.Log.e("MainActivity", "Error parsing location data: ${e.message}")
                            result.success(null)
                        }
                    } else {
                        android.util.Log.d("MainActivity", "No valid location data available or not updated")
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        
        // Create event channel for real-time location updates
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "$CHANNEL/events").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            }
        )
        
        // Start periodic checking for location updates from the native service
        startLocationUpdateListener()
    }
    
    private fun startLocationUpdateListener() {
        locationUpdateHandler = Handler(Looper.getMainLooper())
        locationUpdateRunnable = object : Runnable {
            override fun run() {
                // Check if location was updated
                if (sharedPreferences.getBoolean("location_updated", false)) {
                    // Location was updated, send to Flutter via event channel
                    val lat = sharedPreferences.getString("last_location_lat", null)
                    val lng = sharedPreferences.getString("last_location_lng", null)
                    val username = sharedPreferences.getString("last_username", null)
                    
                    if (lat != null && lng != null && username != null) {
                        val locationMap = mapOf(
                            "lat" to lat.toDouble(),
                            "lng" to lng.toDouble(),
                            "username" to username
                        )
                        
                        eventSink?.success(locationMap)
                        android.util.Log.d("MainActivity", "Location update sent to Flutter: $locationMap")
                        
                        // Reset the updated flag after sending
                        sharedPreferences.edit().putBoolean("location_updated", false).apply()
                    }
                }
                
                // Schedule next check
                locationUpdateHandler?.postDelayed(this, 5000) // Check every 5 seconds
            }
        }
        locationUpdateHandler?.post(locationUpdateRunnable!!)
    }
    
    override fun onDestroy() {
        super.onDestroy()
        locationUpdateRunnable?.let {
            locationUpdateHandler?.removeCallbacks(it)
        }
        eventSink = null
    }
    
    private fun startLocationTrackingService(username: String?) {
        if (username != null) {
            val intent = Intent(this, LocationTrackingService::class.java)
            intent.putExtra("username", username)
            // Use ContextCompat to handle foreground service start compatibly across versions
            ContextCompat.startForegroundService(this, intent)
        }
    }
    
    private fun stopLocationTrackingService() {
        android.util.Log.d("MainActivity", "Stopping location tracking service")
        val intent = Intent(this, LocationTrackingService::class.java)
        stopService(intent)
        
        // Clear the tracking data from SharedPreferences
        sharedPreferences.edit().apply {
            remove("last_username")
            remove("last_location_lat")
            remove("last_location_lng")
            remove("location_updated")
            apply()
        }
        android.util.Log.d("MainActivity", "Location tracking service stopped and prefs cleared")
    }
}